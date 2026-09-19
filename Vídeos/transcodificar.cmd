<# :
@echo off
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression ([System.IO.File]::ReadAllText('%~f0',[System.Text.Encoding]::UTF8))"
exit /b %errorlevel%
#>

# ============================================================
#  Transcodificar - conversor de vídeos em lote (FFmpeg)
#  Arquivo único .cmd (auto-executável como PowerShell)
# ============================================================

try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
try { $Host.UI.RawUI.WindowTitle = 'Transcodificar Vídeos' } catch {}

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
# Configuração persistente (lembra última pasta e qualidade)
# ------------------------------------------------------------
$configDir  = Join-Path $env:APPDATA 'Transcodificar'
$configFile = Join-Path $configDir 'config.json'

function Carregar-Config {
    if (Test-Path -LiteralPath $configFile) {
        try { return Get-Content -LiteralPath $configFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}
    }
    return $null
}

function Salvar-Config($pasta, $qualidade, $saida, $motor) {
    try {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
        [pscustomobject]@{ UltimaPasta = $pasta; UltimaQualidade = $qualidade; UltimaSaida = $saida; UltimoMotor = $motor } |
            ConvertTo-Json | Set-Content -LiteralPath $configFile -Encoding UTF8
    } catch {}
}

# ------------------------------------------------------------
# Perfis de qualidade (o menor/compacto é o último - padrão)
# ------------------------------------------------------------
$perfis = @(
    [pscustomobject]@{ Id=1; Nome='Máxima (resolução original)'; Desc='Mantém a resolução, altíssima qualidade';     Altura=0;    Crf=18; Audio='192k' },
    [pscustomobject]@{ Id=2; Nome='Alta (1080p)';                Desc='Full HD, ótima qualidade';                     Altura=1080; Crf=20; Audio='160k' },
    [pscustomobject]@{ Id=3; Nome='Média (720p)';                Desc='HD, bom equilíbrio tamanho x qualidade';       Altura=720;  Crf=23; Audio='128k' },
    [pscustomobject]@{ Id=4; Nome='Baixa (480p)';                Desc='Arquivo leve, qualidade razoável';             Altura=480;  Crf=26; Audio='96k'  },
    [pscustomobject]@{ Id=5; Nome='Mínima (compacta ~320p)';     Desc='Bem pequena, para prévia / upload rápido';     Altura=320;  Crf=30; Audio='64k'  }
)

# Formatos de vídeo reconhecidos
$extensoes = @(
    '.mp4', '.mkv', '.avi', '.mov', '.wmv',
    '.flv', '.webm', '.m4v', '.mpg', '.mpeg',
    '.mts', '.m2ts', '.ts', '.3gp', '.vob'
)

# ------------------------------------------------------------
# 1) Verificação de dependências
# ------------------------------------------------------------
Titulo 'Transcodificar Vídeos'
Write-Host '  Desenvolvido por Pablo Murad - 2026' -ForegroundColor DarkGray
Write-Host ''
Write-Host 'Verificando o que é necessário...' -ForegroundColor Gray

$ffmpeg = Get-Command ffmpeg -ErrorAction SilentlyContinue
if (-not $ffmpeg) {
    Write-Host ''
    Write-Host '[ERRO] O FFmpeg não foi encontrado no sistema.' -ForegroundColor Red
    Write-Host 'Ele é necessário para converter os vídeos.' -ForegroundColor Yellow
    Write-Host ''
    Write-Host 'Para instalar, abra o Terminal / Prompt e rode:' -ForegroundColor Gray
    Write-Host '    winget install Gyan.FFmpeg' -ForegroundColor White
    Write-Host ''
    Write-Host 'Depois feche e abra este programa novamente.' -ForegroundColor Gray
    Pausar
    exit 1
}
Write-Host "[OK] FFmpeg encontrado: $($ffmpeg.Source)" -ForegroundColor Green
$temNvenc = [bool](& ffmpeg -hide_banner -encoders 2>$null | Select-String 'h264_nvenc')
if ($temNvenc) { Write-Host '[OK] GPU NVENC disponível (aceleração por placa NVIDIA).' -ForegroundColor Green }

$config = Carregar-Config

# ------------------------------------------------------------
# 2) Escolha da pasta OU de um vídeo único (lembra o último)
# ------------------------------------------------------------
$entradaPadrao = Join-Path $env:USERPROFILE 'Downloads\Vídeos'
$entradaAtual  = if ($config -and $config.UltimaPasta) { $config.UltimaPasta } else { $entradaPadrao }

$modoArquivo  = $false
$arquivoUnico = $null

