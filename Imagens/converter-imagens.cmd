<# :
@echo off
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression ([System.IO.File]::ReadAllText('%~f0',[System.Text.Encoding]::UTF8))"
exit /b %errorlevel%
#>

# ============================================================
#  Converter Imagens - redimensiona/converte em lote (ImageMagick)
#  Arquivo único .cmd (auto-executável como PowerShell)
# ============================================================

try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
try { $Host.UI.RawUI.WindowTitle = 'Converter Imagens' } catch {}

function Pausar {
    Write-Host ''
    Write-Host 'Pressione Enter para fechar...' -ForegroundColor DarkGray
    [void][System.Console]::ReadLine()
}

function Titulo($texto) {
    Write-Host ''
    Write-Host '============================================================' -ForegroundColor DarkCyan
    Write-Host "  $texto" -ForegroundColor Cyan
    Write-Host '============================================================' -ForegroundColor DarkCyan
}

# ------------------------------------------------------------
# Configuração persistente (lembra últimas escolhas)
# ------------------------------------------------------------
$configDir  = Join-Path $env:APPDATA 'ConverterImagens'
$configFile = Join-Path $configDir 'config.json'

function Carregar-Config {
    if (Test-Path -LiteralPath $configFile) {
        try { return Get-Content -LiteralPath $configFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}
    }
    return $null
}

function Salvar-Config($entrada, $formato, $modo, $valor, $saida) {
    try {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
        [pscustomobject]@{
            UltimaEntrada   = $entrada
            UltimoFormato   = $formato
            UltimoModo      = $modo
            UltimoValor     = $valor
            UltimaSaida     = $saida
        } | ConvertTo-Json | Set-Content -LiteralPath $configFile -Encoding UTF8
    } catch {}
}

# Formatos de imagem reconhecidos na entrada
$extensoes = @(
    '.jpg', '.jpeg', '.png', '.webp', '.bmp',
    '.gif', '.tif', '.tiff', '.heic', '.heif', '.avif'
)

# Formatos de saída oferecidos
$formatos = @(
    [pscustomobject]@{ Id=1; Nome='Manter formato original'; Desc='Só redimensiona, mantém o tipo do arquivo'; Ext='' },
    [pscustomobject]@{ Id=2; Nome='JPG';  Desc='Fotos, menor tamanho (sem transparência)'; Ext='.jpg'  },
    [pscustomobject]@{ Id=3; Nome='PNG';  Desc='Sem perdas, mantém transparência';         Ext='.png'  },
    [pscustomobject]@{ Id=4; Nome='WebP'; Desc='Ótima compressão, qualidade alta';         Ext='.webp' }
)

# ------------------------------------------------------------
# 1) Verificação de dependências
# ------------------------------------------------------------
Titulo 'Converter Imagens'
Write-Host '  Desenvolvido por Pablo Murad - 2026' -ForegroundColor DarkGray
Write-Host ''
Write-Host 'Verificando o que é necessário...' -ForegroundColor Gray

$magick = Get-Command magick -ErrorAction SilentlyContinue
if (-not $magick) {
    Write-Host ''
    Write-Host '[ERRO] O ImageMagick não foi encontrado no sistema.' -ForegroundColor Red
    Write-Host 'Ele é necessário para converter as imagens.' -ForegroundColor Yellow
    Write-Host ''
    Write-Host 'Para instalar, abra o Terminal / Prompt e rode:' -ForegroundColor Gray
    Write-Host '    winget install ImageMagick.ImageMagick' -ForegroundColor White
    Write-Host ''
    Write-Host 'Depois feche e abra este programa novamente.' -ForegroundColor Gray
    Pausar
    exit 1
}
Write-Host "[OK] ImageMagick encontrado: $($magick.Source)" -ForegroundColor Green

$config = Carregar-Config

# ------------------------------------------------------------
# 2) Escolha da pasta OU de uma imagem única
# ------------------------------------------------------------
$entradaPadrao = Join-Path $env:USERPROFILE 'Downloads\Imagens'
$entradaAtual  = if ($config -and $config.UltimaEntrada) { $config.UltimaEntrada } else { $entradaPadrao }

$modoArquivo  = $false
$arquivoUnico = $null

