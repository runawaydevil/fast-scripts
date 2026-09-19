# Padrões do projeto

Contrato técnico da coleção — leia antes de criar ou alterar qualquer programa.

## 1. Um arquivo, autocontido

Cada programa é **um único `.cmd`**, sem depender de nenhum outro arquivo. Os programas ficam num compartilhamento de rede e podem ser copiados isoladamente, então **não existe biblioteca compartilhada**: o código comum é duplicado de propósito, mas deve ser **idêntico** em todos.

## 2. Cabeçalho polyglot

O arquivo é batch e PowerShell ao mesmo tempo. O batch relança o próprio arquivo no PowerShell:

```
<# :
@echo off
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression ([System.IO.File]::ReadAllText('%~f0',[System.Text.Encoding]::UTF8))"
exit /b %errorlevel%
#>
```

**Variante para quem precisa de administrador** (`verificar-discos`, `limpeza-segura`): expõe o próprio caminho numa variável, porque o script precisa se relançar elevado.

```
<# :
@echo off
set "SELF=%~f0"
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression ([System.IO.File]::ReadAllText($env:SELF,[System.Text.Encoding]::UTF8))"
exit /b %errorlevel%
#>
```

## 3. Codificação — a regra que mais quebra

Os `.cmd` **precisam** ser gravados em **UTF-8 sem BOM** com quebras **CRLF**.

- Com BOM, o batch não reconhece a primeira linha e o duplo-clique falha.
- Com LF, o `cmd.exe` se perde no meio do arquivo.

Depois de qualquer edição, normalize:

```powershell
$t = [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8)
$t = $t -replace "`r`n","`n" -replace "`n","`r`n"
[System.IO.File]::WriteAllText($p, $t, (New-Object System.Text.UTF8Encoding($false)))
```

Os primeiros bytes devem ser `3C 23 20 3A 0D`.

> **Atenção:** para scripts `.ps1` auxiliares vale o **contrário** — o Windows PowerShell 5.1 lê `.ps1` sem BOM como ANSI e destrói os acentos. Esses devem ter BOM.

## 4. Verificação obrigatória

Antes de considerar qualquer arquivo pronto:

```powershell
$e = $null; $tok = $null
[void][System.Management.Automation.Language.Parser]::ParseInput($t, [ref]$tok, [ref]$e)
```

E rodar de verdade, alimentando os prompts por `stdin`, numa pasta de teste.

## 5. Experiência padrão

1. Verificar as dependências primeiro e avisar com o comando `winget` se faltar.
2. Perguntar **pasta ou arquivo** (aceitar os dois).
3. Menus com `>` marcando a opção padrão; Enter aceita o padrão.
4. Perguntar a **pasta de saída**, sugerindo a última usada e **criando-a se não existir**.
5. Lembrar as escolhas em `%APPDATA%\<Nome>\config.json`.
6. Preservar subpastas e **pular o que já foi feito**.
7. Nada destrutivo sem **prévia + confirmação**.
8. Resumo no fim e `Pausar` antes de fechar.
9. Assinatura `Desenvolvido por Pablo Murad - 2026` no comentário do cabeçalho **e** na tela.

## 6. Paralelismo

Programas que processam lotes usam a função `Executar-EmParalelo`, colada dentro de cada `.cmd`.

**Pontos que não podem ser simplificados:**

- Usa `System.Diagnostics.Process`. **Nunca** `Start-Process -ArgumentList` (quebra o quoting) nem `Start-Job` (~125 ms de overhead por item).
- O helper `_Citar` implementa as regras do `CommandLineToArgvW`. A regra crítica é **dobrar as barras finais** — sem isso, uma pasta colada do Explorer terminada em `\` engole a aspa de fechamento.
- Redirecionar **stdout e stderr**. Não redirecionar o stderr trava o ffmpeg quando o buffer do pipe enche.
- Ler `$p.ExitCode` por processo — `$LASTEXITCODE` é global e não sobrevive ao paralelismo. Testar `-ne 0`, nunca `-gt 0` (o ffmpeg devolve `-2`).

**Limites medidos nesta máquina (24 núcleos, RTX 5070 Ti):**

| Tipo | Limite | Ganho medido |
|------|--------|--------------|
| `imagem` | 8 | até **4,2×** |
| `cpu` (x264) | 4 | **1,57×** — com 12 fica *pior* que sequencial |
| `gpu` (NVENC) | 3 | ~10% — o encoder satura sozinho |
| `sonda` (ffprobe) | 12 | elimina N inicializações em série |

## 7. Armadilhas já encontradas

- **`Get-FileHash` não está disponível** quando o `.cmd` roda via `Invoke-Expression`. Use `[System.Security.Cryptography.SHA256]` direto.
- **Variáveis do script não resolvem dentro de funções** nesse contexto: passe o que precisar como **parâmetro**.
- **`catch {}` vazio esconde bugs.** Sempre mostre o motivo do erro.
- **O robocopy é traduzido:** em português imprime `*Arquivo EXTRA`, em inglês `*EXTRA File`. Use uma regex que pegue os dois.
- **`Get-Command` devolve `.Source`; `Get-Item` devolve `.FullName`.** Normalize num caminho só.
- **O `drawtext` do FFmpeg não tem fonte padrão no Windows:** é preciso apontar um `fontfile`, com o `:` da unidade escapado.

---
*Desenvolvido por Pablo Murad - 2026*