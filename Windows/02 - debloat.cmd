<# :
@echo off
set "SELF=%~f0"
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression ([System.IO.File]::ReadAllText($env:SELF,[System.Text.Encoding]::UTF8))"
exit /b %errorlevel%
#>

# ============================================================
#  Debloat - tira o excesso do Windows, com prévia e desfazer
#  Desenvolvido por Pablo Murad - 2026
# ============================================================

try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
try { $Host.UI.RawUI.WindowTitle = 'Debloat' } catch {}

# ------------------------------------------------------------
# Auto-elevação: mexer em serviço, tarefa e HKLM exige administrador
# ------------------------------------------------------------
$souAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $souAdmin) {
    Write-Host 'Solicitando privilégios de administrador...' -ForegroundColor Yellow
    try {
        Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', "`"$env:SELF`"" -Verb RunAs | Out-Null
    } catch {
        Write-Host "[ERRO] Sem administrador não dá para mexer no sistema: $($_.Exception.Message)" -ForegroundColor Red
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

$configDir  = Join-Path $env:APPDATA 'Debloat'
$configFile = Join-Path $configDir 'config.json'
function Carregar-Config { if (Test-Path -LiteralPath $configFile) { try { return Get-Content -LiteralPath $configFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch {} }; return $null }
function Salvar-Config($o) { try { New-Item -ItemType Directory -Path $configDir -Force | Out-Null; $o | ConvertTo-Json | Set-Content -LiteralPath $configFile -Encoding UTF8 } catch {} }

# Pergunta a pasta de saida: sugere a ultima usada e cria se nao existir
function Pedir-Saida($padrao) {
    while ($true) {
        Titulo 'Pasta dos relatórios'
        Write-Host "  $padrao" -ForegroundColor White
        Write-Host 'Enter = usar esta pasta   |   ou cole/digite outra' -ForegroundColor DarkGray
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

# ------------------------------------------------------------
# Perfil da máquina: o que existe aqui muda o que é recomendado
# ------------------------------------------------------------
function Detectar-Perfil {
    $ram = 0
    try { $ram = [math]::Round((Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).TotalPhysicalMemory / 1GB) }
    catch { Write-Host "[!] Não li a memória: $($_.Exception.Message)" -ForegroundColor DarkGray }

    $gpuDedicada = $false
    try {
        foreach ($v in @(Get-CimInstance Win32_VideoController -ErrorAction Stop)) {
            if ("$($v.Name)" -match '(?i)nvidia|geforce|radeon|rtx|gtx|quadro|arc a\d') { $gpuDedicada = $true }
        }
    } catch { Write-Host "[!] Não li a placa de vídeo: $($_.Exception.Message)" -ForegroundColor DarkGray }

    # Lojas de jogos instaladas
    $pastasJogo = @(
        "${env:ProgramFiles(x86)}\Steam\steam.exe"
        "$env:ProgramFiles\Epic Games"
        "${env:ProgramFiles(x86)}\Epic Games"
        "$env:ProgramFiles\GOG Galaxy"
        "${env:ProgramFiles(x86)}\Battle.net"
        "$env:ProgramFiles\Battle.net"
        "$env:LOCALAPPDATA\Programs\Ubisoft Game Launcher"
    )
    $jogos = $false
    foreach ($p in $pastasJogo) { if ($p -and (Test-Path -LiteralPath $p)) { $jogos = $true; break } }

    # Everything (voidtools): quem tem isso nao depende da busca do Windows
    $everything = $false
    foreach ($p in @("$env:ProgramFiles\Everything\Everything.exe", "${env:ProgramFiles(x86)}\Everything\Everything.exe")) {
        if (Test-Path -LiteralPath $p) { $everything = $true; break } }
    if (-not $everything -and (Get-Process -Name 'Everything' -ErrorAction SilentlyContinue)) { $everything = $true }

    $office = $false
    foreach ($p in @("$env:ProgramFiles\Microsoft Office\root\Office16", "${env:ProgramFiles(x86)}\Microsoft Office\root\Office16")) {
        if (Test-Path -LiteralPath $p) { $office = $true; break } }

    return [pscustomobject]@{
        RamGB       = $ram
        GpuDedicada = $gpuDedicada
        Jogos       = $jogos
        Everything  = $everything
        Office      = $office
    }
}

function Mostrar-Perfil($perfil) {
    Write-Host ("[OK] {0} GB de RAM" -f $perfil.RamGB) -ForegroundColor Green
    if ($perfil.Jogos -or $perfil.GpuDedicada) {
        Write-Host '[i] Máquina de jogos: Xbox e Game Bar ficam FORA do automático.' -ForegroundColor Cyan
    }
    if ($perfil.Everything) {
        Write-Host '[i] Everything instalado: dá para aliviar a busca do Windows.' -ForegroundColor Cyan
    }
    if ($perfil.Office) {
        Write-Host '[i] Office instalado: Teams e OneNote ficam fora do automático.' -ForegroundColor Cyan
    }
    if ($perfil.RamGB -ge 32) {
        Write-Host '[i] Com essa quantidade de RAM, mexer em serviço quase não muda nada.' -ForegroundColor DarkGray
    }
}

# ------------------------------------------------------------
# Diário do desfazer
# Toda alteracao e' gravada ANTES de acontecer, com o valor anterior.
# Fica no %APPDATA% para o desfazer funcionar sem o pendrive por perto.
# ------------------------------------------------------------
function Carregar-Diario([string]$arquivo) {
    if (Test-Path -LiteralPath $arquivo) {
        try { return Get-Content -LiteralPath $arquivo -Raw -Encoding UTF8 | ConvertFrom-Json }
        catch { Write-Host "[!] O diário está ilegível ($($_.Exception.Message)). Vou começar um novo." -ForegroundColor Yellow }
    }
    return [pscustomobject]@{ versao = 1; maquina = $env:COMPUTERNAME; execucoes = @() }
}

function Gravar-Diario([string]$arquivo, $diario, $acoes, [string]$copiaEm) {
    if (@($acoes).Count -eq 0) { return }
    $exec = [pscustomobject]@{ data = (Get-Date).ToString('s'); acoes = @($acoes) }
    $diario.execucoes = @($diario.execucoes) + $exec
    try {
        New-Item -ItemType Directory -Path (Split-Path $arquivo -Parent) -Force | Out-Null
        # Depth: sem isso o ConvertTo-Json corta em 2 niveis e o diario sai vazio
        $diario | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $arquivo -Encoding UTF8
        if ($copiaEm) {
            try { Copy-Item -LiteralPath $arquivo -Destination (Join-Path $copiaEm 'desfazer.json') -Force }
            catch { Write-Host "[!] Não copiei o diário para a pasta: $($_.Exception.Message)" -ForegroundColor DarkGray }
        }
    } catch {
        Write-Host "[ERRO] Não consegui gravar o diário: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host '       As alterações foram feitas, mas o desfazer não vai enxergá-las.' -ForegroundColor Yellow
    }
}

# ------------------------------------------------------------
# Ponto de restauração
# ------------------------------------------------------------
function Criar-Ponto-Restauracao {
    Write-Host 'Criando ponto de restauração...' -ForegroundColor Gray
    try {
        Checkpoint-Computer -Description 'Antes do Debloat (fast-scripts)' -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop
        Write-Host '[OK] Ponto de restauração criado.' -ForegroundColor Green
        return $true
    } catch {
        $m = $_.Exception.Message
        Write-Host "[!] Não criei o ponto de restauração: $m" -ForegroundColor Yellow
        if ($m -match '(?i)frequ|1440|already') {
            Write-Host '    O Windows só permite um ponto a cada 24 h. Já deve existir um de hoje.' -ForegroundColor DarkGray
        } else {
            Write-Host '    A Proteção do Sistema pode estar desligada nesta máquina.' -ForegroundColor DarkGray
            if (Confirmar '    Ligar a Proteção do Sistema no C: agora?' $false) {
                try { Enable-ComputerRestore -Drive 'C:\' -ErrorAction Stop; Write-Host '    [OK] Ligada.' -ForegroundColor Green }
                catch { Write-Host "    [!] Não consegui ligar: $($_.Exception.Message)" -ForegroundColor Yellow }
            }
        }
        Write-Host '    O desfazer deste programa continua funcionando: ele usa o diário próprio.' -ForegroundColor DarkGray
        return $false
    }
}

# ------------------------------------------------------------
# Motor de registro
# ------------------------------------------------------------
function Ler-Valor([string]$caminho, [string]$nome) {
    try {
        $i = Get-ItemProperty -LiteralPath $caminho -Name $nome -ErrorAction Stop
        return [pscustomobject]@{ Existe = $true; Valor = $i.$nome }
    } catch { return [pscustomobject]@{ Existe = $false; Valor = $null } }
}

# Grava e devolve a acao para o diario (ou $null se ja estava certo)
function Escrever-Valor([string]$caminho, [string]$nome, $valor, [string]$tipo) {
    $antes = Ler-Valor $caminho $nome
    if ($antes.Existe -and "$($antes.Valor)" -eq "$valor") { return $null }
    try {
        if (-not (Test-Path -LiteralPath $caminho)) { New-Item -Path $caminho -Force | Out-Null }
        New-ItemProperty -LiteralPath $caminho -Name $nome -Value $valor -PropertyType $tipo -Force -ErrorAction Stop | Out-Null
    } catch {
        Write-Host ("  [ERRO] {0} \ {1}: {2}" -f $caminho, $nome, $_.Exception.Message) -ForegroundColor Red
        return $null
    }
    return [pscustomobject]@{
        tipo         = 'registro'
        caminho      = $caminho
        nome         = $nome
        existiaAntes = $antes.Existe
        valorAntes   = $antes.Valor
        tipoValor    = $tipo
        valorDepois  = $valor
    }
}

function Reverter-Valor($a) {
    try {
        if (-not (Test-Path -LiteralPath $a.caminho)) { return $true }
        if ($a.existiaAntes) {
            New-ItemProperty -LiteralPath $a.caminho -Name $a.nome -Value $a.valorAntes -PropertyType $a.tipoValor -Force -ErrorAction Stop | Out-Null
        } else {
            Remove-ItemProperty -LiteralPath $a.caminho -Name $a.nome -Force -ErrorAction SilentlyContinue
        }
        return $true
    } catch {
        Write-Host ("  [ERRO] {0} \ {1}: {2}" -f $a.caminho, $a.nome, $_.Exception.Message) -ForegroundColor Red
        return $false
    }
}

# ------------------------------------------------------------
# Tabelas do que o programa sabe mexer
# Chaves conferidas na documentacao da Microsoft e em projetos
# abertos de debloat; nao foram escritas de memoria.
# ------------------------------------------------------------
function Tabela-Tweaks {
    $HKCU = 'HKCU:\SOFTWARE'; $HKLM = 'HKLM:\SOFTWARE'
    @(
        # --- privacidade e telemetria ---
        [pscustomobject]@{ Area='privacidade'; Nome='Telemetria no mínimo';                  Caminho="$HKLM\Microsoft\Windows\CurrentVersion\Policies\DataCollection"; Chave='AllowTelemetry'; Valor=0; Tipo='DWord' }
        [pscustomobject]@{ Area='privacidade'; Nome='ID de anúncios desligado';              Caminho="$HKCU\Microsoft\Windows\CurrentVersion\AdvertisingInfo"; Chave='Enabled'; Valor=0; Tipo='DWord' }
        [pscustomobject]@{ Area='privacidade'; Nome='Experiências personalizadas';           Caminho="$HKCU\Microsoft\Windows\CurrentVersion\Privacy"; Chave='TailoredExperiencesWithDiagnosticDataEnabled'; Valor=0; Tipo='DWord' }
        [pscustomobject]@{ Area='privacidade'; Nome='Histórico de atividades';               Caminho="$HKLM\Policies\Microsoft\Windows\System"; Chave='PublishUserActivities'; Valor=0; Tipo='DWord' }
        [pscustomobject]@{ Area='privacidade'; Nome='Rastreio de apps abertos';              Caminho="$HKCU\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Chave='Start_TrackProgs'; Valor=0; Tipo='DWord' }
        [pscustomobject]@{ Area='privacidade'; Nome='Reconhecimento de voz online';          Caminho="$HKCU\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy"; Chave='HasAccepted'; Valor=0; Tipo='DWord' }
        [pscustomobject]@{ Area='privacidade'; Nome='Coleta de escrita à mão';               Caminho="$HKCU\Microsoft\InputPersonalization"; Chave='RestrictImplicitInkCollection'; Valor=1; Tipo='DWord' }
        [pscustomobject]@{ Area='privacidade'; Nome='Coleta de texto digitado';              Caminho="$HKCU\Microsoft\InputPersonalization"; Chave='RestrictImplicitTextCollection'; Valor=1; Tipo='DWord' }
        [pscustomobject]@{ Area='privacidade'; Nome='Personalização de digitação';           Caminho="$HKCU\Microsoft\Input\TIPC"; Chave='Enabled'; Valor=0; Tipo='DWord' }
        [pscustomobject]@{ Area='privacidade'; Nome='Pedidos de feedback';                   Caminho="$HKCU\Microsoft\Siuf\Rules"; Chave='NumberOfSIUFInPeriod'; Valor=0; Tipo='DWord' }

        # --- Copilot, Recall e IA ---
        [pscustomobject]@{ Area='ia'; Nome='Copilot desligado (máquina)';                    Caminho="$HKLM\Policies\Microsoft\Windows\WindowsCopilot"; Chave='TurnOffWindowsCopilot'; Valor=1; Tipo='DWord' }
        [pscustomobject]@{ Area='ia'; Nome='Copilot desligado (usuário)';                    Caminho="$HKCU\Policies\Microsoft\Windows\WindowsCopilot"; Chave='TurnOffWindowsCopilot'; Valor=1; Tipo='DWord' }
        [pscustomobject]@{ Area='ia'; Nome='Botão do Copilot fora da barra';                 Caminho="$HKCU\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Chave='ShowCopilotButton'; Valor=0; Tipo='DWord' }
        [pscustomobject]@{ Area='ia'; Nome='Recall: análise de dados desligada';             Caminho="$HKLM\Policies\Microsoft\Windows\WindowsAI"; Chave='DisableAIDataAnalysis'; Valor=1; Tipo='DWord' }
        [pscustomobject]@{ Area='ia'; Nome='Recall: não deixar habilitar';                   Caminho="$HKLM\Policies\Microsoft\Windows\WindowsAI"; Chave='AllowRecallEnablement'; Valor=0; Tipo='DWord' }
        [pscustomobject]@{ Area='ia'; Nome='Recall: não salvar capturas';                    Caminho="$HKLM\Policies\Microsoft\Windows\WindowsAI"; Chave='TurnOffSavingSnapshots'; Valor=1; Tipo='DWord' }
        [pscustomobject]@{ Area='ia'; Nome='Recall: usuário atual';                          Caminho="$HKCU\Policies\Microsoft\Windows\WindowsAI"; Chave='DisableAIDataAnalysis'; Valor=1; Tipo='DWord' }
        [pscustomobject]@{ Area='ia'; Nome='Click to Do desligado';                          Caminho="$HKLM\Policies\Microsoft\Windows\WindowsAI"; Chave='DisableClickToDo'; Valor=1; Tipo='DWord' }
        [pscustomobject]@{ Area='ia'; Nome='IA no Edge desligada';                           Caminho="$HKLM\Policies\Microsoft\Edge"; Chave='HubsSidebarEnabled'; Valor=0; Tipo='DWord' }

        # --- anuncios, sugestoes e irritacoes ---
        [pscustomobject]@{ Area='irritacao'; Nome='Boas-vindas depois de atualizar';         Caminho="$HKCU\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Chave='SubscribedContent-310093Enabled'; Valor=0; Tipo='DWord' }
        [pscustomobject]@{ Area='irritacao'; Nome='Sugestões no Iniciar';                    Caminho="$HKCU\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Chave='SubscribedContent-338388Enabled'; Valor=0; Tipo='DWord' }
        [pscustomobject]@{ Area='irritacao'; Nome='Apps sugeridos no Iniciar';               Caminho="$HKCU\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Chave='SystemPaneSuggestionsEnabled'; Valor=0; Tipo='DWord' }
        [pscustomobject]@{ Area='irritacao'; Nome='Dicas e truques do Windows';              Caminho="$HKCU\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Chave='SubscribedContent-338389Enabled'; Valor=0; Tipo='DWord' }
        [pscustomobject]@{ Area='irritacao'; Nome='Dicas na tela (soft landing)';            Caminho="$HKCU\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Chave='SoftLandingEnabled'; Valor=0; Tipo='DWord' }
        [pscustomobject]@{ Area='irritacao'; Nome='Conteúdo sugerido em Configurações';      Caminho="$HKCU\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Chave='SubscribedContent-338393Enabled'; Valor=0; Tipo='DWord' }
        [pscustomobject]@{ Area='irritacao'; Nome='Instalação silenciosa de apps';           Caminho="$HKCU\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Chave='SilentInstalledAppsEnabled'; Valor=0; Tipo='DWord' }
        [pscustomobject]@{ Area='irritacao'; Nome='Recomendados no Iniciar escondidos';      Caminho="$HKCU\Policies\Microsoft\Windows\Explorer"; Chave='HideRecommendedSection'; Valor=1; Tipo='DWord' }
        [pscustomobject]@{ Area='irritacao'; Nome='Anúncios do Microsoft 365';               Caminho="$HKLM\Policies\Microsoft\Windows\CloudContent"; Chave='DisableConsumerAccountStateContent'; Valor=1; Tipo='DWord' }
        [pscustomobject]@{ Area='irritacao'; Nome='Bing fora da busca do Iniciar';           Caminho="$HKCU\Policies\Microsoft\Windows\Explorer"; Chave='DisableSearchBoxSuggestions'; Valor=1; Tipo='DWord' }
        [pscustomobject]@{ Area='irritacao'; Nome='Cortana fora da busca';                   Caminho="$HKLM\Policies\Microsoft\Windows\Windows Search"; Chave='AllowCortana'; Valor=0; Tipo='DWord' }
        [pscustomobject]@{ Area='irritacao'; Nome='Destaques da busca desligados';           Caminho="$HKCU\Microsoft\Windows\CurrentVersion\SearchSettings"; Chave='IsDynamicSearchBoxEnabled'; Valor=0; Tipo='DWord' }
        [pscustomobject]@{ Area='irritacao'; Nome='Widgets fora da barra';                   Caminho="$HKCU\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Chave='TaskbarDa'; Valor=0; Tipo='DWord' }
        [pscustomobject]@{ Area='irritacao'; Nome='Dicas na tela de bloqueio';               Caminho="$HKCU\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Chave='RotatingLockScreenOverlayEnabled'; Valor=0; Tipo='DWord' }
    )
}

# ------------------------------------------------------------
# Apps: nivel 'seguro' entra no automatico, 'opcional' so' item
# a item, 'nunca' nunca sai sem o usuario pedir explicitamente.
# ------------------------------------------------------------
function Tabela-Apps {
    @(
        # seguros
        [pscustomobject]@{ Id='Clipchamp.Clipchamp';                      Nome='Clipchamp (editor de vídeo)';   Nivel='seguro' }
        [pscustomobject]@{ Id='Microsoft.3DBuilder';                      Nome='3D Builder';                    Nivel='seguro' }
        [pscustomobject]@{ Id='Microsoft.Microsoft3DViewer';              Nome='Visualizador 3D';               Nivel='seguro' }
        [pscustomobject]@{ Id='Microsoft.Print3D';                        Nome='Impressão 3D';                  Nivel='seguro' }
        [pscustomobject]@{ Id='Microsoft.549981C3F5F10';                  Nome='Cortana';                       Nivel='seguro' }
        [pscustomobject]@{ Id='Microsoft.BingFinance';                    Nome='Bing Finanças';                 Nivel='seguro' }
        [pscustomobject]@{ Id='Microsoft.BingFoodAndDrink';               Nome='Bing Culinária';                Nivel='seguro' }
        [pscustomobject]@{ Id='Microsoft.BingHealthAndFitness';           Nome='Bing Saúde';                    Nivel='seguro' }
        [pscustomobject]@{ Id='Microsoft.BingNews';                       Nome='Notícias (Bing)';               Nivel='seguro' }
        [pscustomobject]@{ Id='Microsoft.BingSports';                     Nome='Bing Esportes';                 Nivel='seguro' }
        [pscustomobject]@{ Id='Microsoft.BingTranslator';                 Nome='Tradutor Bing';                 Nivel='seguro' }
        [pscustomobject]@{ Id='Microsoft.BingTravel';                     Nome='Bing Viagens';                  Nivel='seguro' }
        [pscustomobject]@{ Id='Microsoft.BingWeather';                    Nome='Clima (Bing)';                  Nivel='seguro' }
        [pscustomobject]@{ Id='Microsoft.BingSearch';                     Nome='Busca web do Bing no Iniciar';  Nivel='seguro' }
        [pscustomobject]@{ Id='Microsoft.Copilot';                        Nome='Copilot';                       Nivel='seguro' }
        [pscustomobject]@{ Id='Microsoft.Windows.Copilot';                Nome='Copilot (componente)';          Nivel='seguro' }
        [pscustomobject]@{ Id='Microsoft.Windows.AIHub';                  Nome='AI Hub';                        Nivel='seguro' }
        [pscustomobject]@{ Id='Microsoft.PCManager';                      Nome='Microsoft PC Manager';          Nivel='seguro' }
        [pscustomobject]@{ Id='Microsoft.Getstarted';                     Nome='Introdução ao Windows';         Nivel='seguro' }
        [pscustomobject]@{ Id='Microsoft.Messaging';                      Nome='Mensagens';                     Nivel='seguro' }
        [pscustomobject]@{ Id='Microsoft.MicrosoftOfficeHub';             Nome='Office Hub (propaganda)';       Nivel='seguro' }
        [pscustomobject]@{ Id='Microsoft.MicrosoftSolitaireCollection';   Nome='Paciência (com anúncios)';      Nivel='seguro' }
        [pscustomobject]@{ Id='Microsoft.MixedReality.Portal';            Nome='Realidade Misturada';           Nivel='seguro' }
        [pscustomobject]@{ Id='Microsoft.NetworkSpeedTest';               Nome='Teste de Velocidade';           Nivel='seguro' }
        [pscustomobject]@{ Id='Microsoft.News';                           Nome='Microsoft Notícias';            Nivel='seguro' }
        [pscustomobject]@{ Id='Microsoft.Office.Sway';                    Nome='Sway';                          Nivel='seguro' }
        [pscustomobject]@{ Id='Microsoft.OneConnect';                     Nome='Mobile Plans';                  Nivel='seguro' }
        [pscustomobject]@{ Id='Microsoft.SkypeApp';                       Nome='Skype';                         Nivel='seguro' }
        [pscustomobject]@{ Id='Microsoft.Wallet';                         Nome='Carteira';                      Nivel='seguro' }
        [pscustomobject]@{ Id='Microsoft.Whiteboard';                     Nome='Quadro de Comunicações';        Nivel='seguro' }
        [pscustomobject]@{ Id='Microsoft.MicrosoftJournal';               Nome='Journal';                       Nivel='seguro' }
        [pscustomobject]@{ Id='Microsoft.WindowsFeedbackHub';             Nome='Hub de Comentários';            Nivel='seguro' }
        [pscustomobject]@{ Id='Microsoft.WindowsMaps';                    Nome='Mapas';                         Nivel='seguro' }
        [pscustomobject]@{ Id='Microsoft.ZuneVideo';                      Nome='Filmes e TV';                   Nivel='seguro' }
        [pscustomobject]@{ Id='Microsoft.PowerAutomateDesktop';           Nome='Power Automate';                Nivel='seguro' }
        [pscustomobject]@{ Id='Microsoft.Windows.DevHome';                Nome='Dev Home';                      Nivel='seguro' }
        [pscustomobject]@{ Id='Microsoft.Windows.Ai.Copilot.Provider';    Nome='Provedor do Copilot';           Nivel='seguro' }
        [pscustomobject]@{ Id='MicrosoftWindows.Client.WebExperience';    Nome='Widgets';                       Nivel='seguro' }
        [pscustomobject]@{ Id='Microsoft.WidgetsPlatformRuntime';         Nome='Runtime dos Widgets';           Nivel='seguro' }
        [pscustomobject]@{ Id='Microsoft.LinkedIn';                       Nome='LinkedIn';                      Nivel='seguro' }
        [pscustomobject]@{ Id='Microsoft.Family';                         Nome='Segurança da Família';          Nivel='seguro' }
        [pscustomobject]@{ Id='MSTeams';                                  Nome='Teams (pessoal)';               Nivel='seguro'; Condicao='sem-office' }
        [pscustomobject]@{ Id='MicrosoftTeams';                           Nome='Teams (pessoal, antigo)';       Nivel='seguro'; Condicao='sem-office' }

        # dependem de jogo
        [pscustomobject]@{ Id='Microsoft.GamingApp';                      Nome='Xbox (app)';                    Nivel='seguro'; Condicao='sem-jogos' }
        [pscustomobject]@{ Id='Microsoft.XboxApp';                        Nome='Xbox Console Companion';        Nivel='seguro'; Condicao='sem-jogos' }
        [pscustomobject]@{ Id='Microsoft.XboxGameOverlay';                Nome='Game Bar (overlay)';            Nivel='seguro'; Condicao='sem-jogos' }
        [pscustomobject]@{ Id='Microsoft.XboxGamingOverlay';              Nome='Game Bar';                      Nivel='seguro'; Condicao='sem-jogos' }
        [pscustomobject]@{ Id='Microsoft.XboxDevices';                    Nome='Acessórios Xbox';               Nivel='seguro'; Condicao='sem-jogos' }

        # opcionais: uteis para muita gente, so' item a item
        [pscustomobject]@{ Id='Microsoft.OutlookForWindows';              Nome='Novo Outlook';                  Nivel='opcional' }
        [pscustomobject]@{ Id='Microsoft.Office.OneNote';                 Nome='OneNote (UWP)';                 Nivel='opcional' }
        [pscustomobject]@{ Id='Microsoft.People';                         Nome='Pessoas';                       Nivel='opcional' }
        [pscustomobject]@{ Id='Microsoft.Todos';                          Nome='Microsoft To Do';               Nivel='opcional' }
        [pscustomobject]@{ Id='Microsoft.YourPhone';                      Nome='Vínculo com o Celular';         Nivel='opcional' }
        [pscustomobject]@{ Id='MicrosoftWindows.CrossDevice';             Nome='Entre Dispositivos';            Nivel='opcional' }
        [pscustomobject]@{ Id='Microsoft.WindowsAlarms';                  Nome='Alarmes e Relógio';             Nivel='opcional' }
        [pscustomobject]@{ Id='Microsoft.WindowsCamera';                  Nome='Câmera';                        Nivel='opcional' }
        [pscustomobject]@{ Id='Microsoft.WindowsSoundRecorder';           Nome='Gravador de Som';               Nivel='opcional' }
        [pscustomobject]@{ Id='Microsoft.MicrosoftStickyNotes';           Nome='Notas Autoadesivas';            Nivel='opcional' }
        [pscustomobject]@{ Id='Microsoft.ZuneMusic';                      Nome='Windows Media Player';          Nivel='opcional' }
        [pscustomobject]@{ Id='Microsoft.Windows.Photos';                 Nome='Fotos';                         Nivel='opcional' }
        [pscustomobject]@{ Id='Microsoft.Paint';                          Nome='Paint';                         Nivel='opcional' }
        [pscustomobject]@{ Id='Microsoft.WindowsNotepad';                 Nome='Bloco de Notas';                Nivel='opcional' }
        [pscustomobject]@{ Id='Microsoft.WindowsCalculator';              Nome='Calculadora';                   Nivel='opcional' }
        [pscustomobject]@{ Id='Microsoft.ScreenSketch';                   Nome='Ferramenta de Captura';         Nivel='opcional' }
        [pscustomobject]@{ Id='MicrosoftCorporationII.QuickAssist';       Nome='Assistência Rápida';            Nivel='opcional' }

        # nunca: quebram algo ou nao reinstalam
        [pscustomobject]@{ Id='Microsoft.WindowsStore';                   Nome='Microsoft Store';               Nivel='nunca'; Aviso='sem ela não dá para reinstalar nada' }
        [pscustomobject]@{ Id='Microsoft.WindowsTerminal';                Nome='Terminal';                      Nivel='nunca'; Aviso='é onde este programa roda' }
        [pscustomobject]@{ Id='Microsoft.Edge';                           Nome='Edge';                          Nivel='nunca'; Aviso='quebra o Windows Sandbox e outros apps' }
        [pscustomobject]@{ Id='Microsoft.GetHelp';                        Nome='Obter Ajuda';                   Nivel='nunca'; Aviso='usado pelas soluções de problemas do Windows' }
        [pscustomobject]@{ Id='Microsoft.Xbox.TCUI';                      Nome='Xbox TCUI';                     Nivel='nunca'; Aviso='vários jogos dependem dele' }
        [pscustomobject]@{ Id='Microsoft.XboxIdentityProvider';           Nome='Identidade Xbox';               Nivel='nunca'; Aviso='login de jogos para de funcionar' }
        [pscustomobject]@{ Id='Microsoft.XboxSpeechToTextOverlay';        Nome='Legendas do Xbox';              Nivel='nunca'; Aviso='não reinstala' }
    )
}

# ------------------------------------------------------------
# Servicos: sempre para Manual, nunca Desativado.
# BITS, Spooler, WerSvc e tudo de rede/audio/Defender ficam fora
# de proposito: quebram Windows Update, impressao e diagnostico.
# ------------------------------------------------------------
function Tabela-Servicos {
    @(
        [pscustomobject]@{ Nome='DiagTrack';        Desc='Telemetria (Experiências do Usuário Conectado)'; Nivel='seguro' }
        [pscustomobject]@{ Nome='dmwappushservice'; Desc='Encaminhamento de mensagens WAP (telemetria)';   Nivel='seguro' }
        [pscustomobject]@{ Nome='MapsBroker';       Desc='Mapas Offline';                                  Nivel='seguro' }
        [pscustomobject]@{ Nome='RetailDemo';       Desc='Modo demonstração de loja';                      Nivel='seguro' }
        [pscustomobject]@{ Nome='WpcMonSvc';        Desc='Controle dos Pais';                              Nivel='seguro' }
        [pscustomobject]@{ Nome='WSAIFabricSvc';    Desc='Serviço de IA do Windows';                       Nivel='seguro' }
        [pscustomobject]@{ Nome='XblAuthManager';   Desc='Autenticação Xbox Live';   Nivel='seguro'; Condicao='sem-jogos' }
        [pscustomobject]@{ Nome='XblGameSave';      Desc='Salvamento Xbox Live';     Nivel='seguro'; Condicao='sem-jogos' }
        [pscustomobject]@{ Nome='XboxGipSvc';       Desc='Acessórios Xbox';          Nivel='seguro'; Condicao='sem-jogos' }
        [pscustomobject]@{ Nome='XboxNetApiSvc';    Desc='Rede Xbox Live';           Nivel='seguro'; Condicao='sem-jogos' }
        [pscustomobject]@{ Nome='WSearch';          Desc='Indexação do Windows (a busca do Iniciar piora)'; Nivel='opcional'; Condicao='tem-everything' }
        [pscustomobject]@{ Nome='SysMain';          Desc='Superfetch (ganho discutível em SSD)';            Nivel='opcional' }
    )
}

function Tabela-Tarefas {
    @(
        [pscustomobject]@{ Caminho='\Microsoft\Windows\Application Experience\';                  Nome='Microsoft Compatibility Appraiser' }
        [pscustomobject]@{ Caminho='\Microsoft\Windows\Application Experience\';                  Nome='Microsoft Compatibility Appraiser Exp' }
        [pscustomobject]@{ Caminho='\Microsoft\Windows\Application Experience\';                  Nome='ProgramDataUpdater' }
        [pscustomobject]@{ Caminho='\Microsoft\Windows\Application Experience\';                  Nome='MareBackup' }
        [pscustomobject]@{ Caminho='\Microsoft\Windows\Customer Experience Improvement Program\'; Nome='Consolidator' }
        [pscustomobject]@{ Caminho='\Microsoft\Windows\Customer Experience Improvement Program\'; Nome='UsbCeip' }
        [pscustomobject]@{ Caminho='\Microsoft\Windows\Customer Experience Improvement Program\'; Nome='KernelCeipTask' }
        [pscustomobject]@{ Caminho='\Microsoft\Windows\Feedback\Siuf\';                           Nome='DmClient' }
        [pscustomobject]@{ Caminho='\Microsoft\Windows\Feedback\Siuf\';                           Nome='DmClientOnScenarioDownload' }
        [pscustomobject]@{ Caminho='\Microsoft\Windows\Windows Error Reporting\';                 Nome='QueueReporting' }
        [pscustomobject]@{ Caminho='\Microsoft\Windows\Maps\';                                    Nome='MapsToastTask' }
        [pscustomobject]@{ Caminho='\Microsoft\Windows\Autochk\';                                 Nome='Proxy' }
    )
}

# Aplica a regra de perfil: devolve so' o que cabe nesta maquina
function Filtrar-Por-Perfil($itens, $perfil) {
    $r = @()
    foreach ($i in $itens) {
        $c = if ($i.PSObject.Properties['Condicao']) { "$($i.Condicao)" } else { '' }
        switch ($c) {
            'sem-jogos'      { if (-not ($perfil.Jogos -or $perfil.GpuDedicada)) { $r += $i } }
            'sem-office'     { if (-not $perfil.Office) { $r += $i } }
            'tem-everything' { if ($perfil.Everything) { $r += $i } }
            default          { $r += $i }
        }
    }
    return @($r)
}

# ------------------------------------------------------------
# Apps instalados
# ------------------------------------------------------------
function Apps-Presentes($tabela) {
    $inst = @{}
    try { foreach ($a in @(Get-AppxPackage -AllUsers -ErrorAction Stop)) { $inst["$($a.Name)"] = $true } }
    catch {
        Write-Host "[!] Não li os apps de todos os usuários ($($_.Exception.Message)). Tentando só o atual." -ForegroundColor DarkGray
        try { foreach ($a in @(Get-AppxPackage -ErrorAction Stop)) { $inst["$($a.Name)"] = $true } }
        catch { Write-Host "[ERRO] Não consegui listar os apps: $($_.Exception.Message)" -ForegroundColor Red; return @() }
    }
    $prov = @{}
    try { foreach ($p in @(Get-AppxProvisionedPackage -Online -ErrorAction Stop)) { $prov["$($p.DisplayName)"] = $p.PackageName } }
    catch { Write-Host "[!] Não li os pacotes provisionados: $($_.Exception.Message)" -ForegroundColor DarkGray }

    $r = @()
    foreach ($t in $tabela) {
        $temUsuario = $inst.ContainsKey($t.Id)
        $temProv    = $prov.ContainsKey($t.Id)
        if (-not $temUsuario -and -not $temProv) { continue }
        $r += [pscustomobject]@{
            Id = $t.Id; Nome = $t.Nome; Nivel = $t.Nivel
            Aviso = $(if ($t.PSObject.Properties['Aviso']) { $t.Aviso } else { '' })
            Condicao = $(if ($t.PSObject.Properties['Condicao']) { $t.Condicao } else { '' })
            NoUsuario = $temUsuario; Provisionado = $temProv
            PacoteProv = $(if ($temProv) { $prov[$t.Id] } else { '' })
        }
    }
    return @($r)
}

function Remover-App($app) {
    $fezUsuario = $false; $fezProv = $false
    if ($app.NoUsuario) {
        try {
            Get-AppxPackage -AllUsers -Name $app.Id -ErrorAction Stop | Remove-AppxPackage -AllUsers -ErrorAction Stop
            $fezUsuario = $true
        } catch {
            Write-Host ("  [ERRO] {0}: {1}" -f $app.Nome, $_.Exception.Message) -ForegroundColor Red
        }
    }
    # Sem tirar o provisionado, o app volta para o proximo usuario
    if ($app.Provisionado -and $app.PacoteProv) {
        try {
            Remove-AppxProvisionedPackage -Online -PackageName $app.PacoteProv -ErrorAction Stop | Out-Null
            $fezProv = $true
        } catch {
            Write-Host ("  [!] {0}: o provisionado não saiu ({1})" -f $app.Nome, $_.Exception.Message) -ForegroundColor Yellow
        }
    }
    if (-not $fezUsuario -and -not $fezProv) { return $null }
    return [pscustomobject]@{ tipo='app'; id=$app.Id; nome=$app.Nome; usuario=$fezUsuario; provisionado=$fezProv }
}

# ------------------------------------------------------------
# Serviços e tarefas
# ------------------------------------------------------------
function Servicos-Presentes($tabela) {
    $r = @()
    foreach ($t in $tabela) {
        # Servico que nao existe nesta edicao volta vazio, sem erro: o catch
        # aqui so' dispara em problema de verdade, entao mostra o motivo.
        $s = $null
        try { $s = Get-CimInstance Win32_Service -Filter "Name='$($t.Nome)'" -ErrorAction Stop }
        catch { Write-Host ("[!] Não consegui consultar o serviço {0}: {1}" -f $t.Nome, $_.Exception.Message) -ForegroundColor DarkGray }
        if (-not $s) { continue }
        $r += [pscustomobject]@{
            Nome = $t.Nome; Desc = $t.Desc; Nivel = $t.Nivel
            Condicao = $(if ($t.PSObject.Properties['Condicao']) { $t.Condicao } else { '' })
            Inicio = "$($s.StartMode)"; Estado = "$($s.State)"
            JaOk = ("$($s.StartMode)" -eq 'Manual' -or "$($s.StartMode)" -eq 'Disabled')
        }
    }
    return @($r)
}

function Ajustar-Servico($svc) {
    try {
        Set-Service -Name $svc.Nome -StartupType Manual -ErrorAction Stop
        return [pscustomobject]@{ tipo='servico'; nome=$svc.Nome; inicioAntes=$svc.Inicio; inicioDepois='Manual' }
    } catch {
        Write-Host ("  [ERRO] {0}: {1}" -f $svc.Nome, $_.Exception.Message) -ForegroundColor Red
        return $null
    }
}

function Tarefas-Presentes($tabela) {
    $r = @()
    foreach ($t in $tabela) {
        # Aqui e' diferente dos servicos: tarefa inexistente LANCA excecao, e
        # isso e' o caso normal (a lista cobre varias versoes do Windows).
        # Por isso o catch segue em frente sem reclamar.
        $x = $null
        try { $x = Get-ScheduledTask -TaskPath $t.Caminho -TaskName $t.Nome -ErrorAction Stop } catch { continue }
        if (-not $x) { continue }
        $r += [pscustomobject]@{ Caminho=$t.Caminho; Nome=$t.Nome; Estado="$($x.State)"; JaOk=("$($x.State)" -eq 'Disabled') }
    }
    return @($r)
}

function Desligar-Tarefa($tar) {
    try {
        Disable-ScheduledTask -TaskPath $tar.Caminho -TaskName $tar.Nome -ErrorAction Stop | Out-Null
        return [pscustomobject]@{ tipo='tarefa'; caminho=$tar.Caminho; nome=$tar.Nome; estadoAntes=$tar.Estado }
    } catch {
        Write-Host ("  [ERRO] {0}: {1}" -f $tar.Nome, $_.Exception.Message) -ForegroundColor Red
        return $null
    }
}

# ------------------------------------------------------------
# Prévias
# ------------------------------------------------------------
function Previa-Tweaks($itens, [string]$titulo) {
    Titulo "Prévia: $titulo"
    $mudam = @(); $jaOk = @()
    foreach ($i in $itens) {
        $atual = Ler-Valor $i.Caminho $i.Chave
        if ($atual.Existe -and "$($atual.Valor)" -eq "$($i.Valor)") { $jaOk += $i } else { $mudam += $i }
    }
    foreach ($i in $mudam) { Write-Host ("  [ ] {0}" -f $i.Nome) -ForegroundColor White }
    foreach ($i in $jaOk)  { Write-Host ("  [ok] {0}  (já está assim)" -f $i.Nome) -ForegroundColor DarkGray }
    Write-Host ''
    Write-Host ("A mudar: {0}   |   já corretos: {1}" -f $mudam.Count, $jaOk.Count) -ForegroundColor Cyan
    return @($mudam)
}

function Previa-Apps($apps) {
    Titulo 'Prévia: apps a remover'
    $seguros = @($apps | Where-Object { $_.Nivel -eq 'seguro' })
    foreach ($a in $seguros) {
        $onde = @(); if ($a.NoUsuario) { $onde += 'instalado' }; if ($a.Provisionado) { $onde += 'provisionado' }
        Write-Host ("  [ ] {0,-36} {1}" -f $a.Nome, ($onde -join ' + ')) -ForegroundColor White
    }
    Write-Host ''
    Write-Host ("Total: {0} app(s)" -f $seguros.Count) -ForegroundColor Cyan
    Write-Host 'App removido NÃO volta pelo desfazer: só reinstalando pela Microsoft Store.' -ForegroundColor Yellow
    return @($seguros)
}

function Previa-Servicos($svcs) {
    Titulo 'Prévia: serviços para Manual'
    $mudam = @($svcs | Where-Object { -not $_.JaOk })
    foreach ($s in $mudam) { Write-Host ("  [ ] {0,-20} {1}   (hoje: {2})" -f $s.Nome, $s.Desc, $s.Inicio) -ForegroundColor White }
    foreach ($s in @($svcs | Where-Object { $_.JaOk })) { Write-Host ("  [ok] {0,-20} já está em {1}" -f $s.Nome, $s.Inicio) -ForegroundColor DarkGray }
    Write-Host ''
    Write-Host 'Manual, não Desativado: o serviço não sobe no boot, mas ainda liga se algo precisar.' -ForegroundColor DarkGray
    return @($mudam)
}

function Previa-Tarefas($tars) {
    Titulo 'Prévia: tarefas de telemetria a desabilitar'
    $mudam = @($tars | Where-Object { -not $_.JaOk })
    foreach ($t in $mudam) { Write-Host ("  [ ] {0}{1}" -f $t.Caminho, $t.Nome) -ForegroundColor White }
    foreach ($t in @($tars | Where-Object { $_.JaOk })) { Write-Host ("  [ok] {0} já desabilitada" -f $t.Nome) -ForegroundColor DarkGray }
    Write-Host ''
    Write-Host ("A desabilitar: {0}" -f $mudam.Count) -ForegroundColor Cyan
    return @($mudam)
}

# ------------------------------------------------------------
# Aplicação
# ------------------------------------------------------------
function Aplicar-Tweaks($itens) {
    $acoes = @()
    foreach ($i in $itens) {
        $a = Escrever-Valor $i.Caminho $i.Chave $i.Valor $i.Tipo
        if ($a) { $acoes += $a; Write-Host ("  [OK] {0}" -f $i.Nome) -ForegroundColor Green }
    }
    return @($acoes)
}

function Aplicar-Apps($apps) {
    $acoes = @(); $n = 0; $tot = @($apps).Count
    foreach ($a in $apps) {
        $n++
        Write-Progress -Activity 'Removendo apps' -Status $a.Nome -PercentComplete ([int](100 * $n / $tot))
        $r = Remover-App $a
        if ($r) { $acoes += $r; Write-Host ("  [OK] {0}" -f $a.Nome) -ForegroundColor Green }
    }
    Write-Progress -Activity 'Removendo apps' -Completed
    return @($acoes)
}

function Aplicar-Servicos($svcs) {
    $acoes = @()
    foreach ($s in $svcs) {
        $a = Ajustar-Servico $s
        if ($a) { $acoes += $a; Write-Host ("  [OK] {0} -> Manual" -f $s.Nome) -ForegroundColor Green }
    }
    return @($acoes)
}

function Aplicar-Tarefas($tars) {
    $acoes = @()
    foreach ($t in $tars) {
        $a = Desligar-Tarefa $t
        if ($a) { $acoes += $a; Write-Host ("  [OK] {0}" -f $t.Nome) -ForegroundColor Green }
    }
    return @($acoes)
}

# ------------------------------------------------------------
# Desfazer
# ------------------------------------------------------------
function Desfazer-Tudo($diario) {
    $execs = @($diario.execucoes)
    if ($execs.Count -eq 0) {
        Write-Host '[i] O diário está vazio: este programa ainda não alterou nada nesta máquina.' -ForegroundColor Cyan
        return $false
    }
    $todas = @()
    foreach ($e in $execs) { $todas += @($e.acoes) }

    $reg  = @($todas | Where-Object { $_.tipo -eq 'registro' })
    $svc  = @($todas | Where-Object { $_.tipo -eq 'servico' })
    $tar  = @($todas | Where-Object { $_.tipo -eq 'tarefa' })
    $apps = @($todas | Where-Object { $_.tipo -eq 'app' })

    Titulo 'Prévia: o que será revertido'
    Write-Host ("  Execuções registradas: {0}" -f $execs.Count) -ForegroundColor White
    Write-Host ("  Chaves de registro:    {0}" -f $reg.Count) -ForegroundColor White
    Write-Host ("  Serviços:              {0}" -f $svc.Count) -ForegroundColor White
    Write-Host ("  Tarefas:               {0}" -f $tar.Count) -ForegroundColor White
    Write-Host ("  Apps removidos:        {0}   (estes NÃO voltam por aqui)" -f $apps.Count) -ForegroundColor Yellow
    Write-Host ''
    if (-not (Confirmar 'Reverter tudo?' $false)) { Write-Host 'Cancelado.' -ForegroundColor Yellow; return $false }

    Titulo 'Revertendo'
    $ok = 0; $err = 0
    # Ordem inversa: o ultimo valor gravado e' o primeiro a voltar
    for ($i = $todas.Count - 1; $i -ge 0; $i--) {
        $a = $todas[$i]
        switch ($a.tipo) {
            'registro' { if (Reverter-Valor $a) { $ok++ } else { $err++ } }
            'servico' {
                try { Set-Service -Name $a.nome -StartupType $a.inicioAntes -ErrorAction Stop; $ok++ }
                catch { $err++; Write-Host ("  [ERRO] serviço {0}: {1}" -f $a.nome, $_.Exception.Message) -ForegroundColor Red }
            }
            'tarefa' {
                try { Enable-ScheduledTask -TaskPath $a.caminho -TaskName $a.nome -ErrorAction Stop | Out-Null; $ok++ }
                catch { $err++; Write-Host ("  [ERRO] tarefa {0}: {1}" -f $a.nome, $_.Exception.Message) -ForegroundColor Red }
            }
        }
    }
    Write-Host ''
    Write-Host ("Revertidos: {0}" -f $ok) -ForegroundColor Green
    if ($err -gt 0) { Write-Host ("Falharam:   {0}" -f $err) -ForegroundColor Red }

    if ($apps.Count -gt 0) {
        Write-Host ''
        Write-Host 'Estes apps foram removidos e precisam ser reinstalados pela Store:' -ForegroundColor Yellow
        foreach ($a in ($apps | Sort-Object nome -Unique)) { Write-Host ("  - {0}" -f $a.nome) -ForegroundColor Gray }
        Write-Host ''
        if (Confirmar 'Abrir a Microsoft Store?' $false) { Abrir-Url 'ms-windows-store://home' }
    }
    return $true
}

# ------------------------------------------------------------
# Relatório
# ------------------------------------------------------------
function Salvar-Relatorio([string]$arquivo, $perfil, $apps, $svcs, $tars, $tweaks) {
    $l = @()
    $l += "Relatorio do Debloat - $env:COMPUTERNAME - $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
    $l += "Desenvolvido por Pablo Murad - 2026"
    $l += ''
    $l += "RAM: $($perfil.RamGB) GB | GPU dedicada: $($perfil.GpuDedicada) | Jogos: $($perfil.Jogos) | Everything: $($perfil.Everything) | Office: $($perfil.Office)"
    $l += ''
    $l += '--- APPS DA MICROSOFT PRESENTES ---'
    foreach ($nivel in @('seguro','opcional','nunca')) {
        $g = @($apps | Where-Object { $_.Nivel -eq $nivel })
        if ($g.Count -eq 0) { continue }
        $l += "[$nivel]"
        foreach ($a in $g) { $l += "  $($a.Id)  -  $($a.Nome)" }
    }
    $l += ''
    $l += '--- SERVICOS ---'
    foreach ($s in $svcs) { $l += ("  {0,-20} {1,-10} {2}" -f $s.Nome, $s.Inicio, $s.Desc) }
    $l += ''
    $l += '--- TAREFAS DE TELEMETRIA ---'
    foreach ($t in $tars) { $l += ("  {0,-10} {1}{2}" -f $t.Estado, $t.Caminho, $t.Nome) }
    $l += ''
    $l += '--- CONFIGURACOES ---'
    foreach ($i in $tweaks) {
        $v = Ler-Valor $i.Caminho $i.Chave
        $estado = if ($v.Existe -and "$($v.Valor)" -eq "$($i.Valor)") { 'ok    ' } else { 'aberto' }
        $l += ("  [{0}] {1}" -f $estado, $i.Nome)
    }
    try {
        Set-Content -LiteralPath $arquivo -Value $l -Encoding UTF8
        Write-Host ''
        Write-Host ("[OK] Relatório salvo: {0}" -f $arquivo) -ForegroundColor Green
    } catch { Write-Host "[!] Não salvei o relatório: $($_.Exception.Message)" -ForegroundColor Yellow }
}

# ------------------------------------------------------------
# Início
# ------------------------------------------------------------
Abrir 'Debloat'
Write-Host ''
Write-Host 'O ganho de velocidade é pequeno e honesto: de 200 a 800 MB de RAM e' -ForegroundColor Gray
Write-Host 'de 1 a 3 segundos de boot. O que muda mesmo é tirar irritação e telemetria.' -ForegroundColor Gray
Write-Host ''

$perfil = Detectar-Perfil
Mostrar-Perfil $perfil

$config = Carregar-Config
$padrao = if ($config -and $config.UltimaPasta) { $config.UltimaPasta } else { Join-Path $env:USERPROFILE 'Downloads\Debloat' }
$raiz   = Pedir-Saida $padrao
Salvar-Config ([pscustomobject]@{ UltimaPasta = $raiz })

$pastaPc = Join-Path $raiz $env:COMPUTERNAME
try { New-Item -ItemType Directory -Path $pastaPc -Force | Out-Null }
catch { Write-Host "[ERRO] Não criei a pasta desta máquina: $($_.Exception.Message)" -ForegroundColor Red; Pausar; exit 1 }

$diarioArq = Join-Path $configDir 'desfazer.json'
$tabTweaks = Filtrar-Por-Perfil (Tabela-Tweaks)   $perfil
$tabApps   = Filtrar-Por-Perfil (Tabela-Apps)     $perfil
$tabSvcs   = Filtrar-Por-Perfil (Tabela-Servicos) $perfil
$tabTars   = Tabela-Tarefas

# Guarda se ja criamos ponto de restauracao nesta execucao
$pontoFeito = $false

while ($true) {
    Titulo 'DEBLOAT'
    Write-Host ("  {0}  |  relatórios: {1}" -f $env:COMPUTERNAME, $raiz) -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '> [1] Diagnóstico: o que dá para limpar nesta máquina' -ForegroundColor White
    Write-Host '  [2] Fazer tudo o que é recomendado' -ForegroundColor Gray
    Write-Host '  [3] Apps da Microsoft' -ForegroundColor Gray
    Write-Host '  [4] Privacidade e telemetria' -ForegroundColor Gray
    Write-Host '  [5] Copilot, Recall e IA' -ForegroundColor Gray
    Write-Host '  [6] Anúncios, sugestões e irritações' -ForegroundColor Gray
    Write-Host '  [7] Serviços em segundo plano' -ForegroundColor Gray
    Write-Host '  [8] Tarefas agendadas de telemetria' -ForegroundColor Gray
    Write-Host '  [9] Desfazer o que este programa fez' -ForegroundColor Gray
    Write-Host ''
    Write-Host '  [0] Sair' -ForegroundColor DarkGray
    Write-Host 'Enter = usar a opção padrão [1]' -ForegroundColor DarkGray
    $op = Read-Host 'Opção (0-9)'
    if ([string]::IsNullOrWhiteSpace($op)) { $op = '1' }
    $op = $op.Trim()
    if ($op -eq '0') { break }

    $diario = Carregar-Diario $diarioArq
    $acoes  = @()

    switch ($op) {

        '1' {
            Titulo 'Diagnóstico'
            Write-Host 'Lendo apps, serviços, tarefas e configurações...' -ForegroundColor Gray
            $apps = Apps-Presentes $tabApps
            $svcs = Servicos-Presentes $tabSvcs
            $tars = Tarefas-Presentes $tabTars

            Write-Host ''
            foreach ($nivel in @('seguro','opcional','nunca')) {
                $g = @($apps | Where-Object { $_.Nivel -eq $nivel })
                if ($g.Count -eq 0) { continue }
                $rot = switch ($nivel) { 'seguro' {'Seguros de remover'} 'opcional' {'Opcionais (você decide)'} default {'Não recomendo remover'} }
                $cor = switch ($nivel) { 'seguro' {'Green'} 'opcional' {'Yellow'} default {'Red'} }
                Write-Host ("  {0}  ({1})" -f $rot, $g.Count) -ForegroundColor $cor
                foreach ($a in $g) {
                    $av = if ($a.Aviso) { "  <- $($a.Aviso)" } else { '' }
                    Write-Host ("     {0}{1}" -f $a.Nome, $av) -ForegroundColor Gray
                }
                Write-Host ''
            }
            Write-Host ("  Serviços que dá para aliviar: {0} de {1}" -f @($svcs | Where-Object { -not $_.JaOk }).Count, $svcs.Count) -ForegroundColor White
            Write-Host ("  Tarefas de telemetria ativas: {0} de {1}" -f @($tars | Where-Object { -not $_.JaOk }).Count, $tars.Count) -ForegroundColor White
            $abertos = 0
            foreach ($i in $tabTweaks) { $v = Ler-Valor $i.Caminho $i.Chave; if (-not ($v.Existe -and "$($v.Valor)" -eq "$($i.Valor)")) { $abertos++ } }
            Write-Host ("  Configurações fora do ideal:  {0} de {1}" -f $abertos, @($tabTweaks).Count) -ForegroundColor White

            # O Windows Update reinstala o que foi removido: avisa o que voltou
            $jaRemovidos = @()
            foreach ($e in @($diario.execucoes)) { foreach ($a in @($e.acoes)) { if ($a.tipo -eq 'app') { $jaRemovidos += "$($a.id)" } } }
            $voltaram = @($apps | Where-Object { $jaRemovidos -contains $_.Id })
            if ($voltaram.Count -gt 0) {
                Write-Host ''
                Write-Host ("[!] {0} app(s) que você já removeu VOLTARAM (atualização do Windows):" -f $voltaram.Count) -ForegroundColor Yellow
                foreach ($a in $voltaram) { Write-Host ("     {0}" -f $a.Nome) -ForegroundColor Gray }
            }
            Write-Host ''
            Write-Host 'Para limpar arquivos temporários e a lixeira, use o Úteis\limpeza-segura.' -ForegroundColor DarkGray
            Salvar-Relatorio (Join-Path $pastaPc ("relatorio-{0}.txt" -f (Get-Date -Format 'yyyy-MM-dd'))) $perfil $apps $svcs $tars $tabTweaks
            Pausar
        }

        '2' {
            Titulo 'Tudo o que é recomendado'
            $apps = @((Apps-Presentes $tabApps) | Where-Object { $_.Nivel -eq 'seguro' })
            $svcs = @((Servicos-Presentes $tabSvcs) | Where-Object { $_.Nivel -eq 'seguro' -and -not $_.JaOk })
            $tars = @((Tarefas-Presentes $tabTars) | Where-Object { -not $_.JaOk })
            $tw   = Previa-Tweaks $tabTweaks 'privacidade, IA e irritações'
            Write-Host ''
            Write-Host ("Apps a remover:      {0}" -f $apps.Count) -ForegroundColor White
            Write-Host ("Serviços a aliviar:  {0}" -f $svcs.Count) -ForegroundColor White
            Write-Host ("Tarefas a desligar:  {0}" -f $tars.Count) -ForegroundColor White
            Write-Host ''
            Write-Host 'App removido NÃO volta pelo desfazer. O resto volta.' -ForegroundColor Yellow
            Write-Host ''
            if (-not (Confirmar 'Aplicar tudo isso?' $false)) { Write-Host 'Cancelado.' -ForegroundColor Yellow; Pausar; continue }
            if (-not $pontoFeito) { [void](Criar-Ponto-Restauracao); $pontoFeito = $true }
            Titulo 'Aplicando'
            $acoes += Aplicar-Tweaks   $tw
            $acoes += Aplicar-Apps     $apps
            $acoes += Aplicar-Servicos $svcs
            $acoes += Aplicar-Tarefas  $tars
        }

        '3' {
            Titulo 'Apps da Microsoft'
            $apps = Apps-Presentes $tabApps
            $alvo = Previa-Apps $apps
            if ($alvo.Count -eq 0) { Write-Host '[OK] Nada seguro a remover: já está limpo.' -ForegroundColor Green; Pausar; continue }
            Write-Host ''
            if (-not (Confirmar 'Remover esses apps?' $false)) { Write-Host 'Cancelado.' -ForegroundColor Yellow; Pausar; continue }
            if (-not $pontoFeito) { [void](Criar-Ponto-Restauracao); $pontoFeito = $true }
            Titulo 'Removendo'
            $acoes += Aplicar-Apps $alvo
        }

        { $_ -in @('4','5','6') } {
            $area = switch ($op) { '4' {'privacidade'} '5' {'ia'} default {'irritacao'} }
            $rot  = switch ($op) { '4' {'Privacidade e telemetria'} '5' {'Copilot, Recall e IA'} default {'Anúncios, sugestões e irritações'} }
            $itens = @($tabTweaks | Where-Object { $_.Area -eq $area })
            $mudam = Previa-Tweaks $itens $rot
            if ($mudam.Count -eq 0) { Write-Host ''; Write-Host '[OK] Já está tudo do jeito certo.' -ForegroundColor Green; Pausar; continue }
            Write-Host ''
            if (-not (Confirmar 'Aplicar?' $true)) { Write-Host 'Cancelado.' -ForegroundColor Yellow; Pausar; continue }
            if (-not $pontoFeito) { [void](Criar-Ponto-Restauracao); $pontoFeito = $true }
            Titulo 'Aplicando'
            $acoes += Aplicar-Tweaks $mudam
        }

        '7' {
            Titulo 'Serviços em segundo plano'
            if ($perfil.RamGB -ge 32) {
                Write-Host ("Com {0} GB de RAM isso quase não muda nada. Faça só se quiser padronizar." -f $perfil.RamGB) -ForegroundColor DarkGray
            }
            $svcs = Servicos-Presentes $tabSvcs
            $mudam = Previa-Servicos $svcs
            if ($mudam.Count -eq 0) { Write-Host ''; Write-Host '[OK] Nada a mudar.' -ForegroundColor Green; Pausar; continue }
            Write-Host ''
            if (-not (Confirmar 'Passar esses para Manual?' $false)) { Write-Host 'Cancelado.' -ForegroundColor Yellow; Pausar; continue }
            if (-not $pontoFeito) { [void](Criar-Ponto-Restauracao); $pontoFeito = $true }
            Titulo 'Aplicando'
            $acoes += Aplicar-Servicos $mudam
        }

        '8' {
            Titulo 'Tarefas agendadas de telemetria'
            $tars = Tarefas-Presentes $tabTars
            $mudam = Previa-Tarefas $tars
            if ($mudam.Count -eq 0) { Write-Host ''; Write-Host '[OK] Todas já estão desabilitadas.' -ForegroundColor Green; Pausar; continue }
            Write-Host ''
            if (-not (Confirmar 'Desabilitar essas tarefas?' $true)) { Write-Host 'Cancelado.' -ForegroundColor Yellow; Pausar; continue }
            if (-not $pontoFeito) { [void](Criar-Ponto-Restauracao); $pontoFeito = $true }
            Titulo 'Aplicando'
            $acoes += Aplicar-Tarefas $mudam
        }

        '9' {
            Titulo 'Desfazer'
            [void](Desfazer-Tudo $diario)
            # O desfazer zera o diario: o que foi revertido nao deve ser revertido de novo
            try {
                $vazio = [pscustomobject]@{ versao=1; maquina=$env:COMPUTERNAME; execucoes=@() }
                $vazio | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $diarioArq -Encoding UTF8
            } catch { Write-Host "[!] Não limpei o diário: $($_.Exception.Message)" -ForegroundColor DarkGray }
            Pausar
        }

        default { Write-Host '[!] Escolha de 0 a 9.' -ForegroundColor Yellow; Start-Sleep -Seconds 1 }
    }

    if (@($acoes).Count -gt 0) {
        Gravar-Diario $diarioArq $diario $acoes $pastaPc
        Write-Host ''
        Write-Host ("[OK] {0} alteração(ões) registradas no diário. A opção 9 reverte." -f @($acoes).Count) -ForegroundColor Green
        Write-Host '[i] Algumas mudanças só aparecem depois de reiniciar o Explorer ou o PC.' -ForegroundColor Cyan
        Pausar
    }
}

Titulo 'Concluído'
Write-Host ("Relatórios: {0}" -f $pastaPc) -ForegroundColor White
Write-Host ("Diário do desfazer: {0}" -f $diarioArq) -ForegroundColor White
Write-Host '  Desenvolvido por Pablo Murad - 2026' -ForegroundColor DarkGray
Write-Host ''
