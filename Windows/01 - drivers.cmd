<# :
@echo off
set "SELF=%~f0"
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression ([System.IO.File]::ReadAllText($env:SELF,[System.Text.Encoding]::UTF8))"
exit /b %errorlevel%
#>

# ============================================================
#  Drivers - backup, restauração e atualização de drivers
#  Desenvolvido por Pablo Murad - 2026
# ============================================================

try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
try { $Host.UI.RawUI.WindowTitle = 'Drivers' } catch {}

# ------------------------------------------------------------
# Auto-elevação: exportar e instalar driver exige administrador
# ------------------------------------------------------------
$souAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $souAdmin) {
    Write-Host 'Solicitando privilégios de administrador...' -ForegroundColor Yellow
    try {
        Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', "`"$env:SELF`"" -Verb RunAs | Out-Null
    } catch {
        Write-Host "[ERRO] Sem administrador não dá para mexer em driver: $($_.Exception.Message)" -ForegroundColor Red
        Start-Sleep -Seconds 3
    }
    exit
}

function Pausar { Write-Host ''; Write-Host 'Pressione Enter para voltar ao menu...' -ForegroundColor DarkGray; [void][System.Console]::ReadLine() }
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

$configDir  = Join-Path $env:APPDATA 'Drivers'
$configFile = Join-Path $configDir 'config.json'
function Carregar-Config { if (Test-Path -LiteralPath $configFile) { try { return Get-Content -LiteralPath $configFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch {} }; return $null }
function Salvar-Config($o) { try { New-Item -ItemType Directory -Path $configDir -Force | Out-Null; $o | ConvertTo-Json | Set-Content -LiteralPath $configFile -Encoding UTF8 } catch {} }

# Pergunta a pasta de saida: sugere a ultima usada e cria se nao existir
function Pedir-Saida($padrao) {
    while ($true) {
        Titulo 'Pasta dos drivers'
        Write-Host "  $padrao" -ForegroundColor White
        Write-Host 'Enter = usar esta pasta   |   ou cole/digite outra (pendrive, rede...)' -ForegroundColor DarkGray
        $r = Read-Host 'Pasta'
        $d = if ([string]::IsNullOrWhiteSpace($r)) { $padrao } else { $r.Trim().Trim('"') }
        try { New-Item -ItemType Directory -Path $d -Force | Out-Null; return (Resolve-Path -LiteralPath $d).Path }
        catch { Write-Host '[!] Não foi possível criar/usar essa pasta.' -ForegroundColor Yellow }
    }
}

function Abrir($titulo) {
    Titulo $titulo
    Write-Host '  Desenvolvido por Pablo Murad - 2026' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host 'Verificando o que é necessário...' -ForegroundColor Gray
}

# Pergunta S/n; Enter aceita o padrao
function Confirmar([string]$pergunta, [bool]$padraoSim) {
    $dica = if ($padraoSim) { '(S/n)' } else { '(s/N)' }
    $r = Read-Host "$pergunta $dica"
    if ([string]::IsNullOrWhiteSpace($r)) { return $padraoSim }
    return ($r.Trim() -match '^(?i)(s|sim|y|yes)$')
}

function Abrir-Url([string]$u) {
    try { Start-Process $u | Out-Null; Write-Host "  Abrindo: $u" -ForegroundColor Gray }
    catch { Write-Host "  Abra no navegador: $u" -ForegroundColor White }
}

# Pede uma pasta ja existente, sugerindo um padrao
function Pedir-Pasta([string]$sugestao, [string]$dica) {
    Write-Host "  $sugestao" -ForegroundColor White
    Write-Host $dica -ForegroundColor DarkGray
    $r = Read-Host 'Pasta com os drivers'
    $d = if ([string]::IsNullOrWhiteSpace($r)) { $sugestao } else { $r.Trim().Trim('"') }
    if (-not (Test-Path -LiteralPath $d -PathType Container)) {
        Write-Host '[!] Pasta não encontrada.' -ForegroundColor Yellow
        return $null
    }
    return (Resolve-Path -LiteralPath $d).Path
}

# ------------------------------------------------------------
# Identificação da máquina
# ------------------------------------------------------------
function Detectar-Maquina {
    $fab = ''; $mod = ''; $placa = ''
    try {
        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        $fab = "$($cs.Manufacturer)".Trim()
        $mod = "$($cs.Model)".Trim()
    } catch { Write-Host "[!] Não consegui ler o fabricante: $($_.Exception.Message)" -ForegroundColor DarkGray }
    try {
        $bb = Get-CimInstance Win32_BaseBoard -ErrorAction Stop | Select-Object -First 1
        $placa = ("{0} {1}" -f "$($bb.Manufacturer)".Trim(), "$($bb.Product)".Trim()).Trim()
    } catch { Write-Host "[!] Não consegui ler a placa-mãe: $($_.Exception.Message)" -ForegroundColor DarkGray }

    $marca = 'outro'
    if     ($fab -match '(?i)dell')          { $marca = 'dell' }
    elseif ($fab -match '(?i)hp|hewlett')    { $marca = 'hp' }
    elseif ($fab -match '(?i)lenovo')        { $marca = 'lenovo' }
    # Quando o "fabricante" e' um fabricante de placa-mae, a maquina e' montada
    elseif ($fab -match '(?i)system manufacturer|to be filled|o\.e\.m\.|asrock|gigabyte|micro-star|^msi$|biostar|supermicro' -or $fab -eq '') { $marca = 'montado' }

    if (-not $fab)   { $fab = '(desconhecido)' }
    if (-not $mod)   { $mod = '(desconhecido)' }
    if (-not $placa) { $placa = '(desconhecida)' }
    return [pscustomobject]@{ Fabricante=$fab; Modelo=$mod; PlacaMae=$placa; Marca=$marca }
}

function Placas-Video {
    $r = @()
    try {
        foreach ($v in @(Get-CimInstance Win32_VideoController -ErrorAction Stop)) {
            $n = "$($v.Name)".Trim()
            if (-not $n) { continue }
            $tipo = if ($n -match '(?i)nvidia|geforce|quadro|rtx|gtx') { 'nvidia' }
                    elseif ($n -match '(?i)radeon|\bamd\b')            { 'amd' }
                    elseif ($n -match '(?i)intel')                     { 'intel' }
                    else                                               { 'outro' }
            $r += [pscustomobject]@{ Nome=$n; Tipo=$tipo; Versao="$($v.DriverVersion)" }
        }
    } catch { Write-Host "[!] Não consegui listar a placa de vídeo: $($_.Exception.Message)" -ForegroundColor DarkGray }
    return $r
}

# ------------------------------------------------------------
# Inventário de dispositivos
# ------------------------------------------------------------
$codigosProblema = @{
    1  = 'não está configurado corretamente'
    3  = 'driver corrompido ou sem memória'
    10 = 'não consegue iniciar'
    12 = 'não há recursos livres suficientes'
    18 = 'precisa reinstalar o driver'
    19 = 'registro do dispositivo com problema'
    21 = 'o Windows está removendo o dispositivo'
    22 = 'desativado'
    24 = 'não está presente ou está com defeito'
    28 = 'SEM DRIVER instalado'
    31 = 'o Windows não conseguiu carregar o driver'
    37 = 'o driver não inicializou'
    39 = 'driver corrompido ou ausente'
    43 = 'o Windows parou o dispositivo (erro relatado)'
    45 = 'não está conectado agora'
}

# Reduz o Hardware ID ao pedaco que o Catalog casa bem
function Hwid-Curto([string]$h) {
    if ($h -match '(?i)(PCI\\VEN_[0-9A-F]{4}&DEV_[0-9A-F]{4})')                        { return $matches[1].ToUpperInvariant() }
    if ($h -match '(?i)(USB\\VID_[0-9A-F]{4}&PID_[0-9A-F]{4})')                        { return $matches[1].ToUpperInvariant() }
    if ($h -match '(?i)(HDAUDIO\\FUNC_[0-9A-F]+&VEN_[0-9A-F]{4}&DEV_[0-9A-F]{4})')     { return $matches[1].ToUpperInvariant() }
    return $h
}

function Coletar-Dispositivos($problemas) {
    $drv = @{}
    try {
        foreach ($d in @(Get-CimInstance Win32_PnPSignedDriver -ErrorAction Stop)) {
            if ($d.DeviceID) { $drv["$($d.DeviceID)"] = $d }
        }
    } catch { Write-Host "[!] Não consegui ler as versões de driver: $($_.Exception.Message)" -ForegroundColor DarkGray }

    try { $ents = @(Get-CimInstance Win32_PnPEntity -ErrorAction Stop) }
    catch { Write-Host "[ERRO] Não consegui listar os dispositivos: $($_.Exception.Message)" -ForegroundColor Red; return @() }

    $lista = @()
    foreach ($e in $ents) {
        # O WMI devolve algumas entradas sem nome: nao servem para nada aqui
        if ([string]::IsNullOrWhiteSpace("$($e.Name)")) { continue }
        $cod = 0
        try { $cod = [int]$e.ConfigManagerErrorCode } catch { $cod = 0 }
        $d  = $drv["$($e.DeviceID)"]
        $hw = ''
        if ($e.HardwareID -and @($e.HardwareID).Count -gt 0) { $hw = "$(@($e.HardwareID)[0])" }
        $ver = if ($d -and $d.DriverVersion) { "$($d.DriverVersion)" } else { '-' }
        $dat = '-'
        if ($d -and $d.DriverDate) {
            try { $dat = ([datetime]$d.DriverDate).ToString('yyyy-MM-dd') } catch { $dat = '-' }
        }
        $lista += [pscustomobject]@{
            Nome       = "$($e.Name)"
            Classe     = if ($d) { "$($d.DeviceClass)" } else { '' }
            Fabricante = if ($d -and $d.DriverProviderName) { "$($d.DriverProviderName)" } else { "$($e.Manufacturer)" }
            Versao     = $ver
            Data       = $dat
            HardwareID = $hw
            Codigo     = $cod
            Problema   = if ($cod -ne 0) { if ($problemas.ContainsKey($cod)) { $problemas[$cod] } else { "código $cod" } } else { '' }
        }
    }
    return @($lista | Sort-Object Nome)
}

function Salvar-Inventario($disp, [string]$arquivo) {
    try {
        $disp | Select-Object Nome,Classe,Fabricante,Versao,Data,HardwareID,Codigo,Problema |
            Export-Csv -LiteralPath $arquivo -NoTypeInformation -Encoding UTF8
        Write-Host ''
        Write-Host ("[OK] Inventário salvo: {0}" -f $arquivo) -ForegroundColor Green
    } catch { Write-Host "[!] Não consegui salvar o inventário: $($_.Exception.Message)" -ForegroundColor Yellow }
}

# Devolve os dispositivos com defeito real (22 = desativado e 45 = desconectado nao sao)
function Mostrar-Inventario($disp) {
    $ruins = @($disp | Where-Object { $_.Codigo -ne 0 -and $_.Codigo -ne 22 -and $_.Codigo -ne 45 })
    Write-Host ''
    Write-Host ("Dispositivos encontrados: {0}" -f @($disp).Count) -ForegroundColor White
    if ($ruins.Count -eq 0) {
        Write-Host '[OK] Nenhum dispositivo com problema: está tudo com driver.' -ForegroundColor Green
        return @()
    }
    Write-Host ''
    Write-Host ("{0} dispositivo(s) precisando de atenção:" -f $ruins.Count) -ForegroundColor Yellow
    Write-Host ''
    foreach ($x in $ruins) {
        $cor = if ($x.Codigo -eq 28) { 'Red' } else { 'Yellow' }
        Write-Host ("  {0}" -f $x.Nome) -ForegroundColor $cor
        Write-Host ("     {0}" -f $x.Problema) -ForegroundColor DarkGray
        if ($x.HardwareID) { Write-Host ("     {0}" -f (Hwid-Curto $x.HardwareID)) -ForegroundColor DarkGray }
    }
    return $ruins
}

# ------------------------------------------------------------
# Backup: exportar os drivers que já funcionam nesta máquina
# ------------------------------------------------------------
function Exportar-Drivers([string]$pasta) {
    try { New-Item -ItemType Directory -Path $pasta -Force | Out-Null }
    catch { Write-Host "[ERRO] Não consegui criar a pasta: $($_.Exception.Message)" -ForegroundColor Red; return $false }

    Write-Host ''
    Write-Host 'Exportando os drivers instalados. Isso leva alguns minutos...' -ForegroundColor Gray
    Write-Host "Destino: $pasta" -ForegroundColor DarkGray
    $t0 = Get-Date
    & pnputil.exe /export-driver '*' "$pasta" 2>&1 | Out-Null

    # O codigo de saida do pnputil nao e' confiavel aqui: quem diz a verdade
    # e' a contagem de .inf que chegou no destino.
    $infs = @(Get-ChildItem -LiteralPath $pasta -Recurse -Filter '*.inf' -File -ErrorAction SilentlyContinue)
    if ($infs.Count -eq 0) {
        Write-Host '[ERRO] Nada foi exportado. Confirme que a janela está como administrador.' -ForegroundColor Red
        return $false
    }
    $bytes = 0
    foreach ($f in @(Get-ChildItem -LiteralPath $pasta -Recurse -File -ErrorAction SilentlyContinue)) { $bytes += $f.Length }
    Write-Host ("[OK] {0} driver(s) exportados, {1}, em {2:N0}s." -f $infs.Count, (Tam $bytes), ((Get-Date) - $t0).TotalSeconds) -ForegroundColor Green
    return $true
}

# Garante que existe backup de hoje; pula se ja tiver
function Garantir-Backup([string]$pastaHoje) {
    $jaTem = @(Get-ChildItem -LiteralPath $pastaHoje -Recurse -Filter '*.inf' -File -ErrorAction SilentlyContinue)
    if ($jaTem.Count -gt 0) {
        Write-Host ("[OK] Backup de hoje já existe ({0} drivers). Pulando." -f $jaTem.Count) -ForegroundColor Green
        return $true
    }
    Titulo 'Backup dos drivers desta máquina'
    return (Exportar-Drivers $pastaHoje)
}

# ------------------------------------------------------------
# Leitura de .inf - para a prévia antes de restaurar
# ------------------------------------------------------------
$nomesClasse = @{
    'net'='Rede'; 'display'='Vídeo'; 'media'='Áudio'; 'system'='Chipset/Sistema'
    'usb'='USB'; 'bluetooth'='Bluetooth'; 'hidclass'='Entrada (teclado/mouse)'
    'mouse'='Mouse'; 'keyboard'='Teclado'; 'printer'='Impressora'; 'image'='Câmera/Scanner'
    'scsiadapter'='Armazenamento'; 'hdc'='Armazenamento'; 'diskdrive'='Disco'
    'monitor'='Monitor'; 'firmware'='Firmware'; 'smartcardreader'='Leitor de cartão'
    'ports'='Portas COM/LPT'; 'battery'='Bateria'; 'biometric'='Biometria'
    'camera'='Câmera'; 'securitydevices'='Segurança'; 'softwarecomponent'='Componente do fabricante'
    'extension'='Extensão de driver'; 'volume'='Volume'; 'computer'='Computador'
    'modem'='Modem'; 'sdhost'='Leitor de cartão SD'; 'usbdevice'='Dispositivo USB'
}

function Ler-Inf([string]$caminho, $mapaClasses) {
    $info = [pscustomobject]@{
        Arquivo  = $caminho
        Nome     = [System.IO.Path]::GetFileName($caminho)
        Classe   = '?'
        Amigavel = 'Outro'
        Provedor = '?'
        Versao   = '-'
        Data     = '-'
    }
    # Le o arquivo inteiro de proposito: o [Strings] fica no FIM do .inf, e
    # ler so' o comeco deixaria os tokens %NOME% sem resolver.
    $linhas = $null
    try { $linhas = [System.IO.File]::ReadAllLines($caminho) } catch { return $info }

    # Uma passada so': [Version] da' os dados, [Strings] resolve os tokens
    $strings = @{}
    $secao = ''
    foreach ($l in $linhas) {
        $t = "$l".Trim()
        if ($t -match '^\[(.+)\]\s*$') { $secao = $matches[1].Trim().ToLowerInvariant(); continue }
        if ($secao -eq 'strings') {
            if ($t -match '^([^;=]+?)\s*=\s*"?([^";]*)"?\s*$') { $strings[$matches[1].Trim()] = $matches[2].Trim() }
            continue
        }
        if ($secao -ne 'version') { continue }
        if ($t -match '^(?i)class\s*=\s*([^;]+)')     { $info.Classe   = $matches[1].Trim() }
        if ($t -match '^(?i)provider\s*=\s*([^;]+)')  { $info.Provedor = $matches[1].Trim() }
        if ($t -match '^(?i)driverver\s*=\s*([^;]+)') {
            $p = $matches[1].Trim() -split ','
            if ($p.Count -ge 1) { $info.Data   = $p[0].Trim() }
            if ($p.Count -ge 2) { $info.Versao = $p[1].Trim() }
        }
    }
    if ($info.Provedor -match '^%(.+)%$') {
        $k = $matches[1]
        if ($strings.ContainsKey($k)) { $info.Provedor = $strings[$k] }
    }
    $ck = $info.Classe.ToLowerInvariant()
    $info.Amigavel = if ($mapaClasses.ContainsKey($ck)) { $mapaClasses[$ck] } else { $info.Classe }
    return $info
}

function Listar-Infs([string]$pasta, $mapaClasses) {
    $arqs = @(Get-ChildItem -LiteralPath $pasta -Recurse -Filter '*.inf' -File -ErrorAction SilentlyContinue)
    if ($arqs.Count -eq 0) { return @() }
    Write-Host ("Lendo {0} arquivo(s) .inf..." -f $arqs.Count) -ForegroundColor Gray
    $r = @()
    foreach ($a in $arqs) { $r += (Ler-Inf $a.FullName $mapaClasses) }
    return @($r | Sort-Object Amigavel, Provedor, Nome)
}

function Previa-Infs($infs) {
    Titulo 'Prévia: o que será instalado'
    foreach ($g in @($infs | Group-Object Amigavel | Sort-Object Count -Descending)) {
        Write-Host ''
        Write-Host ("  {0}  ({1})" -f $g.Name, $g.Count) -ForegroundColor Cyan
        foreach ($i in @($g.Group | Sort-Object Provedor, Nome)) {
            Write-Host ("     {0,-30} {1,-16} {2}" -f $i.Provedor, $i.Versao, $i.Nome) -ForegroundColor Gray
        }
    }
    Write-Host ''
    Write-Host ("TOTAL: {0} driver(s)" -f @($infs).Count) -ForegroundColor White
    Write-Host 'Nada é apagado: o Windows mantém o driver mais adequado entre o atual e o novo.' -ForegroundColor DarkGray
}

# Codigos do pnputil, medidos: 0 = instalou, 3010 = instalou e pede reinicio,
# 259 = o driver JA estava no repositorio (nao e' erro). Arquivo invalido
# devolve numero NEGATIVO, entao comparar sempre com -ne, nunca com -gt.
function Pnputil-Ok([int]$rc)  { return ($rc -eq 0 -or $rc -eq 3010 -or $rc -eq 259) }
function Pnputil-Novo([int]$rc) { return ($rc -eq 0 -or $rc -eq 3010) }

# Instala um .inf por vez: lento, mas diz exatamente qual falhou
function Instalar-Um-A-Um($infs) {
    $ok = 0; $ign = 0; $err = 0; $reinicia = $false
    $tot = @($infs).Count
    $n = 0
    foreach ($i in $infs) {
        $n++
        Write-Progress -Activity 'Instalando drivers' -Status $i.Nome -PercentComplete ([int](100 * $n / $tot))
        $saida = & pnputil.exe /add-driver "$($i.Arquivo)" /install 2>&1
        $rc = $LASTEXITCODE
        if ($rc -eq 3010) { $reinicia = $true }
        if (Pnputil-Novo $rc)   { $ok++ }
        elseif (Pnputil-Ok $rc) { $ign++ }
        else {
            $err++
            Write-Host ("  [ERRO] {0}" -f $i.Nome) -ForegroundColor Red
            $motivo = (@($saida) | Where-Object { "$_".Trim() } | Select-Object -Last 1)
            if ($motivo) { Write-Host ("         {0}" -f "$motivo".Trim()) -ForegroundColor DarkGray }
        }
    }
    Write-Progress -Activity 'Instalando drivers' -Completed
    return [pscustomobject]@{ Ok=$ok; Ignorados=$ign; Erros=$err; Reinicia=$reinicia }
}

# Tenta a chamada unica (segundos em vez de minutos) e, se falhar,
# refaz um por um so' para saber qual driver deu problema.
function Instalar-Infs($infs, [string]$pastaLote) {
    if ($pastaLote) {
        Write-Host ("Instalando {0} driver(s) de uma vez..." -f @($infs).Count) -ForegroundColor Gray
        $curinga = Join-Path $pastaLote '*.inf'
        & pnputil.exe /add-driver "$curinga" /subdirs /install 2>&1 | Out-Null
        $rc = $LASTEXITCODE
        if (Pnputil-Ok $rc) {
            Write-Host ''
            if ($rc -eq 259) { Write-Host '[OK] Os drivers dessa pasta já estavam no repositório.' -ForegroundColor Green }
            else             { Write-Host ("[OK] {0} driver(s) instalados." -f @($infs).Count) -ForegroundColor Green }
            if ($rc -eq 3010) { Write-Host '[i] É preciso REINICIAR para concluir.' -ForegroundColor Cyan }
            return $true
        }
        Write-Host ''
        Write-Host ("[!] A instalação em lote terminou com o código {0}." -f $rc) -ForegroundColor Yellow
        Write-Host '    Refazendo um por um para identificar o que falhou...' -ForegroundColor Yellow
        Write-Host ''
    }
    $r = Instalar-Um-A-Um $infs
    Write-Host ''
    Write-Host ("Instalados:  {0}" -f $r.Ok) -ForegroundColor Green
    if ($r.Ignorados -gt 0) { Write-Host ("Já existiam: {0}" -f $r.Ignorados) -ForegroundColor Yellow }
    if ($r.Erros -gt 0) {
        Write-Host ("Falharam:    {0}" -f $r.Erros) -ForegroundColor Red
        Write-Host 'Driver que falha aqui costuma ser de hardware que não existe nesta máquina.' -ForegroundColor DarkGray
    }
    if ($r.Reinicia) { Write-Host '[i] É preciso REINICIAR para concluir.' -ForegroundColor Cyan }
    return (($r.Ok + $r.Ignorados) -gt 0)
}

# ------------------------------------------------------------
# Atualizações pelo Windows Update
# ------------------------------------------------------------
function Buscar-Atualizacoes {
    Titulo 'Procurar atualizações de driver'
    Write-Host 'Consultando o Windows Update. Pode levar de 1 a 3 minutos...' -ForegroundColor Gray

    $ses = $null
    try { $ses = New-Object -ComObject Microsoft.Update.Session -ErrorAction Stop }
    catch { Write-Host "[ERRO] Não consegui falar com o Windows Update: $($_.Exception.Message)" -ForegroundColor Red; return }

    $res = $null
    # O Microsoft Update traz os drivers opcionais que o Windows Update comum esconde
    try {
        $b = $ses.CreateUpdateSearcher()
        $b.ServerSelection = 3
        $b.ServiceID = '7971f918-a847-4430-9279-4a52d1efe18d'
        $res = $b.Search("IsInstalled=0 and Type='Driver'")
    } catch {
        Write-Host ("[!] Microsoft Update indisponível ({0})." -f $_.Exception.Message) -ForegroundColor Yellow
        Write-Host '    Tentando pelo Windows Update padrão...' -ForegroundColor Yellow
        try {
            $b2 = $ses.CreateUpdateSearcher()
            $res = $b2.Search("IsInstalled=0 and Type='Driver'")
        } catch { Write-Host "[ERRO] A busca falhou: $($_.Exception.Message)" -ForegroundColor Red; return }
    }

    $achados = @($res.Updates)
    if ($achados.Count -eq 0) {
        Write-Host ''
        Write-Host '[OK] Nenhuma atualização de driver pendente.' -ForegroundColor Green
        return
    }

    Titulo ('Prévia: {0} atualização(ões) encontrada(s)' -f $achados.Count)
    $bytes = 0
    foreach ($u in $achados) {
        $tam = 0
        try { $tam = [double]$u.MaxDownloadSize } catch { $tam = 0 }
        $bytes += $tam
        Write-Host ("  {0}" -f $u.Title) -ForegroundColor Gray
        $quando = ''
        try { if ($u.DriverVerDate) { $quando = ([datetime]$u.DriverVerDate).ToString('yyyy-MM-dd') } } catch { $quando = '' }
        if ($quando -or $tam -gt 0) {
            Write-Host ("     {0}  {1}" -f $quando, $(if ($tam -gt 0) { Tam $tam } else { '' })) -ForegroundColor DarkGray
        }
    }
    Write-Host ''
    if ($bytes -gt 0) { Write-Host ("Download total: {0}" -f (Tam $bytes)) -ForegroundColor White }
    Write-Host ''
    if (-not (Confirmar 'Baixar e instalar tudo?' $true)) { Write-Host 'Cancelado.' -ForegroundColor Yellow; return }

    $col = New-Object -ComObject Microsoft.Update.UpdateColl
    foreach ($u in $achados) {
        try { if (-not $u.EulaAccepted) { $u.AcceptEula() } }
        catch { Write-Host ("  [!] Não aceitei o EULA de '{0}': {1}" -f $u.Title, $_.Exception.Message) -ForegroundColor DarkGray }
        [void]$col.Add($u)
    }

    Write-Host ''
    Write-Host 'Baixando...' -ForegroundColor Gray
    try { $dl = $ses.CreateUpdateDownloader(); $dl.Updates = $col; [void]$dl.Download() }
    catch { Write-Host "[ERRO] Falha no download: $($_.Exception.Message)" -ForegroundColor Red; return }

    Write-Host 'Instalando...' -ForegroundColor Gray
    try {
        $ins = $ses.CreateUpdateInstaller(); $ins.Updates = $col
        $r = $ins.Install()
        switch ([int]$r.ResultCode) {
            2 { Write-Host '[OK] Instalado com sucesso.' -ForegroundColor Green }
            3 { Write-Host '[!] Instalado, mas com avisos. Confira o Gerenciador de Dispositivos.' -ForegroundColor Yellow }
            default { Write-Host ("[!] A instalação terminou com o código {0}." -f $r.ResultCode) -ForegroundColor Yellow }
        }
        if ($r.RebootRequired) { Write-Host '[i] É preciso REINICIAR para concluir.' -ForegroundColor Cyan }
    } catch { Write-Host "[ERRO] Falha na instalação: $($_.Exception.Message)" -ForegroundColor Red }
}

# ------------------------------------------------------------
# Microsoft Update Catalog
# A unica parte do programa que depende do HTML de um site alheio.
# Quando a Microsoft mudar a pagina, as regex abaixo param de casar.
# ------------------------------------------------------------
function Catalog-Preparar {
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 }
    catch { Write-Host "[!] Não consegui forçar TLS 1.2: $($_.Exception.Message)" -ForegroundColor DarkGray }
}

