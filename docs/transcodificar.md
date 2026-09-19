# Transcodificar Vídeos

Converte vídeos em lote para MP4, escolhendo a qualidade e quem faz o trabalho pesado (placa de vídeo ou processador).

## Como abrir

Dê um duplo-clique em `Vídeos\transcodificar.cmd` — ou abra o `canivete.cmd` na raiz e escolha pelo número.

## O que precisa

- **FFmpeg** — `winget install Gyan.FFmpeg`
- *(opcional)* placa **NVIDIA** para o modo GPU

## Passo a passo

1. Informe a **pasta ou um vídeo** (ele lembra o último caminho).
2. Escolha a **qualidade** (1 a 5).
3. Escolha o **motor** de codificação (velocidade × tamanho).
4. Confirme a **pasta de saída** (é criada se não existir).
5. Ele converte vários ao mesmo tempo, com barra de progresso.

## Opções

**Qualidade**

| # | Perfil | Resolução | CRF |
|---|--------|-----------|-----|
| 1 | Máxima | original | 18 |
| 2 | Alta | 1080p | 20 |
| 3 | Média | 720p | 23 |
| 4 | Baixa | 480p | 26 |
| 5 | Mínima (compacta) | ~320p | 30 |

**Motor**

| # | Motor | Quando usar |
|---|-------|-------------|
| 1 | GPU NVENC | Qualidades altas e vídeos longos — bem mais rápido |
| 2 | CPU rápido (veryfast) | Melhor para a qualidade mínima e lotes |
| 3 | CPU qualidade (medium) | Arquivo menor no mesmo nível |

## Onde salva

Na pasta de saída que você escolher (padrão: subpasta `Transcodificado` dentro da origem). A estrutura de subpastas é preservada.

## Dicas

- Nunca amplia o vídeo: se a origem for menor que o perfil, mantém o tamanho.
- Arquivos já convertidos são **pulados** — dá para rodar de novo sem medo.
- Para a qualidade mínima, o **CPU rápido** costuma bater a GPU (o vídeo é pequeno demais para compensar ligar a placa).

---
*Desenvolvido por Pablo Murad - 2026*