while ($true) {
    Titulo 'Pasta ou imagem'
    Write-Host 'Caminho atual:' -ForegroundColor Gray
    Write-Host "  $entradaAtual" -ForegroundColor White
    Write-Host ''
    Write-Host 'Enter = confirmar   |   ou cole/digite uma PASTA ou uma IMAGEM' -ForegroundColor DarkGray
    $resp = Read-Host 'Pasta/imagem'

    if (-not [string]::IsNullOrWhiteSpace($resp)) {
        $entradaAtual = $resp.Trim().Trim('"')
    }

    if (Test-Path -LiteralPath $entradaAtual -PathType Leaf) {
        $ext = [System.IO.Path]::GetExtension($entradaAtual).ToLowerInvariant()
        if ($extensoes -notcontains $ext) {
            Write-Host ''
            Write-Host "[!] Esse arquivo não é uma imagem suportada ($ext)." -ForegroundColor Yellow
            continue
        }
        $modoArquivo  = $true
        $arquivoUnico = (Resolve-Path -LiteralPath $entradaAtual).Path
        break
    }
    elseif (Test-Path -LiteralPath $entradaAtual -PathType Container) {
        $modoArquivo = $false
        break
    }

    Write-Host ''
    Write-Host "[!] Caminho não encontrado: $entradaAtual" -ForegroundColor Yellow
    $criar = Read-Host 'Criar como pasta? (s/N)'
    if ($criar -match '^(s|sim|y|yes)$') {
        try {
            New-Item -ItemType Directory -Path $entradaAtual -Force | Out-Null
            Write-Host "[OK] Pasta criada." -ForegroundColor Green
            $modoArquivo = $false
            break
        } catch {
            Write-Host "[ERRO] Não foi possível criar a pasta." -ForegroundColor Red
        }
    }
}

if ($modoArquivo) {
    $arquivoObj = Get-Item -LiteralPath $arquivoUnico
    $origem     = $arquivoObj.DirectoryName
} else {
    $origem     = (Resolve-Path -LiteralPath $entradaAtual).Path
}
$destino = Join-Path $origem 'Convertido'

# ------------------------------------------------------------
# 3) Formato de saída
# ------------------------------------------------------------
$formatoPadrao = if ($config -and $config.UltimoFormato) { [int]$config.UltimoFormato } else { 1 }

Titulo 'Formato de saída'
foreach ($fmt in $formatos) {
    $marca = if ($fmt.Id -eq $formatoPadrao) { '>' } else { ' ' }
    $cor   = if ($fmt.Id -eq $formatoPadrao) { 'White' } else { 'Gray' }
    Write-Host ("{0} [{1}] {2}" -f $marca, $fmt.Id, $fmt.Nome) -ForegroundColor $cor
    Write-Host ("       {0}" -f $fmt.Desc) -ForegroundColor DarkGray
}
Write-Host ''
Write-Host "Enter = usar a opção padrão [$formatoPadrao]" -ForegroundColor DarkGray

$formato = $null
while (-not $formato) {
    $escolha = Read-Host 'Formato (1-4)'
    if ([string]::IsNullOrWhiteSpace($escolha)) { $escolha = "$formatoPadrao" }
    $formato = $formatos | Where-Object { $_.Id -eq ($escolha -as [int]) } | Select-Object -First 1
    if (-not $formato) { Write-Host '[!] Escolha inválida. Digite um número de 1 a 4.' -ForegroundColor Yellow }
}

# ------------------------------------------------------------
# 4) Tamanho: px (maior lado), % ou não redimensionar
# ------------------------------------------------------------
$modoPadrao = if ($config -and $config.UltimoModo) { $config.UltimoModo } else { 'px' }

Titulo 'Tamanho'
Write-Host '  [1] Pixels do maior lado   (ex.: 1920 - a imagem cabe em 1920x1920)' -ForegroundColor Gray
Write-Host '  [2] Porcentagem (%)        (ex.: 50 = metade do tamanho)' -ForegroundColor Gray
Write-Host '  [3] Não redimensionar      (só converter o formato)' -ForegroundColor Gray
Write-Host ''
$rotuloPadrao = switch ($modoPadrao) { 'px' {'1'} 'pct' {'2'} 'none' {'3'} default {'1'} }
Write-Host "Enter = usar o modo padrão [$rotuloPadrao]" -ForegroundColor DarkGray

$modo = $null
while (-not $modo) {
    $op = Read-Host 'Modo (1-3)'
    if ([string]::IsNullOrWhiteSpace($op)) { $op = $rotuloPadrao }
    switch ($op) {
        '1' { $modo = 'px' }
        '2' { $modo = 'pct' }
        '3' { $modo = 'none' }
        default { Write-Host '[!] Escolha inválida. Digite 1, 2 ou 3.' -ForegroundColor Yellow }
    }
}

$valor      = $null
$resizeArg  = $null
$resumoTam  = ''

