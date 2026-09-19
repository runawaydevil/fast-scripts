<# :
@echo off
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression ([System.IO.File]::ReadAllText('%~f0',[System.Text.Encoding]::UTF8))"
exit /b %errorlevel%
#>

# ============================================================
#  Baixar Vídeos - download de vídeos/áudio (yt-dlp)
#  Baixa de YouTube, Instagram, TikTok, X, Vimeo e +1000 sites
#  Desenvolvido por Pablo Murad - 2026
# ============================================================

try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
try { $Host.UI.RawUI.WindowTitle = 'Baixar Vídeos' } catch {}

function Pausar { Write-Host ''; Write-Host 'Pressione Enter para fechar...' -ForegroundColor DarkGray; [void][System.Console]::ReadLine() }
function Titulo($t) {
    Write-Host ''
    Write-Host '============================================================' -ForegroundColor DarkCyan
    Write-Host "  $t" -ForegroundColor Cyan
    Write-Host '============================================================' -ForegroundColor DarkCyan
}

$configDir  = Join-Path $env:APPDATA 'BaixarVideos'
$configFile = Join-Path $configDir 'config.json'
function Carregar-Config { if (Test-Path -LiteralPath $configFile) { try { return Get-Content -LiteralPath $configFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch {} }; return $null }
function Salvar-Config($o) { try { New-Item -ItemType Directory -Path $configDir -Force | Out-Null; $o | ConvertTo-Json | Set-Content -LiteralPath $configFile -Encoding UTF8 } catch {} }

# Perfis de qualidade / formato
$perfis = @(
    [pscustomobject]@{ Id=1; Nome='Melhor qualidade (resolução máxima)'; Tipo='video'; Altura=0 },
    [pscustomobject]@{ Id=2; Nome='1080p (Full HD)';                      Tipo='video'; Altura=1080 },
    [pscustomobject]@{ Id=3; Nome='720p (HD)';                            Tipo='video'; Altura=720 },
    [pscustomobject]@{ Id=4; Nome='480p';                                 Tipo='video'; Altura=480 },
    [pscustomobject]@{ Id=5; Nome='360p (compacto)';                      Tipo='video'; Altura=360 },
    [pscustomobject]@{ Id=6; Nome='Só áudio - MP3';                       Tipo='mp3';   Altura=0 },
    [pscustomobject]@{ Id=7; Nome='Só áudio - M4A';                       Tipo='m4a';   Altura=0 }
)

Titulo 'Baixar Vídeos'
Write-Host '  Desenvolvido por Pablo Murad - 2026' -ForegroundColor DarkGray
Write-Host ''
Write-Host 'Verificando o que é necessário...' -ForegroundColor Gray

# ------------------------------------------------------------
# 1) Localizar / baixar o yt-dlp (o baixador mais moderno)
# ------------------------------------------------------------
$localDir = Join-Path $env:LOCALAPPDATA 'fast-scripts'
$localExe = Join-Path $localDir 'yt-dlp.exe'
$ytdlp = $null
$cmd = Get-Command yt-dlp -ErrorAction SilentlyContinue
if ($cmd) { $ytdlp = $cmd.Source }
elseif (Test-Path -LiteralPath $localExe) { $ytdlp = $localExe }
else {
    Write-Host ''
    Write-Host 'yt-dlp não encontrado. Baixando a versão mais recente (site oficial)...' -ForegroundColor Yellow
    try {
        New-Item -ItemType Directory -Path $localDir -Force | Out-Null
        try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
        $url = 'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe'
        Invoke-WebRequest -Uri $url -OutFile $localExe -UseBasicParsing
        $ytdlp = $localExe
        Write-Host '[OK] yt-dlp baixado.' -ForegroundColor Green
    } catch {
        Write-Host "[ERRO] Não foi possível baixar o yt-dlp: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host 'Verifique sua internet e tente de novo.' -ForegroundColor Yellow
        Pausar; exit 1
    }
}
Write-Host "[OK] yt-dlp: $ytdlp" -ForegroundColor Green

# Auto-atualiza SÓ a cópia que este programa baixou (não mexe numa instalação sua)
if ($ytdlp -eq $localExe) {
    $idadeDias = (New-TimeSpan -Start (Get-Item $localExe).LastWriteTime -End (Get-Date)).TotalDays
    if ($idadeDias -gt 15) {
        Write-Host 'Procurando atualização do yt-dlp...' -ForegroundColor Gray
        & $ytdlp -U 2>$null | Out-Null
    }
}

# ffmpeg (necessário p/ juntar vídeo+áudio de alta qualidade e converter áudio)
$ffmpeg = Get-Command ffmpeg -ErrorAction SilentlyContinue
$ffmpegDir = if ($ffmpeg) { Split-Path $ffmpeg.Source -Parent } else { $null }
if ($ffmpeg) { Write-Host "[OK] FFmpeg: $($ffmpeg.Source)" -ForegroundColor Green }
else { Write-Host '[!] FFmpeg não encontrado - alta qualidade e conversão de áudio podem falhar. Instale: winget install Gyan.FFmpeg' -ForegroundColor Yellow }

$config = Carregar-Config

# ------------------------------------------------------------
# 2) Link(s)
# ------------------------------------------------------------
$urls = @()
while ($urls.Count -eq 0) {
    Titulo 'Link do vídeo'
    Write-Host 'Cole o link (ou vários separados por espaço).' -ForegroundColor DarkGray
    Write-Host 'Funciona com YouTube, Instagram, TikTok, X, Vimeo, Facebook e +1000 sites.' -ForegroundColor DarkGray
    $resp = Read-Host 'Link'
    $urls = @($resp -split '\s+' | Where-Object { $_ -match '^https?://' })
    if ($urls.Count -eq 0) { Write-Host '[!] Cole um link válido (começando com http).' -ForegroundColor Yellow }
}

# ------------------------------------------------------------
# 3) Qualidade / formato
# ------------------------------------------------------------
$qPadrao = if ($config -and $config.UltimaQualidade) { [int]$config.UltimaQualidade } else { 1 }
Titulo 'Qualidade / formato'
foreach ($p in $perfis) {
    $m = if ($p.Id -eq $qPadrao) { '>' } else { ' ' }
    $c = if ($p.Id -eq $qPadrao) { 'White' } else { 'Gray' }
    Write-Host ("{0} [{1}] {2}" -f $m, $p.Id, $p.Nome) -ForegroundColor $c
}
Write-Host "Enter = usar a opção padrão [$qPadrao]" -ForegroundColor DarkGray
$perfil = $null
while (-not $perfil) {
    $e = Read-Host 'Qualidade (1-7)'; if ([string]::IsNullOrWhiteSpace($e)) { $e = "$qPadrao" }
    $perfil = $perfis | Where-Object { $_.Id -eq ($e -as [int]) } | Select-Object -First 1
    if (-not $perfil) { Write-Host '[!] Escolha de 1 a 7.' -ForegroundColor Yellow }
}

# ------------------------------------------------------------
# 4) Playlist?
# ------------------------------------------------------------
$plPadrao = if ($config -and $config.UltimaPlaylist) { "$($config.UltimaPlaylist)" } else { 'nao' }
Titulo 'Playlist'
Write-Host 'Se o link fizer parte de uma playlist, baixar a playlist INTEIRA?' -ForegroundColor Gray
$dicaPl = if ($plPadrao -eq 'sim') { '(Enter = SIM)' } else { '(Enter = NÃO)' }
$rpl = Read-Host "Baixar playlist inteira? (s/n) $dicaPl"
$playlist = if ([string]::IsNullOrWhiteSpace($rpl)) { $plPadrao -eq 'sim' } else { $rpl -match '^(s|sim|y|yes)$' }

# ------------------------------------------------------------
# 5) Pasta de saída (lembra a última; cria se não existir)
# ------------------------------------------------------------
$saidaPadrao = if ($config -and $config.UltimaSaida) { $config.UltimaSaida } else { Join-Path $env:USERPROFILE 'Downloads\Baixados' }
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

Salvar-Config ([pscustomobject]@{ UltimaQualidade=$perfil.Id; UltimaPlaylist=$(if ($playlist) {'sim'} else {'nao'}); UltimaSaida=$destino })

# ------------------------------------------------------------
# 6) Monta os argumentos do yt-dlp
# ------------------------------------------------------------
switch ($perfil.Tipo) {
    'mp3' { $fmtArgs = @('-f','ba/b','-x','--audio-format','mp3','--audio-quality','0') }
    'm4a' { $fmtArgs = @('-f','ba/b','-x','--audio-format','m4a') }
    default {
        if ($perfil.Altura -eq 0) { $fmtArgs = @('-f','bv*+ba/b','--merge-output-format','mp4') }
        else { $fmtArgs = @('-f',"bv*[height<=$($perfil.Altura)]+ba/b[height<=$($perfil.Altura)]/b[height<=$($perfil.Altura)]",'--merge-output-format','mp4') }
    }
}

$ytArgs = @()
$ytArgs += $fmtArgs
$ytArgs += @('-o', (Join-Path $destino '%(title)s.%(ext)s'))
$ytArgs += @('--embed-metadata','--embed-thumbnail')     # título, capa, etc.
$ytArgs += @('--no-overwrites')                          # pula o que já foi baixado
$ytArgs += @('--concurrent-fragments','8')               # baixa varios pedacos de uma vez
# O aria2c baixa em muitas conexoes ao mesmo tempo: bem mais rapido quando existe.
$aria = Get-Command aria2c -ErrorAction SilentlyContinue
if ($aria) {
    Write-Host '[OK] aria2c encontrado: download acelerado ligado.' -ForegroundColor Green
    $ytArgs += @('--downloader','aria2c','--downloader-args','aria2c:-x16 -s16 -k1M')
}               # download mais rápido
$ytArgs += @('--ignore-errors')                          # em lote, continua se um falhar
$ytArgs += if ($playlist) { '--yes-playlist' } else { '--no-playlist' }
if ($ffmpegDir) { $ytArgs += @('--ffmpeg-location', $ffmpegDir) }

# ------------------------------------------------------------
# 7) Baixar
# ------------------------------------------------------------
Titulo 'Baixando'
Write-Host "Qualidade: $($perfil.Nome)"
Write-Host "Playlist:  $(if ($playlist) {'sim'} else {'não'})"
Write-Host "Destino:   $destino"
Write-Host "Links:     $($urls.Count)"
Write-Host ''

& $ytdlp @ytArgs @urls
$rc = $LASTEXITCODE

Titulo 'Concluído'
if ($rc -eq 0) { Write-Host '[OK] Download finalizado.' -ForegroundColor Green }
else { Write-Host "[!] Terminou com avisos/erros (código $rc). Alguns itens podem não ter baixado." -ForegroundColor Yellow }
Write-Host "Pasta: $destino"
Pausar
