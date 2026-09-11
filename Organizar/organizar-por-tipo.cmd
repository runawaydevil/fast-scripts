<# :
@echo off
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression ([System.IO.File]::ReadAllText('%~f0',[System.Text.Encoding]::UTF8))"
exit /b %errorlevel%
#>

# ============================================================
#  Organizar por tipo - separa arquivos em subpastas por categoria
#  Desenvolvido por Pablo Murad - 2026
# ============================================================

try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
try { $Host.UI.RawUI.WindowTitle = 'Organizar por tipo' } catch {}

function Pausar { Write-Host ''; Write-Host 'Pressione Enter para fechar...' -ForegroundColor DarkGray; [void][System.Console]::ReadLine() }
function Titulo($t) {
    Write-Host ''
    Write-Host '============================================================' -ForegroundColor DarkCyan
    Write-Host "  $t" -ForegroundColor Cyan
    Write-Host '============================================================' -ForegroundColor DarkCyan
}
function Nome-Livre($dir,$nome) {
    $base=[System.IO.Path]::GetFileNameWithoutExtension($nome); $ext=[System.IO.Path]::GetExtension($nome)
    $t=Join-Path $dir $nome; $n=1
    while (Test-Path -LiteralPath $t) { $t=Join-Path $dir ("$base ($n)$ext"); $n++ }
    return $t
}

# Mapa extensão -> categoria
$categorias = [ordered]@{
    'Imagens'     = @('.jpg','.jpeg','.png','.gif','.webp','.bmp','.tif','.tiff','.heic','.heif','.svg','.raw','.cr2','.nef')
    'Vídeos'      = @('.mp4','.mkv','.avi','.mov','.wmv','.flv','.webm','.m4v','.mpg','.mpeg','.ts','.3gp','.vob')
    'Áudio'       = @('.mp3','.m4a','.wav','.flac','.aac','.ogg','.wma','.opus')
    'Documentos'  = @('.pdf','.doc','.docx','.xls','.xlsx','.ppt','.pptx','.txt','.odt','.ods','.csv','.rtf','.md','.epub')
    'Compactados' = @('.zip','.rar','.7z','.tar','.gz','.bz2','.xz')
    'Programas'   = @('.exe','.msi','.bat','.cmd','.ps1')
}

Titulo 'Organizar por tipo'
Write-Host '  Desenvolvido por Pablo Murad - 2026' -ForegroundColor DarkGray

$pasta = $null
while (-not $pasta) {
    Write-Host ''
    $p = (Read-Host 'Cole o caminho da pasta a organizar').Trim().Trim('"')
    if (Test-Path -LiteralPath $p -PathType Container) { $pasta = (Resolve-Path -LiteralPath $p).Path } else { Write-Host '[!] Pasta não encontrada.' -ForegroundColor Yellow }
}

# Só arquivos no primeiro nível (não entra em subpastas)
$nomesCategorias = @($categorias.Keys) + 'Outros'
$arquivos = @(Get-ChildItem -LiteralPath $pasta -File)
if ($arquivos.Count -eq 0) { Write-Host 'Nenhum arquivo solto nessa pasta.' -ForegroundColor Yellow; Pausar; exit 0 }

# Descobre a categoria de cada arquivo
function Categoria-De($ext) {
    foreach ($cat in $categorias.Keys) { if ($categorias[$cat] -contains $ext) { return $cat } }
    return 'Outros'
}
$planos = foreach ($a in $arquivos) {
    [pscustomobject]@{ Arquivo=$a; Categoria=(Categoria-De $a.Extension.ToLowerInvariant()) }
}

Titulo 'Prévia'
$planos | Group-Object Categoria | Sort-Object Name | ForEach-Object {
    Write-Host ("  {0,-14} {1} arquivo(s)" -f $_.Name, $_.Count) -ForegroundColor Gray
}
Write-Host ''
$ok = Read-Host "Mover $($arquivos.Count) arquivo(s) para subpastas por categoria? (s/N)"
if ($ok -notmatch '^(s|sim|y|yes)$') { Write-Host 'Cancelado.' -ForegroundColor Yellow; Pausar; exit 0 }

$movidos=0;$err=0
foreach ($pl in $planos) {
    $destPasta = Join-Path $pasta $pl.Categoria
    New-Item -ItemType Directory -Path $destPasta -Force | Out-Null
    $destino = Nome-Livre $destPasta $pl.Arquivo.Name
    try { Move-Item -LiteralPath $pl.Arquivo.FullName -Destination $destino -ErrorAction Stop; $movidos++ }
    catch { Write-Host "   [ERRO] $($pl.Arquivo.Name): $($_.Exception.Message)" -ForegroundColor Red; $err++ }
}
Titulo 'Concluído'
Write-Host "Movidos: $movidos" -ForegroundColor Green
Write-Host "Erros:   $err" -ForegroundColor $(if ($err -gt 0){'Red'}else{'Gray'})
Write-Host "Pasta:   $pasta"
Pausar
