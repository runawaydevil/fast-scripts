# Extrair Áudio

Tira a trilha de áudio de vídeos e salva como MP3, M4A ou WAV.

## Como abrir

Dê um duplo-clique em `Vídeos\extrair-audio.cmd` — ou abra o `canivete.cmd` na raiz e escolha pelo número.

## O que precisa

- **FFmpeg** — `winget install Gyan.FFmpeg`

## Passo a passo

1. Informe a **pasta ou um vídeo**.
2. Escolha o **formato** do áudio.
3. Confirme a **pasta de saída**.

## Opções

| # | Formato | Observação |
|---|---------|------------|
| 1 | MP3 (192 kbps) | Compatível com tudo |
| 2 | M4A / AAC (192 kbps) | Melhor qualidade no mesmo tamanho |
| 3 | WAV | Sem compressão, arquivo grande |

## Onde salva

Na pasta de saída escolhida (padrão: subpasta `Áudio`), preservando as subpastas.

## Dicas

- **Muito rápido quando dá para copiar:** se o áudio do vídeo já for do formato pedido (por exemplo M4A de um MP4), ele **copia sem recodificar** — é quase instantâneo. O programa avisa na tela quantos entraram nesse caso.
- Processa vários vídeos ao mesmo tempo.

---
*Desenvolvido por Pablo Murad - 2026*