<# :
@echo off
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression ([System.IO.File]::ReadAllText('%~f0',[System.Text.Encoding]::UTF8))"
exit /b %errorlevel%
#>

# ============================================================
#  Analisar Espaço - mostra o que está ocupando o disco
#  Desenvolvido por Pablo Murad - 2026
# ============================================================

try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
try { $Host.UI.RawUI.WindowTitle = 'Analisar Espaço' } catch {}
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

$configDir  = Join-Path $env:APPDATA 'AnalisarEspaco'
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

Abrir 'Analisar Espaço'
Write-Host '[OK] Não precisa de nenhum programa extra. Só leitura: nada é alterado.' -ForegroundColor Green
$config = Carregar-Config

Titulo 'Espaço nas unidades'
Get-Volume | Where-Object { $_.DriveLetter -and $_.Size -gt 0 } | Sort-Object DriveLetter | ForEach-Object {
    $usado = $_.Size - $_.SizeRemaining
    $pc = if ($_.Size -gt 0) { [int](($usado / $_.Size) * 100) } else { 0 }
    $ch = [int]($pc / 5)
    $cor = if ($pc -ge 90) { 'Red' } elseif ($pc -ge 75) { 'Yellow' } else { 'Gray' }
    Write-Host ("  {0}:  [{1}] {2,3}%   {3} livres de {4}" -f $_.DriveLetter, (('#'*$ch)+('-'*(20-$ch))), $pc, (Tam $_.SizeRemaining), (Tam $_.Size)) -ForegroundColor $cor
}

$padrao = if ($config -and $config.UltimaEntrada) { $config.UltimaEntrada } else { Join-Path $env:USERPROFILE 'Downloads' }
$pasta = $null
while (-not $pasta) {
    Titulo 'Pasta para analisar'
    Write-Host "  $padrao" -ForegroundColor White
    $r = Read-Host 'Pasta (Enter = confirmar)'
    $x = if ([string]::IsNullOrWhiteSpace($r)) { $padrao } else { $r.Trim().Trim('"') }
    if (Test-Path -LiteralPath $x -PathType Container) { $pasta = (Resolve-Path -LiteralPath $x).Path } else { Write-Host '[!] Pasta não encontrada.' -ForegroundColor Yellow; $padrao = $x }
}
Salvar-Config ([pscustomobject]@{ UltimaEntrada=$pasta })

Titulo 'Analisando'
Write-Host 'Lendo a árvore de pastas (pode demorar em pastas enormes)...' -ForegroundColor Gray
$todos = @(Get-ChildItem -LiteralPath $pasta -Recurse -File -Force -ErrorAction SilentlyContinue)
if ($todos.Count -eq 0) { Write-Host 'Pasta vazia ou sem acesso.' -ForegroundColor Yellow; Pausar; exit 0 }
$total = ($todos | Measure-Object -Property Length -Sum).Sum

Titulo 'Maiores subpastas'
$subs = @(Get-ChildItem -LiteralPath $pasta -Directory -Force -ErrorAction SilentlyContinue)
$linhas = @()
foreach ($s in $subs) {
    $b = (Get-ChildItem -LiteralPath $s.FullName -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    $linhas += [pscustomobject]@{ Nome=$s.Name; Bytes=[int64]$b }
}
$naRaiz = ($todos | Where-Object { $_.DirectoryName -eq $pasta } | Measure-Object -Property Length -Sum).Sum
if ($naRaiz -gt 0) { $linhas += [pscustomobject]@{ Nome='(arquivos soltos aqui)'; Bytes=[int64]$naRaiz } }
$linhas = $linhas | Sort-Object Bytes -Descending | Select-Object -First 15
foreach ($l in $linhas) {
    $pc = if ($total -gt 0) { [int](($l.Bytes / $total) * 100) } else { 0 }
    $ch = [int]($pc / 5)
    Write-Host ("  {0,10}  [{1}] {2,3}%  {3}" -f (Tam $l.Bytes), (('#'*$ch)+('-'*(20-$ch))), $pc, $l.Nome) -ForegroundColor Gray
}

Titulo 'Maiores arquivos'
$todos | Sort-Object Length -Descending | Select-Object -First 15 | ForEach-Object {
    Write-Host ("  {0,10}  {1}" -f (Tam $_.Length), $_.FullName.Substring($pasta.Length).TrimStart('\')) -ForegroundColor Gray
}

Titulo 'Resumo'
Write-Host ("Pasta:    {0}" -f $pasta)
Write-Host ("Arquivos: {0:N0}" -f $todos.Count)
Write-Host ("Tamanho:  {0}" -f (Tam $total)) -ForegroundColor Cyan
Pausar