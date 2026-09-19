# Limpeza Segura

Libera espaço apagando arquivos temporários e esvaziando a lixeira — sempre mostrando antes quanto dá para recuperar.

## Como abrir

Dê um duplo-clique em `Úteis\limpeza-segura.cmd` — ou abra o `canivete.cmd` na raiz e escolha pelo número.

## O que precisa

- Nenhum programa extra

## Passo a passo

1. O programa **pede permissão de administrador** (sem ela, os temporários do Windows não podem ser lidos nem limpos).
2. Veja a **prévia** com o tamanho de cada local.
3. Confirme se quer limpar.
4. Responda se quer esvaziar a **lixeira** também.

## O que é limpo

- Temporários do usuário (`%TEMP%`)
- Temporários do Windows (`C:\Windows\Temp`)
- Cache de downloads do Windows Update
- Lixeira (opcional, pergunta separada)

## Onde salva

Nada é salvo — só apaga.

## Dicas

- **Nada é apagado sem você confirmar.**
- Arquivos em uso são pulados automaticamente.
- De propósito **não** mexe no Prefetch: apagá-lo não traz ganho e pode deixar os programas abrindo mais devagar.

---
*Desenvolvido por Pablo Murad - 2026*