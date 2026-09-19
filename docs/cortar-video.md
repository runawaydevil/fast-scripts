# Cortar Vídeo

Recorta um trecho do vídeo informando início e fim. No modo rápido é praticamente instantâneo, porque não recodifica nada.

## Como abrir

Dê um duplo-clique em `Vídeos\cortar-video.cmd` — ou abra o `canivete.cmd` na raiz e escolha pelo número.

## O que precisa

- **FFmpeg** — `winget install Gyan.FFmpeg`

## Passo a passo

1. Informe o **vídeo** (ou uma pasta, e escolha pelo número).
2. Informe o **início** e o **fim** — aceita `90`, `01:30` ou `00:01:30`.
3. Escolha o **modo** do corte.
4. Confirme a **pasta de saída**.

## Opções

| # | Modo | Como funciona |
|---|------|---------------|
| 1 | Rápido | Não recodifica — **instantâneo**. Corta no quadro-chave mais próximo (pode variar alguns décimos) |
| 2 | Exato | Recodifica para cortar no ponto exato. Demora mais |

## Onde salva

Na pasta de saída escolhida (padrão: subpasta `Cortado`). O arquivo sai como `<nome>-corte`.

## Dicas

- Use o **rápido** em 99% dos casos: um vídeo de 1 hora é cortado em menos de um segundo.
- Só use o **exato** se precisar do frame exato (ex.: sincronizar com áudio).
- Deixe o fim em branco para cortar até o final do vídeo.

---
*Desenvolvido por Pablo Murad - 2026*