<# :
@echo off
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression ([System.IO.File]::ReadAllText('%~f0',[System.Text.Encoding]::UTF8))"
exit /b %errorlevel%
#>

# ============================================================
#  Verificar Integridade - detecta arquivos corrompidos por checksum SHA256
#  Desenvolvido por Pablo Murad - 2026
# ============================================================

try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
try { $Host.UI.RawUI.WindowTitle = 'Verificar Integridade' } catch {}
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

$configDir  = Join-Path $env:APPDATA 'VerificarIntegridade'
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

Abrir 'Verificar Integridade'
Write-Host '[OK] Não precisa de nenhum programa extra.' -ForegroundColor Green
$config = Carregar-Config

Write-Host ''
Write-Host 'Gera uma "impressão digital" de cada arquivo e confere depois,' -ForegroundColor DarkGray
Write-Host 'detectando arquivos corrompidos silenciosamente ou cópias com erro.' -ForegroundColor DarkGray

Titulo 'O que você quer fazer?'
Write-Host '  [1] Gerar o registro de integridade da pasta' -ForegroundColor White
Write-Host '  [2] Conferir a pasta contra um registro existente' -ForegroundColor White
$acao = $null
while (-not $acao) { $a = Read-Host 'Opção (1-2)'; switch ($a.Trim()) { '1' { $acao='gerar' } '2' { $acao='conferir' } default { Write-Host '[!] Digite 1 ou 2.' -ForegroundColor Yellow } } }

$padrao = if ($config -and $config.UltimaEntrada) { $config.UltimaEntrada } else { Join-Path $env:USERPROFILE 'Documents' }
$pasta = $null
while (-not $pasta) {
    Titulo 'Pasta'
    Write-Host "  $padrao" -ForegroundColor White
    $r = Read-Host 'Pasta (Enter = confirmar)'
    $x = if ([string]::IsNullOrWhiteSpace($r)) { $padrao } else { $r.Trim().Trim('"') }
    if (Test-Path -LiteralPath $x -PathType Container) { $pasta = (Resolve-Path -LiteralPath $x).Path } else { Write-Host '[!] Pasta não encontrada.' -ForegroundColor Yellow; $padrao = $x }
}
Salvar-Config ([pscustomobject]@{ UltimaEntrada=$pasta })
$registro = Join-Path $pasta 'integridade.sha256'

$arquivos = @(Get-ChildItem -LiteralPath $pasta -Recurse -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'integridade.sha256' })
if ($arquivos.Count -eq 0) { Write-Host 'Nenhum arquivo nessa pasta.' -ForegroundColor Yellow; Pausar; exit 0 }

function Hash-SHA256([string]$caminho) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $fs  = [System.IO.File]::OpenRead($caminho)
    try { return ([BitConverter]::ToString($sha.ComputeHash($fs)) -replace '-', '') }
    finally { $fs.Close(); $sha.Dispose() }
}
# $base e' passado explicitamente: dentro da funcao o escopo do script
# nao e' confiavel quando o arquivo roda via Invoke-Expression.
function Calcular($lista, $rotulo, $base) {
    $mapa = @{}
    $i = 0
    $falhas = 0
    foreach ($f in $lista) {
        $i++
        $pc = [int](($i / $lista.Count) * 100); $ch = [int]($pc / 5)
        Write-Host ("`r  {0} [{1}] {2,3}%  {3}/{4}   " -f $rotulo, (('#'*$ch)+('-'*(20-$ch))), $pc, $i, $lista.Count) -NoNewline -ForegroundColor Cyan
        $rel = $f.FullName
        if ($base -and $f.FullName.StartsWith($base, [System.StringComparison]::OrdinalIgnoreCase)) {
            $rel = $f.FullName.Substring($base.Length).TrimStart('\')
        }
        try { $mapa[$rel] = Hash-SHA256 $f.FullName }
        catch {
            $falhas++
            Write-Host ("`r  [ERRO] {0}: {1}" -f $f.Name, $_.Exception.Message) -ForegroundColor Red
        }
    }
    Write-Host ''
    if ($falhas -gt 0) { Write-Host ("  [!] {0} arquivo(s) nao puderam ser lidos." -f $falhas) -ForegroundColor Yellow }
    return $mapa
}

if ($acao -eq 'gerar') {
    Titulo 'Gerando'
    $mapa = Calcular $arquivos 'Calculando' $pasta
    $sb = New-Object System.Text.StringBuilder
    foreach ($k in ($mapa.Keys | Sort-Object)) { [void]$sb.AppendLine("$($mapa[$k]) *$k") }
    [System.IO.File]::WriteAllText($registro, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
    Titulo 'Concluído'
    Write-Host ("[OK] Registro criado com {0} arquivo(s)." -f $mapa.Count) -ForegroundColor Green
    Write-Host "Arquivo: $registro"
    Write-Host 'Guarde-o junto com os dados: rode a opção [2] depois para conferir.' -ForegroundColor DarkGray
    Pausar
}
else {
    if (-not (Test-Path -LiteralPath $registro)) {
        Write-Host ''
        Write-Host "[ERRO] Não achei o registro: $registro" -ForegroundColor Red
        Write-Host 'Rode primeiro a opção [1] nessa pasta.' -ForegroundColor Yellow
        Pausar; exit 1
    }
    $antigo = @{}
    foreach ($l in [System.IO.File]::ReadAllLines($registro, [System.Text.Encoding]::UTF8)) {
        $m = [regex]::Match($l, '^([0-9A-Fa-f]{64}) \*(.+)$')
        if ($m.Success) { $antigo[$m.Groups[2].Value] = $m.Groups[1].Value.ToUpperInvariant() }
    }
    Titulo 'Conferindo'
    $novo = Calcular $arquivos 'Conferindo' $pasta

    $iguais=0; $alterados=@(); $sumidos=@(); $novos=@()
    foreach ($k in $antigo.Keys) {
        if (-not $novo.ContainsKey($k)) { $sumidos += $k }
        elseif ($novo[$k] -ne $antigo[$k]) { $alterados += $k }
        else { $iguais++ }
    }
    foreach ($k in $novo.Keys) { if (-not $antigo.ContainsKey($k)) { $novos += $k } }

    Titulo 'Resultado'
    Write-Host ("  Intactos:  {0}" -f $iguais) -ForegroundColor Green
    Write-Host ("  ALTERADOS: {0}" -f $alterados.Count) -ForegroundColor $(if ($alterados.Count) { 'Red' } else { 'Gray' })
    Write-Host ("  Sumidos:   {0}" -f $sumidos.Count) -ForegroundColor $(if ($sumidos.Count) { 'Yellow' } else { 'Gray' })
    Write-Host ("  Novos:     {0}" -f $novos.Count) -ForegroundColor Gray
    if ($alterados.Count) {
        Write-Host ''
        Write-Host '  Arquivos com conteúdo diferente (possível corrupção):' -ForegroundColor Red
        $alterados | Select-Object -First 20 | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
    }
    if ($sumidos.Count) {
        Write-Host ''
        Write-Host '  Arquivos que sumiram:' -ForegroundColor Yellow
        $sumidos | Select-Object -First 20 | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
    }
    Pausar
}