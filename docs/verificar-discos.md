# Verificar Discos

Mostra a saúde dos seus HDs e SSDs — temperatura, desgaste, erros — e pode fazer um teste completo de leitura procurando setores defeituosos.

## Como abrir

Dê um duplo-clique em `Úteis\verificar-discos.cmd` — ou abra o `canivete.cmd` na raiz e escolha pelo número.

## O que precisa

- Nenhum programa extra (usa o próprio Windows)
- *(opcional)* **smartmontools** — `winget install smartmontools` — para os detalhes SMART avançados

## Passo a passo

1. O programa **pede permissão de administrador** (necessária para ler os sensores).
2. Escolha uma opção do menu.
3. Ele volta ao menu ao terminar.

## Opções

| # | Opção | Tempo |
|---|-------|-------|
| 1 | Diagnóstico de saúde | Segundos |
| 2 | Teste de superfície | **Horas** — lê o disco inteiro |
| 3 | Resumo simples | Instantâneo |

## Onde salva

Nada é salvo — é só leitura.

## Dicas

- **Nada é alterado no disco**: mesmo o teste de superfície apenas *lê*.
- HDs externos por USB às vezes não expõem os dados SMART — é limitação da gaveta, não do programa.
- O teste de superfície pode ser cancelado a qualquer momento com Ctrl+C.

---
*Desenvolvido por Pablo Murad - 2026*