function Catalog-Buscar([string]$hwid) {
    $url = 'https://www.catalog.update.microsoft.com/Search.aspx?q=' + [System.Uri]::EscapeDataString($hwid)
    $html = $null
    try { $html = (Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 90).Content }
    catch {
        Write-Host ("     [ERRO] Não consegui consultar o Catalog: {0}" -f $_.Exception.Message) -ForegroundColor Red
        Write-Host ("     Busca manual: {0}" -f $url) -ForegroundColor White
        return @()
    }

    # O id do link vem com aspas SIMPLES na pagina real: aceitar os dois tipos
    $achados = @()
    $rx = [regex]'(?s)<a[^>]+id=["'']([0-9a-fA-F\-]{36})_link["''][^>]*>(.*?)</a>(.*?)</tr>'
    foreach ($m in $rx.Matches($html)) {
        $celulas = @()
        foreach ($c in [regex]::Matches($m.Groups[3].Value, '(?s)<td[^>]*>(.*?)</td>')) {
            $txt = ($c.Groups[1].Value -replace '<[^>]+>', '').Trim()
            if ($txt) { $celulas += $txt }
        }
        $data = $null; $versao = ''
        foreach ($txt in $celulas) {
            if (-not $data -and $txt -match '^\d{1,2}/\d{1,2}/\d{4}$') {
                try { $data = [datetime]::Parse($txt, [System.Globalization.CultureInfo]::GetCultureInfo('en-US')) } catch { $data = $null }
                continue
            }
            if (-not $versao -and $txt -match '^\d+(\.\d+){1,3}$') { $versao = $txt }
        }
        $achados += [pscustomobject]@{
            Id       = $m.Groups[1].Value
            Titulo   = ($m.Groups[2].Value -replace '<[^>]+>', '').Trim()
            Produtos = if ($celulas.Count -gt 0) { $celulas[0] } else { '' }
            Data     = $data
            Versao   = $versao
        }
    }
    if ($achados.Count -eq 0) { return @() }

    # O titulo nao diz a versao do Windows: quem diz e' a coluna de produtos
    $arch = if ([Environment]::Is64BitOperatingSystem) { 'x64' } else { 'x86' }
    $win  = if ([Environment]::OSVersion.Version.Build -ge 22000) { 'Windows 11' } else { 'Windows 10' }
    $ctx  = { param($x) "$($x.Titulo) $($x.Produtos)" }
    $bons = @($achados | Where-Object { (& $ctx $_) -notmatch '(?i)\b(arm64|itanium)\b' })
    if ($arch -eq 'x86') { $bons = @($bons | Where-Object { (& $ctx $_) -notmatch '(?i)x64' }) }
    $doWin = @($bons | Where-Object { (& $ctx $_) -match [regex]::Escape($win) })
    if ($doWin.Count -gt 0) { $bons = $doWin }
    if ($bons.Count -eq 0) { $bons = $achados }

    # A mesma atualizacao aparece repetida uma vez por produto: fica uma so'
    $vistos = @{}
    $unicos = @()
    foreach ($b in @($bons | Sort-Object @{ Expression = { if ($_.Data) { $_.Data } else { [datetime]::MinValue } } } -Descending)) {
        $chave = "$($b.Titulo)|$($b.Versao)"
        if ($vistos.ContainsKey($chave)) { continue }
        $vistos[$chave] = $true
        $unicos += $b
    }
    return @($unicos)
}

