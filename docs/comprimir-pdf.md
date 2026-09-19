# Comprimir PDF

Diminui o tamanho de arquivos PDF, mostrando quanto cada um encolheu.

## Como abrir

Dê um duplo-clique em `Imagens\comprimir-pdf.cmd` — ou abra o `canivete.cmd` na raiz e escolha pelo número.

## O que precisa

- **Ghostscript** — `winget install ArtifexSoftware.GhostScript`
  *(o programa acha o Ghostscript mesmo que ele não esteja no PATH)*

## Passo a passo

1. Informe a **pasta ou um PDF**.
2. Escolha o **nível de compressão**.
3. Confirme a **pasta de saída**.

## Opções

| # | Nível | Resolução das imagens |
|---|-------|-----------------------|
| 1 | Tela | 72 dpi — menor arquivo |
| 2 | E-book | 150 dpi — equilibrado |
| 3 | Impressão | 300 dpi |
| 4 | Gráfica | máxima qualidade |

## Onde salva

Na pasta de saída escolhida (padrão: subpasta `Comprimido`).

## Dicas

- No fim aparece uma tabela **antes → depois** com a porcentagem de redução de cada arquivo.
- PDFs cheios de imagens encolhem muito; PDFs só de texto quase não mudam.

---
*Desenvolvido por Pablo Murad - 2026*