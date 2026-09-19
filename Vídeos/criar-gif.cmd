<# :
@echo off
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression ([System.IO.File]::ReadAllText('%~f0',[System.Text.Encoding]::UTF8))"
exit /b %errorlevel%
#>

# ============================================================
#  Criar GIF / Slideshow - vídeo -> GIF, ou fotos -> vídeo (FFmpeg)
#  Desenvolvido por Pablo Murad - 2026
# ============================================================

try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
try { $Host.UI.RawUI.WindowTitle = 'Criar GIF / Slideshow' } catch {}

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

$configDir  = Join-Path $env:APPDATA 'CriarGif'
$configFile = Join-Path $configDir 'config.json'
function Carregar-Config { if (Test-Path -LiteralPath $configFile) { try { return Get-Content -LiteralPath $configFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch {} }; return $null }
function Salvar-Config($o) { try { New-Item -ItemType Directory -Path $configDir -Force | Out-Null; $o | ConvertTo-Json | Set-Content -LiteralPath $configFile -Encoding UTF8 } catch {} }

function Relatar($resultados, $tarefas, [ref]$ok, [ref]$err) {
    foreach ($x in $resultados) {
        $alvo = $tarefas[$x.Indice].Alvo
        if ($x.Codigo -eq 0 -and (Test-Path -LiteralPath $alvo)) { $ok.Value++ }
        else {
            $err.Value++
            Write-Host ("  [ERRO] {0}" -f $x.Rotulo) -ForegroundColor Red
            $motivo = ($x.Erro -split "`n" | Where-Object { $_.Trim() } | Select-Object -Last 1)
            if ($motivo) { Write-Host ("         {0}" -f $motivo.Trim()) -ForegroundColor DarkGray }
            if (Test-Path -LiteralPath $alvo) { Remove-Item -LiteralPath $alvo -Force -ErrorAction SilentlyContinue }
        }
    }
}
$extVideo = @('.mp4','.mkv','.avi','.mov','.wmv','.flv','.webm','.m4v','.mpg','.mpeg','.ts','.3gp','.vob')
$extImg   = @('.jpg','.jpeg','.png','.webp','.bmp','.tif','.tiff')

Titulo 'Criar GIF / Slideshow'
Write-Host '  Desenvolvido por Pablo Murad - 2026' -ForegroundColor DarkGray
Write-Host ''
Write-Host 'Verificando o que é necessário...' -ForegroundColor Gray
$ffmpeg = Get-Command ffmpeg -ErrorAction SilentlyContinue
if (-not $ffmpeg) { Write-Host ''; Write-Host '[ERRO] FFmpeg não encontrado.' -ForegroundColor Red; Write-Host 'Instale com:  winget install Gyan.FFmpeg' -ForegroundColor White; Pausar; exit 1 }
Write-Host "[OK] FFmpeg: $($ffmpeg.Source)" -ForegroundColor Green
$config = Carregar-Config

Titulo 'O que você quer fazer?'
Write-Host '  [1] Vídeo -> GIF' -ForegroundColor White
Write-Host '  [2] Fotos (pasta) -> vídeo (slideshow)' -ForegroundColor White
$acao = $null
while (-not $acao) { $a = Read-Host 'Opção (1-2)'; switch ($a.Trim()) { '1'{$acao='gif'} '2'{$acao='slide'} default{Write-Host '[!] Digite 1 ou 2.' -ForegroundColor Yellow} } }

if ($acao -eq 'gif') {
    # ---------------- Vídeo -> GIF ----------------
    $entrada = $null; $modoArquivo = $false; $arquivoUnico = $null
    while (-not $entrada) {
        Titulo 'Pasta ou vídeo'
        $p = (Read-Host 'Cole o caminho de um VÍDEO ou de uma PASTA').Trim().Trim('"')
        if (Test-Path -LiteralPath $p -PathType Leaf) {
            if ($extVideo -notcontains [System.IO.Path]::GetExtension($p).ToLowerInvariant()) { Write-Host '[!] Não é um vídeo suportado.' -ForegroundColor Yellow; continue }
            $entrada = (Resolve-Path -LiteralPath $p).Path; $modoArquivo = $true; $arquivoUnico = $entrada
        } elseif (Test-Path -LiteralPath $p -PathType Container) { $entrada = (Resolve-Path -LiteralPath $p).Path }
        else { Write-Host '[!] Caminho não encontrado.' -ForegroundColor Yellow }
    }
    $lEnt = Read-Host 'Largura do GIF em px (Enter = 480)'; $larg = if ($lEnt -as [int]) { [int]$lEnt } else { 480 }
    $fEnt = Read-Host 'Quadros por segundo / FPS (Enter = 12)'; $fps = if ($fEnt -as [int]) { [int]$fEnt } else { 12 }

    if ($modoArquivo) { $arquivoObj = Get-Item -LiteralPath $arquivoUnico; $origem = $arquivoObj.DirectoryName; $videos = @($arquivoObj) }
    else { $origem = $entrada; $videos = @(Get-ChildItem -LiteralPath $origem -File | Where-Object { $extVideo -contains $_.Extension.ToLowerInvariant() }) }
    $destino = Join-Path $origem 'GIF'

    # Pasta de saída (lembra a última; cria se não existir)
    $saidaPadrao = if ($config -and $config.UltimaSaidaGif) { $config.UltimaSaidaGif } else { $destino }
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
    Salvar-Config ([pscustomobject]@{ UltimaSaidaGif=$destino; UltimaSaidaSlide=($config.UltimaSaidaSlide) })

    Titulo 'Processando'
    Write-Host "Largura: $larg px   |   FPS: $fps   |   Destino: $destino"
    Write-Host "Vídeos: $($videos.Count)" -ForegroundColor Cyan
    if ($videos.Count -eq 0) { Write-Host 'Nenhum vídeo encontrado.' -ForegroundColor Yellow; Pausar; exit 0 }
    New-Item -ItemType Directory -Path $destino -Force | Out-Null

    $ok=0;$ign=0;$err=0

    # Cada GIF exige 2 passagens (gerar paleta + aplicar). Fazemos as duas
    # fases em paralelo, em vez de 2 processos em serie por video.
    $alvos = @()
    foreach ($v in $videos) {
        $saida = Join-Path $destino ($v.BaseName + '.gif')
        if (Test-Path -LiteralPath $saida) { $ign++; continue }
        $alvos += [pscustomobject]@{
            Video  = $v
            Saida  = $saida
            Paleta = Join-Path $env:TEMP ("paleta_{0}.png" -f ([guid]::NewGuid().ToString('N')))
            Filtro = "fps=$fps,scale=${larg}:-1:flags=lanczos"
        }
    }
    if ($ign -gt 0) { Write-Host "$ign ja existiam no destino e foram pulados." -ForegroundColor Yellow }

    if ($alvos.Count -gt 0) {
        $lim = Limite-Padrao 'cpu'
        Write-Host ("{0} video(s), ate {1} ao mesmo tempo..." -f $alvos.Count, $lim) -ForegroundColor Gray

        Write-Host '  Fase 1/2: gerando as paletas de cor...' -ForegroundColor DarkGray
        $t1 = @()
        foreach ($a in $alvos) {
            $t1 += @{ Exe='ffmpeg'; Rotulo=$a.Video.Name; Alvo=$a.Paleta
                      Args=@('-hide_banner','-nostdin','-loglevel','error','-i',$a.Video.FullName,'-vf',"$($a.Filtro),palettegen",'-y',$a.Paleta) }
        }
        $r1 = Executar-EmParalelo -Tarefas $t1 -Limite $lim

        Write-Host '  Fase 2/2: montando os GIFs...' -ForegroundColor DarkGray
        $t2 = @(); $mapa = @()
        for ($i = 0; $i -lt $alvos.Count; $i++) {
            if ($r1[$i].Codigo -ne 0 -or -not (Test-Path -LiteralPath $alvos[$i].Paleta)) {
                $err++
                Write-Host ("  [ERRO] {0} (paleta)" -f $alvos[$i].Video.Name) -ForegroundColor Red
                continue
            }
            $a = $alvos[$i]
            $t2 += @{ Exe='ffmpeg'; Rotulo=$a.Video.Name; Alvo=$a.Saida
                      Args=@('-hide_banner','-nostdin','-loglevel','error','-i',$a.Video.FullName,'-i',$a.Paleta,
                             '-lavfi',"$($a.Filtro) [x]; [x][1:v] paletteuse",'-y',$a.Saida) }
            $mapa += $a
        }
        if ($t2.Count -gt 0) {
            $r2 = Executar-EmParalelo -Tarefas $t2 -Limite $lim
            Relatar $r2 $t2 ([ref]$ok) ([ref]$err)
        }
        foreach ($a in $alvos) { if (Test-Path -LiteralPath $a.Paleta) { Remove-Item -LiteralPath $a.Paleta -Force -ErrorAction SilentlyContinue } }
    }
    Titulo 'Concluído'
    Write-Host "GIFs criados: $ok" -ForegroundColor Green
    Write-Host "Erros: $err" -ForegroundColor $(if ($err -gt 0){'Red'}else{'Gray'})
    Write-Host "Destino: $destino"
    Pausar; exit 0
}

# ---------------- Fotos -> vídeo (slideshow) ----------------
$pasta = $null
while (-not $pasta) {
    Titulo 'Pasta com as fotos'
    $p = (Read-Host 'Cole o caminho da pasta').Trim().Trim('"')
    if (Test-Path -LiteralPath $p -PathType Container) { $pasta = (Resolve-Path -LiteralPath $p).Path } else { Write-Host '[!] Pasta não encontrada.' -ForegroundColor Yellow }
}
$fotos = @(Get-ChildItem -LiteralPath $pasta -File | Where-Object { $extImg -contains $_.Extension.ToLowerInvariant() } | Sort-Object Name)
if ($fotos.Count -eq 0) { Write-Host 'Nenhuma imagem nessa pasta.' -ForegroundColor Yellow; Pausar; exit 0 }
Write-Host ''; Write-Host "$($fotos.Count) fotos encontradas (em ordem alfabética)." -ForegroundColor Cyan

$sEnt = Read-Host 'Segundos por foto (Enter = 2)'; $seg = if ($sEnt -as [double]) { [double]$sEnt } else { 2 }
$nome = (Read-Host 'Nome do vídeo de saída (Enter = slideshow.mp4)').Trim()
if ([string]::IsNullOrWhiteSpace($nome)) { $nome = 'slideshow.mp4' }
if ($nome -notmatch '\.mp4$') { $nome += '.mp4' }
# Pasta de saída (lembra a última; cria se não existir)
$saidaPadrao = if ($config -and $config.UltimaSaidaSlide) { $config.UltimaSaidaSlide } else { $pasta }
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
Salvar-Config ([pscustomobject]@{ UltimaSaidaGif=($config.UltimaSaidaGif); UltimaSaidaSlide=$destino })
$saida = Join-Path $destino $nome

# Monta arquivo de lista para o demuxer concat (caminhos com / e aspas)
$listaTxt = Join-Path $env:TEMP ("slide_{0}.txt" -f ([guid]::NewGuid().ToString('N')))
$sb = New-Object System.Text.StringBuilder
foreach ($f in $fotos) {
    $cam = $f.FullName -replace '\\','/'
    [void]$sb.AppendLine("file '$cam'")
    [void]$sb.AppendLine("duration $seg")
}
# repete a última foto (exigência do concat p/ respeitar a última duração)
$ultimo = $fotos[-1].FullName -replace '\\','/'
[void]$sb.AppendLine("file '$ultimo'")
[System.IO.File]::WriteAllText($listaTxt, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))

Titulo 'Gerando slideshow'
Write-Host "Saída: $saida" -ForegroundColor Cyan
$vf = 'scale=1280:720:force_original_aspect_ratio=decrease,pad=1280:720:(ow-iw)/2:(oh-ih)/2:color=black,format=yuv420p'
& ffmpeg -hide_banner -nostdin -f concat -safe 0 -i $listaTxt -vf $vf -r 30 -c:v libx264 -preset medium -crf 20 -movflags +faststart -y $saida 2>$null
$rc = $LASTEXITCODE
Remove-Item -LiteralPath $listaTxt -Force -ErrorAction SilentlyContinue

Titulo 'Concluído'
if ($rc -eq 0 -and (Test-Path -LiteralPath $saida)) {
    Write-Host "[OK] Slideshow criado com $($fotos.Count) fotos." -ForegroundColor Green
    Write-Host "Arquivo: $saida"
} else { Write-Host '[ERRO] Falha ao gerar o slideshow.' -ForegroundColor Red }
Pausar
