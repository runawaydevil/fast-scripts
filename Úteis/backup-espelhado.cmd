<# :
@echo off
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression ([System.IO.File]::ReadAllText('%~f0',[System.Text.Encoding]::UTF8))"
exit /b %errorlevel%
#>

# ============================================================
#  Backup Espelhado - copia/espelha pastas com robocopy multithread
#  Desenvolvido por Pablo Murad - 2026
# ============================================================

try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
try { $Host.UI.RawUI.WindowTitle = 'Backup Espelhado' } catch {}
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

$configDir  = Join-Path $env:APPDATA 'BackupEspelhado'
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

Abrir 'Backup Espelhado'
Write-Host '[OK] Usa o robocopy do próprio Windows (multithread).' -ForegroundColor Green
$config = Carregar-Config

$origem = $null
$padrao = if ($config -and $config.UltimaOrigem) { $config.UltimaOrigem } else { Join-Path $env:USERPROFILE 'Documents' }
while (-not $origem) {
    Titulo 'Pasta de ORIGEM (o que será copiado)'
    Write-Host "  $padrao" -ForegroundColor White
    $r = Read-Host 'Origem (Enter = confirmar)'
    $x = if ([string]::IsNullOrWhiteSpace($r)) { $padrao } else { $r.Trim().Trim('"') }
    if (Test-Path -LiteralPath $x -PathType Container) { $origem = (Resolve-Path -LiteralPath $x).Path } else { Write-Host '[!] Pasta não encontrada.' -ForegroundColor Yellow; $padrao = $x }
}
$destino = Pedir-Saida $(if ($config -and $config.UltimoDestino) { $config.UltimoDestino } else { 'D:\Backup' })
if ($destino.TrimEnd('\') -ieq $origem.TrimEnd('\')) { Write-Host '[ERRO] Origem e destino são a mesma pasta.' -ForegroundColor Red; Pausar; exit 1 }

Titulo 'Modo'
Write-Host '> [1] Cópia  - só adiciona/atualiza; NUNCA apaga nada no destino' -ForegroundColor White
Write-Host '  [2] Espelho - deixa o destino IDÊNTICO à origem (APAGA no destino o que não existe mais na origem)' -ForegroundColor Yellow
$m = Read-Host 'Modo (Enter = 1)'
$espelho = ($m.Trim() -eq '2')
$modoArg = if ($espelho) { '/MIR' } else { '/E' }

Salvar-Config ([pscustomobject]@{ UltimaOrigem=$origem; UltimoDestino=$destino })

$comuns = @($origem, $destino, '/MT:16', '/R:1', '/W:1', '/NP', '/NDL', '/XJ')

Titulo 'Prévia (simulação - nada é copiado ou apagado)'
Write-Host 'Analisando as diferenças...' -ForegroundColor Gray
$previa = & robocopy @comuns $modoArg /L /NJH /NJS 2>&1
$aCopiar = @($previa | Where-Object { $_ -match '\S' -and $_ -notmatch '^\s*\*.*EXTRA' }).Count
$aApagar = @($previa | Where-Object { $_ -match '^\s*\*.*EXTRA' }).Count
Write-Host ''
Write-Host ("  Serão copiados/atualizados: {0} item(ns)" -f $aCopiar) -ForegroundColor Cyan
if ($espelho) {
    Write-Host ("  Serão APAGADOS no destino:  {0} item(ns)" -f $aApagar) -ForegroundColor $(if ($aApagar -gt 0) { 'Red' } else { 'Gray' })
    if ($aApagar -gt 0) {
        Write-Host ''
        Write-Host '  Exemplos do que será apagado no destino:' -ForegroundColor Red
        $previa | Where-Object { $_ -match '^\s*\*.*EXTRA' } | Select-Object -First 10 | ForEach-Object { Write-Host ("    " + $_.Trim()) -ForegroundColor DarkGray }
    }
}
Write-Host ''
Write-Host "Origem:  $origem"
Write-Host "Destino: $destino"
Write-Host ("Modo:    {0}" -f $(if ($espelho) { 'ESPELHO (apaga no destino)' } else { 'Cópia (não apaga)' })) -ForegroundColor $(if ($espelho) { 'Yellow' } else { 'Gray' })
Write-Host ''
if ($espelho -and $aApagar -gt 0) {
    $conf = Read-Host 'Isto APAGA arquivos no destino. Digite ESPELHAR para confirmar'
    if ($conf -cne 'ESPELHAR') { Write-Host 'Cancelado.' -ForegroundColor Yellow; Pausar; exit 0 }
} else {
    $conf = Read-Host 'Fazer o backup agora? (s/N)'
    if ($conf -notmatch '^(s|sim|y|yes)$') { Write-Host 'Cancelado.' -ForegroundColor Yellow; Pausar; exit 0 }
}

$pastaLog = Join-Path $env:LOCALAPPDATA 'fast-scripts\logs-backup'
New-Item -ItemType Directory -Path $pastaLog -Force | Out-Null
$log = Join-Path $pastaLog ("backup_{0}.log" -f (Get-Date -Format 'yyyy-MM-dd_HH-mm'))
Titulo 'Copiando'
Write-Host "Log: $log" -ForegroundColor DarkGray
Write-Host ''
$t = Measure-Command { & robocopy @comuns $modoArg "/LOG+:$log" /TEE | Out-Null }
$rc = $LASTEXITCODE

# robocopy: 0-7 = sucesso (8+ = erro real)
Titulo 'Concluído'
if ($rc -lt 8) {
    Write-Host ("[OK] Backup finalizado em {0:hh\:mm\:ss}." -f $t) -ForegroundColor Green
    Write-Host ("Código do robocopy: {0} (0-7 = sucesso)" -f $rc) -ForegroundColor DarkGray
} else {
    Write-Host ("[ERRO] O robocopy retornou {0} - houve falhas. Veja o log." -f $rc) -ForegroundColor Red
}
Write-Host "Destino: $destino"
Write-Host "Log:     $log"
Pausar