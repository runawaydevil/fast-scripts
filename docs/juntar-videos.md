# Juntar Vídeos

Emenda vários vídeos de uma pasta num arquivo só, na ordem alfabética dos nomes.

## Como abrir

Dê um duplo-clique em `Vídeos\juntar-videos.cmd` — ou abra o `canivete.cmd` na raiz e escolha pelo número.

## O que precisa

- **FFmpeg** — `winget install Gyan.FFmpeg`

## Passo a passo

1. Informe a **pasta** com os vídeos.
2. Confira a **ordem** mostrada na tela e confirme.
3. Escolha o **modo** (rápido ou seguro).
4. Dê o **nome** do arquivo final e confirme a pasta de saída.

## Opções

| # | Modo | Quando usar |
|---|------|-------------|
| 1 | Rápido | Vídeos do mesmo tipo/codec — não recodifica, é quase instantâneo |
| 2 | Seguro | Vídeos diferentes entre si — recodifica tudo para um padrão. Sempre funciona |

## Onde salva

Na pasta de saída escolhida (padrão: a própria pasta dos vídeos).

## Dicas

- Para controlar a ordem, renomeie com números na frente: `01-intro.mp4`, `02-meio.mp4`... (o [limpar-nomes](limpar-nomes.md) e o [renomear-em-lote](renomear-em-lote.md) ajudam).
- Se o modo rápido falhar, é sinal de que os vídeos são diferentes entre si: use o modo seguro.

---
*Desenvolvido por Pablo Murad - 2026*