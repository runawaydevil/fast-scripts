<# :
@echo off
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression ([System.IO.File]::ReadAllText('%~f0',[System.Text.Encoding]::UTF8))"
exit /b %errorlevel%
#>

# ============================================================
#  Imagens e PDF - junta imagens em PDF, ou PDF em imagens (ImageMagick)
#  Desenvolvido por Pablo Murad - 2026
# ============================================================

try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
try { $Host.UI.RawUI.WindowTitle = 'Imagens e PDF' } catch {}

# ============================================================
#  Executar-EmParalelo - pool de processos externos (PS 5.1)
#  Cada tarefa: @{ Exe='ffmpeg'; Args=@(...); Rotulo='x.mp4'; Dur=123.4 }
#  Dur e' opcional (segundos) e so' pondera a barra de progresso.
#  Devolve 1 objeto por tarefa: Indice/Rotulo/Codigo/Saida/Erro/Segundos
# ============================================================
function Limite-Padrao([string]$tipo) {
    $n = [Environment]::ProcessorCount
    switch ($tipo) {
        'gpu'    { 3 }
        'cpu'    { [Math]::Max(2, [Math]::Min(4,  [int]($n / 6))) }
        'imagem' { [Math]::Max(2, [Math]::Min(8,  [int]($n / 3))) }
        'sonda'  { [Math]::Max(4, [Math]::Min(12, [int]($n / 2))) }
        default  { 4 }
    }
}

