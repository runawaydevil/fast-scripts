<# :
@echo off
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression ([System.IO.File]::ReadAllText('%~f0',[System.Text.Encoding]::UTF8))"
exit /b %errorlevel%
#>

# ============================================================
#  Marca d'água - aplica texto ou logo em imagens (ImageMagick)
#  Desenvolvido por Pablo Murad - 2026
# ============================================================

try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
try { $Host.UI.RawUI.WindowTitle = "Marca d'água" } catch {}

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

$configDir  = Join-Path $env:APPDATA 'MarcaDagua'
$configFile = Join-Path $configDir 'config.json'
function Carregar-Config { if (Test-Path -LiteralPath $configFile) { try { return Get-Content -LiteralPath $configFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch {} }; return $null }
function Salvar-Config($o) { try { New-Item -ItemType Directory -Path $configDir -Force | Out-Null; $o | ConvertTo-Json | Set-Content -LiteralPath $configFile -Encoding UTF8 } catch {} }

$extensoes = @('.jpg','.jpeg','.png','.webp','.bmp','.tif','.tiff')
$posicoes = @(
    [pscustomobject]@{ Id=1; Nome='Inferior direita';  Gravity='SouthEast' },
    [pscustomobject]@{ Id=2; Nome='Inferior esquerda'; Gravity='SouthWest' },
    [pscustomobject]@{ Id=3; Nome='Superior direita';  Gravity='NorthEast' },
    [pscustomobject]@{ Id=4; Nome='Superior esquerda'; Gravity='NorthWest' },
    [pscustomobject]@{ Id=5; Nome='Centro';            Gravity='Center'    }
)

Titulo "Marca d'água"
Write-Host '  Desenvolvido por Pablo Murad - 2026' -ForegroundColor DarkGray
Write-Host ''
Write-Host 'Verificando o que é necessário...' -ForegroundColor Gray
$magick = Get-Command magick -ErrorAction SilentlyContinue
if (-not $magick) { Write-Host ''; Write-Host '[ERRO] ImageMagick não encontrado.' -ForegroundColor Red; Write-Host 'Instale com:  winget install ImageMagick.ImageMagick' -ForegroundColor White; Pausar; exit 1 }
Write-Host "[OK] ImageMagick: $($magick.Source)" -ForegroundColor Green
$config = Carregar-Config

# Pasta ou imagem
$entradaAtual = if ($config -and $config.UltimaEntrada) { $config.UltimaEntrada } else { Join-Path $env:USERPROFILE 'Downloads\Imagens' }
$modoArquivo = $false; $arquivoUnico = $null
while ($true) {
    Titulo 'Pasta ou imagem'
    Write-Host "  $entradaAtual" -ForegroundColor White
    Write-Host 'Enter = confirmar | ou cole uma PASTA ou uma IMAGEM' -ForegroundColor DarkGray
    $resp = Read-Host 'Pasta/imagem'
    if (-not [string]::IsNullOrWhiteSpace($resp)) { $entradaAtual = $resp.Trim().Trim('"') }
    if (Test-Path -LiteralPath $entradaAtual -PathType Leaf) {
        if ($extensoes -notcontains [System.IO.Path]::GetExtension($entradaAtual).ToLowerInvariant()) { Write-Host '[!] Não é uma imagem suportada.' -ForegroundColor Yellow; continue }
        $modoArquivo = $true; $arquivoUnico = (Resolve-Path -LiteralPath $entradaAtual).Path; break
    } elseif (Test-Path -LiteralPath $entradaAtual -PathType Container) { $modoArquivo = $false; break }
    Write-Host '[!] Caminho não encontrado.' -ForegroundColor Yellow
}
if ($modoArquivo) { $arquivoObj = Get-Item -LiteralPath $arquivoUnico; $origem = $arquivoObj.DirectoryName } else { $origem = (Resolve-Path -LiteralPath $entradaAtual).Path }
$destino = Join-Path $origem 'ComMarca'

# Tipo de marca
Titulo "Tipo de marca d'água"
Write-Host '  [1] Texto' -ForegroundColor White
Write-Host '  [2] Logo (arquivo PNG, de preferência com fundo transparente)' -ForegroundColor White
$tipo = $null
while (-not $tipo) { $t = Read-Host 'Tipo (1-2)'; switch ($t.Trim()) { '1'{$tipo='texto'} '2'{$tipo='logo'} default{Write-Host '[!] Digite 1 ou 2.' -ForegroundColor Yellow} } }

$texto = $null; $logo = $null; $pct = 20
if ($tipo -eq 'texto') {
    while ([string]::IsNullOrWhiteSpace($texto)) { $texto = Read-Host 'Texto da marca' }
} else {
    while (-not $logo) {
        $l = (Read-Host 'Caminho do logo (PNG)').Trim().Trim('"')
        if (Test-Path -LiteralPath $l -PathType Leaf) { $logo = (Resolve-Path -LiteralPath $l).Path } else { Write-Host '[!] Arquivo não encontrado.' -ForegroundColor Yellow }
    }
    $p = Read-Host 'Tamanho do logo em % da largura (Enter = 20)'
    if (-not [string]::IsNullOrWhiteSpace($p) -and ($p -as [int])) { $pct = [int]$p }
}

# Posição
Titulo 'Posição'
foreach ($ps in $posicoes) { Write-Host ("  [{0}] {1}" -f $ps.Id,$ps.Nome) -ForegroundColor Gray }
$posicao = $null
while (-not $posicao) { $e = Read-Host 'Posição (1-5, Enter = 1)'; if ([string]::IsNullOrWhiteSpace($e)) { $e = '1' }; $posicao = $posicoes | Where-Object { $_.Id -eq ($e -as [int]) } | Select-Object -First 1; if (-not $posicao) { Write-Host '[!] Inválido.' -ForegroundColor Yellow } }
$grav = $posicao.Gravity
$offset = if ($grav -eq 'Center') { '+0+0' } else { '+25+25' }

# Pasta de saída (lembra a última; cria se não existir)
$saidaPadrao = if ($config -and $config.UltimaSaida) { $config.UltimaSaida } else { $destino }
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

Salvar-Config ([pscustomobject]@{ UltimaEntrada=$origem; UltimoTipo=$tipo; UltimoTexto=$texto; UltimoLogo=$logo; UltimaPosicao=$posicao.Id; UltimaSaida=$destino })

# Coleta
if ($modoArquivo) { $arquivos = @($arquivoObj) } else {
    $arquivos = @(Get-ChildItem -LiteralPath $origem -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
        ($extensoes -contains $_.Extension.ToLowerInvariant()) -and (-not $_.FullName.StartsWith($destino,[System.StringComparison]::OrdinalIgnoreCase)) })
}
Titulo 'Processando'
Write-Host "Marca: $tipo   |   Posição: $($posicao.Nome)   |   Destino: $destino"
Write-Host "Imagens encontradas: $($arquivos.Count)" -ForegroundColor Cyan
if ($arquivos.Count -eq 0) { Write-Host 'Nenhuma imagem encontrada.' -ForegroundColor Yellow; Pausar; exit 0 }
New-Item -ItemType Directory -Path $destino -Force | Out-Null

