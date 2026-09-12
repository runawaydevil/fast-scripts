<# :
@echo off
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression ([System.IO.File]::ReadAllText('%~f0',[System.Text.Encoding]::UTF8))"
exit /b %errorlevel%
#>

# ============================================================
#  Extrair Áudio - tira o áudio de vídeos (FFmpeg)
#  Desenvolvido por Pablo Murad - 2026
# ============================================================

try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
try { $Host.UI.RawUI.WindowTitle = 'Extrair Áudio' } catch {}

function Pausar { Write-Host ''; Write-Host 'Pressione Enter para fechar...' -ForegroundColor DarkGray; [void][System.Console]::ReadLine() }
function Titulo($t) {
    Write-Host ''
    Write-Host '============================================================' -ForegroundColor DarkCyan
    Write-Host "  $t" -ForegroundColor Cyan
    Write-Host '============================================================' -ForegroundColor DarkCyan
}

$configDir  = Join-Path $env:APPDATA 'ExtrairAudio'
$configFile = Join-Path $configDir 'config.json'
function Carregar-Config { if (Test-Path -LiteralPath $configFile) { try { return Get-Content -LiteralPath $configFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch {} }; return $null }
function Salvar-Config($e,$f,$s) { try { New-Item -ItemType Directory -Path $configDir -Force | Out-Null; [pscustomobject]@{ UltimaEntrada=$e; UltimoFormato=$f; UltimaSaida=$s } | ConvertTo-Json | Set-Content -LiteralPath $configFile -Encoding UTF8 } catch {} }

$extensoes = @('.mp4','.mkv','.avi','.mov','.wmv','.flv','.webm','.m4v','.mpg','.mpeg','.mts','.m2ts','.ts','.3gp','.vob')

$formatos = @(
    [pscustomobject]@{ Id=1; Nome='MP3';       Desc='Compatível com tudo (192 kbps)';    Ext='.mp3'; Args=@('-c:a','libmp3lame','-b:a','192k') },
    [pscustomobject]@{ Id=2; Nome='M4A (AAC)';  Desc='Ótima qualidade x tamanho (192 kbps)'; Ext='.m4a'; Args=@('-c:a','aac','-b:a','192k') },
    [pscustomobject]@{ Id=3; Nome='WAV';        Desc='Sem compressão (arquivo grande)';   Ext='.wav'; Args=@('-c:a','pcm_s16le') }
)

Titulo 'Extrair Áudio'
Write-Host '  Desenvolvido por Pablo Murad - 2026' -ForegroundColor DarkGray
Write-Host ''
Write-Host 'Verificando o que é necessário...' -ForegroundColor Gray
$ffmpeg = Get-Command ffmpeg -ErrorAction SilentlyContinue
if (-not $ffmpeg) {
    Write-Host ''; Write-Host '[ERRO] FFmpeg não encontrado.' -ForegroundColor Red
    Write-Host 'Instale com:  winget install Gyan.FFmpeg' -ForegroundColor White
    Pausar; exit 1
}
Write-Host "[OK] FFmpeg: $($ffmpeg.Source)" -ForegroundColor Green
$config = Carregar-Config

# Pasta ou vídeo
$entradaAtual = if ($config -and $config.UltimaEntrada) { $config.UltimaEntrada } else { Join-Path $env:USERPROFILE 'Downloads\Vídeos' }
$modoArquivo = $false; $arquivoUnico = $null
while ($true) {
    Titulo 'Pasta ou vídeo'
    Write-Host "  $entradaAtual" -ForegroundColor White
    Write-Host 'Enter = confirmar | ou cole uma PASTA ou um VÍDEO' -ForegroundColor DarkGray
    $resp = Read-Host 'Pasta/vídeo'
    if (-not [string]::IsNullOrWhiteSpace($resp)) { $entradaAtual = $resp.Trim().Trim('"') }
    if (Test-Path -LiteralPath $entradaAtual -PathType Leaf) {
        if ($extensoes -notcontains [System.IO.Path]::GetExtension($entradaAtual).ToLowerInvariant()) { Write-Host '[!] Não é um vídeo suportado.' -ForegroundColor Yellow; continue }
        $modoArquivo = $true; $arquivoUnico = (Resolve-Path -LiteralPath $entradaAtual).Path; break
    } elseif (Test-Path -LiteralPath $entradaAtual -PathType Container) { $modoArquivo = $false; break }
    Write-Host "[!] Caminho não encontrado." -ForegroundColor Yellow
}
if ($modoArquivo) { $arquivoObj = Get-Item -LiteralPath $arquivoUnico; $origem = $arquivoObj.DirectoryName } else { $origem = (Resolve-Path -LiteralPath $entradaAtual).Path }
$destino = Join-Path $origem 'Áudio'

# Formato
$fmtPadrao = if ($config -and $config.UltimoFormato) { [int]$config.UltimoFormato } else { 1 }
Titulo 'Formato do áudio'
foreach ($f in $formatos) {
    $m = if ($f.Id -eq $fmtPadrao) { '>' } else { ' ' }
    $c = if ($f.Id -eq $fmtPadrao) { 'White' } else { 'Gray' }
    Write-Host ("{0} [{1}] {2}" -f $m,$f.Id,$f.Nome) -ForegroundColor $c
    Write-Host ("       {0}" -f $f.Desc) -ForegroundColor DarkGray
}
Write-Host "Enter = padrão [$fmtPadrao]" -ForegroundColor DarkGray
$formato = $null
while (-not $formato) {
    $e = Read-Host 'Formato (1-3)'; if ([string]::IsNullOrWhiteSpace($e)) { $e = "$fmtPadrao" }
    $formato = $formatos | Where-Object { $_.Id -eq ($e -as [int]) } | Select-Object -First 1
    if (-not $formato) { Write-Host '[!] Inválido.' -ForegroundColor Yellow }
}
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

Salvar-Config $origem $formato.Id $destino

# Coleta
if ($modoArquivo) { $arquivos = @($arquivoObj) } else {
    $arquivos = @(Get-ChildItem -LiteralPath $origem -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
        ($extensoes -contains $_.Extension.ToLowerInvariant()) -and (-not $_.FullName.StartsWith($destino,[System.StringComparison]::OrdinalIgnoreCase)) })
}
Titulo 'Processando'
Write-Host "Formato: $($formato.Nome)   |   Destino: $destino"
Write-Host "Vídeos encontrados: $($arquivos.Count)" -ForegroundColor Cyan
if ($arquivos.Count -eq 0) { Write-Host 'Nenhum vídeo encontrado.' -ForegroundColor Yellow; Pausar; exit 0 }
New-Item -ItemType Directory -Path $destino -Force | Out-Null