function Catalog-Baixar([string]$updateId, [string]$destino) {
    try { New-Item -ItemType Directory -Path $destino -Force | Out-Null }
    catch { Write-Host ("     [ERRO] Não consegui criar a pasta: {0}" -f $_.Exception.Message) -ForegroundColor Red; return $null }

    $json = '[{"size":0,"languages":"","uidInfo":"' + $updateId + '","updateID":"' + $updateId + '"}]'
    $body = 'updateIDs=' + [System.Uri]::EscapeDataString($json) + '&updateIDsBlockedForInstall=&wsusApiPresent=&contentImport=&sku=&serverName=&ssl=&portNumber=&version='
    $html = $null
    try {
        $html = (Invoke-WebRequest -Uri 'https://www.catalog.update.microsoft.com/DownloadDialog.aspx' `
                    -Method Post -Body $body -ContentType 'application/x-www-form-urlencoded' `
                    -UseBasicParsing -TimeoutSec 90).Content
    } catch {
        Write-Host ("     [ERRO] O Catalog recusou o pedido de download: {0}" -f $_.Exception.Message) -ForegroundColor Red
        return $null
    }

    $link = @([regex]::Matches($html, '(?i)https?://[^\s]+?\.(?:cab|msu|exe)') | ForEach-Object { $_.Value } | Select-Object -Unique -First 1)
    if ($link.Count -eq 0) {
        Write-Host '     [ERRO] Não achei o link do arquivo na resposta do Catalog.' -ForegroundColor Red
        Write-Host '     A página do Catalog deve ter mudado de formato.' -ForegroundColor DarkGray
        return $null
    }
    $url = $link[0]
    $arq = Join-Path $destino ([System.IO.Path]::GetFileName(($url -split '\?')[0]))
    Write-Host ("     Baixando {0}..." -f [System.IO.Path]::GetFileName($arq)) -ForegroundColor Gray
    try { Invoke-WebRequest -Uri $url -OutFile $arq -UseBasicParsing -TimeoutSec 600 }
    catch { Write-Host ("     [ERRO] Falha no download: {0}" -f $_.Exception.Message) -ForegroundColor Red; return $null }
    if (-not (Test-Path -LiteralPath $arq)) { return $null }
    return $arq
}

