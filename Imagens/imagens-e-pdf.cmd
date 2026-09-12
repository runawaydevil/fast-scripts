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
foreach ($pf in $pdfs) {
    $outDir = Join-Path $destino ($pf.BaseName + '-imagens')
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    $padraoSaida = Join-Path $outDir ('pagina-%03d' + $extSaida)
    Write-Host ''; Write-Host $pf.Name -ForegroundColor Magenta
    $imgArgs = @('-density',"$dpi",$pf.FullName)
    if ($extSaida -eq '.jpg') { $imgArgs += @('-quality','90','-background','white','-alpha','remove') }
    $imgArgs += $padraoSaida
    & magick @imgArgs
    if ($LASTEXITCODE -eq 0) {
        $qtd = @(Get-ChildItem -LiteralPath $outDir -File).Count
        Write-Host "   [OK] $qtd página(s) -> $outDir" -ForegroundColor Green; $ok++
    } else { Write-Host '   [ERRO] Falha ao converter.' -ForegroundColor Red; $err++ }
}
Titulo 'Concluído'
Write-Host "PDFs convertidos: $ok" -ForegroundColor Green
Write-Host "Erros: $err" -ForegroundColor $(if ($err -gt 0){'Red'}else{'Gray'})
Pausar