$ok=0;$ign=0;$err=0;$i=0
foreach ($a in $arquivos) {
    $i++
    $rel = $a.FullName.Substring($origem.Length).TrimStart('\'); $sub = Split-Path $rel -Parent
    $pastaSaida = if ([string]::IsNullOrWhiteSpace($sub)) { $destino } else { Join-Path $destino $sub }
    New-Item -ItemType Directory -Path $pastaSaida -Force | Out-Null
    $saida = Join-Path $pastaSaida ($a.BaseName + $formato.Ext)
    Write-Host ''; Write-Host ("[{0}/{1}] {2}" -f $i,$arquivos.Count,$a.Name) -ForegroundColor Magenta
    if (Test-Path -LiteralPath $saida) { Write-Host '   [IGNORADO] Já existe.' -ForegroundColor Yellow; $ign++; continue }
    $ffArgs = @('-hide_banner','-nostdin','-i',$a.FullName,'-vn') + $formato.Args + @('-y',$saida)
    & ffmpeg @ffArgs
    if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $saida)) { Write-Host '   [OK] Áudio extraído.' -ForegroundColor Green; $ok++ }
    else { Write-Host '   [ERRO] Falha (o vídeo tem áudio?).' -ForegroundColor Red; if (Test-Path -LiteralPath $saida) { Remove-Item -LiteralPath $saida -Force -ErrorAction SilentlyContinue }; $err++ }
}
Titulo 'Concluído'
Write-Host "Extraídos: $ok" -ForegroundColor Green
Write-Host "Ignorados: $ign" -ForegroundColor Yellow
Write-Host "Erros:     $err" -ForegroundColor $(if ($err -gt 0){'Red'}else{'Gray'})
Write-Host "Destino:   $destino"
Pausar