while ($true) {
    Titulo 'Pasta ou vídeo'
    Write-Host 'Caminho atual:' -ForegroundColor Gray
    Write-Host "  $entradaAtual" -ForegroundColor White
    Write-Host ''
    Write-Host 'Enter = confirmar   |   ou cole/digite uma PASTA ou um ARQUIVO de vídeo' -ForegroundColor DarkGray
    $resp = Read-Host 'Pasta/arquivo'

    if (-not [string]::IsNullOrWhiteSpace($resp)) {
        $entradaAtual = $resp.Trim().Trim('"')
    }

    if (Test-Path -LiteralPath $entradaAtual -PathType Leaf) {
        $ext = [System.IO.Path]::GetExtension($entradaAtual).ToLowerInvariant()
        if ($extensoes -notcontains $ext) {
            Write-Host ''
            Write-Host "[!] Esse arquivo não é um vídeo suportado ($ext)." -ForegroundColor Yellow
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
$destino = Join-Path $origem 'Transcodificado'

# ------------------------------------------------------------
# 3) Escolha da qualidade
# ------------------------------------------------------------
$qualidadePadrao = if ($config -and $config.UltimaQualidade) { [int]$config.UltimaQualidade } else { 5 }

Titulo 'Qualidade de saída'
foreach ($p in $perfis) {
    $marca = if ($p.Id -eq $qualidadePadrao) { '>' } else { ' ' }
    $cor   = if ($p.Id -eq $qualidadePadrao) { 'White' } else { 'Gray' }
    Write-Host ("{0} [{1}] {2}" -f $marca, $p.Id, $p.Nome) -ForegroundColor $cor
    Write-Host ("       {0}" -f $p.Desc) -ForegroundColor DarkGray
}
Write-Host ''
Write-Host "Enter = usar a opção padrão [$qualidadePadrao]" -ForegroundColor DarkGray

$perfil = $null
while (-not $perfil) {
    $escolha = Read-Host 'Qualidade (1-5)'
    if ([string]::IsNullOrWhiteSpace($escolha)) { $escolha = "$qualidadePadrao" }
    $perfil = $perfis | Where-Object { $_.Id -eq ($escolha -as [int]) } | Select-Object -First 1
    if (-not $perfil) { Write-Host '[!] Escolha inválida. Digite um número de 1 a 5.' -ForegroundColor Yellow }
}

# ------------------------------------------------------------
# Motor de codificação (velocidade x qualidade/tamanho)
# ------------------------------------------------------------
$motorPadrao = if ($config -and $config.UltimoMotor) { $config.UltimoMotor } else { if ($temNvenc) { 'gpu' } else { 'cpu-rapido' } }
$motoresMenu = @(
    [pscustomobject]@{ Id=1; Cod='gpu';           Nome='GPU NVENC (mais rápido)' },
    [pscustomobject]@{ Id=2; Cod='cpu-rapido';    Nome='CPU rápido (veryfast)' },
    [pscustomobject]@{ Id=3; Cod='cpu-qualidade'; Nome='CPU qualidade (medium, menor arquivo)' }
)
$idPadrao = ($motoresMenu | Where-Object { $_.Cod -eq $motorPadrao } | Select-Object -First 1).Id
if (-not $idPadrao) { $idPadrao = 1 }
Titulo 'Motor de codificação (velocidade)'
foreach ($mo in $motoresMenu) {
    $extra = if ($mo.Cod -eq 'gpu' -and -not $temNvenc) { '  (indisponível nesta máquina)' } else { '' }
    $marca = if ($mo.Id -eq $idPadrao) { '>' } else { ' ' }
    $cor   = if ($mo.Id -eq $idPadrao) { 'White' } else { 'Gray' }
    Write-Host ("{0} [{1}] {2}{3}" -f $marca, $mo.Id, $mo.Nome, $extra) -ForegroundColor $cor
}
Write-Host "Enter = usar a opção padrão [$idPadrao]" -ForegroundColor DarkGray
$motor = $null
while (-not $motor) {
    $em = Read-Host 'Motor (1-3)'; if ([string]::IsNullOrWhiteSpace($em)) { $em = "$idPadrao" }
    $sel = $motoresMenu | Where-Object { $_.Id -eq ($em -as [int]) } | Select-Object -First 1
    if ($sel) { $motor = $sel.Cod } else { Write-Host '[!] Escolha 1, 2 ou 3.' -ForegroundColor Yellow }
}
if ($motor -eq 'gpu' -and -not $temNvenc) {
    Write-Host '[!] GPU indisponível; usando CPU rápido (veryfast).' -ForegroundColor Yellow
    $motor = 'cpu-rapido'
}
$motorNome = ($motoresMenu | Where-Object { $_.Cod -eq $motor } | Select-Object -First 1).Nome

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

Salvar-Config $origem $perfil.Id $destino $motor

# ------------------------------------------------------------
# 4) Coleta dos arquivos de vídeo
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
Write-Host "Pasta:     $origem"
Write-Host "Qualidade: $($perfil.Nome)  (CRF $($perfil.Crf), áudio $($perfil.Audio))"
Write-Host "Motor:     $motorNome"
Write-Host "Destino:   $destino"
Write-Host "Vídeos encontrados: $($arquivos.Count)" -ForegroundColor Cyan

if ($arquivos.Count -eq 0) {
    Write-Host ''
    Write-Host 'Nenhum vídeo para converter nessa pasta.' -ForegroundColor Yellow
    Pausar
    exit 0
}

New-Item -ItemType Directory -Path $destino -Force | Out-Null

# Filtro de escala conforme o perfil (nunca faz upscaling)
if ($perfil.Altura -eq 0) {
    $vf = 'scale=trunc(iw/2)*2:trunc(ih/2)*2'
} else {
    $vf = "scale=-2:trunc(min($($perfil.Altura)\,ih)/2)*2"
}

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

    $saida = Join-Path $pastaSaida ($arquivo.BaseName + '.mp4')

    Write-Host ''
    Write-Host ("[{0}/{1}]" -f $indice, $arquivos.Count) -ForegroundColor Magenta -NoNewline
    Write-Host " $($arquivo.Name)"

    if (Test-Path -LiteralPath $saida) {
        Write-Host "   [IGNORADO] Já existe na pasta de destino." -ForegroundColor Yellow
        $ignorados++
        continue
    }

    # Codec de vídeo conforme o motor escolhido
    switch ($motor) {
        'gpu'          { $vcodec = @('-c:v', 'h264_nvenc', '-preset', 'p5', '-cq', "$($perfil.Crf)", '-pix_fmt', 'yuv420p') }
        'cpu-rapido'   { $vcodec = @('-c:v', 'libx264', '-preset', 'veryfast', '-crf', "$($perfil.Crf)", '-pix_fmt', 'yuv420p') }
        default        { $vcodec = @('-c:v', 'libx264', '-preset', 'medium', '-crf', "$($perfil.Crf)", '-pix_fmt', 'yuv420p') }
    }
    $ffArgs = @('-hide_banner', '-nostdin', '-i', $arquivo.FullName, '-map', '0:v:0', '-map', '0:a?', '-vf', $vf) +
              $vcodec +
              @('-c:a', 'aac', '-b:a', $perfil.Audio, '-ac', '2', '-movflags', '+faststart', '-progress', 'pipe:1', '-nostats', '-y', $saida)

    # Duração do vídeo para a barra de progresso
    $dur = 0.0
    try { $dur = [double](& ffprobe -v error -show_entries format=duration -of csv=p=0 $arquivo.FullName 2>$null) } catch {}

    & ffmpeg @ffArgs 2>$null | ForEach-Object {
        if ($dur -gt 0 -and $_ -match '^out_time=(\d+):(\d+):([\d.]+)') {
            $seg = [int]$matches[1]*3600 + [int]$matches[2]*60 + [double]$matches[3]
            $pct = [int](($seg / $dur) * 100); if ($pct -gt 100) { $pct = 100 }
            $cheio = [int]($pct / 5)
            $barra = ('#' * $cheio) + ('-' * (20 - $cheio))
            Write-Host ("`r   [{0}] {1,3}%  " -f $barra, $pct) -NoNewline -ForegroundColor Cyan
        }
    }
    $rc = $LASTEXITCODE
    if ($dur -gt 0) { Write-Host ("`r   [{0}] 100%  " -f ('#' * 20)) -ForegroundColor Cyan }

    if ($rc -eq 0 -and (Test-Path -LiteralPath $saida)) {
        Write-Host "   [OK] Convertido." -ForegroundColor Green
        $convertidos++
    } else {
        Write-Host "   [ERRO] Falha ao converter." -ForegroundColor Red
        if (Test-Path -LiteralPath $saida) { Remove-Item -LiteralPath $saida -Force -ErrorAction SilentlyContinue }
        $erros++
    }
}

# ------------------------------------------------------------
# 5) Resumo final
# ------------------------------------------------------------
Titulo 'Concluído'
Write-Host "Convertidos: $convertidos" -ForegroundColor Green
Write-Host "Ignorados:   $ignorados"  -ForegroundColor Yellow
Write-Host "Erros:       $erros"       -ForegroundColor $(if ($erros -gt 0) { 'Red' } else { 'Gray' })
Write-Host "Destino:     $destino"
Pausar
