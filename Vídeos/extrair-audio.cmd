<# :
@echo off
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression ([System.IO.File]::ReadAllText('%~f0',[System.Text.Encoding]::UTF8))"
exit /b %errorlevel%
#>

# ============================================================
#  Extrair Áudio - tira o áudio de vídeos (FFmpeg)
#  Desenvolvido por Pablo Murad - 2026
# ============================================================

try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
try { $Host.UI.RawUI.WindowTitle = 'Extrair Áudio' } catch {}

# ------------------------------------------------------------
# Blindagem de fechamento: amarra este processo a um Job do Windows
# com KILL_ON_JOB_CLOSE. Se a janela for fechada no X (ou o processo
# morrer de qualquer jeito), o Windows mata junto todo processo-filho
# (ffmpeg, yt-dlp, etc.) — nada fica rodando orfao. O 'finally' do
# pool so' cobre Ctrl+C e erros; o X escapa dele, e este Job cobre o X.
# ------------------------------------------------------------
try {
    Add-Type -Namespace FS -Name Job -MemberDefinition @'
[DllImport("kernel32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr CreateJobObject(IntPtr a, string n);
[DllImport("kernel32.dll", SetLastError=true)] public static extern bool SetInformationJobObject(IntPtr j, int c, IntPtr i, uint s);
[DllImport("kernel32.dll", SetLastError=true)] public static extern bool AssignProcessToJobObject(IntPtr j, IntPtr p);
[DllImport("kernel32.dll")] public static extern IntPtr GetCurrentProcess();
'@ -ErrorAction Stop
    if ([IntPtr]::Size -eq 8) {
        $__job = [FS.Job]::CreateJobObject([IntPtr]::Zero, $null)
        if ($__job -ne [IntPtr]::Zero) {
            $__sz = 144   # JOBOBJECT_EXTENDED_LIMIT_INFORMATION em 64 bits
            $__pi = [System.Runtime.InteropServices.Marshal]::AllocHGlobal($__sz)
            for ($__i = 0; $__i -lt $__sz; $__i++) { [System.Runtime.InteropServices.Marshal]::WriteByte($__pi, $__i, 0) }
            [System.Runtime.InteropServices.Marshal]::WriteInt32($__pi, 16, 0x2000)  # KILL_ON_JOB_CLOSE
            [void][FS.Job]::SetInformationJobObject($__job, 9, $__pi, $__sz)
            [System.Runtime.InteropServices.Marshal]::FreeHGlobal($__pi)
            # O handle fica aberto DE PROPOSITO ate o processo morrer: e' o
            # fechamento dele que dispara a matanca dos filhos. $__job global
            # impede o coletor de lixo de fechar cedo.
            [void][FS.Job]::AssignProcessToJobObject($__job, [FS.Job]::GetCurrentProcess())
        }
    }
} catch { Write-Host "[i] Blindagem de fechamento indisponivel: $($_.Exception.Message)" -ForegroundColor DarkGray }

# ============================================================
#  Executar-EmParalelo - pool de processos externos (PS 5.1)
#  Cada tarefa: @{ Exe='ffmpeg'; Args=@(...); Rotulo='x.mp4'; Dur=123.4 }
#  Dur e' opcional (segundos) e so' pondera a barra de progresso.
#  Devolve 1 objeto por tarefa: Indice/Rotulo/Codigo/Saida/Erro/Segundos
# ============================================================
function Limite-Padrao([string]$tipo) {
    $n = [Environment]::ProcessorCount
    switch ($tipo) {
        'gpu'    { 3 }
        'cpu'    { [Math]::Max(2, [Math]::Min(4,  [int]($n / 6))) }
        'imagem' { [Math]::Max(2, [Math]::Min(8,  [int]($n / 3))) }
        'sonda'  { [Math]::Max(4, [Math]::Min(12, [int]($n / 2))) }
        default  { 4 }
    }
}

function Executar-EmParalelo {
    param(
        [object[]]$Tarefas,
        [int]$Limite = 4,
        [switch]$SemProgresso
    )

    # Quoting do Windows (CommandLineToArgvW). NAO simplificar: dobrar as
    # barras finais e' o que impede um caminho terminado em '\' de comer
    # a aspa de fechamento.
    function _Citar([string]$a) {
        if ($a -eq '')            { return '""' }
        if ($a -notmatch '[\s"]') { return $a }
        $s = ''; $bs = 0
        foreach ($c in $a.ToCharArray()) {
            if ($c -eq '\') { $bs++; continue }
            if ($c -eq '"') { $s += ('\' * ($bs * 2 + 1)) + '"'; $bs = 0; continue }
            if ($bs) { $s += ('\' * $bs); $bs = 0 }
            $s += $c
        }
        if ($bs) { $s += ('\' * ($bs * 2)) }
        return '"' + $s + '"'
    }

    $tot = @($Tarefas).Count
    if ($tot -eq 0) { return @() }
    if ($Limite -lt 1) { $Limite = 1 }

    $res    = New-Object object[] $tot
    $ativos = New-Object System.Collections.ArrayList
    $prox = 0; $feitos = 0; $falhas = 0
    $durTotal = 0.0; foreach ($t in $Tarefas) { if ($t.Dur) { $durTotal += [double]$t.Dur } }
    $durFeita = 0.0
    $t0 = Get-Date

    try {
        while ($feitos -lt $tot) {

            while ($ativos.Count -lt $Limite -and $prox -lt $tot) {
                $t = $Tarefas[$prox]
                $psi = New-Object System.Diagnostics.ProcessStartInfo
                $psi.FileName               = $t.Exe
                $psi.Arguments              = ((@($t.Args) | ForEach-Object { _Citar $_ }) -join ' ')
                $psi.UseShellExecute        = $false
                $psi.CreateNoWindow         = $true
                $psi.RedirectStandardOutput = $true
                $psi.RedirectStandardError  = $true
                $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
                $psi.StandardErrorEncoding  = [System.Text.Encoding]::UTF8
                $p = [System.Diagnostics.Process]::Start($psi)
                [void]$ativos.Add([pscustomobject]@{
                    Idx   = $prox
                    Rot   = $t.Rotulo
                    Dur   = $(if ($t.Dur) { [double]$t.Dur } else { 0.0 })
                    Proc  = $p
                    Linha = $p.StandardOutput.ReadLineAsync()
                    Err   = $p.StandardError.ReadToEndAsync()
                    Buf   = (New-Object System.Text.StringBuilder)
                    Seg   = 0.0
                    Ini   = (Get-Date)
                })
                $prox++
            }

            # drena stdout sem bloquear (senao o pipe cheio trava o processo)
            foreach ($a in $ativos) {
                while ($a.Linha -and $a.Linha.IsCompleted) {
                    $l = $a.Linha.Result
                    if ($null -eq $l) { $a.Linha = $null; break }
                    [void]$a.Buf.AppendLine($l)
                    if ($l -match '^out_time_us=(\d+)' -or $l -match '^out_time_ms=(\d+)') {
                        $a.Seg = [double]$matches[1] / 1000000.0
                    }
                    $a.Linha = $a.Proc.StandardOutput.ReadLineAsync()
                }
            }

            for ($i = $ativos.Count - 1; $i -ge 0; $i--) {
                $a = $ativos[$i]
                if (-not $a.Proc.HasExited) { continue }
                while ($a.Linha) {
                    $l = $a.Linha.Result
                    if ($null -eq $l) { $a.Linha = $null; break }
                    [void]$a.Buf.AppendLine($l)
                    $a.Linha = $a.Proc.StandardOutput.ReadLineAsync()
                }
                $rc = $a.Proc.ExitCode
                $res[$a.Idx] = [pscustomobject]@{
                    Indice   = $a.Idx
                    Rotulo   = $a.Rot
                    Codigo   = $rc
                    Saida    = $a.Buf.ToString()
                    Erro     = $a.Err.Result
                    Segundos = [math]::Round(((Get-Date) - $a.Ini).TotalSeconds, 1)
                }
                $durFeita += $a.Dur
                try { $a.Proc.Dispose() } catch {}
                $ativos.RemoveAt($i)
                $feitos++
                if ($rc -ne 0) { $falhas++ }
            }

            if (-not $SemProgresso) {
                if ($durTotal -gt 0) {
                    $parcial = $durFeita; foreach ($a in $ativos) { $parcial += $a.Seg }
                    $frac = $parcial / $durTotal
                } else {
                    $frac = $feitos / $tot
                }
                if ($frac -gt 1) { $frac = 1 }
                $pct = [int]($frac * 100)
                $dec = (Get-Date) - $t0
                $eta = if ($frac -gt 0.01) { [TimeSpan]::FromSeconds($dec.TotalSeconds / $frac - $dec.TotalSeconds) } else { [TimeSpan]::Zero }
                $ch  = [int]($pct / 5)
                Write-Host ("`r  [{0}] {1,3}%  {2}/{3}  ativos:{4}  falhas:{5}  restante ~{6:mm\:ss}   " -f `
                    (('#' * $ch) + ('-' * (20 - $ch))), $pct, $feitos, $tot, $ativos.Count, $falhas, $eta) `
                    -NoNewline -ForegroundColor Cyan
            }

            if ($feitos -lt $tot) { Start-Sleep -Milliseconds 150 }
        }
    }
    finally {
        foreach ($a in $ativos) {
            try { if (-not $a.Proc.HasExited) { $a.Proc.Kill() } } catch {}
            try { $a.Proc.Dispose() } catch {}
        }
    }
    if (-not $SemProgresso) { Write-Host '' }
    return ,$res
}

function Pausar { Write-Host ''; Write-Host 'Pressione Enter para fechar...' -ForegroundColor DarkGray; [void][System.Console]::ReadLine() }
function Titulo($t) {
    Write-Host ''
    Write-Host '============================================================' -ForegroundColor DarkCyan
    Write-Host "  $t" -ForegroundColor Cyan
    Write-Host '============================================================' -ForegroundColor DarkCyan
}

$configDir  = Join-Path $env:APPDATA 'ExtrairAudio'
$configFile = Join-Path $configDir 'config.json'
function Carregar-Config { if (Test-Path -LiteralPath $configFile) { try { return Get-Content -LiteralPath $configFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch {} }; return $null }
function Salvar-Config($e,$f,$s) { try { New-Item -ItemType Directory -Path $configDir -Force | Out-Null; [pscustomobject]@{ UltimaEntrada=$e; UltimoFormato=$f; UltimaSaida=$s } | ConvertTo-Json | Set-Content -LiteralPath $configFile -Encoding UTF8 } catch {} }

$extensoes = @('.mp4','.mkv','.avi','.mov','.wmv','.flv','.webm','.m4v','.mpg','.mpeg','.mts','.m2ts','.ts','.3gp','.vob')

$formatos = @(
    [pscustomobject]@{ Id=1; Nome='MP3';       Desc='Compatível com tudo (192 kbps)';    Ext='.mp3'; Args=@('-c:a','libmp3lame','-b:a','192k') },
    [pscustomobject]@{ Id=2; Nome='M4A (AAC)';  Desc='Ótima qualidade x tamanho (192 kbps)'; Ext='.m4a'; Args=@('-c:a','aac','-b:a','192k') },
    [pscustomobject]@{ Id=3; Nome='WAV';        Desc='Sem compressão (arquivo grande)';   Ext='.wav'; Args=@('-c:a','pcm_s16le') }
)

Titulo 'Extrair Áudio'
Write-Host '  Desenvolvido por Pablo Murad - 2026' -ForegroundColor DarkGray
Write-Host ''
Write-Host 'Verificando o que é necessário...' -ForegroundColor Gray
$ffmpeg = Get-Command ffmpeg -ErrorAction SilentlyContinue
if (-not $ffmpeg) {
    Write-Host ''; Write-Host '[ERRO] FFmpeg não encontrado.' -ForegroundColor Red
    Write-Host 'Instale com:  winget install Gyan.FFmpeg' -ForegroundColor White
    Pausar; exit 1
}
Write-Host "[OK] FFmpeg: $($ffmpeg.Source)" -ForegroundColor Green
$config = Carregar-Config

# Pasta ou vídeo
$entradaAtual = if ($config -and $config.UltimaEntrada) { $config.UltimaEntrada } else { Join-Path $env:USERPROFILE 'Downloads\Vídeos' }
$modoArquivo = $false; $arquivoUnico = $null
while ($true) {
    Titulo 'Pasta ou vídeo'
    Write-Host "  $entradaAtual" -ForegroundColor White
    Write-Host 'Enter = confirmar | ou cole uma PASTA ou um VÍDEO' -ForegroundColor DarkGray
    $resp = Read-Host 'Pasta/vídeo'
    if (-not [string]::IsNullOrWhiteSpace($resp)) { $entradaAtual = $resp.Trim().Trim('"') }
    if (Test-Path -LiteralPath $entradaAtual -PathType Leaf) {
        if ($extensoes -notcontains [System.IO.Path]::GetExtension($entradaAtual).ToLowerInvariant()) { Write-Host '[!] Não é um vídeo suportado.' -ForegroundColor Yellow; continue }
        $modoArquivo = $true; $arquivoUnico = (Resolve-Path -LiteralPath $entradaAtual).Path; break
    } elseif (Test-Path -LiteralPath $entradaAtual -PathType Container) { $modoArquivo = $false; break }
    Write-Host "[!] Caminho não encontrado." -ForegroundColor Yellow
}
if ($modoArquivo) { $arquivoObj = Get-Item -LiteralPath $arquivoUnico; $origem = $arquivoObj.DirectoryName } else { $origem = (Resolve-Path -LiteralPath $entradaAtual).Path }
$destino = Join-Path $origem 'Áudio'

# Formato
$fmtPadrao = if ($config -and $config.UltimoFormato) { [int]$config.UltimoFormato } else { 1 }
Titulo 'Formato do áudio'
foreach ($f in $formatos) {
    $m = if ($f.Id -eq $fmtPadrao) { '>' } else { ' ' }
    $c = if ($f.Id -eq $fmtPadrao) { 'White' } else { 'Gray' }
    Write-Host ("{0} [{1}] {2}" -f $m,$f.Id,$f.Nome) -ForegroundColor $c
    Write-Host ("       {0}" -f $f.Desc) -ForegroundColor DarkGray
}
Write-Host "Enter = padrão [$fmtPadrao]" -ForegroundColor DarkGray
$formato = $null
while (-not $formato) {
    $e = Read-Host 'Formato (1-3)'; if ([string]::IsNullOrWhiteSpace($e)) { $e = "$fmtPadrao" }
    $formato = $formatos | Where-Object { $_.Id -eq ($e -as [int]) } | Select-Object -First 1
    if (-not $formato) { Write-Host '[!] Inválido.' -ForegroundColor Yellow }
}
# Pasta de saída (lembra a última; cria se não existir)
$saidaPadrao = if ($config -and $config.UltimaSaida) { $config.UltimaSaida } else { $destino }
while ($true) {
    Titulo 'Pasta de saída'
    Write-Host "  $saidaPadrao" -ForegroundColor White
    Write-Host 'Enter = usar esta pasta   |   ou cole/digite outra' -ForegroundColor DarkGray
    $rsaida = Read-Host 'Pasta de saída'
    $destino = if ([string]::IsNullOrWhiteSpace($rsaida)) { $saidaPadrao } else { $rsaida.Trim().Trim('"') }
    try { New-Item -ItemType Directory -Path $destino -Force | Out-Null; break }
    catch { Write-Host '[!] Não foi possível criar/usar essa pasta.' -ForegroundColor Yellow }
}
$destino = (Resolve-Path -LiteralPath $destino).Path

Salvar-Config $origem $formato.Id $destino

# Coleta
if ($modoArquivo) { $arquivos = @($arquivoObj) } else {
    $arquivos = @(Get-ChildItem -LiteralPath $origem -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
        ($extensoes -contains $_.Extension.ToLowerInvariant()) -and (-not $_.FullName.StartsWith($destino,[System.StringComparison]::OrdinalIgnoreCase)) })
}
Titulo 'Processando'
Write-Host "Formato: $($formato.Nome)   |   Destino: $destino"
Write-Host "Vídeos encontrados: $($arquivos.Count)" -ForegroundColor Cyan
if ($arquivos.Count -eq 0) { Write-Host 'Nenhum vídeo encontrado.' -ForegroundColor Yellow; Pausar; exit 0 }
New-Item -ItemType Directory -Path $destino -Force | Out-Null

# --- 1) sonda os codecs de audio em paralelo (para poder copiar sem recodificar) ---
$sonda = @()
foreach ($a in $arquivos) {
    $sonda += @{ Exe = 'ffprobe'; Rotulo = $a.Name
                 Args = @('-v','error','-select_streams','a:0','-show_entries','stream=codec_name','-of','csv=p=0',$a.FullName) }
}
$codecs = @{}
if ($sonda.Count -gt 0) {
    Write-Host 'Analisando os audios...' -ForegroundColor Gray
    $rs = Executar-EmParalelo -Tarefas $sonda -Limite (Limite-Padrao 'sonda') -SemProgresso
    for ($i = 0; $i -lt $rs.Count; $i++) {
        $c = ''
        if ($rs[$i] -and $rs[$i].Codigo -eq 0) { $c = ($rs[$i].Saida -split "`n" | Where-Object { $_.Trim() } | Select-Object -First 1) }
        $codecs[$arquivos[$i].FullName] = "$c".Trim()
    }
}

$ok=0;$ign=0;$err=0;$copiados=0

# --- 2) monta as tarefas ---
$tarefas = @()
foreach ($a in $arquivos) {
    $rel = $a.FullName.Substring($origem.Length).TrimStart('\'); $sub = Split-Path $rel -Parent
    $pastaSaida = if ([string]::IsNullOrWhiteSpace($sub)) { $destino } else { Join-Path $destino $sub }
    New-Item -ItemType Directory -Path $pastaSaida -Force | Out-Null
    $saida = Join-Path $pastaSaida ($a.BaseName + $formato.Ext)
    if (Test-Path -LiteralPath $saida) { $ign++; continue }

    # Se o codec da fonte ja e' o do destino, copia o stream: quase instantaneo
    $cod = "$($codecs[$a.FullName])".ToLowerInvariant()
    $podeCopiar = ($formato.Ext -eq '.m4a' -and $cod -eq 'aac') -or ($formato.Ext -eq '.mp3' -and $cod -eq 'mp3')
    if ($podeCopiar) { $audioArgs = @('-c:a','copy'); $copiados++ } else { $audioArgs = $formato.Args }

    $ffArgs = @('-hide_banner','-nostdin','-loglevel','error','-i',$a.FullName,'-vn') + $audioArgs + @('-y',$saida)
    $tarefas += @{ Exe = 'ffmpeg'; Rotulo = $a.Name; Alvo = $saida; Args = $ffArgs }
}

if ($ign -gt 0) { Write-Host "$ign ja existiam no destino e foram pulados." -ForegroundColor Yellow }
if ($copiados -gt 0) { Write-Host "$copiados serao copiados sem recodificar (bem mais rapido)." -ForegroundColor Green }

# --- 3) executa em paralelo ---
if ($tarefas.Count -gt 0) {
    $lim = Limite-Padrao 'cpu'
    Write-Host ("Extraindo de {0} video(s), ate {1} ao mesmo tempo..." -f $tarefas.Count, $lim) -ForegroundColor Gray
    $resultados = Executar-EmParalelo -Tarefas $tarefas -Limite $lim
    foreach ($x in $resultados) {
        $alvo = $tarefas[$x.Indice].Alvo
        if ($x.Codigo -eq 0 -and (Test-Path -LiteralPath $alvo)) { $ok++ }
        else {
            $err++
            Write-Host ("  [ERRO] {0}" -f $x.Rotulo) -ForegroundColor Red
            $motivo = ($x.Erro -split "`n" | Where-Object { $_.Trim() } | Select-Object -Last 1)
            if ($motivo) { Write-Host ("         {0}" -f $motivo.Trim()) -ForegroundColor DarkGray }
            if (Test-Path -LiteralPath $alvo) { Remove-Item -LiteralPath $alvo -Force -ErrorAction SilentlyContinue }
        }
    }
}
Titulo 'Concluído'
Write-Host "Extraídos: $ok" -ForegroundColor Green
Write-Host "Ignorados: $ign" -ForegroundColor Yellow
Write-Host "Erros:     $err" -ForegroundColor $(if ($err -gt 0){'Red'}else{'Gray'})
Write-Host "Destino:   $destino"
Pausar
