<# :
@echo off
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression ([System.IO.File]::ReadAllText('%~f0',[System.Text.Encoding]::UTF8))"
exit /b %errorlevel%
#>

# ============================================================
#  Compactar / Extrair - compacta e extrai arquivos em lote
#  Desenvolvido por Pablo Murad - 2026
# ============================================================

try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
try { $Host.UI.RawUI.WindowTitle = 'Compactar / Extrair' } catch {}
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

$configDir  = Join-Path $env:APPDATA 'CompactarZip'
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

Abrir 'Compactar / Extrair'
# Get-Command devolve .Source e Get-Item devolve .FullName: normaliza tudo
# num caminho unico para nao misturar os dois tipos.
$seteExe = $null
$c7 = Get-Command 7z -ErrorAction SilentlyContinue
if ($c7) { $seteExe = $c7.Source }
else {
    foreach ($cand in @("$env:ProgramFiles\7-Zip\7z.exe", "${env:ProgramFiles(x86)}\7-Zip\7z.exe")) {
        if (Test-Path -LiteralPath $cand) { $seteExe = $cand; break }
    }
}
if ($seteExe) { Write-Host ("[OK] 7-Zip: {0}" -f $seteExe) -ForegroundColor Green }
else { Write-Host '[OK] Usando o compactador do Windows (instale o 7-Zip para mais formatos: winget install 7zip.7zip)' -ForegroundColor Gray }
$config = Carregar-Config

Titulo 'O que você quer fazer?'
Write-Host '  [1] Compactar uma pasta' -ForegroundColor White
Write-Host '  [2] Extrair arquivos compactados' -ForegroundColor White
$acao = $null
while (-not $acao) { $a = Read-Host 'Opção (1-2)'; switch ($a.Trim()) { '1' { $acao='zip' } '2' { $acao='unzip' } default { Write-Host '[!] Digite 1 ou 2.' -ForegroundColor Yellow } } }

$padrao = if ($config -and $config.UltimaEntrada) { $config.UltimaEntrada } else { Join-Path $env:USERPROFILE 'Downloads' }

if ($acao -eq 'zip') {
    $pasta = $null
    while (-not $pasta) {
        Titulo 'Pasta para compactar'
        Write-Host "  $padrao" -ForegroundColor White
        $r = Read-Host 'Pasta (Enter = confirmar)'
        $x = if ([string]::IsNullOrWhiteSpace($r)) { $padrao } else { $r.Trim().Trim('"') }
        if (Test-Path -LiteralPath $x -PathType Container) { $pasta = (Resolve-Path -LiteralPath $x).Path } else { Write-Host '[!] Pasta não encontrada.' -ForegroundColor Yellow; $padrao = $x }
    }
    $nome = (Read-Host "Nome do arquivo (Enter = $([System.IO.Path]::GetFileName($pasta)).zip)").Trim()
    if ([string]::IsNullOrWhiteSpace($nome)) { $nome = [System.IO.Path]::GetFileName($pasta) + '.zip' }
    if ($nome -notmatch '\.(zip|7z)$') { $nome += '.zip' }
    $destino = Pedir-Saida $(if ($config -and $config.UltimaSaida) { $config.UltimaSaida } else { Split-Path $pasta -Parent })
    Salvar-Config ([pscustomobject]@{ UltimaEntrada=$pasta; UltimaSaida=$destino })
    $saida = Join-Path $destino $nome
    if (Test-Path -LiteralPath $saida) {
        $s = Read-Host 'Já existe um arquivo com esse nome. Sobrescrever? (s/N)'
        if ($s -notmatch '^(s|sim|y|yes)$') { Write-Host 'Cancelado.' -ForegroundColor Yellow; Pausar; exit 0 }
        Remove-Item -LiteralPath $saida -Force
    }
    Titulo 'Compactando'
    Write-Host "Saída: $saida"
    $t = Measure-Command {
        if ($seteExe) { & $seteExe a -mmt=on -- $saida (Join-Path $pasta '*') | Out-Null; $global:rc = $LASTEXITCODE }
        else { Compress-Archive -Path (Join-Path $pasta '*') -DestinationPath $saida -CompressionLevel Optimal -Force; $global:rc = 0 }
    }
    if ($rc -eq 0 -and (Test-Path -LiteralPath $saida)) {
        Write-Host ("[OK] Pronto em {0:N1}s  ({1})" -f $t.TotalSeconds, (Tam (Get-Item $saida).Length)) -ForegroundColor Green
        Resumo 1 0 0 $destino
    } else { Write-Host '[ERRO] Falha ao compactar.' -ForegroundColor Red; Resumo 0 0 1 $destino }
}
else {
    $ent = Pedir-Entrada $padrao @('.zip','.7z','.rar','.tar','.gz') 'Pasta ou arquivo compactado'
    $itens = Listar $ent @('.zip','.7z','.rar','.tar','.gz')
    if ($itens.Count -eq 0) { Write-Host 'Nenhum arquivo compactado encontrado.' -ForegroundColor Yellow; Pausar; exit 0 }
    $destino = Pedir-Saida $(if ($config -and $config.UltimaSaida) { $config.UltimaSaida } else { Join-Path $ent.Origem 'Extraido' })
    Salvar-Config ([pscustomobject]@{ UltimaEntrada=$ent.Origem; UltimaSaida=$destino })
    Titulo 'Extraindo'
    $ok=0;$err=0
    foreach ($f in $itens) {
        $sub = Join-Path $destino $f.BaseName
        New-Item -ItemType Directory -Path $sub -Force | Out-Null
        Write-Host ("  {0}..." -f $f.Name) -ForegroundColor Gray
        $falhou = $false
        if ($seteExe) { & $seteExe x -y "-o$sub" -- $f.FullName | Out-Null; if ($LASTEXITCODE -ne 0) { $falhou = $true } }
        elseif ($f.Extension -eq '.zip') { try { Expand-Archive -LiteralPath $f.FullName -DestinationPath $sub -Force } catch { $falhou = $true } }
        else { Write-Host '     (formato exige o 7-Zip)' -ForegroundColor Yellow; $falhou = $true }
        if ($falhou) { $err++ } else { $ok++ }
    }
    Resumo $ok 0 $err $destino
}