$ok=0;$ign=0;$err=0

# --- 1) mede as larguras: 1 processo por imagem, porem todos em paralelo ---
$sonda = @()
foreach ($a in $arquivos) { $sonda += @{ Exe='magick'; Rotulo=$a.Name; Args=@('identify','-format','%w',"$($a.FullName)[0]") } }
$larguras = @{}
if ($sonda.Count -gt 0) {
    Write-Host 'Medindo as imagens...' -ForegroundColor Gray
    $rs = Executar-EmParalelo -Tarefas $sonda -Limite (Limite-Padrao 'imagem') -SemProgresso
    for ($i = 0; $i -lt $rs.Count; $i++) {
        $w = 0
        if ($rs[$i] -and $rs[$i].Codigo -eq 0) { $w = ("$($rs[$i].Saida)".Trim() -replace '\D','') -as [int] }
        if (-not $w -or $w -le 0) { $w = 1000 }
        $larguras[$arquivos[$i].FullName] = [int]$w
    }
}

# --- 2) monta as tarefas de composicao ---
$tarefas = @()
foreach ($a in $arquivos) {
    $rel = $a.FullName.Substring($origem.Length).TrimStart('\'); $sub = Split-Path $rel -Parent
    $pastaSaida = if ([string]::IsNullOrWhiteSpace($sub)) { $destino } else { Join-Path $destino $sub }
    New-Item -ItemType Directory -Path $pastaSaida -Force | Out-Null
    $saida = Join-Path $pastaSaida $a.Name
    if (Test-Path -LiteralPath $saida) { $ign++; continue }

    $w = [int]$larguras[$a.FullName]; if ($w -le 0) { $w = 1000 }
    if ($tipo -eq 'texto') {
        $ps = [int]($w / 22); if ($ps -lt 12) { $ps = 12 }
        $imgArgs = @($a.FullName,'-gravity',$grav,'-pointsize',"$ps",'-fill','rgba(255,255,255,0.85)','-undercolor','rgba(0,0,0,0.35)','-annotate',$offset,$texto,$saida)
    } else {
        $lw = [int]($w * $pct / 100); if ($lw -lt 10) { $lw = 10 }
        $imgArgs = @($a.FullName,'(',$logo,'-resize',"${lw}x",')','-gravity',$grav,'-geometry',$offset,'-composite',$saida)
    }
    $tarefas += @{ Exe='magick'; Rotulo=$a.Name; Alvo=$saida; Args=$imgArgs }
}

if ($ign -gt 0) { Write-Host "$ign ja existiam no destino e foram puladas." -ForegroundColor Yellow }

# --- 3) aplica em paralelo ---
if ($tarefas.Count -gt 0) {
    $lim = Limite-Padrao 'imagem'
    Write-Host ("Aplicando em {0} imagem(ns), ate {1} ao mesmo tempo..." -f $tarefas.Count, $lim) -ForegroundColor Gray
    $resultados = Executar-EmParalelo -Tarefas $tarefas -Limite $lim
    foreach ($x in $resultados) {
        $alvo = $tarefas[$x.Indice].Alvo
        if ($x.Codigo -eq 0 -and (Test-Path -LiteralPath $alvo)) { $ok++ }
        else {
            $err++
            Write-Host ("  [ERRO] {0}" -f $x.Rotulo) -ForegroundColor Red
            $motivo = ($x.Erro -split "`n" | Where-Object { $_.Trim() } | Select-Object -Last 1)
            if ($motivo) { Write-Host ("         {0}" -f $motivo.Trim()) -ForegroundColor DarkGray }
            if (Test-Path -LiteralPath $alvo) { Remove-Item -LiteralPath $alvo -Force -ErrorAction SilentlyContinue }
        }
    }
}
Titulo 'Concluído'
Write-Host "Aplicadas: $ok" -ForegroundColor Green
Write-Host "Ignoradas: $ign" -ForegroundColor Yellow
Write-Host "Erros:     $err" -ForegroundColor $(if ($err -gt 0){'Red'}else{'Gray'})
Write-Host "Destino:   $destino"
Pausar
