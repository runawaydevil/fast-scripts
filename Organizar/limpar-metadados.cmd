<# :
@echo off
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression ([System.IO.File]::ReadAllText('%~f0',[System.Text.Encoding]::UTF8))"
exit /b %errorlevel%
#>

# ============================================================
#  Limpar Metadados - remove EXIF/GPS de fotos e vídeos (privacidade)
#  Desenvolvido por Pablo Murad - 2026
# ============================================================

try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
try { $Host.UI.RawUI.WindowTitle = 'Limpar Metadados' } catch {}

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
    return $res
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

$configDir  = Join-Path $env:APPDATA 'LimparMetadados'
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

Abrir 'Limpar Metadados'
Checar 'magick' 'ImageMagick' 'winget install ImageMagick.ImageMagick' | Out-Null
$temFfmpeg = [bool](Get-Command ffmpeg -ErrorAction SilentlyContinue)
if ($temFfmpeg) { Write-Host '[OK] FFmpeg encontrado (vídeos também serão limpos).' -ForegroundColor Green }
else { Write-Host '[!] Sem FFmpeg: só as imagens serão limpas.' -ForegroundColor Yellow }
$config = Carregar-Config

Write-Host ''
Write-Host 'Remove EXIF, GPS, câmera, data e outros metadados - útil antes de publicar.' -ForegroundColor DarkGray
Write-Host 'Os arquivos ORIGINAIS não são alterados: as cópias limpas vão para a pasta de saída.' -ForegroundColor DarkGray

$padrao = if ($config -and $config.UltimaEntrada) { $config.UltimaEntrada } else { Join-Path $env:USERPROFILE 'Downloads' }
$aceitos = $extImg + $extVideo
$ent = Pedir-Entrada $padrao $aceitos 'Pasta ou arquivo'
$itens = Listar $ent $aceitos
if ($itens.Count -eq 0) { Write-Host 'Nenhum arquivo encontrado.' -ForegroundColor Yellow; Pausar; exit 0 }

# previa: mostra o que existe hoje numa amostra
Titulo 'Prévia'
$amostra = $itens | Where-Object { $extImg -contains $_.Extension.ToLowerInvariant() } | Select-Object -First 1
if ($amostra) {
    $info = & magick identify -format '%[EXIF:Make] %[EXIF:Model] %[EXIF:DateTimeOriginal] %[EXIF:GPSLatitude]' "$($amostra.FullName)[0]" 2>$null
    if ("$info".Trim()) { Write-Host ("  Exemplo ({0}) contém: {1}" -f $amostra.Name, "$info".Trim()) -ForegroundColor Yellow }
    else { Write-Host ("  Exemplo ({0}): sem EXIF relevante." -f $amostra.Name) -ForegroundColor Gray }
}
Write-Host ("  {0} arquivo(s) serão limpos." -f $itens.Count) -ForegroundColor White

$destino = Pedir-Saida $(if ($config -and $config.UltimaSaida) { $config.UltimaSaida } else { Join-Path $ent.Origem 'SemMetadados' })
Salvar-Config ([pscustomobject]@{ UltimaEntrada=$ent.Origem; UltimaSaida=$destino })

$ok=0;$ign=0;$err=0
$tarefas = @()
foreach ($f in $itens) {
    $saida = Join-Path $destino $f.Name
    if (Test-Path -LiteralPath $saida) { $ign++; continue }
    if ($extImg -contains $f.Extension.ToLowerInvariant()) {
        $tarefas += @{ Exe='magick'; Rotulo=$f.Name; Alvo=$saida; Args=@($f.FullName,'-strip',$saida) }
    } elseif ($temFfmpeg) {
        $tarefas += @{ Exe='ffmpeg'; Rotulo=$f.Name; Alvo=$saida
                       Args=@('-hide_banner','-nostdin','-loglevel','error','-i',$f.FullName,'-map_metadata','-1','-c','copy','-y',$saida) }
    }
}
if ($ign -gt 0) { Write-Host "$ign já existiam no destino e foram pulados." -ForegroundColor Yellow }

Titulo 'Limpando'
if ($tarefas.Count -gt 0) {
    $lim = Limite-Padrao 'imagem'
    Write-Host ("{0} arquivo(s), até {1} ao mesmo tempo..." -f $tarefas.Count, $lim) -ForegroundColor Gray
    $rs = Executar-EmParalelo -Tarefas $tarefas -Limite $lim
    Relatar $rs $tarefas ([ref]$ok) ([ref]$err)
}
Resumo $ok $ign $err $destino