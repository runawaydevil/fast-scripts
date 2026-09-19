# Normalizar Áudio

Deixa todos os arquivos com o mesmo volume percebido, usando o padrão EBU R128 — acaba com aquele vídeo baixo demais e o seguinte estourando.

## Como abrir

Dê um duplo-clique em `Vídeos\normalizar-audio.cmd` — ou abra o `canivete.cmd` na raiz e escolha pelo número.

## O que precisa

- **FFmpeg** — `winget install Gyan.FFmpeg`

## Passo a passo

1. Informe a **pasta ou um arquivo** (vídeo ou áudio).
2. Escolha o **volume alvo**.
3. Confirme a **pasta de saída**.

## Opções

| # | Alvo | Para que serve |
|---|------|----------------|
| 1 | -14 LUFS | Streaming / YouTube |
| 2 | -16 LUFS | Podcast / voz |
| 3 | -23 LUFS | TV / broadcast |

## Onde salva

Na pasta de saída escolhida (padrão: subpasta `Normalizado`).

## Dicas

- Em vídeos, a **imagem é copiada sem recodificar** — só o áudio é tratado.
- Processa vários ao mesmo tempo.

---
*Desenvolvido por Pablo Murad - 2026*