if ($modo -eq 'px') {
    $valorPadrao = if ($config -and $config.UltimoModo -eq 'px' -and $config.UltimoValor) { $config.UltimoValor } else { '' }
    while (-not $valor) {
        $dica = if ($valorPadrao) { " (Enter = $valorPadrao)" } else { '' }
        $ent = Read-Host "Maior lado em pixels$dica"
        if ([string]::IsNullOrWhiteSpace($ent) -and $valorPadrao) { $ent = "$valorPadrao" }
        $n = $ent -as [int]
        if ($n -and $n -gt 0) { $valor = $n } else { Write-Host '[!] Digite um número de pixels válido (ex.: 1920).' -ForegroundColor Yellow }
    }
    # ">" garante proporcional e NUNCA amplia
    $resizeArg = "$($valor)x$($valor)>"
    $resumoTam = "maior lado $valor px"
}
elseif ($modo -eq 'pct') {
    $valorPadrao = if ($config -and $config.UltimoModo -eq 'pct' -and $config.UltimoValor) { $config.UltimoValor } else { '' }
    while (-not $valor) {
        $dica = if ($valorPadrao) { " (Enter = $valorPadrao)" } else { '' }
        $ent = Read-Host "Porcentagem %$dica"
        if ([string]::IsNullOrWhiteSpace($ent) -and $valorPadrao) { $ent = "$valorPadrao" }
        $p = ($ent -replace '%','') -as [double]
        if ($p -and $p -gt 0) { $valor = $p } else { Write-Host '[!] Digite uma porcentagem válida (ex.: 50).' -ForegroundColor Yellow }
    }
    $resizeArg = "$valor%"
    $resumoTam = "$valor%"
}
else {
    $resumoTam = 'sem redimensionar'
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

Salvar-Config $origem $formato.Id $modo $valor $destino

# ------------------------------------------------------------
# 5) Coleta das imagens
# ------------------------------------------------------------
if ($modoArquivo) {
    $arquivos = @($arquivoObj)
} else {
    $arquivos = @(Get-ChildItem -LiteralPath $origem -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object {
            ($extensoes -contains $_.Extension.ToLowerInvariant()) -and
            (-not $_.FullName.StartsWith($destino, [System.StringComparison]::OrdinalIgnoreCase))
        })
}

Titulo 'Processando'
Write-Host "Pasta:    $origem"
Write-Host "Formato:  $($formato.Nome)"
Write-Host "Tamanho:  $resumoTam"
Write-Host "Destino:  $destino"
Write-Host "Imagens encontradas: $($arquivos.Count)" -ForegroundColor Cyan

if ($arquivos.Count -eq 0) {
    Write-Host ''
    Write-Host 'Nenhuma imagem para converter nesse local.' -ForegroundColor Yellow
    Pausar
    exit 0
}

New-Item -ItemType Directory -Path $destino -Force | Out-Null

$convertidos = 0
$ignorados   = 0
$erros       = 0
$indice      = 0

foreach ($arquivo in $arquivos) {
    $indice++

    $relativo = $arquivo.FullName.Substring($origem.Length).TrimStart('\')
    $subpasta = Split-Path -Path $relativo -Parent
    $pastaSaida = if ([string]::IsNullOrWhiteSpace($subpasta)) { $destino } else { Join-Path $destino $subpasta }
    New-Item -ItemType Directory -Path $pastaSaida -Force | Out-Null

    # Extensão de saída: mantém a original ou usa a do formato escolhido
    $extSaida = if ([string]::IsNullOrEmpty($formato.Ext)) { $arquivo.Extension.ToLowerInvariant() } else { $formato.Ext }
    $saida = Join-Path $pastaSaida ($arquivo.BaseName + $extSaida)

    Write-Host ''
    Write-Host ("[{0}/{1}]" -f $indice, $arquivos.Count) -ForegroundColor Magenta -NoNewline
    Write-Host " $($arquivo.Name)"

    if (Test-Path -LiteralPath $saida) {
        Write-Host "   [IGNORADO] Já existe na pasta de destino." -ForegroundColor Yellow
        $ignorados++
        continue
    }

    # Entrada: para GIF/multiframe indo para formato de imagem única, pega o 1o quadro
    $entradaMagick = $arquivo.FullName
    if ($arquivo.Extension.ToLowerInvariant() -eq '.gif' -and $extSaida -ne '.gif') {
        $entradaMagick = "$($arquivo.FullName)[0]"
    }

    $imgArgs = @($entradaMagick)
    if ($resizeArg) { $imgArgs += @('-resize', $resizeArg) }
    # JPG não tem transparência: achata sobre fundo branco
    if ($extSaida -eq '.jpg' -or $extSaida -eq '.jpeg') {
        $imgArgs += @('-background', 'white', '-alpha', 'remove', '-alpha', 'off')
    }
    if ($extSaida -in '.jpg', '.jpeg', '.webp') {
        $imgArgs += @('-quality', '85')
    }
    $imgArgs += $saida

    & magick @imgArgs

    if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $saida)) {
        Write-Host "   [OK] Convertida." -ForegroundColor Green
        $convertidos++
    } else {
        Write-Host "   [ERRO] Falha ao converter." -ForegroundColor Red
        if (Test-Path -LiteralPath $saida) { Remove-Item -LiteralPath $saida -Force -ErrorAction SilentlyContinue }
        $erros++
    }
}

# ------------------------------------------------------------
# 6) Resumo final
# ------------------------------------------------------------
Titulo 'Concluído'
Write-Host "Convertidas: $convertidos" -ForegroundColor Green
Write-Host "Ignoradas:   $ignorados"  -ForegroundColor Yellow
Write-Host "Erros:       $erros"       -ForegroundColor $(if ($erros -gt 0) { 'Red' } else { 'Gray' })
Write-Host "Destino:     $destino"
Pausar
