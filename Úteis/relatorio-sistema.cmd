<# :
@echo off
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression ([System.IO.File]::ReadAllText('%~f0',[System.Text.Encoding]::UTF8))"
exit /b %errorlevel%
#>

# ============================================================
#  Relatório do sistema - specs, memória, discos e espaço
#  Desenvolvido por Pablo Murad - 2026
# ============================================================

try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
try { $Host.UI.RawUI.WindowTitle = 'Relatório do sistema' } catch {}

function Pausar { Write-Host ''; Write-Host 'Pressione Enter para fechar...' -ForegroundColor DarkGray; [void][System.Console]::ReadLine() }
function GB($bytes) { '{0:N1} GB' -f ($bytes/1GB) }

$linhas = New-Object System.Collections.Generic.List[string]
function Add($txt, $cor='Gray') { Write-Host $txt -ForegroundColor $cor; $linhas.Add($txt) }
function Sec($t) {
    Write-Host ''
    Write-Host "== $t ==" -ForegroundColor Cyan
    $linhas.Add(''); $linhas.Add("== $t ==")
}

Write-Host ''
Write-Host '============================================================' -ForegroundColor DarkCyan
Write-Host '  Relatório do sistema' -ForegroundColor Cyan
Write-Host '  Desenvolvido por Pablo Murad - 2026' -ForegroundColor DarkGray
Write-Host '============================================================' -ForegroundColor DarkCyan
$linhas.Add('=== Relatório do sistema - Desenvolvido por Pablo Murad - 2026 ===')
$linhas.Add("Gerado em: $(Get-Date -Format 'dd/MM/yyyy HH:mm')")

try {
    $os  = Get-CimInstance Win32_OperatingSystem
    $cs  = Get-CimInstance Win32_ComputerSystem
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1

    Sec 'Computador'
    Add ("Nome:      {0}" -f $env:COMPUTERNAME)
    Add ("Usuário:   {0}" -f $env:USERNAME)
    Add ("Fabricante:{0} {1}" -f $cs.Manufacturer, $cs.Model)
    Add ("Sistema:   {0}" -f $os.Caption)
    Add ("Versão:    {0} (build {1})" -f $os.Version, $os.BuildNumber)
    $boot = $os.LastBootUpTime
    $up = (Get-Date) - $boot
    Add ("Ligado há: {0}d {1}h {2}min  (desde {3:dd/MM HH:mm})" -f $up.Days, $up.Hours, $up.Minutes, $boot)

    Sec 'Processador e memória'
    Add ("CPU:       {0}" -f $cpu.Name.Trim())
    Add ("Núcleos:   {0} físicos / {1} lógicos" -f $cpu.NumberOfCores, $cpu.NumberOfLogicalProcessors)
    $ramTotal = $os.TotalVisibleMemorySize * 1KB
    $ramLivre = $os.FreePhysicalMemory * 1KB
    $ramUso   = $ramTotal - $ramLivre
    $pct = if ($ramTotal -gt 0) { [int](($ramUso / $ramTotal) * 100) } else { 0 }
    Add ("Memória:   {0} no total  |  {1} em uso ({2}%)  |  {3} livre" -f (GB $ramTotal), (GB $ramUso), $pct, (GB $ramLivre))

    Sec 'Vídeo'
    Get-CimInstance Win32_VideoController | ForEach-Object { Add ("GPU:       {0}" -f $_.Name) }

    Sec 'Discos físicos'
    Get-PhysicalDisk | Sort-Object DeviceId | ForEach-Object {
        $tam = if ($_.Size -ge 1TB) { '{0:N2} TB' -f ($_.Size/1TB) } else { GB $_.Size }
        $cor = if ($_.HealthStatus -eq 'Healthy') { 'Green' } elseif ($_.HealthStatus -eq 'Warning') { 'Yellow' } else { 'Red' }
        Add ("[{0}] {1,-26} {2,10}  {3}  ({4})" -f $_.DeviceId, $_.FriendlyName, $tam, $_.HealthStatus, $_.MediaType) $cor
    }

    Sec 'Espaço nas unidades'
    Get-Volume | Where-Object { $_.DriveLetter -and $_.Size -gt 0 } | Sort-Object DriveLetter | ForEach-Object {
        $usado = $_.Size - $_.SizeRemaining
        $pctU = if ($_.Size -gt 0) { [int](($usado / $_.Size) * 100) } else { 0 }
        $rot = if ($_.FileSystemLabel) { $_.FileSystemLabel } else { '(sem rótulo)' }
        $cor = if ($pctU -ge 90) { 'Red' } elseif ($pctU -ge 75) { 'Yellow' } else { 'Gray' }
        Add ("{0}:  {1,-18} {2} livres de {3}  ({4}% usado)" -f $_.DriveLetter, $rot, (GB $_.SizeRemaining), (GB $_.Size), $pctU) $cor
    }
} catch {
    Write-Host "[ERRO] $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ''
$salvar = Read-Host 'Salvar este relatório num arquivo .txt? (s/N)'
if ($salvar -match '^(s|sim|y|yes)$') {
    $arq = Join-Path ([Environment]::GetFolderPath('Desktop')) ("relatorio-sistema_{0}.txt" -f (Get-Date -Format 'yyyy-MM-dd_HH-mm'))
    try { $linhas | Set-Content -LiteralPath $arq -Encoding UTF8; Write-Host "[OK] Salvo em: $arq" -ForegroundColor Green }
    catch { Write-Host "[ERRO] Não foi possível salvar: $($_.Exception.Message)" -ForegroundColor Red }
}
Pausar
