# Converter Imagens

Redimensiona e converte imagens em lote, sempre mantendo a proporção.

## Como abrir

Dê um duplo-clique em `Imagens\converter-imagens.cmd` — ou abra o `canivete.cmd` na raiz e escolha pelo número.

## O que precisa

- **ImageMagick** — `winget install ImageMagick.ImageMagick`

## Passo a passo

1. Informe a **pasta ou uma imagem**.
2. Escolha o **formato de saída**.
3. Escolha como informar o **tamanho**.
4. Confirme a **pasta de saída**.

## Opções

**Formato:** manter o original · JPG · PNG · WebP

**Tamanho**

| # | Modo | Exemplo |
|---|------|---------|
| 1 | Pixels do maior lado | `1920` — a imagem cabe em 1920×1920 |
| 2 | Porcentagem | `50` — metade do tamanho |
| 3 | Não redimensionar | Só converte o formato |

## Onde salva

Na pasta de saída escolhida (padrão: subpasta `Convertido`), preservando as subpastas.

## Dicas

- **Nunca amplia** a imagem — só reduz.
- Converter PNG com transparência para JPG achata sobre fundo branco automaticamente.
- É o programa que mais ganha com o processamento paralelo: lotes grandes ficam **várias vezes mais rápidos**.

---
*Desenvolvido por Pablo Murad - 2026*