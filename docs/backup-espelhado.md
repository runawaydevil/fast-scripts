# Backup Espelhado

Copia uma pasta para outro lugar (HD externo, rede) de forma incremental — só o que mudou — usando o robocopy com vários núcleos.

## Como abrir

Dê um duplo-clique em `Úteis\backup-espelhado.cmd` — ou abra o `canivete.cmd` na raiz e escolha pelo número.

## O que precisa

- Nenhum programa extra (o robocopy já vem no Windows)

## Passo a passo

1. Informe a **pasta de origem**.
2. Informe a **pasta de destino** (é criada se não existir).
3. Escolha o **modo**.
4. Veja a **prévia** (simulação — nada é copiado ainda).
5. Confirme.

## Opções

| # | Modo | Cuidado |
|---|------|---------|
| 1 | Cópia | Só adiciona e atualiza. **Nunca apaga nada** no destino |
| 2 | Espelho | Deixa o destino idêntico à origem — **apaga no destino** o que não existe mais na origem |

## Onde salva

Na pasta de destino. O log fica em `%LOCALAPPDATA%\fast-scripts\logs-backup`.

## Dicas

- A **prévia é uma simulação real**: mostra quantos arquivos seriam copiados e, no modo espelho, exatamente quais seriam apagados.
- O modo espelho exige digitar **`ESPELHAR`** para confirmar — não dá para apagar sem querer.
- O log fica **fora do destino** de propósito: senão o próprio espelho apagaria os logs antigos.
- É incremental: a segunda execução copia só o que mudou, e é muito mais rápida.

---
*Desenvolvido por Pablo Murad - 2026*