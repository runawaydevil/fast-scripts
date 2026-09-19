<# :
@echo off
set "SELF=%~f0"
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression ([System.IO.File]::ReadAllText($env:SELF,[System.Text.Encoding]::UTF8))"
exit /b %errorlevel%
#>

# ============================================================
#  Limpeza segura - remove temporários e esvazia a lixeira
#  Mostra uma prévia do que será apagado antes de fazer
#  Desenvolvido por Pablo Murad - 2026
# ============================================================

try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
try { $Host.UI.RawUI.WindowTitle = 'Limpeza segura' } catch {}

# ------------------------------------------------------------
# Auto-elevacao: sem admin, C:\Windows\Temp e o cache do Windows
# Update nao podem ser lidos nem limpos (falhava em silencio).
# ------------------------------------------------------------
$souAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $souAdmin) {
    Write-Host 'Solicitando privilegios de administrador...' -ForegroundColor Yellow
    try { Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', "`"$env:SELF`"" -Verb RunAs | Out-Null }
    catch { Write-Host '[!] Sem elevacao: os temporarios do Windows serao ignorados.' -ForegroundColor Yellow; Start-Sleep -Seconds 2 }
    exit
}
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
function Medir($caminho) {
    if (-not (Test-Path -LiteralPath $caminho)) { return [pscustomobject]@{ Itens=0; Bytes=0 } }
    $itens = @(Get-ChildItem -LiteralPath $caminho -Recurse -Force -ErrorAction SilentlyContinue)
    $bytes = ($itens | Where-Object { -not $_.PSIsContainer } | Measure-Object -Property Length -Sum).Sum
    return [pscustomobject]@{ Itens=$itens.Count; Bytes=[int64]$bytes }
}

# Locais seguros de limpeza (apenas pastas de temporários/cache)
$alvos = @(
    [pscustomobject]@{ Nome='Temporários do usuário';        Caminho=$env:TEMP },
    [pscustomobject]@{ Nome='Temporários do Windows';        Caminho='C:\Windows\Temp' },
    [pscustomobject]@{ Nome='Cache do Windows Update (Download)'; Caminho='C:\Windows\SoftwareDistribution\Download' }
)

Titulo 'Limpeza segura'
Write-Host '  Desenvolvido por Pablo Murad - 2026' -ForegroundColor DarkGray
Write-Host ''
Write-Host 'Analisando o que pode ser limpo... (nada é apagado ainda)' -ForegroundColor Gray

$totalBytes = 0
foreach ($alvo in $alvos) {
    $m = Medir $alvo.Caminho
    $alvo | Add-Member -NotePropertyName Bytes -NotePropertyValue $m.Bytes -Force
    $alvo | Add-Member -NotePropertyName Itens -NotePropertyValue $m.Itens -Force
    $totalBytes += $m.Bytes
}

Titulo 'Prévia (o que será limpo)'
foreach ($alvo in $alvos) {
    $cor = if ($alvo.Bytes -gt 0) { 'White' } else { 'DarkGray' }
    Write-Host ("  {0,-38} {1,10}  ({2} itens)" -f $alvo.Nome, (Tam $alvo.Bytes), $alvo.Itens) -ForegroundColor $cor
    Write-Host ("     {0}" -f $alvo.Caminho) -ForegroundColor DarkGray
}
Write-Host ''
Write-Host ("Total recuperável (aprox.): {0}" -f (Tam $totalBytes)) -ForegroundColor Cyan
Write-Host '(Arquivos em uso são pulados automaticamente.)' -ForegroundColor DarkGray

Write-Host ''
$ok = Read-Host 'Limpar os temporários listados acima? (s/N)'
if ($ok -match '^(s|sim|y|yes)$') {
    Titulo 'Limpando'
    foreach ($alvo in $alvos) {
        if (-not (Test-Path -LiteralPath $alvo.Caminho)) { continue }
        Write-Host ("  {0}..." -f $alvo.Nome) -ForegroundColor Gray
        Get-ChildItem -LiteralPath $alvo.Caminho -Force -ErrorAction SilentlyContinue | ForEach-Object {
            Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    # Recalcula o que sobrou p/ estimar o que foi liberado
    $sobrou = 0
    foreach ($alvo in $alvos) { $sobrou += (Medir $alvo.Caminho).Bytes }
    $liberado = $totalBytes - $sobrou
    if ($liberado -lt 0) { $liberado = 0 }
    Write-Host ''
    Write-Host ("[OK] Liberado aproximadamente: {0}" -f (Tam $liberado)) -ForegroundColor Green
} else {
    Write-Host 'Temporários não foram alterados.' -ForegroundColor Yellow
}

Write-Host ''
$lix = Read-Host 'Esvaziar a Lixeira também? (s/N)'
if ($lix -match '^(s|sim|y|yes)$') {
    try {
        Clear-RecycleBin -Force -ErrorAction Stop
        Write-Host '[OK] Lixeira esvaziada.' -ForegroundColor Green
    } catch {
        if ("$($_.Exception.Message)" -match 'empty|vazia|0x8000FFFF') { Write-Host '[OK] A Lixeira já estava vazia.' -ForegroundColor Green }
        else { Write-Host "[!] Não foi possível esvaziar a Lixeira: $($_.Exception.Message)" -ForegroundColor Yellow }
    }
}

Titulo 'Concluído'
Write-Host 'Limpeza finalizada.' -ForegroundColor Green
Pausar
