<# :
@echo off
set "SELF=%~f0"
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression ([System.IO.File]::ReadAllText($env:SELF,[System.Text.Encoding]::UTF8))"
exit /b %errorlevel%
#>

# ============================================================
#  Verificar Discos - saúde dos HDs/SSDs (somente leitura)
#  Desenvolvido por Pablo Murad - 2026
# ============================================================

try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
try { $Host.UI.RawUI.WindowTitle = 'Verificar Discos' } catch {}

# ------------------------------------------------------------
# Auto-elevação para administrador (necessário p/ ler tudo)
# ------------------------------------------------------------
$souAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $souAdmin) {
    Write-Host 'Solicitando privilégios de administrador...' -ForegroundColor Yellow
    try {
        Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', "`"$env:SELF`"" -Verb RunAs | Out-Null
    } catch {
        Write-Host '[!] Sem elevação. Alguns dados (temperatura, testes) podem faltar.' -ForegroundColor Yellow
        Start-Sleep -Seconds 2
    }
    exit
}

function Pausar {
    Write-Host ''
    Write-Host 'Pressione Enter para voltar ao menu...' -ForegroundColor DarkGray
    [void][System.Console]::ReadLine()
}

function Titulo($texto) {
    Write-Host ''
    Write-Host '============================================================' -ForegroundColor DarkCyan
    Write-Host "  $texto" -ForegroundColor Cyan
    Write-Host '============================================================' -ForegroundColor DarkCyan
}

function Cor-Saude($status) {
    switch ("$status") {
        'Healthy' { 'Green' }
        'Warning' { 'Yellow' }
        default   { if ([string]::IsNullOrWhiteSpace("$status")) { 'DarkGray' } else { 'Red' } }
    }
}

function Formatar-Tamanho($bytes) {
    if (-not $bytes) { return '-' }
    $gb = [double]$bytes / 1GB
    if ($gb -ge 1024) { return ('{0:N2} TB' -f ($gb / 1024)) }
    return ('{0:N0} GB' -f $gb)
}

$smartctl = Get-Command smartctl -ErrorAction SilentlyContinue

