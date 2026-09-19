# Achar Duplicados

Encontra arquivos com o **conteúdo** idêntico (mesmo com nomes diferentes) e mostra quanto espaço dá para recuperar.

## Como abrir

Dê um duplo-clique em `Organizar\achar-duplicados.cmd` — ou abra o `canivete.cmd` na raiz e escolha pelo número.

## O que precisa

- Nenhum programa extra

## Passo a passo

1. Informe a **pasta** (ele olha também as subpastas).
2. Aguarde a comparação.
3. Veja os grupos de iguais.
4. Escolha o que fazer com as cópias extras.

## Opções

| # | Ação | O que faz |
|---|------|-----------|
| 1 | Só listar | Não altera nada — é o padrão |
| 2 | Mover | Move as cópias extras para a subpasta `_Duplicados` |
| 3 | Apagar | Apaga as cópias extras (exige digitar `APAGAR`) |

## Onde salva

A opção 2 cria a subpasta `_Duplicados` dentro da pasta analisada.

## Dicas

- **Sempre mantém uma cópia** de cada arquivo — o primeiro em ordem alfabética, marcado como `[manter]`.
- É rápido porque compara em três etapas: primeiro o tamanho, depois só as pontas do arquivo, e só então o conteúdo inteiro.
- Na dúvida, use a opção 2 (mover): dá para conferir antes de apagar de vez.

---
*Desenvolvido por Pablo Murad - 2026*