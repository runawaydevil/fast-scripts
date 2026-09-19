# Verificar Integridade

Gera uma "impressão digital" de cada arquivo de uma pasta e, depois, confere se algo mudou — detectando corrupção silenciosa e cópias que deram errado.

## Como abrir

Dê um duplo-clique em `Úteis\verificar-integridade.cmd` — ou abra o `canivete.cmd` na raiz e escolha pelo número.

## O que precisa

- Nenhum programa extra

## Passo a passo

1. Escolha **[1] Gerar** o registro ou **[2] Conferir**.
2. Informe a **pasta**.
3. Aguarde o cálculo (mostra o progresso).

## O resultado da conferência

| Estado | Significa |
|--------|-----------|
| Intactos | O conteúdo continua igual |
| **ALTERADOS** | O conteúdo mudou — possível corrupção |
| Sumidos | Estavam no registro e não existem mais |
| Novos | Apareceram depois do registro |

## Onde salva

Um arquivo `integridade.sha256` dentro da própria pasta analisada.

## Dicas

- Rode o **[1] Gerar** logo depois de fazer um backup, e o **[2] Conferir** meses depois para saber se algum arquivo apodreceu no disco.
- Combina com o [backup-espelhado](backup-espelhado.md): copie e depois confira se chegou íntegro.
- Nada é alterado nos seus arquivos — só leitura.

---
*Desenvolvido por Pablo Murad - 2026*