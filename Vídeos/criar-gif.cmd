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

    $ok=0;$err=0;$i=0
    foreach ($v in $videos) {
        $i++
        $saida = Join-Path $destino ($v.BaseName + '.gif')
        Write-Host ''; Write-Host ("[{0}/{1}] {2}" -f $i,$videos.Count,$v.Name) -ForegroundColor Magenta
        if (Test-Path -LiteralPath $saida) { Write-Host '   [IGNORADO] Já existe.' -ForegroundColor Yellow; continue }
        $paleta = Join-Path $env:TEMP ("paleta_{0}.png" -f ([guid]::NewGuid().ToString('N')))
        $filtro = "fps=$fps,scale=${larg}:-1:flags=lanczos"
        & ffmpeg -hide_banner -nostdin -i $v.FullName -vf "$filtro,palettegen" -y $paleta 2>$null
        & ffmpeg -hide_banner -nostdin -i $v.FullName -i $paleta -lavfi "$filtro [x]; [x][1:v] paletteuse" -y $saida 2>$null
        Remove-Item -LiteralPath $paleta -Force -ErrorAction SilentlyContinue
        if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $saida)) { Write-Host '   [OK] GIF criado.' -ForegroundColor Green; $ok++ }
        else { Write-Host '   [ERRO] Falha.' -ForegroundColor Red; if (Test-Path -LiteralPath $saida) { Remove-Item -LiteralPath $saida -Force -ErrorAction SilentlyContinue }; $err++ }
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
