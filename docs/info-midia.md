# Info de Mídia

Mostra uma tabela com codec, resolução, duração, bitrate e tamanho de todos os vídeos e áudios de uma pasta — e salva tudo numa planilha.

## Como abrir

Dê um duplo-clique em `Vídeos\info-midia.cmd` — ou abra o `canivete.cmd` na raiz e escolha pelo número.

## O que precisa

- **FFmpeg / FFprobe** — `winget install Gyan.FFmpeg`

## Passo a passo

1. Informe a **pasta ou um arquivo**.
2. Ele lê tudo em paralelo e mostra a tabela.
3. Confirme a **pasta de saída** para salvar a planilha.


## Onde salva

Um arquivo `info-midia_<data>.csv` na pasta de saída escolhida (separado por `;`, abre direto no Excel).

## Dicas

- Ótimo para descobrir **por que um vídeo está pesado** antes de transcodificar.
- Também serve para conferir se um lote saiu na resolução certa.

---
*Desenvolvido por Pablo Murad - 2026*