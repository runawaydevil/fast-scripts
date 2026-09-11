<# :
@echo off
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression ([System.IO.File]::ReadAllText('%~f0',[System.Text.Encoding]::UTF8))"
exit /b %errorlevel%
#>

# ============================================================
#  Achar duplicados - encontra arquivos iguais por conteúdo (hash)
#  Desenvolvido por Pablo Murad - 2026
# ============================================================

try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
try { $Host.UI.RawUI.WindowTitle = 'Achar duplicados' } catch {}

function Pausar { Write-Host ''; Write-Host 'Pressione Enter para fechar...' -ForegroundColor DarkGray; [void][System.Console]::ReadLine() }
function Titulo($t) {
    Write-Host ''
    Write-Host '============================================================' -ForegroundColor DarkCyan
    Write-Host "  $t" -ForegroundColor Cyan
    Write-Host '============================================================' -ForegroundColor DarkCyan
}
function Tam($bytes) { if ($bytes -ge 1GB) { '{0:N2} GB' -f ($bytes/1GB) } elseif ($bytes -ge 1MB) { '{0:N1} MB' -f ($bytes/1MB) } else { '{0:N0} KB' -f ($bytes/1KB) } }

Titulo 'Achar duplicados'
Write-Host '  Desenvolvido por Pablo Murad - 2026' -ForegroundColor DarkGray

$pasta = $null
while (-not $pasta) {
    Write-Host ''
    $p = (Read-Host 'Cole o caminho da pasta (verifica também as subpastas)').Trim().Trim('"')
    if (Test-Path -LiteralPath $p -PathType Container) { $pasta = (Resolve-Path -LiteralPath $p).Path } else { Write-Host '[!] Pasta não encontrada.' -ForegroundColor Yellow }
}

Write-Host ''
Write-Host 'Analisando... (agrupa por tamanho e depois compara o conteúdo)' -ForegroundColor Gray
$todos = @(Get-ChildItem -LiteralPath $pasta -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Length -gt 0 })

# 1) agrupa por tamanho (rápido); 2) só calcula hash de quem tem tamanho repetido
$porTamanho = $todos | Group-Object Length | Where-Object { $_.Count -gt 1 }
$grupos = @()
foreach ($g in $porTamanho) {
    $porHash = $g.Group | Group-Object { (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
    foreach ($h in ($porHash | Where-Object { $_.Count -gt 1 })) {
        $grupos += ,@($h.Group | Sort-Object FullName)
    }
}

if ($grupos.Count -eq 0) { Titulo 'Resultado'; Write-Host 'Nenhum arquivo duplicado encontrado.' -ForegroundColor Green; Pausar; exit 0 }

$totalDup = 0; $espaco = 0
foreach ($grp in $grupos) { $totalDup += ($grp.Count - 1); $espaco += ($grp.Count - 1) * $grp[0].Length }

Titulo 'Duplicados encontrados'
Write-Host ("Grupos de iguais: {0}   |   Cópias extras: {1}   |   Espaço recuperável: {2}" -f $grupos.Count, $totalDup, (Tam $espaco)) -ForegroundColor Cyan
Write-Host ''
$mostra = [Math]::Min($grupos.Count, 15)
for ($i=0; $i -lt $mostra; $i++) {
    $grp = $grupos[$i]
    Write-Host ("Grupo {0} ({1} cópias, {2} cada):" -f ($i+1), $grp.Count, (Tam $grp[0].Length)) -ForegroundColor White
    for ($j=0; $j -lt $grp.Count; $j++) {
        $marca = if ($j -eq 0) { '[manter] ' } else { '[extra]  ' }
        $cor   = if ($j -eq 0) { 'Green' } else { 'DarkGray' }
        Write-Host ("   $marca" + $grp[$j].FullName) -ForegroundColor $cor
    }
}
if ($grupos.Count -gt $mostra) { Write-Host ("... e mais {0} grupo(s)." -f ($grupos.Count - $mostra)) -ForegroundColor DarkGray }

Titulo 'O que fazer com as cópias extras?'
Write-Host '  [1] Só listar (nada é alterado) - padrão' -ForegroundColor White
Write-Host '  [2] Mover as cópias extras para uma subpasta "_Duplicados"' -ForegroundColor White
Write-Host '  [3] Apagar as cópias extras (mantém sempre 1 original)' -ForegroundColor White
$acao = Read-Host 'Opção (Enter = 1)'
if ([string]::IsNullOrWhiteSpace($acao)) { $acao = '1' }

if ($acao -eq '1') { Write-Host ''; Write-Host 'Nada foi alterado. Relatório acima.' -ForegroundColor Gray; Pausar; exit 0 }

if ($acao -eq '3') {
    Write-Host ''
    Write-Host 'ATENÇÃO: isto APAGA as cópias extras permanentemente.' -ForegroundColor Red
    $conf = Read-Host 'Digite APAGAR para confirmar'
    if ($conf -cne 'APAGAR') { Write-Host 'Cancelado.' -ForegroundColor Yellow; Pausar; exit 0 }
}

$feitos=0;$err=0
$destDup = Join-Path $pasta '_Duplicados'
foreach ($grp in $grupos) {
    for ($j=1; $j -lt $grp.Count; $j++) {
        $f = $grp[$j]
        try {
            if ($acao -eq '2') {
                New-Item -ItemType Directory -Path $destDup -Force | Out-Null
                $base=[System.IO.Path]::GetFileNameWithoutExtension($f.Name); $ext=$f.Extension
                $dest=Join-Path $destDup $f.Name; $n=1
                while (Test-Path -LiteralPath $dest) { $dest=Join-Path $destDup ("$base ($n)$ext"); $n++ }
                Move-Item -LiteralPath $f.FullName -Destination $dest -ErrorAction Stop
            } else {
                Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop
            }
            $feitos++
        } catch { Write-Host "   [ERRO] $($f.Name): $($_.Exception.Message)" -ForegroundColor Red; $err++ }
    }
}
Titulo 'Concluído'
$verbo = if ($acao -eq '2') { 'Movidas' } else { 'Apagadas' }
Write-Host "$verbo`: $feitos cópia(s) extra(s)" -ForegroundColor Green
Write-Host "Erros:   $err" -ForegroundColor $(if ($err -gt 0){'Red'}else{'Gray'})
if ($acao -eq '2') { Write-Host "Movidos para: $destDup" }
Pausar