function Executar-EmParalelo {
    param(
        [object[]]$Tarefas,
        [int]$Limite = 4,
        [switch]$SemProgresso
    )

    # Quoting do Windows (CommandLineToArgvW). NAO simplificar: dobrar as
    # barras finais e' o que impede um caminho terminado em '\' de comer
    # a aspa de fechamento.
    function _Citar([string]$a) {
        if ($a -eq '')            { return '""' }
        if ($a -notmatch '[\s"]') { return $a }
        $s = ''; $bs = 0
        foreach ($c in $a.ToCharArray()) {
            if ($c -eq '\') { $bs++; continue }
            if ($c -eq '"') { $s += ('\' * ($bs * 2 + 1)) + '"'; $bs = 0; continue }
            if ($bs) { $s += ('\' * $bs); $bs = 0 }
            $s += $c
        }
        if ($bs) { $s += ('\' * ($bs * 2)) }
        return '"' + $s + '"'
    }

    $tot = @($Tarefas).Count
    if ($tot -eq 0) { return @() }
    if ($Limite -lt 1) { $Limite = 1 }

    $res    = New-Object object[] $tot
    $ativos = New-Object System.Collections.ArrayList
    $prox = 0; $feitos = 0; $falhas = 0
    $durTotal = 0.0; foreach ($t in $Tarefas) { if ($t.Dur) { $durTotal += [double]$t.Dur } }
    $durFeita = 0.0
    $t0 = Get-Date

    try {
        while ($feitos -lt $tot) {

            while ($ativos.Count -lt $Limite -and $prox -lt $tot) {
                $t = $Tarefas[$prox]
                $psi = New-Object System.Diagnostics.ProcessStartInfo
                $psi.FileName               = $t.Exe
                $psi.Arguments              = ((@($t.Args) | ForEach-Object { _Citar $_ }) -join ' ')
                $psi.UseShellExecute        = $false
                $psi.CreateNoWindow         = $true
                $psi.RedirectStandardOutput = $true
                $psi.RedirectStandardError  = $true
                $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
                $psi.StandardErrorEncoding  = [System.Text.Encoding]::UTF8
                $p = [System.Diagnostics.Process]::Start($psi)
                [void]$ativos.Add([pscustomobject]@{
                    Idx   = $prox
                    Rot   = $t.Rotulo
                    Dur   = $(if ($t.Dur) { [double]$t.Dur } else { 0.0 })
                    Proc  = $p
                    Linha = $p.StandardOutput.ReadLineAsync()
                    Err   = $p.StandardError.ReadToEndAsync()
                    Buf   = (New-Object System.Text.StringBuilder)
                    Seg   = 0.0
                    Ini   = (Get-Date)
                })
                $prox++
            }

            # drena stdout sem bloquear (senao o pipe cheio trava o processo)
            foreach ($a in $ativos) {
                while ($a.Linha -and $a.Linha.IsCompleted) {
                    $l = $a.Linha.Result
                    if ($null -eq $l) { $a.Linha = $null; break }
                    [void]$a.Buf.AppendLine($l)
                    if ($l -match '^out_time_us=(\d+)' -or $l -match '^out_time_ms=(\d+)') {
                        $a.Seg = [double]$matches[1] / 1000000.0
                    }
                    $a.Linha = $a.Proc.StandardOutput.ReadLineAsync()
                }
            }

            for ($i = $ativos.Count - 1; $i -ge 0; $i--) {
                $a = $ativos[$i]
                if (-not $a.Proc.HasExited) { continue }
                while ($a.Linha) {
                    $l = $a.Linha.Result
                    if ($null -eq $l) { $a.Linha = $null; break }
                    [void]$a.Buf.AppendLine($l)
                    $a.Linha = $a.Proc.StandardOutput.ReadLineAsync()
                }
                $rc = $a.Proc.ExitCode
                $res[$a.Idx] = [pscustomobject]@{
                    Indice   = $a.Idx
                    Rotulo   = $a.Rot
                    Codigo   = $rc
                    Saida    = $a.Buf.ToString()
                    Erro     = $a.Err.Result
                    Segundos = [math]::Round(((Get-Date) - $a.Ini).TotalSeconds, 1)
                }
                $durFeita += $a.Dur
                try { $a.Proc.Dispose() } catch {}
                $ativos.RemoveAt($i)
                $feitos++
                if ($rc -ne 0) { $falhas++ }
            }

            if (-not $SemProgresso) {
                if ($durTotal -gt 0) {
                    $parcial = $durFeita; foreach ($a in $ativos) { $parcial += $a.Seg }
                    $frac = $parcial / $durTotal
                } else {
                    $frac = $feitos / $tot
                }
                if ($frac -gt 1) { $frac = 1 }
                $pct = [int]($frac * 100)
                $dec = (Get-Date) - $t0
                $eta = if ($frac -gt 0.01) { [TimeSpan]::FromSeconds($dec.TotalSeconds / $frac - $dec.TotalSeconds) } else { [TimeSpan]::Zero }
                $ch  = [int]($pct / 5)
                Write-Host ("`r  [{0}] {1,3}%  {2}/{3}  ativos:{4}  falhas:{5}  restante ~{6:mm\:ss}   " -f `
                    (('#' * $ch) + ('-' * (20 - $ch))), $pct, $feitos, $tot, $ativos.Count, $falhas, $eta) `
                    -NoNewline -ForegroundColor Cyan
            }

            if ($feitos -lt $tot) { Start-Sleep -Milliseconds 150 }
        }
    }
    finally {
        foreach ($a in $ativos) {
            try { if (-not $a.Proc.HasExited) { $a.Proc.Kill() } } catch {}
            try { $a.Proc.Dispose() } catch {}
        }
    }
    if (-not $SemProgresso) { Write-Host '' }
    return $res
}

function Pausar { Write-Host ''; Write-Host 'Pressione Enter para fechar...' -ForegroundColor DarkGray; [void][System.Console]::ReadLine() }
function Titulo($t) {
    Write-Host ''
    Write-Host '============================================================' -ForegroundColor DarkCyan
    Write-Host "  $t" -ForegroundColor Cyan
    Write-Host '============================================================' -ForegroundColor DarkCyan
}

$extImg = @('.jpg','.jpeg','.png','.webp','.bmp','.tif','.tiff')
$configDir  = Join-Path $env:APPDATA 'ImagensEPdf'
$configFile = Join-Path $configDir 'config.json'
function Carregar-Config { if (Test-Path -LiteralPath $configFile) { try { return Get-Content -LiteralPath $configFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch {} }; return $null }
function Salvar-Config($o) { try { New-Item -ItemType Directory -Path $configDir -Force | Out-Null; $o | ConvertTo-Json | Set-Content -LiteralPath $configFile -Encoding UTF8 } catch {} }

Titulo 'Imagens e PDF'
Write-Host '  Desenvolvido por Pablo Murad - 2026' -ForegroundColor DarkGray
Write-Host ''
Write-Host 'Verificando o que é necessário...' -ForegroundColor Gray
$magick = Get-Command magick -ErrorAction SilentlyContinue
if (-not $magick) { Write-Host ''; Write-Host '[ERRO] ImageMagick não encontrado.' -ForegroundColor Red; Write-Host 'Instale com:  winget install ImageMagick.ImageMagick' -ForegroundColor White; Pausar; exit 1 }
Write-Host "[OK] ImageMagick: $($magick.Source)" -ForegroundColor Green
$config = Carregar-Config

Titulo 'O que você quer fazer?'
Write-Host '  [1] Imagens -> PDF   (junta todas as imagens de uma pasta num PDF)' -ForegroundColor White
Write-Host '  [2] PDF -> Imagens   (salva cada página como imagem)' -ForegroundColor White
$acao = $null
while (-not $acao) { $a = Read-Host 'Opção (1-2)'; switch ($a.Trim()) { '1'{$acao='img2pdf'} '2'{$acao='pdf2img'} default{Write-Host '[!] Digite 1 ou 2.' -ForegroundColor Yellow} } }

if ($acao -eq 'img2pdf') {
    # ---- Imagens -> PDF ----
    $pasta = $null
    while (-not $pasta) {
        Titulo 'Pasta com as imagens'
        $p = (Read-Host 'Cole o caminho da pasta').Trim().Trim('"')
        if (Test-Path -LiteralPath $p -PathType Container) { $pasta = (Resolve-Path -LiteralPath $p).Path } else { Write-Host '[!] Pasta não encontrada.' -ForegroundColor Yellow }
    }
    $imagens = @(Get-ChildItem -LiteralPath $pasta -File | Where-Object { $extImg -contains $_.Extension.ToLowerInvariant() } | Sort-Object Name)
    if ($imagens.Count -eq 0) { Write-Host 'Nenhuma imagem nessa pasta.' -ForegroundColor Yellow; Pausar; exit 0 }
    Write-Host ''
    Write-Host "$($imagens.Count) imagens encontradas (em ordem alfabética)." -ForegroundColor Cyan
    $nome = (Read-Host 'Nome do PDF de saída (Enter = saida.pdf)').Trim()
    if ([string]::IsNullOrWhiteSpace($nome)) { $nome = 'saida.pdf' }
    if ($nome -notmatch '\.pdf$') { $nome += '.pdf' }
    $saidaPadrao = if ($config -and $config.UltimaSaidaPdf) { $config.UltimaSaidaPdf } else { $pasta }
    while ($true) {
        Titulo 'Pasta de saída'
        Write-Host "  $saidaPadrao" -ForegroundColor White
        Write-Host 'Enter = usar esta pasta   |   ou cole/digite outra' -ForegroundColor DarkGray
        $rsaida = Read-Host 'Pasta de saída'
        $destino = if ([string]::IsNullOrWhiteSpace($rsaida)) { $saidaPadrao } else { $rsaida.Trim().Trim('"') }
        try { New-Item -ItemType Directory -Path $destino -Force | Out-Null; break }
        catch { Write-Host '[!] Não foi possível criar/usar essa pasta.' -ForegroundColor Yellow }
    }
    $destino = (Resolve-Path -LiteralPath $destino).Path
    Salvar-Config ([pscustomobject]@{ UltimaSaidaPdf=$destino; UltimaSaidaImg=($config.UltimaSaidaImg) })
    $pdf = Join-Path $destino $nome
    Write-Host ''; Write-Host "Gerando: $pdf ..." -ForegroundColor Cyan
    $imgArgs = @($imagens.FullName) + @('-auto-orient', $pdf)
    & magick @imgArgs
    if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $pdf)) {
        Titulo 'Concluído'
        Write-Host "[OK] PDF criado com $($imagens.Count) páginas." -ForegroundColor Green
        Write-Host "Arquivo: $pdf"
    } else { Write-Host '[ERRO] Falha ao gerar o PDF.' -ForegroundColor Red }
    Pausar; exit 0
}

# ---- PDF -> Imagens ----
$pdfAlvo = $null; $modoArquivo = $false
while (-not $pdfAlvo) {
    Titulo 'PDF de entrada'
    $p = (Read-Host 'Cole o caminho de um PDF ou de uma pasta com PDFs').Trim().Trim('"')
    if ((Test-Path -LiteralPath $p -PathType Leaf) -and ($p -match '\.pdf$')) { $pdfAlvo = (Resolve-Path -LiteralPath $p).Path; $modoArquivo = $true }
    elseif (Test-Path -LiteralPath $p -PathType Container) { $pdfAlvo = (Resolve-Path -LiteralPath $p).Path; $modoArquivo = $false }
    else { Write-Host '[!] Caminho inválido (informe um .pdf ou uma pasta).' -ForegroundColor Yellow }
}
Titulo 'Formato das imagens'
Write-Host '  [1] PNG (sem perdas)   [2] JPG (menor)' -ForegroundColor Gray
$fmt = Read-Host 'Formato (Enter = 1)'
$extSaida = if ($fmt.Trim() -eq '2') { '.jpg' } else { '.png' }
$dpiEnt = Read-Host 'Qualidade em DPI (Enter = 150; 300 = alta)'
$dpi = if (($dpiEnt.Trim()) -and ($dpiEnt -as [int])) { [int]$dpiEnt } else { 150 }

if ($modoArquivo) { $pdfs = @(Get-Item -LiteralPath $pdfAlvo) } else { $pdfs = @(Get-ChildItem -LiteralPath $pdfAlvo -File | Where-Object { $_.Extension.ToLowerInvariant() -eq '.pdf' }) }
if ($pdfs.Count -eq 0) { Write-Host 'Nenhum PDF encontrado.' -ForegroundColor Yellow; Pausar; exit 0 }

$baseSaida = if ($modoArquivo) { Split-Path $pdfAlvo -Parent } else { $pdfAlvo }
$saidaPadrao = if ($config -and $config.UltimaSaidaImg) { $config.UltimaSaidaImg } else { $baseSaida }
while ($true) {
    Titulo 'Pasta de saída (base)'
    Write-Host "  $saidaPadrao" -ForegroundColor White
    Write-Host '(cada PDF cria uma subpasta <nome>-imagens aqui dentro)' -ForegroundColor DarkGray
    Write-Host 'Enter = usar esta pasta   |   ou cole/digite outra' -ForegroundColor DarkGray
    $rsaida = Read-Host 'Pasta de saída'
    $destino = if ([string]::IsNullOrWhiteSpace($rsaida)) { $saidaPadrao } else { $rsaida.Trim().Trim('"') }
    try { New-Item -ItemType Directory -Path $destino -Force | Out-Null; break }
    catch { Write-Host '[!] Não foi possível criar/usar essa pasta.' -ForegroundColor Yellow }
}
$destino = (Resolve-Path -LiteralPath $destino).Path
Salvar-Config ([pscustomobject]@{ UltimaSaidaPdf=($config.UltimaSaidaPdf); UltimaSaidaImg=$destino })

Titulo 'Processando'
$ok=0;$err=0
$tarefas = @(); $pastas = @()
foreach ($pf in $pdfs) {
    $outDir = Join-Path $destino ($pf.BaseName + '-imagens')
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    $padraoSaida = Join-Path $outDir ('pagina-%03d' + $extSaida)
    $a = @('-density',"$dpi",$pf.FullName)
    if ($extSaida -eq '.jpg') { $a += @('-quality','90','-background','white','-alpha','remove') }
    $a += $padraoSaida
    $tarefas += @{ Exe='magick'; Rotulo=$pf.Name; Alvo=$outDir; Args=$a }
    $pastas += $outDir
}
if ($tarefas.Count -gt 0) {
    $lim = Limite-Padrao 'imagem'
    Write-Host ("{0} PDF(s), ate {1} ao mesmo tempo..." -f $tarefas.Count, $lim) -ForegroundColor Gray
    $rs = Executar-EmParalelo -Tarefas $tarefas -Limite $lim
    for ($i = 0; $i -lt $tarefas.Count; $i++) {
        $qtd = @(Get-ChildItem -LiteralPath $pastas[$i] -File -ErrorAction SilentlyContinue).Count
        if ($rs[$i].Codigo -eq 0 -and $qtd -gt 0) {
            Write-Host ("  [OK] {0}: {1} pagina(s)" -f $tarefas[$i].Rotulo, $qtd) -ForegroundColor Green
            $ok++
        } else {
            $err++
            Write-Host ("  [ERRO] {0}" -f $tarefas[$i].Rotulo) -ForegroundColor Red
            $motivo = ($rs[$i].Erro -split "`n" | Where-Object { $_.Trim() } | Select-Object -Last 1)
            if ($motivo) { Write-Host ("         {0}" -f $motivo.Trim()) -ForegroundColor DarkGray }
        }
    }
}
Titulo 'Concluído'
Write-Host "PDFs convertidos: $ok" -ForegroundColor Green
Write-Host "Erros: $err" -ForegroundColor $(if ($err -gt 0){'Red'}else{'Gray'})
Pausar
