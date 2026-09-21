# Debloat

Tira o excesso do Windows — apps que você nunca abriu, telemetria, Copilot, Recall, anúncios no Iniciar — mostrando tudo antes e guardando como desfazer.

## Antes de tudo: o que esperar

O ganho de velocidade é pequeno, e vale dizer isso de frente. Os testes publicados mostram de 200 a 800 MB de RAM livre em repouso e de 1 a 3 segundos no boot com SSD. Numa máquina com 32 GB ou mais, isso é ruído.

O que o debloat entrega de verdade é outra coisa: menos irritação, menos telemetria, e cinco máquinas configuradas igual. Se a sua expectativa é ganhar FPS, não é aqui.

## Como abrir

Dê um duplo-clique em `Windows\02 - debloat.cmd` — ou abra o `canivete.cmd` na raiz e escolha pelo número.

## O que precisa

Nada. Usa só o próprio Windows.

## Passo a passo

1. O programa **pede permissão de administrador**.
2. Ele olha a máquina e ajusta as recomendações ao que encontrou.
3. Pergunta onde salvar os relatórios, lembrando a última pasta.
4. Mostra o menu. Toda opção tem prévia e confirmação.

## Ele se adapta à máquina

O programa não aplica a mesma lista em tudo:

| Encontrou | Muda o quê |
|---|---|
| Steam, Epic, GOG, Battle.net ou placa dedicada | Xbox e Game Bar saem do automático |
| Everything (voidtools) | Passa a oferecer aliviar a indexação do Windows |
| Office instalado | Não mexe em Teams nem OneNote |
| 32 GB de RAM ou mais | Avisa que mexer em serviço quase não muda nada |

## Opções

| # | Opção | Altera algo? |
|---|-------|---|
| 1 | Diagnóstico: o que dá para limpar | Não, só leitura |
| 2 | Fazer tudo o que é recomendado | Sim, com prévia |
| 3 | Apps da Microsoft | Sim, com prévia |
| 4 | Privacidade e telemetria | Sim, com prévia |
| 5 | Copilot, Recall e IA | Sim, com prévia |
| 6 | Anúncios, sugestões e irritações | Sim, com prévia |
| 7 | Serviços em segundo plano | Sim, com prévia |
| 8 | Tarefas agendadas de telemetria | Sim, com prévia |
| 9 | Desfazer o que este programa fez | Reverte |

## Os três níveis de app

Os 72 apps que o programa conhece são separados por risco, e só o primeiro nível entra no automático:

- **Seguro** — Bing, Clipchamp, Solitaire, Teams pessoal, Copilot, widgets, 3D Builder e companhia.
- **Opcional** — Paint, Bloco de Notas, Fotos, Calculadora, Ferramenta de Captura, Câmera, novo Outlook. Muita gente usa; você escolhe um a um.
- **Nunca** — Store, Terminal, Edge, Obter Ajuda, e três componentes do Xbox. A Store não reinstala nada depois de removida, e as legendas do Xbox não voltam de jeito nenhum.

## Serviços viram Manual, não Desativado

Assim o serviço para de subir no boot, mas ainda liga se algo precisar dele. Ficam de fora de propósito, em qualquer nível: `BITS` (quebra o Windows Update), `Spooler` (quebra impressão), `WerSvc`, e tudo de rede, áudio e Defender.

## Onde salva

```
<sua pasta>\
    DESKTOP-PABLO\
        relatorio-2026-09-20.txt
        desfazer.json            <- cópia
```

O diário do desfazer vive em `%APPDATA%\Debloat\desfazer.json`, para funcionar mesmo sem o pendrive por perto. Ele guarda o valor anterior de cada chave, serviço e tarefa alterados.

## Dicas

- **Antes da primeira alteração de cada execução, o programa cria um ponto de restauração.** O Windows só permite um a cada 24 horas; se já existir um de hoje, ele avisa e segue.
- **O que o desfazer devolve:** chaves de registro, serviços e tarefas. Chave que não existia antes é apagada, chave que existia volta ao valor original.
- **O que o desfazer NÃO devolve: apps.** Não existe forma honesta de reinstalar um Appx removido sem a Store. O programa lista o que removeu e abre a Store para você.
- **O Windows Update traz coisa de volta.** Pacotes provisionados voltam em atualizações de recurso. Por isso o programa foi feito para rodar de novo: o diagnóstico compara com o diário e avisa quais apps reapareceram.
- **Rodar duas vezes não faz mal.** Tudo que já está do jeito certo aparece marcado como `[ok]` e é pulado.
- Algumas mudanças na barra de tarefas e no Iniciar só aparecem depois de reiniciar o Explorer ou o PC.
- Para limpar arquivos temporários e a lixeira, use o **[limpeza-segura](limpeza-segura.md)** — este programa não duplica aquilo.

---
*Desenvolvido por Pablo Murad - 2026*
