<# :
@echo off
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression ([System.IO.File]::ReadAllText('%~f0',[System.Text.Encoding]::UTF8))"
exit /b %errorlevel%
#>

# ============================================================
#  Juntar Vídeos - concatena vários vídeos num só (FFmpeg)
#  Desenvolvido por Pablo Murad - 2026
# ============================================================

try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
try { $Host.UI.RawUI.WindowTitle = 'Juntar Vídeos' } catch {}
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

$configDir  = Join-Path $env:APPDATA 'JuntarVideos'
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

Abrir 'Juntar Vídeos'
Checar 'ffmpeg' 'FFmpeg' 'winget install Gyan.FFmpeg' | Out-Null
$config = Carregar-Config

$padrao = if ($config -and $config.UltimaEntrada) { $config.UltimaEntrada } else { Join-Path $env:USERPROFILE 'Downloads' }
$pasta = $null
while (-not $pasta) {
    Titulo 'Pasta com os vídeos'
    Write-Host "  $padrao" -ForegroundColor White
    Write-Host 'Enter = confirmar  |  os vídeos são juntados em ordem alfabética' -ForegroundColor DarkGray
    $r = Read-Host 'Pasta'
    $c = if ([string]::IsNullOrWhiteSpace($r)) { $padrao } else { $r.Trim().Trim('"') }
    if (Test-Path -LiteralPath $c -PathType Container) { $pasta = (Resolve-Path -LiteralPath $c).Path } else { Write-Host '[!] Pasta não encontrada.' -ForegroundColor Yellow; $padrao = $c }
}
$videos = @(Get-ChildItem -LiteralPath $pasta -File | Where-Object { $extVideo -contains $_.Extension.ToLowerInvariant() } | Sort-Object Name)
if ($videos.Count -lt 2) { Write-Host 'São necessários pelo menos 2 vídeos nessa pasta.' -ForegroundColor Yellow; Pausar; exit 0 }

Titulo 'Ordem'
for ($i=0; $i -lt $videos.Count; $i++) { Write-Host ("  {0,2}. {1}" -f ($i+1), $videos[$i].Name) -ForegroundColor Gray }
Write-Host ''
$ok = Read-Host "Juntar esses $($videos.Count) vídeos nessa ordem? (s/N)"
if ($ok -notmatch '^(s|sim|y|yes)$') { Write-Host 'Cancelado.' -ForegroundColor Yellow; Pausar; exit 0 }

Titulo 'Modo'
Write-Host '> [1] Rápido - sem recodificar (exige que sejam do mesmo tipo/codec)' -ForegroundColor White
Write-Host '  [2] Seguro - recodifica tudo para um padrão (sempre funciona, demora)' -ForegroundColor Gray
$m = Read-Host 'Modo (Enter = 1)'
$recodificar = ($m.Trim() -eq '2')

$nome = (Read-Host 'Nome do arquivo final (Enter = juntado.mp4)').Trim()
if ([string]::IsNullOrWhiteSpace($nome)) { $nome = 'juntado.mp4' }
if ($nome -notmatch '\.\w+$') { $nome += '.mp4' }

$destino = Pedir-Saida $(if ($config -and $config.UltimaSaida) { $config.UltimaSaida } else { $pasta })
Salvar-Config ([pscustomobject]@{ UltimaEntrada=$pasta; UltimaSaida=$destino })
$saida = Join-Path $destino $nome

$lista = Join-Path $env:TEMP ("juntar_{0}.txt" -f ([guid]::NewGuid().ToString('N')))
$sb = New-Object System.Text.StringBuilder
foreach ($v in $videos) { [void]$sb.AppendLine("file '" + ($v.FullName -replace '\\', '/') + "'") }
[System.IO.File]::WriteAllText($lista, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))

$ffArgs = @('-hide_banner','-nostdin','-loglevel','error','-f','concat','-safe','0','-i',$lista)
if ($recodificar) { $ffArgs += @('-c:v','libx264','-preset','veryfast','-crf','20','-c:a','aac','-b:a','160k') }
else { $ffArgs += @('-c','copy') }
$ffArgs += @('-movflags','+faststart','-y',$saida)

Titulo 'Juntando'
Write-Host "Saída: $saida"
Write-Host ''
& ffmpeg @ffArgs
$rc = $LASTEXITCODE
Remove-Item -LiteralPath $lista -Force -ErrorAction SilentlyContinue

if ($rc -eq 0 -and (Test-Path -LiteralPath $saida)) {
    Write-Host ("[OK] {0} vídeos juntados ({1})." -f $videos.Count, (Tam (Get-Item $saida).Length)) -ForegroundColor Green
    Resumo 1 0 0 $destino
} else {
    Write-Host '[ERRO] Falhou. Se usou o modo rápido, tente o modo seguro (opção 2).' -ForegroundColor Red
    if (Test-Path -LiteralPath $saida) { Remove-Item -LiteralPath $saida -Force -ErrorAction SilentlyContinue }
    Resumo 0 0 1 $destino
}