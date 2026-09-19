<# :
@echo off
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression ([System.IO.File]::ReadAllText('%~f0',[System.Text.Encoding]::UTF8))"
exit /b %errorlevel%
#>

# ============================================================
#  Cortar Vídeo - apara um trecho do vídeo (FFmpeg)
#  Desenvolvido por Pablo Murad - 2026
# ============================================================

try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
try { $Host.UI.RawUI.WindowTitle = 'Cortar Vídeo' } catch {}
function Pausar { Write-Host ''; Write-Host 'Pressione Enter para fechar...' -ForegroundColor DarkGray; [void][System.Console]::ReadLine() }
function Titulo($t) {
    Write-Host ''
    Write-Host '============================================================' -ForegroundColor DarkCyan
    Write-Host "  $t" -ForegroundColor Cyan
    Write-Host '============================================================' -ForegroundColor DarkCyan
}
function Tam($bytes) {
    if ($bytes -ge 1GB) { '{0:N2} GB' -f ($bytes/1GB) }
    elseif ($bytes -ge 1MB) { '{0:N1} MB' -f ($bytes/1MB) }
    else { '{0:N0} KB' -f ($bytes/1KB) }
}

$configDir  = Join-Path $env:APPDATA 'CortarVideo'
$configFile = Join-Path $configDir 'config.json'
function Carregar-Config { if (Test-Path -LiteralPath $configFile) { try { return Get-Content -LiteralPath $configFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch {} }; return $null }
function Salvar-Config($o) { try { New-Item -ItemType Directory -Path $configDir -Force | Out-Null; $o | ConvertTo-Json | Set-Content -LiteralPath $configFile -Encoding UTF8 } catch {} }

# Pergunta a pasta de saida: sugere a ultima usada e cria se nao existir
function Pedir-Saida($padrao) {
    while ($true) {
        Titulo 'Pasta de saída'
        Write-Host "  $padrao" -ForegroundColor White
        Write-Host 'Enter = usar esta pasta   |   ou cole/digite outra' -ForegroundColor DarkGray
        $r = Read-Host 'Pasta de saída'
        $d = if ([string]::IsNullOrWhiteSpace($r)) { $padrao } else { $r.Trim().Trim('"') }
        try { New-Item -ItemType Directory -Path $d -Force | Out-Null; return (Resolve-Path -LiteralPath $d).Path }
        catch { Write-Host '[!] Não foi possível criar/usar essa pasta.' -ForegroundColor Yellow }
    }
}

function Checar($exe, $nomeAmigavel, $comandoInstalar) {
    $c = Get-Command $exe -ErrorAction SilentlyContinue
    if (-not $c) {
        Write-Host ''
        Write-Host "[ERRO] $nomeAmigavel não foi encontrado." -ForegroundColor Red
        Write-Host "Instale com:  $comandoInstalar" -ForegroundColor White
        Pausar; exit 1
    }
    Write-Host ("[OK] {0}: {1}" -f $nomeAmigavel, $c.Source) -ForegroundColor Green
    return $c
}

function Abrir($titulo) {
    Titulo $titulo
    Write-Host '  Desenvolvido por Pablo Murad - 2026' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host 'Verificando o que é necessário...' -ForegroundColor Gray
}

$extVideo = @('.mp4','.mkv','.avi','.mov','.wmv','.flv','.webm','.m4v','.mpg','.mpeg','.mts','.m2ts','.ts','.3gp','.vob')
$extAudio = @('.mp3','.m4a','.wav','.flac','.aac','.ogg','.wma','.opus')
$extImg   = @('.jpg','.jpeg','.png','.webp','.bmp','.tif','.tiff')

# Pede uma PASTA ou um ARQUIVO; devolve @{ Modo; Caminho; Origem }
function Pedir-Entrada($padrao, $exts, $rotulo) {
    while ($true) {
        Titulo $rotulo
        Write-Host "  $padrao" -ForegroundColor White
        Write-Host 'Enter = confirmar   |   ou cole/digite uma PASTA ou um ARQUIVO' -ForegroundColor DarkGray
        $r = Read-Host 'Caminho'
        $c = if ([string]::IsNullOrWhiteSpace($r)) { $padrao } else { $r.Trim().Trim('"') }
        if (Test-Path -LiteralPath $c -PathType Leaf) {
            if ($exts -notcontains [System.IO.Path]::GetExtension($c).ToLowerInvariant()) {
                Write-Host '[!] Esse arquivo não é de um tipo suportado.' -ForegroundColor Yellow; $padrao = $c; continue
            }
            $f = Get-Item -LiteralPath $c
            return @{ Modo='arquivo'; Caminho=$f.FullName; Origem=$f.DirectoryName }
        }
        elseif (Test-Path -LiteralPath $c -PathType Container) {
            $p = (Resolve-Path -LiteralPath $c).Path
            return @{ Modo='pasta'; Caminho=$p; Origem=$p }
        }
        Write-Host "[!] Caminho não encontrado." -ForegroundColor Yellow
        $padrao = $c
    }
}

function Listar($ent, $exts) {
    if ($ent.Modo -eq 'arquivo') { return @(Get-Item -LiteralPath $ent.Caminho) }
    return @(Get-ChildItem -LiteralPath $ent.Caminho -File | Where-Object { $exts -contains $_.Extension.ToLowerInvariant() } | Sort-Object Name)
}

function Resumo($ok, $ign, $err, $destino) {
    Titulo 'Concluído'
    Write-Host "Prontos:   $ok" -ForegroundColor Green
    if ($ign -gt 0) { Write-Host "Ignorados: $ign" -ForegroundColor Yellow }
    Write-Host "Erros:     $err" -ForegroundColor $(if ($err -gt 0) { 'Red' } else { 'Gray' })
    if ($destino) { Write-Host "Destino:   $destino" }
    Pausar
}

function Relatar($resultados, $tarefas, [ref]$ok, [ref]$err) {
    foreach ($x in $resultados) {
        $alvo = $tarefas[$x.Indice].Alvo
        if ($x.Codigo -eq 0 -and (Test-Path -LiteralPath $alvo)) { $ok.Value++ }
        else {
            $err.Value++
            Write-Host ("  [ERRO] {0}" -f $x.Rotulo) -ForegroundColor Red
            $motivo = ($x.Erro -split "`n" | Where-Object { $_.Trim() } | Select-Object -Last 1)
            if ($motivo) { Write-Host ("         {0}" -f $motivo.Trim()) -ForegroundColor DarkGray }
            if (Test-Path -LiteralPath $alvo) { Remove-Item -LiteralPath $alvo -Force -ErrorAction SilentlyContinue }
        }
    }
}

Abrir 'Cortar Vídeo'
Checar 'ffmpeg' 'FFmpeg' 'winget install Gyan.FFmpeg' | Out-Null
$config = Carregar-Config

$padrao = if ($config -and $config.UltimaEntrada) { $config.UltimaEntrada } else { Join-Path $env:USERPROFILE 'Downloads' }
$ent = Pedir-Entrada $padrao $extVideo 'Vídeo para cortar'
if ($ent.Modo -ne 'arquivo') {
    $lista = Listar $ent $extVideo
    if ($lista.Count -eq 0) { Write-Host 'Nenhum vídeo nessa pasta.' -ForegroundColor Yellow; Pausar; exit 0 }
    Titulo 'Qual vídeo?'
    for ($i=0; $i -lt $lista.Count; $i++) { Write-Host ("  [{0}] {1}" -f ($i+1), $lista[$i].Name) -ForegroundColor Gray }
    $sel = $null
    while (-not $sel) { $e = Read-Host "Número (1-$($lista.Count))"; $n = $e -as [int]; if ($n -ge 1 -and $n -le $lista.Count) { $sel = $lista[$n-1] } else { Write-Host '[!] Inválido.' -ForegroundColor Yellow } }
    $video = $sel
} else { $video = Get-Item -LiteralPath $ent.Caminho }

# duração, para ajudar o usuário
$dur = 0.0
try {
    $b = (& ffprobe -v error -show_entries format=duration -of csv=p=0 $video.FullName 2>$null)
    [double]::TryParse(("$b" -replace ',', '.'), [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$dur) | Out-Null
} catch {}
Titulo 'Trecho'
Write-Host ("  Vídeo: {0}" -f $video.Name) -ForegroundColor White
if ($dur -gt 0) { Write-Host ("  Duração total: {0:hh\:mm\:ss}" -f [TimeSpan]::FromSeconds($dur)) -ForegroundColor Gray }
Write-Host '  Formato aceito: 90   ou   01:30   ou   00:01:30' -ForegroundColor DarkGray
$inicio = Read-Host 'Início (Enter = 0)'
if ([string]::IsNullOrWhiteSpace($inicio)) { $inicio = '0' }
$fim = Read-Host 'Fim (Enter = até o final)'

Titulo 'Modo do corte'
Write-Host '> [1] Rápido - sem recodificar (instantâneo; corta no quadro-chave mais próximo)' -ForegroundColor White
Write-Host '  [2] Exato  - recodifica (corta no ponto exato, demora mais)' -ForegroundColor Gray
$m = Read-Host 'Modo (Enter = 1)'
$exato = ($m.Trim() -eq '2')

$destino = Pedir-Saida $(if ($config -and $config.UltimaSaida) { $config.UltimaSaida } else { Join-Path $video.DirectoryName 'Cortado' })
Salvar-Config ([pscustomobject]@{ UltimaEntrada=$video.DirectoryName; UltimaSaida=$destino })

$saida = Join-Path $destino ($video.BaseName + '-corte' + $video.Extension)
$n = 1
while (Test-Path -LiteralPath $saida) { $saida = Join-Path $destino ($video.BaseName + "-corte ($n)" + $video.Extension); $n++ }

$ffArgs = @('-hide_banner','-nostdin','-loglevel','error')
if ($exato) {
    $ffArgs += @('-i', $video.FullName, '-ss', $inicio)
    if (-not [string]::IsNullOrWhiteSpace($fim)) { $ffArgs += @('-to', $fim) }
    $ffArgs += @('-c:v','libx264','-preset','veryfast','-crf','20','-c:a','aac','-b:a','160k')
} else {
    $ffArgs += @('-ss', $inicio)
    if (-not [string]::IsNullOrWhiteSpace($fim)) { $ffArgs += @('-to', $fim) }
    $ffArgs += @('-i', $video.FullName, '-c', 'copy', '-avoid_negative_ts', 'make_zero')
}
$ffArgs += @('-y', $saida)

Titulo 'Cortando'
Write-Host ("Modo: {0}" -f $(if ($exato) { 'exato (recodifica)' } else { 'rápido (sem recodificar)' }))
Write-Host "Saída: $saida"
Write-Host ''
$t = Measure-Command { & ffmpeg @ffArgs }
$rc = $LASTEXITCODE
if ($rc -eq 0 -and (Test-Path -LiteralPath $saida)) {
    Write-Host ("[OK] Corte pronto em {0:N1}s  ({1})" -f $t.TotalSeconds, (Tam (Get-Item $saida).Length)) -ForegroundColor Green
    Resumo 1 0 0 $destino
} else {
    Write-Host '[ERRO] Não foi possível cortar (confira os tempos informados).' -ForegroundColor Red
    if (Test-Path -LiteralPath $saida) { Remove-Item -LiteralPath $saida -Force -ErrorAction SilentlyContinue }
    Resumo 0 0 1 $destino
}