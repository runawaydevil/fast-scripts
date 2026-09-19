<# :
@echo off
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression ([System.IO.File]::ReadAllText('%~f0',[System.Text.Encoding]::UTF8))"
exit /b %errorlevel%
#>

# ============================================================
#  Limpar Nomes - normaliza nomes de arquivo para web/upload
#  Desenvolvido por Pablo Murad - 2026
# ============================================================

try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
try { $Host.UI.RawUI.WindowTitle = 'Limpar Nomes' } catch {}
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

$configDir  = Join-Path $env:APPDATA 'LimparNomes'
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

Abrir 'Limpar Nomes'
Write-Host '[OK] Não precisa de nenhum programa extra.' -ForegroundColor Green
$config = Carregar-Config

Write-Host ''
Write-Host 'Deixa os nomes seguros para web/upload: tira acentos, troca espaços por hífen e usa minúsculas.' -ForegroundColor DarkGray

$padrao = if ($config -and $config.UltimaEntrada) { $config.UltimaEntrada } else { Join-Path $env:USERPROFILE 'Downloads' }
$pasta = $null
while (-not $pasta) {
    Titulo 'Pasta'
    Write-Host "  $padrao" -ForegroundColor White
    $r = Read-Host 'Pasta (Enter = confirmar)'
    $x = if ([string]::IsNullOrWhiteSpace($r)) { $padrao } else { $r.Trim().Trim('"') }
    if (Test-Path -LiteralPath $x -PathType Container) { $pasta = (Resolve-Path -LiteralPath $x).Path } else { Write-Host '[!] Pasta não encontrada.' -ForegroundColor Yellow; $padrao = $x }
}
Salvar-Config ([pscustomobject]@{ UltimaEntrada=$pasta })

function Limpar-Nome([string]$nome) {
    $base = [System.IO.Path]::GetFileNameWithoutExtension($nome)
    $ext  = [System.IO.Path]::GetExtension($nome).ToLowerInvariant()
    $n = $base.Normalize([System.Text.NormalizationForm]::FormD)
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $n.ToCharArray()) {
        if ([System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne [System.Globalization.UnicodeCategory]::NonSpacingMark) { [void]$sb.Append($ch) }
    }
    $r = $sb.ToString().ToLowerInvariant()
    $r = $r -replace '[^a-z0-9]+', '-'
    $r = $r -replace '-+', '-'
    $r = $r.Trim('-')
    if ([string]::IsNullOrWhiteSpace($r)) { $r = 'arquivo' }
    return $r + $ext
}

$arquivos = @(Get-ChildItem -LiteralPath $pasta -File | Sort-Object Name)
if ($arquivos.Count -eq 0) { Write-Host 'Nenhum arquivo nessa pasta.' -ForegroundColor Yellow; Pausar; exit 0 }

$plano = @(); $reservados = @()
foreach ($a in $arquivos) {
    $novo = Limpar-Nome $a.Name
    if ($novo -ceq $a.Name) { continue }
    $alvo = Join-Path $pasta $novo
    $b = [System.IO.Path]::GetFileNameWithoutExtension($novo); $e = [System.IO.Path]::GetExtension($novo); $i = 1
    while ((Test-Path -LiteralPath $alvo) -or ($reservados -contains $alvo)) { $alvo = Join-Path $pasta ("$b-$i$e"); $i++ }
    $reservados += $alvo
    $plano += [pscustomobject]@{ De=$a; Para=$alvo }
}
if ($plano.Count -eq 0) { Write-Host 'Todos os nomes já estão limpos. Nada a fazer.' -ForegroundColor Green; Pausar; exit 0 }

Titulo 'Prévia'
$mostra = [Math]::Min($plano.Count, 15)
for ($i=0; $i -lt $mostra; $i++) {
    Write-Host ("  {0}" -f $plano[$i].De.Name) -ForegroundColor Gray -NoNewline
    Write-Host ("   ->   {0}" -f (Split-Path $plano[$i].Para -Leaf)) -ForegroundColor White
}
if ($plano.Count -gt $mostra) { Write-Host ("  ... e mais {0}." -f ($plano.Count - $mostra)) -ForegroundColor DarkGray }
Write-Host ''
$ok = Read-Host "Renomear $($plano.Count) arquivo(s)? (s/N)"
if ($ok -notmatch '^(s|sim|y|yes)$') { Write-Host 'Cancelado.' -ForegroundColor Yellow; Pausar; exit 0 }

$feitos=0;$err=0
foreach ($p in $plano) {
    try { Rename-Item -LiteralPath $p.De.FullName -NewName (Split-Path $p.Para -Leaf) -ErrorAction Stop; $feitos++ }
    catch { Write-Host ("  [ERRO] {0}: {1}" -f $p.De.Name, $_.Exception.Message) -ForegroundColor Red; $err++ }
}
Resumo $feitos 0 $err $pasta