# ------------------------------------------------------------
# Ação 1: Diagnóstico de saúde (rápido, somente leitura)
# ------------------------------------------------------------
function Diagnostico-Saude {
    Titulo 'Diagnóstico de saúde'

    $discos = Get-PhysicalDisk | Sort-Object DeviceId
    foreach ($d in $discos) {
        $cor = Cor-Saude $d.HealthStatus
        Write-Host ''
        Write-Host ("Disco {0}: {1}" -f $d.DeviceId, $d.FriendlyName) -ForegroundColor White
        Write-Host ("   Tipo:      {0}   |   Tamanho: {1}   |   Barramento: {2}" -f `
            $d.MediaType, (Formatar-Tamanho $d.Size), $d.BusType) -ForegroundColor Gray
        Write-Host ("   Saúde:     {0}   (operacional: {1})" -f $d.HealthStatus, ($d.OperationalStatus -join ',')) -ForegroundColor $cor

        # Contadores de confiabilidade (temperatura, desgaste, erros)
        try {
            $rc = $d | Get-StorageReliabilityCounter -ErrorAction Stop
            $partes = @()
            if ($null -ne $rc.Temperature)      { $partes += "Temp: $($rc.Temperature) C" }
            if ($null -ne $rc.Wear)             { $partes += "Desgaste: $($rc.Wear)%" }
            if ($null -ne $rc.PowerOnHours)     { $partes += "Horas ligado: $($rc.PowerOnHours)" }
            if ($null -ne $rc.ReadErrorsTotal)  { $partes += "Erros leitura: $($rc.ReadErrorsTotal)" }
            if ($null -ne $rc.WriteErrorsTotal) { $partes += "Erros escrita: $($rc.WriteErrorsTotal)" }
            if ($partes.Count -gt 0) { Write-Host ("   " + ($partes -join '   |   ')) -ForegroundColor DarkGray }
        } catch {}

        # SMART detalhado via smartctl, se disponível
        if ($smartctl) {
            try {
                $dev = "/dev/pd$($d.DeviceId)"
                $saidaS = & smartctl -H -A -d ata $dev 2>$null
                if (-not $saidaS) { $saidaS = & smartctl -H -A $dev 2>$null }
                $linhaSaude = $saidaS | Select-String 'SMART overall-health|test result'
                if ($linhaSaude) { Write-Host ("   SMART:     " + ($linhaSaude[0].Line.Trim())) -ForegroundColor Gray }
                $attrs = $saidaS | Select-String 'Reallocated_Sector|Current_Pending|Offline_Uncorrectable|Power_On_Hours'
                foreach ($a in $attrs) { Write-Host ("      " + ($a.Line.Trim() -replace '\s{2,}', '  ')) -ForegroundColor DarkGray }
            } catch {}
        }
    }

    if (-not $smartctl) {
        Write-Host ''
        Write-Host '(Dica: para detalhes SMART avançados instale o smartmontools:' -ForegroundColor DarkGray
        Write-Host ' winget install smartmontools )' -ForegroundColor DarkGray
    }
}

# ------------------------------------------------------------
# Ação 2: Resumo simples
# ------------------------------------------------------------
function Resumo-Simples {
    Titulo 'Resumo simples'
    Get-PhysicalDisk | Sort-Object DeviceId | ForEach-Object {
        $ok  = $_.HealthStatus -eq 'Healthy'
        $txt = if ($ok) { 'OK' } else { "FALHA/AVISO ($($_.HealthStatus))" }
        $cor = Cor-Saude $_.HealthStatus
        Write-Host ('[{0}] {1,-32} {2,10}   ' -f $_.DeviceId, $_.FriendlyName, (Formatar-Tamanho $_.Size)) -NoNewline
        Write-Host $txt -ForegroundColor $cor
    }
}

# ------------------------------------------------------------
# Ação 3: Teste de superfície (leitura sequencial, só leitura)
# ------------------------------------------------------------
function Teste-Superficie {
    Titulo 'Teste de superfície (somente leitura)'
    $discos = Get-PhysicalDisk | Sort-Object DeviceId
    foreach ($d in $discos) {
        Write-Host ('  [{0}] {1}  ({2})' -f $d.DeviceId, $d.FriendlyName, (Formatar-Tamanho $d.Size)) -ForegroundColor Gray
    }
    Write-Host ''
    Write-Host 'AVISO: lê todos os setores do disco escolhido. Pode levar HORAS.' -ForegroundColor Yellow
    Write-Host 'É seguro (apenas leitura). Ctrl+C cancela a qualquer momento.' -ForegroundColor DarkGray
    $sel = Read-Host 'Número do disco para testar (Enter = cancelar)'
    if ([string]::IsNullOrWhiteSpace($sel)) { Write-Host 'Cancelado.' -ForegroundColor Gray; return }

    $alvo = $discos | Where-Object { "$($_.DeviceId)" -eq $sel.Trim() } | Select-Object -First 1
    if (-not $alvo) { Write-Host '[!] Disco não encontrado.' -ForegroundColor Yellow; return }

    $total = [int64]$alvo.Size
    $caminho = "\\.\PhysicalDrive$($alvo.DeviceId)"
    Write-Host ''
    Write-Host "Lendo $caminho  ($(Formatar-Tamanho $total))..." -ForegroundColor Cyan

    $bloco = 8MB
    $buffer = New-Object byte[] $bloco
    $lidos = [int64]0
    $errosRegioes = @()
    $inicio = Get-Date
    $ultimoPct = -1

    try {
        $fs = [System.IO.File]::Open($caminho, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    } catch {
        Write-Host "[ERRO] Não foi possível abrir o disco: $($_.Exception.Message)" -ForegroundColor Red
        return
    }

    try {
        while ($lidos -lt $total) {
            try {
                $n = $fs.Read($buffer, 0, $bloco)
                if ($n -le 0) { break }
                $lidos += $n
            } catch {
                $errosRegioes += ('offset {0:N0} MB' -f ($lidos / 1MB))
                # pula o bloco problemático e continua
                $lidos += $bloco
                try { $fs.Seek($lidos, [System.IO.SeekOrigin]::Begin) | Out-Null } catch { break }
            }

            $pct = [int](($lidos / $total) * 100)
            if ($pct -ne $ultimoPct) {
                $ultimoPct = $pct
                $decorrido = (Get-Date) - $inicio
                $mbs = if ($decorrido.TotalSeconds -gt 0) { ($lidos / 1MB) / $decorrido.TotalSeconds } else { 0 }
                Write-Host ("`r  Progresso: {0,3}%   ({1:N0}/{2:N0} MB)   {3:N0} MB/s   Erros: {4}   " -f `
                    $pct, ($lidos / 1MB), ($total / 1MB), $mbs, $errosRegioes.Count) -NoNewline -ForegroundColor Cyan
            }
        }
    } finally {
        $fs.Close()
    }

    Write-Host ''
    Write-Host ''
    if ($errosRegioes.Count -eq 0) {
        Write-Host "[OK] Nenhum erro de leitura. Todos os setores lidos com sucesso." -ForegroundColor Green
    } else {
        Write-Host ("[!] {0} regiões com erro de leitura (possíveis setores defeituosos):" -f $errosRegioes.Count) -ForegroundColor Red
        $errosRegioes | Select-Object -First 20 | ForEach-Object { Write-Host "     $_" -ForegroundColor Red }
        if ($errosRegioes.Count -gt 20) { Write-Host "     ... e mais $($errosRegioes.Count - 20)." -ForegroundColor Red }
    }
}

# ------------------------------------------------------------
# Menu principal
# ------------------------------------------------------------
while ($true) {
    Titulo 'Verificar Discos'
    Write-Host '  Desenvolvido por Pablo Murad - 2026' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '  [1] Diagnóstico de saúde (rápido, recomendado)' -ForegroundColor White
    Write-Host '        SMART, temperatura, erros e desgaste de todos os discos' -ForegroundColor DarkGray
    Write-Host '  [2] Teste de superfície (lê todos os setores - demorado)' -ForegroundColor White
    Write-Host '        Procura setores defeituosos num disco escolhido' -ForegroundColor DarkGray
    Write-Host '  [3] Resumo simples (só OK/Falha por disco)' -ForegroundColor White
    Write-Host '  [0] Sair' -ForegroundColor White
    Write-Host ''
    $op = Read-Host 'Escolha (0-3)'

    switch ($op.Trim()) {
        '1' { Diagnostico-Saude; Pausar }
        '2' { Teste-Superficie;  Pausar }
        '3' { Resumo-Simples;    Pausar }
        '0' { break }
        ''  { break }
        default { Write-Host '[!] Opção inválida.' -ForegroundColor Yellow; Start-Sleep -Seconds 1 }
    }
}
