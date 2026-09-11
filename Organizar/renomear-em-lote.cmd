<# :
@echo off
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression ([System.IO.File]::ReadAllText('%~f0',[System.Text.Encoding]::UTF8))"
exit /b %errorlevel%
#>

# ============================================================
#  Renomear em lote - por sequência, data ou localizar/substituir
#  Também organiza fotos/arquivos por data em pastas
#  Desenvolvido por Pablo Murad - 2026
# ============================================================

try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
try { $Host.UI.RawUI.WindowTitle = 'Renomear em lote' } catch {}

function Pausar { Write-Host ''; Write-Host 'Pressione Enter para fechar...' -ForegroundColor DarkGray; [void][System.Console]::ReadLine() }
function Titulo($t) {
    Write-Host ''
    Write-Host '============================================================' -ForegroundColor DarkCyan
    Write-Host "  $t" -ForegroundColor Cyan
    Write-Host '============================================================' -ForegroundColor DarkCyan
}
function Nome-Livre($dir,$nome,$reservados) {
    $base=[System.IO.Path]::GetFileNameWithoutExtension($nome); $ext=[System.IO.Path]::GetExtension($nome)
    $t=Join-Path $dir $nome; $n=1
    while ((Test-Path -LiteralPath $t) -or ($reservados -contains $t)) { $t=Join-Path $dir ("$base ($n)$ext"); $n++ }
    return $t
}

$magick = Get-Command magick -ErrorAction SilentlyContinue
$extImgExif = @('.jpg','.jpeg','.tif','.tiff','.heic','.heif','.png','.webp')
function Data-Do-Arquivo($file) {
    if ($magick -and ($extImgExif -contains $file.Extension.ToLowerInvariant())) {
        try {
            $d = & magick identify -format '%[EXIF:DateTimeOriginal]' "$($file.FullName)[0]" 2>$null
            if ($d -and ($d.Trim() -match '^\d{4}:\d{2}:\d{2}\s\d{2}:\d{2}:\d{2}$')) {
                return [datetime]::ParseExact($d.Trim(),'yyyy:MM:dd HH:mm:ss',$null)
            }
        } catch {}
    }
    return $file.LastWriteTime
}

Titulo 'Renomear em lote'
Write-Host '  Desenvolvido por Pablo Murad - 2026' -ForegroundColor DarkGray

$pasta = $null
while (-not $pasta) {
    Write-Host ''
    $p = (Read-Host 'Cole o caminho da pasta').Trim().Trim('"')
    if (Test-Path -LiteralPath $p -PathType Container) { $pasta = (Resolve-Path -LiteralPath $p).Path } else { Write-Host '[!] Pasta não encontrada.' -ForegroundColor Yellow }
}
$arquivos = @(Get-ChildItem -LiteralPath $pasta -File | Sort-Object Name)
if ($arquivos.Count -eq 0) { Write-Host 'Nenhum arquivo nessa pasta.' -ForegroundColor Yellow; Pausar; exit 0 }

Titulo 'Modo de renomeação'
Write-Host '  [1] Sequência         (ex.: Foto_001, Foto_002, ...)' -ForegroundColor White
Write-Host '  [2] Data/hora         (ex.: 2026-09-11_14-30-05)' -ForegroundColor White
Write-Host '  [3] Localizar e substituir no nome' -ForegroundColor White
Write-Host '  [4] Mover para pastas por data (AAAA-MM)' -ForegroundColor White
$modo = $null
while (-not $modo) { $m = Read-Host 'Modo (1-4)'; if ('1','2','3','4' -contains $m.Trim()) { $modo = $m.Trim() } else { Write-Host '[!] Digite 1 a 4.' -ForegroundColor Yellow } }

# Monta o plano: cada item = { Origem ; Destino(caminho completo) }
$reservados = @()
$plano = @()

