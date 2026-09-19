# Renomear em Lote

Renomeia vários arquivos de uma vez, de quatro formas diferentes — sempre com prévia antes de mexer em qualquer coisa.

## Como abrir

Dê um duplo-clique em `Organizar\renomear-em-lote.cmd` — ou abra o `canivete.cmd` na raiz e escolha pelo número.

## O que precisa

- Nenhum programa extra (o **ImageMagick** é usado, se existir, para ler a data da foto)

## Passo a passo

1. Informe a **pasta**.
2. Escolha o **modo**.
3. Responda o que o modo pedir.
4. **Confira a prévia** e confirme.

## Opções

| # | Modo | Resultado |
|---|------|-----------|
| 1 | Sequência | `Foto_001`, `Foto_002`, ... |
| 2 | Data/hora | `2026-09-19_14-30-05` |
| 3 | Localizar e substituir | Troca um texto no nome |
| 4 | Mover para pastas por data | Cria pastas `2026-09`, `2026-08`... |

## Onde salva

Renomeia na própria pasta. No modo 4, move os arquivos para subpastas por mês.

## Dicas

- Nos modos 2 e 4 ele tenta ler a **data original da foto** (EXIF); se não achar, usa a data do arquivo.
- Nomes repetidos ganham `(1)`, `(2)`... automaticamente — nada é sobrescrito.
- **Sempre mostra a prévia** e pede confirmação antes de renomear.

---
*Desenvolvido por Pablo Murad - 2026*