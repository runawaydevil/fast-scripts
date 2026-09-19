# Marca d'água em Vídeo

Coloca um texto ou um logo por cima dos vídeos, em lote.

## Como abrir

Dê um duplo-clique em `Vídeos\marca-dagua-video.cmd` — ou abra o `canivete.cmd` na raiz e escolha pelo número.

## O que precisa

- **FFmpeg** — `winget install Gyan.FFmpeg`
- *(opcional)* placa **NVIDIA** — é usada automaticamente se existir

## Passo a passo

1. Informe a **pasta ou um vídeo**.
2. Escolha **texto** ou **logo** (PNG).
3. Escolha a **posição** (5 opções).
4. Confirme a **pasta de saída**.

## Opções

| # | Posição |
|---|---------|
| 1 | Inferior direita |
| 2 | Inferior esquerda |
| 3 | Superior direita |
| 4 | Superior esquerda |
| 5 | Centro |

## Onde salva

Na pasta de saída escolhida (padrão: subpasta `ComMarca`). Sai sempre em MP4.

## Dicas

- O **áudio é copiado sem recodificar**, então não perde qualidade nem tempo.
- Use um PNG com fundo transparente para o logo ficar bonito.
- O tamanho do logo é em % da largura do vídeo (padrão 20%), então fica proporcional em qualquer resolução.

---
*Desenvolvido por Pablo Murad - 2026*