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

function Salvar-Config($pasta, $qualidade) {
    try {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
        [pscustomobject]@{ UltimaPasta = $pasta; UltimaQualidade = $qualidade } |
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

Salvar-Config $origem $perfil.Id

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

    $ffArgs = @(
        '-hide_banner', '-nostdin',
        '-i', $arquivo.FullName,
        '-map', '0:v:0', '-map', '0:a?',
        '-vf', $vf,
        '-c:v', 'libx264', '-preset', 'medium', '-crf', "$($perfil.Crf)", '-pix_fmt', 'yuv420p',
        '-c:a', 'aac', '-b:a', $perfil.Audio, '-ac', '2',
        '-movflags', '+faststart',
        '-y', $saida
    )

    & ffmpeg @ffArgs

    if ($LASTEXITCODE -eq 0) {
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