switch ($modo) {
    '1' {
        $prefixo = Read-Host 'Prefixo (ex.: Foto)'; if ([string]::IsNullOrWhiteSpace($prefixo)) { $prefixo = 'Arquivo' }
        $iniEnt = Read-Host 'Número inicial (Enter = 1)'; $ini = if ($iniEnt -as [int]) { [int]$iniEnt } else { 1 }
        $digEnt = Read-Host 'Quantos dígitos (Enter = 3)'; $dig = if ($digEnt -as [int]) { [int]$digEnt } else { 3 }
        $c = $ini
        foreach ($a in $arquivos) {
            $novo = ('{0}_{1}{2}' -f $prefixo, ($c.ToString().PadLeft($dig,'0')), $a.Extension.ToLowerInvariant())
            $dest = Nome-Livre $pasta $novo $reservados; $reservados += $dest
            $plano += [pscustomobject]@{ Origem=$a; Destino=$dest }; $c++
        }
    }
    '2' {
        foreach ($a in $arquivos) {
            $dt = Data-Do-Arquivo $a
            $novo = ('{0}{1}' -f $dt.ToString('yyyy-MM-dd_HH-mm-ss'), $a.Extension.ToLowerInvariant())
            $dest = Nome-Livre $pasta $novo $reservados; $reservados += $dest
            $plano += [pscustomobject]@{ Origem=$a; Destino=$dest }
        }
    }
    '3' {
        $de = Read-Host 'Localizar (texto no nome)'
        if ([string]::IsNullOrEmpty($de)) { Write-Host 'Nada para localizar.' -ForegroundColor Yellow; Pausar; exit 0 }
        $para = Read-Host 'Substituir por (pode deixar vazio para remover)'
        foreach ($a in $arquivos) {
            if ($a.Name -like "*$de*") {
                $novoNome = $a.Name.Replace($de,$para)
                if ([string]::IsNullOrWhiteSpace([System.IO.Path]::GetFileNameWithoutExtension($novoNome))) { continue }
                $dest = Nome-Livre $pasta $novoNome $reservados; $reservados += $dest
                $plano += [pscustomobject]@{ Origem=$a; Destino=$dest }
            }
        }
        if ($plano.Count -eq 0) { Write-Host "Nenhum arquivo contém '$de'." -ForegroundColor Yellow; Pausar; exit 0 }
    }
    '4' {
        foreach ($a in $arquivos) {
            $dt = Data-Do-Arquivo $a
            $subPasta = Join-Path $pasta $dt.ToString('yyyy-MM')
            $dest = Join-Path $subPasta $a.Name
            $plano += [pscustomobject]@{ Origem=$a; Destino=$dest }
        }
    }
}

# Prévia
Titulo 'Prévia'
$acao = if ($modo -eq '4') { 'MOVER' } else { 'RENOMEAR' }
$mostra = [Math]::Min($plano.Count, 12)
for ($i=0; $i -lt $mostra; $i++) {
    $rel = $plano[$i].Destino.Substring($pasta.Length).TrimStart('\')
    Write-Host ("  {0}" -f $plano[$i].Origem.Name) -ForegroundColor Gray -NoNewline
    Write-Host ("   ->   {0}" -f $rel) -ForegroundColor White
}
if ($plano.Count -gt $mostra) { Write-Host ("  ... e mais {0} arquivo(s)." -f ($plano.Count - $mostra)) -ForegroundColor DarkGray }
Write-Host ''
$ok = Read-Host "$acao $($plano.Count) arquivo(s)? (s/N)"
if ($ok -notmatch '^(s|sim|y|yes)$') { Write-Host 'Cancelado.' -ForegroundColor Yellow; Pausar; exit 0 }

$feitos=0;$err=0
foreach ($p in $plano) {
    try {
        if ($modo -eq '4') {
            $dir = Split-Path $p.Destino -Parent
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            $destFinal = Nome-Livre $dir (Split-Path $p.Destino -Leaf) @()
            Move-Item -LiteralPath $p.Origem.FullName -Destination $destFinal -ErrorAction Stop
        } else {
            Rename-Item -LiteralPath $p.Origem.FullName -NewName (Split-Path $p.Destino -Leaf) -ErrorAction Stop
        }
        $feitos++
    } catch { Write-Host "   [ERRO] $($p.Origem.Name): $($_.Exception.Message)" -ForegroundColor Red; $err++ }
}
Titulo 'Concluído'
Write-Host "Processados: $feitos" -ForegroundColor Green
Write-Host "Erros:       $err" -ForegroundColor $(if ($err -gt 0){'Red'}else{'Gray'})
Write-Host "Pasta:       $pasta"
Pausar
