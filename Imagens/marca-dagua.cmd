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

Salvar-Config ([pscustomobject]@{ UltimaEntrada=$origem; UltimoTipo=$tipo; UltimoTexto=$texto; UltimoLogo=$logo; UltimaPosicao=$posicao.Id })

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

$ok=0;$ign=0;$err=0;$i=0
foreach ($a in $arquivos) {
    $i++
    $rel = $a.FullName.Substring($origem.Length).TrimStart('\'); $sub = Split-Path $rel -Parent
    $pastaSaida = if ([string]::IsNullOrWhiteSpace($sub)) { $destino } else { Join-Path $destino $sub }
    New-Item -ItemType Directory -Path $pastaSaida -Force | Out-Null
    $saida = Join-Path $pastaSaida $a.Name
    Write-Host ''; Write-Host ("[{0}/{1}] {2}" -f $i,$arquivos.Count,$a.Name) -ForegroundColor Magenta
    if (Test-Path -LiteralPath $saida) { Write-Host '   [IGNORADO] Já existe.' -ForegroundColor Yellow; $ign++; continue }

    if ($tipo -eq 'texto') {
        $w = [int](& magick identify -format '%w' "$($a.FullName)[0]" 2>$null)
        if (-not $w -or $w -le 0) { $w = 1000 }
        $ps = [int]($w / 22); if ($ps -lt 12) { $ps = 12 }
        $imgArgs = @($a.FullName,'-gravity',$grav,'-pointsize',"$ps",'-fill','rgba(255,255,255,0.85)','-undercolor','rgba(0,0,0,0.35)','-annotate',$offset,$texto,$saida)
    } else {
        $w = [int](& magick identify -format '%w' "$($a.FullName)[0]" 2>$null)
        if (-not $w -or $w -le 0) { $w = 1000 }
        $lw = [int]($w * $pct / 100); if ($lw -lt 10) { $lw = 10 }
        $imgArgs = @($a.FullName,'(',$logo,'-resize',"${lw}x",')','-gravity',$grav,'-geometry',$offset,'-composite',$saida)
    }
    & magick @imgArgs
    if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $saida)) { Write-Host '   [OK] Marca aplicada.' -ForegroundColor Green; $ok++ }
    else { Write-Host '   [ERRO] Falha.' -ForegroundColor Red; if (Test-Path -LiteralPath $saida) { Remove-Item -LiteralPath $saida -Force -ErrorAction SilentlyContinue }; $err++ }
}
Titulo 'Concluído'
Write-Host "Aplicadas: $ok" -ForegroundColor Green
Write-Host "Ignoradas: $ign" -ForegroundColor Yellow
Write-Host "Erros:     $err" -ForegroundColor $(if ($err -gt 0){'Red'}else{'Gray'})
Write-Host "Destino:   $destino"
Pausar