# Extrai .cab/.msu com o expand.exe do proprio Windows
function Catalog-Extrair([string]$arquivo, [string]$destino) {
    $ext = [System.IO.Path]::GetExtension($arquivo).ToLowerInvariant()
    if ($ext -eq '.exe') {
        Write-Host '     [!] Veio um instalador .exe: rode-o à mão, o pnputil não abre isso.' -ForegroundColor Yellow
        Write-Host ("     {0}" -f $arquivo) -ForegroundColor White
        return $null
    }
    $dir = Join-Path $destino 'extraido'
    try { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    catch { Write-Host ("     [ERRO] {0}" -f $_.Exception.Message) -ForegroundColor Red; return $null }

    & expand.exe -F:* "$arquivo" "$dir" | Out-Null
    # Um .msu traz um .cab dentro: extrai o de dentro tambem
    foreach ($cab in @(Get-ChildItem -LiteralPath $dir -Filter '*.cab' -File -ErrorAction SilentlyContinue)) {
        & expand.exe -F:* "$($cab.FullName)" "$dir" | Out-Null
    }
    $infs = @(Get-ChildItem -LiteralPath $dir -Recurse -Filter '*.inf' -File -ErrorAction SilentlyContinue)
    if ($infs.Count -eq 0) {
        Write-Host '     [ERRO] O pacote não tinha nenhum .inf dentro.' -ForegroundColor Red
        return $null
    }
    return $dir
}

# Percorre os dispositivos sem driver e tenta resolver cada um pelo Catalog
function Catalog-Resolver($semDriver, [string]$pastaPc, $mapaClasses) {
    Titulo 'Microsoft Update Catalog'
    Write-Host ("{0} dispositivo(s) sem driver. Vou procurar um a um." -f @($semDriver).Count) -ForegroundColor Gray
    Write-Host 'Esta busca depende da página da Microsoft e pode falhar se o site mudar.' -ForegroundColor DarkGray
    Catalog-Preparar

    $resolvidos = 0
    foreach ($d in $semDriver) {
        $hw = Hwid-Curto $d.HardwareID
        Write-Host ''
        Write-Host ("  {0}" -f $d.Nome) -ForegroundColor White
        Write-Host ("     {0}" -f $hw) -ForegroundColor DarkGray

        $achados = Catalog-Buscar $hw
        if (@($achados).Count -eq 0) {
            Write-Host '     Nada encontrado para este dispositivo.' -ForegroundColor Yellow
            continue
        }
        $melhor = $achados[0]
        $quando = if ($melhor.Data) { $melhor.Data.ToString('yyyy-MM-dd') } else { 'sem data' }
        Write-Host ("     Encontrado: {0}" -f $melhor.Titulo) -ForegroundColor Green
        Write-Host ("     {0}   versão {1}" -f $quando, $(if ($melhor.Versao) { $melhor.Versao } else { '?' })) -ForegroundColor DarkGray
        if (-not (Confirmar '     Baixar e instalar este?' $true)) { continue }

        $pasta = Join-Path (Join-Path $pastaPc 'catalog') ($hw -replace '[\\&]', '_')
        $arq = Catalog-Baixar $melhor.Id $pasta
        if (-not $arq) { continue }
        $dir = Catalog-Extrair $arq $pasta
        if (-not $dir) { continue }

        $infs = Listar-Infs $dir $mapaClasses
        if (@($infs).Count -eq 0) { continue }
        if (Instalar-Infs $infs $dir) { $resolvidos++ }
    }

    Write-Host ''
    Write-Host ("Dispositivos resolvidos pelo Catalog: {0}" -f $resolvidos) -ForegroundColor Cyan
}

# ------------------------------------------------------------
# Ferramenta do fabricante
# ------------------------------------------------------------
# Windows recem-instalado as vezes vem sem o winget. Como ele e' o que
# instala as ferramentas dos fabricantes, o programa busca o instalador
# oficial (o mesmo aka.ms que a Microsoft publica) e o registra sozinho.
function Garantir-Winget {
    $w = Get-Command winget -ErrorAction SilentlyContinue
    if ($w) { return $w.Source }

    Write-Host ''
    Write-Host '[!] O winget não existe nesta máquina. Vou instalá-lo.' -ForegroundColor Yellow
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
    $pacote = Join-Path $env:TEMP 'AppInstaller.msixbundle'
    try {
        Write-Host '    Baixando o App Installer da Microsoft...' -ForegroundColor Gray
        Invoke-WebRequest -Uri 'https://aka.ms/getwinget' -OutFile $pacote -UseBasicParsing -TimeoutSec 600
    } catch {
        Write-Host ("[ERRO] Não consegui baixar o winget: {0}" -f $_.Exception.Message) -ForegroundColor Red
        return $null
    }
    try {
        Write-Host '    Instalando...' -ForegroundColor Gray
        Add-AppxPackage -Path $pacote -ErrorAction Stop
    } catch {
        Write-Host ("[ERRO] Não consegui instalar o winget: {0}" -f $_.Exception.Message) -ForegroundColor Red
        Write-Host '    Instale a "Instalador de Aplicativo" pela Microsoft Store e tente de novo.' -ForegroundColor White
        return $null
    }
    # O winget entra no PATH do usuario: recarrega sem precisar reabrir
    $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
    $w = Get-Command winget -ErrorAction SilentlyContinue
    if ($w) { Write-Host '[OK] winget instalado.' -ForegroundColor Green; return $w.Source }
    Write-Host '[!] O winget foi instalado mas só aparece depois de reabrir o programa.' -ForegroundColor Yellow
    return $null
}

function Tentar-Winget([string]$id, [string]$nome, [string]$url, [string]$fonte) {
    if (-not (Garantir-Winget)) { if ($url) { Abrir-Url $url }; return $false }
    Write-Host ("Instalando {0} pelo winget..." -f $nome) -ForegroundColor Gray
    if ($fonte) { & winget install --id $id -e --source $fonte --accept-package-agreements --accept-source-agreements }
    else        { & winget install --id $id -e --accept-package-agreements --accept-source-agreements }
    $rc = $LASTEXITCODE
    # -1978335189 = "nenhuma atualizacao disponivel", ou seja, ja esta instalado
    if ($rc -eq 0 -or $rc -eq -1978335189) {
        Write-Host ("[OK] {0} pronto." -f $nome) -ForegroundColor Green
        return $true
    }
    Write-Host ("[!] O winget não instalou o {0} (código {1})." -f $nome, $rc) -ForegroundColor Yellow
    if ($url) { Abrir-Url $url }
    return $false
}

function Achar-Exe([string]$nome, $pastas) {
    $c = Get-Command $nome -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    foreach ($b in $pastas) {
        if (-not $b -or -not (Test-Path -LiteralPath $b)) { continue }
        $a = Get-ChildItem -LiteralPath $b -Recurse -Filter $nome -File -ErrorAction SilentlyContinue |
             Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($a) { return $a.FullName }
    }
    return $null
}

function Achar-Dcu {
    foreach ($b in @("$env:ProgramFiles\Dell\CommandUpdate", "${env:ProgramFiles(x86)}\Dell\CommandUpdate")) {
        $p = Join-Path $b 'dcu-cli.exe'
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return $null
}

function Ferramenta-Fabricante($maq, [string]$pastaPc) {
    Titulo 'Ferramenta do fabricante'
    Write-Host ("Fabricante: {0}" -f $maq.Fabricante) -ForegroundColor White
    Write-Host ("Modelo:     {0}" -f $maq.Modelo) -ForegroundColor White
    Write-Host ("Placa-mãe:  {0}" -f $maq.PlacaMae) -ForegroundColor White
    Write-Host ''

    switch ($maq.Marca) {
        'dell' {
            $dcu = Achar-Dcu
            if (-not $dcu) {
                Write-Host 'O Dell Command | Update entrega o driver homologado para este modelo exato.' -ForegroundColor Gray
                if (Confirmar 'Instalar o Dell Command | Update agora?' $true) {
                    [void](Tentar-Winget 'Dell.CommandUpdate' 'Dell Command | Update' 'https://www.dell.com/support/kbdoc/pt-br/000177325/dell-command-update' '')
                    $dcu = Achar-Dcu
                }
            }
            if (-not $dcu) {
                Write-Host '[!] Não achei o dcu-cli.exe. Abra o Dell Command Update pelo menu Iniciar.' -ForegroundColor Yellow
            } else {
                Write-Host ''
                Write-Host 'Procurando atualizações na Dell...' -ForegroundColor Gray
                & $dcu /scan
                Write-Host ''
                if (Confirmar 'Aplicar as atualizações encontradas?' $true) {
                    & $dcu /applyUpdates -reboot=disable
                    Write-Host '[i] Pode ser preciso reiniciar.' -ForegroundColor Cyan
                }
            }
        }
        'hp' {
            $hpia = Achar-Exe 'HPImageAssistant.exe' @("$env:ProgramFiles\HP", "${env:ProgramFiles(x86)}\HP", 'C:\SWSetup')
            if (-not $hpia) {
                Write-Host 'O HP Image Assistant entrega o driver homologado para este modelo exato.' -ForegroundColor Gray
                if (Confirmar 'Instalar o HP Image Assistant agora?' $true) {
                    [void](Tentar-Winget 'HP.ImageAssistant' 'HP Image Assistant' 'https://hp.com/go/clientmanagement' '')
                    $hpia = Achar-Exe 'HPImageAssistant.exe' @("$env:ProgramFiles\HP", "${env:ProgramFiles(x86)}\HP", 'C:\SWSetup')
                }
            }
            if (-not $hpia) {
                Write-Host '[!] Não achei o HPImageAssistant.exe. Abra o HP Image Assistant pelo menu Iniciar.' -ForegroundColor Yellow
            } else {
                $rel = Join-Path $pastaPc 'hpia'
                try { New-Item -ItemType Directory -Path $rel -Force | Out-Null } catch { Write-Host "[!] $($_.Exception.Message)" -ForegroundColor DarkGray }
                Write-Host ''
                Write-Host 'Analisando e instalando os drivers da HP. Isso demora...' -ForegroundColor Gray
                & $hpia /Operation:Analyze /Action:Install /Selection:All /Category:Drivers /Silent `
                        /ReportFolder:"$rel" /SoftpaqDownloadFolder:"$rel"
                Write-Host ("[OK] HPIA terminou (código {0}). Relatório em {1}" -f $LASTEXITCODE, $rel) -ForegroundColor Green
                Write-Host '[i] Pode ser preciso reiniciar.' -ForegroundColor Cyan
            }
        }
        'lenovo' {
            $lsu = Achar-Exe 'Tvsu.exe' @("$env:ProgramFiles\Lenovo\System Update", "${env:ProgramFiles(x86)}\Lenovo\System Update")
            if (-not $lsu) {
                Write-Host 'Na Lenovo, quem faz esse trabalho é o System Update.' -ForegroundColor Gray
                if (Confirmar 'Instalar o Lenovo System Update agora?' $true) {
                    [void](Tentar-Winget 'Lenovo.SystemUpdate' 'Lenovo System Update' 'https://support.lenovo.com/solutions/ht003029' '')
                    $lsu = Achar-Exe 'Tvsu.exe' @("$env:ProgramFiles\Lenovo\System Update", "${env:ProgramFiles(x86)}\Lenovo\System Update")
                }
            }
            if ($lsu) {
                Write-Host ''
                Write-Host 'Abrindo o Lenovo System Update...' -ForegroundColor Gray
                try { Start-Process -FilePath $lsu | Out-Null }
                catch { Write-Host "[!] Não consegui abrir: $($_.Exception.Message)" -ForegroundColor Yellow }
            } else {
                Abrir-Url 'https://support.lenovo.com/solutions/ht003029'
            }
        }
        default {
            Write-Host 'Esta máquina não tem ferramenta de linha de comando do fabricante.' -ForegroundColor Yellow
            Write-Host 'Em PC montado o que importa é a placa-mãe: chipset, rede e áudio vêm dela.' -ForegroundColor Gray
            Write-Host ''
            Abrir-Url ('https://www.bing.com/search?q=' + [System.Uri]::EscapeDataString("$($maq.PlacaMae) drivers"))
        }
    }

    # Placa de video e' caso a parte: o pacote oficial traz o painel de controle
    $todas = @(Placas-Video)
    $gpus  = @($todas | Where-Object { $_.Tipo -eq 'nvidia' -or $_.Tipo -eq 'amd' })
    if ($gpus.Count -gt 0) {
        Titulo 'Placa de vídeo dedicada'
        foreach ($g in $gpus) { Write-Host ("  {0}   (driver atual {1})" -f $g.Nome, $g.Versao) -ForegroundColor White }
        Write-Host ''
        Write-Host 'O driver restaurado por INF faz a placa funcionar, mas não traz o painel de controle.' -ForegroundColor Gray

        if (@($gpus | Where-Object { $_.Tipo -eq 'nvidia' }).Count -gt 0) {
            Write-Host ''
            Write-Host 'A NVIDIA não publica o driver no winget. Quem instala e mantém é o NVIDIA App.' -ForegroundColor Gray
            if (Confirmar 'Instalar o NVIDIA App (ele baixa o driver)?' $true) {
                if (-not (Tentar-Winget 'XP8CLZL93F5Z4P' 'NVIDIA App' 'https://www.nvidia.com/pt-br/drivers/' 'msstore')) {
                    Write-Host '    Baixe o driver direto na página que abri.' -ForegroundColor White
                }
            }
        }
        if (@($gpus | Where-Object { $_.Tipo -eq 'amd' }).Count -gt 0) {
            Write-Host ''
            Write-Host 'A AMD não publica o Adrenalin no winget: só na página oficial.' -ForegroundColor Gray
            if (Confirmar 'Abrir a página do driver AMD?' $true) { Abrir-Url 'https://www.amd.com/pt/support' }
        }
    }

    # Intel tem CLI de verdade e cobre chipset, Wi-Fi e video integrado
    if (@($todas | Where-Object { $_.Tipo -eq 'intel' }).Count -gt 0 -or $maq.PlacaMae -match '(?i)intel') {
        Titulo 'Componentes Intel'
        Write-Host 'O Intel Driver & Support Assistant cuida de chipset, Wi-Fi e vídeo integrado.' -ForegroundColor Gray
        if (Confirmar 'Instalar o Intel Driver & Support Assistant?' $false) {
            [void](Tentar-Winget 'Intel.IntelDriverAndSupportAssistant' 'Intel DSA' 'https://www.intel.com.br/content/www/br/pt/support/intel-driver-support-assistant.html' '')
        }
    }
}

# ------------------------------------------------------------
# Início
# ------------------------------------------------------------
Abrir 'Drivers'
$pnp = Get-Command pnputil.exe -ErrorAction SilentlyContinue
if (-not $pnp) {
    Write-Host ''
    Write-Host '[ERRO] O pnputil.exe não foi encontrado. Ele faz parte do Windows.' -ForegroundColor Red
    Pausar; exit 1
}
Write-Host ("[OK] pnputil: {0}" -f $pnp.Source) -ForegroundColor Green

$maquina = Detectar-Maquina
Write-Host ("[OK] Máquina: {0} {1}" -f $maquina.Fabricante, $maquina.Modelo) -ForegroundColor Green
if ($maquina.Marca -eq 'montado' -or $maquina.Marca -eq 'outro') {
    Write-Host ("[OK] Placa-mãe: {0}" -f $maquina.PlacaMae) -ForegroundColor Green
}

$config = Carregar-Config
$padrao = if ($config -and $config.UltimaPasta) { $config.UltimaPasta } else { Join-Path $env:USERPROFILE 'Downloads\Drivers' }
$raiz   = Pedir-Saida $padrao
Salvar-Config ([pscustomobject]@{ UltimaPasta = $raiz })

$pastaPc   = Join-Path $raiz $env:COMPUTERNAME
$pastaHoje = Join-Path $pastaPc (Get-Date -Format 'yyyy-MM-dd')
try { New-Item -ItemType Directory -Path $pastaPc -Force | Out-Null }
catch { Write-Host "[ERRO] Não consegui criar a pasta desta máquina: $($_.Exception.Message)" -ForegroundColor Red; Pausar; exit 1 }

# O backup completo costuma ocupar de 0,5 a 3 GB
try {
    $un = (Get-Item -LiteralPath $raiz).PSDrive
    if ($un -and $un.Free -and $un.Free -lt 5GB) {
        Write-Host ("[!] Só restam {0} nessa unidade. O backup costuma ocupar de 0,5 a 3 GB." -f (Tam $un.Free)) -ForegroundColor Yellow
    }
} catch { Write-Host "[!] Não consegui checar o espaço livre: $($_.Exception.Message)" -ForegroundColor DarkGray }

[void](Garantir-Backup $pastaHoje)

# Sugere sempre o backup mais recente daquela maquina
function Backup-Mais-Recente([string]$pastaPc, [string]$pastaHoje) {
    $ult = @(Get-ChildItem -LiteralPath $pastaPc -Directory -ErrorAction SilentlyContinue |
             Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}' } | Sort-Object Name -Descending | Select-Object -First 1)
    if ($ult.Count -gt 0) { return $ult[0].FullName }
    return $pastaHoje
}

# ------------------------------------------------------------
# Menu
# ------------------------------------------------------------
$rotuloFab = switch ($maquina.Marca) {
    'dell'   { 'Dell Command | Update (driver oficial do modelo)' }
    'hp'     { 'HP Image Assistant (driver oficial do modelo)' }
    'lenovo' { 'Lenovo System Update (driver oficial do modelo)' }
    default  { 'Placa-mãe e placa de vídeo (páginas oficiais)' }
}

while ($true) {
    Titulo 'DRIVERS'
    Write-Host ("  {0}  |  pasta: {1}" -f $env:COMPUTERNAME, $raiz) -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '> [1] Inventário: o que tem e o que falta' -ForegroundColor White
    Write-Host '  [2] Fazer um novo backup agora' -ForegroundColor Gray
    Write-Host '  [3] Restaurar drivers de uma pasta' -ForegroundColor Gray
    Write-Host '  [4] Restaurar só o driver de rede (destrava a internet)' -ForegroundColor Gray
    Write-Host '  [5] Procurar atualizações no Windows Update' -ForegroundColor Gray
    Write-Host ("  [6] {0}" -f $rotuloFab) -ForegroundColor Gray
    Write-Host ''
    Write-Host '  [0] Sair' -ForegroundColor DarkGray
    Write-Host 'Enter = usar a opção padrão [1]' -ForegroundColor DarkGray
    $op = Read-Host 'Opção (0-6)'
    if ([string]::IsNullOrWhiteSpace($op)) { $op = '1' }
    $op = $op.Trim()
    if ($op -eq '0') { break }

    switch ($op) {

        '1' {
            Titulo 'Inventário'
            Write-Host 'Lendo os dispositivos...' -ForegroundColor Gray
            $disp  = Coletar-Dispositivos $codigosProblema
            $ruins = Mostrar-Inventario $disp
            Salvar-Inventario $disp (Join-Path $pastaPc 'inventario.csv')
            $sem = @($ruins | Where-Object { $_.Codigo -eq 28 -and $_.HardwareID })
            if ($sem.Count -gt 0) {
                Write-Host ''
                Write-Host 'O Windows Update (opção 5) resolve a maior parte disso.' -ForegroundColor Gray
                if (Confirmar 'Procurar esses no Microsoft Update Catalog agora?' $true) {
                    Catalog-Resolver $sem $pastaPc $nomesClasse
                }
            }
            Pausar
        }

        '2' {
            Titulo 'Novo backup'
            [void](Exportar-Drivers (Join-Path $pastaPc (Get-Date -Format 'yyyy-MM-dd_HHmm')))
            Pausar
        }

        '3' {
            Titulo 'Restaurar drivers'
            $de = Pedir-Pasta (Backup-Mais-Recente $pastaPc $pastaHoje) 'Enter = usar esta pasta   |   ou cole a pasta de outro PC / do pendrive'
            if (-not $de) { Pausar; continue }
            $infs = Listar-Infs $de $nomesClasse
            if (@($infs).Count -eq 0) { Write-Host '[!] Nenhum .inf nessa pasta.' -ForegroundColor Yellow; Pausar; continue }
            Previa-Infs $infs
            Write-Host ''
            if (-not (Confirmar 'Instalar esses drivers?' $true)) { Write-Host 'Cancelado.' -ForegroundColor Yellow; Pausar; continue }
            Titulo 'Instalando'
            [void](Instalar-Infs $infs $de)
            Write-Host ''
            if (Confirmar 'Procurar atualizações no Windows Update agora?' $true) { Buscar-Atualizacoes }
            Pausar
        }

        '4' {
            Titulo 'Restaurar só o driver de rede'
            $de = Pedir-Pasta (Backup-Mais-Recente $pastaPc $pastaHoje) 'Enter = usar esta pasta   |   ou cole a pasta do pendrive'
            if (-not $de) { Pausar; continue }
            $rede = @((Listar-Infs $de $nomesClasse) | Where-Object { $_.Classe -match '^(?i)net$' })
            if ($rede.Count -eq 0) { Write-Host '[!] Nenhum driver de rede nessa pasta.' -ForegroundColor Yellow; Pausar; continue }
            Previa-Infs $rede
            Write-Host ''
            if (-not (Confirmar 'Instalar só esses?' $true)) { Write-Host 'Cancelado.' -ForegroundColor Yellow; Pausar; continue }
            Titulo 'Instalando'
            # Sem lote: a pasta tem drivers de tudo, e aqui so' a rede pode entrar
            [void](Instalar-Infs $rede $null)
            Pausar
        }

        '5' {
            Buscar-Atualizacoes
            $sem = @((Coletar-Dispositivos $codigosProblema) | Where-Object { $_.Codigo -eq 28 -and $_.HardwareID })
            if ($sem.Count -gt 0) {
                Write-Host ''
                Write-Host ("[!] Ainda faltam {0} dispositivo(s) sem driver." -f $sem.Count) -ForegroundColor Yellow
                if (Confirmar 'Procurar esses no Microsoft Update Catalog?' $true) {
                    Catalog-Resolver $sem $pastaPc $nomesClasse
                }
            }
            Pausar
        }

        '6' { Ferramenta-Fabricante $maquina $pastaPc; Pausar }

        default { Write-Host '[!] Escolha de 0 a 6.' -ForegroundColor Yellow; Start-Sleep -Seconds 1 }
    }
}

Titulo 'Concluído'
Write-Host ("Pasta desta máquina: {0}" -f $pastaPc) -ForegroundColor White
Write-Host '  Desenvolvido por Pablo Murad - 2026' -ForegroundColor DarkGray
Write-Host ''
