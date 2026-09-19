# Criar GIF / Slideshow

Dois usos: transformar um vídeo em GIF, ou transformar uma pasta de fotos num vídeo de slideshow.

## Como abrir

Dê um duplo-clique em `Vídeos\criar-gif.cmd` — ou abra o `canivete.cmd` na raiz e escolha pelo número.

## O que precisa

- **FFmpeg** — `winget install Gyan.FFmpeg`

## Passo a passo

1. Escolha **[1] Vídeo → GIF** ou **[2] Fotos → vídeo**.
2. **GIF:** informe pasta/vídeo, a largura (padrão 480 px) e os quadros por segundo (padrão 12).
3. **Slideshow:** informe a pasta das fotos, quantos segundos cada foto aparece e o nome do vídeo.
4. Confirme a **pasta de saída**.


## Onde salva

Na pasta de saída escolhida (padrão: subpasta `GIF` para os GIFs; a própria pasta das fotos para o slideshow).

## Dicas

- O GIF usa paleta otimizada (duas passagens), o que deixa a imagem bem melhor que um GIF comum.
- GIF é pesado por natureza: largura 480 e 12 fps já dão um bom equilíbrio.
- No slideshow, fotos em pé e deitadas são ajustadas para 1280×720 com bordas.

---
*Desenvolvido por Pablo Murad - 2026*