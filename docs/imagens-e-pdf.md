# Imagens e PDF

Vai nos dois sentidos: junta várias imagens num único PDF, ou transforma cada página de um PDF numa imagem.

## Como abrir

Dê um duplo-clique em `Imagens\imagens-e-pdf.cmd` — ou abra o `canivete.cmd` na raiz e escolha pelo número.

## O que precisa

- **ImageMagick** — `winget install ImageMagick.ImageMagick`
- **Ghostscript** (só para PDF → imagens) — `winget install ArtifexSoftware.GhostScript`

## Passo a passo

1. Escolha **[1] Imagens → PDF** ou **[2] PDF → Imagens**.
2. Informe a pasta (ou o PDF).
3. Para PDF → imagens, escolha PNG ou JPG e a qualidade em DPI.
4. Confirme a **pasta de saída**.


## Onde salva

O PDF vai para a pasta escolhida. As imagens vão para uma subpasta `<nome do pdf>-imagens`.

## Dicas

- As imagens entram no PDF em **ordem alfabética** — numere os nomes se a ordem importa.
- 150 DPI serve para ler na tela; use 300 DPI se for imprimir.

---
*Desenvolvido por Pablo Murad - 2026*