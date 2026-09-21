# Drivers

Salva os drivers que já funcionam na sua máquina, devolve depois de formatar e busca o que estiver faltando. Feito para as cinco máquinas: cada uma cria a própria pasta, e todas cabem no mesmo pendrive.

## Como abrir

Dê um duplo-clique em `Windows\01 - drivers.cmd` — ou abra o `canivete.cmd` na raiz e escolha pelo número.

## O que precisa

Nada. O programa usa o `pnputil` e o `expand` do próprio Windows, e **instala sozinho** o que mais precisar: se o winget não existir na máquina recém-formatada, ele baixa o App Installer oficial da Microsoft e registra; se a ferramenta do fabricante faltar, ele instala pelo winget antes de usar.

## Passo a passo

1. O programa **pede permissão de administrador**. Sem ela não dá para mexer em driver.
2. Ele identifica a máquina: fabricante, modelo e placa-mãe.
3. Pergunta a **pasta dos drivers**, lembrando a última usada. Pode ser um pendrive ou uma pasta de rede.
4. **Faz o backup do dia**, se ainda não existir.
5. Mostra o menu e volta para ele ao terminar cada opção.

## Opções

| # | Opção | Tempo |
|---|-------|-------|
| 1 | Inventário: o que tem e o que falta | Segundos |
| 2 | Fazer um novo backup agora | 1 a 5 minutos |
| 3 | Restaurar drivers de uma pasta | Segundos a minutos |
| 4 | Restaurar só o driver de rede | Segundos |
| 5 | Procurar atualizações no Windows Update | 1 a 3 minutos |
| 6 | Ferramenta do fabricante | Varia |

A opção 6 muda conforme a máquina, e em quase todos os casos **instala em vez de só indicar**:

| Máquina | O que ele faz |
|---|---|
| Dell | Instala o Dell Command \| Update e roda `dcu-cli /scan` e `/applyUpdates` |
| HP | Instala o HP Image Assistant e roda a análise em modo silencioso |
| Lenovo | Instala e abre o Lenovo System Update |
| Montado | Mostra a placa-mãe e abre a busca pelos drivers dela |

Depois disso, seja qual for a máquina: se houver **NVIDIA**, oferece instalar o NVIDIA App, que é quem baixa e mantém o driver; se houver **AMD**, abre a página do Adrenalin, porque a AMD não publica no winget; e se houver **Intel**, oferece o Intel Driver & Support Assistant, que cobre chipset, Wi-Fi e vídeo integrado.

## Onde salva

Na pasta que você escolher, separado por máquina:

```
<sua pasta>\
    DESKTOP-PABLO\
        2026-09-20\          <- os drivers exportados
        inventario.csv       <- todos os dispositivos e versões
        catalog\             <- o que veio do Microsoft Update Catalog
    NOTEBOOK-SALA\
        ...
```

O backup do dia é feito uma vez só: se você abrir o programa de novo no mesmo dia, ele pula essa etapa. Para forçar um novo, use a opção 2 — ela cria uma pasta com a hora no nome e não sobrescreve nada.

## A ordem que funciona

Antes de formatar, rode o programa e deixe o backup terminar. Guarde a pasta num pendrive.

Depois de formatar, com a máquina sem internet:

1. Opção **4**, apontando para o pendrive. A placa de rede volta em segundos e a internet funciona.
2. Opção **3**, para o resto dos drivers.
3. Opção **5**, para pegar o que houver de mais novo.
4. Opção **6**, se a máquina for de marca ou tiver placa de vídeo dedicada.

## Dicas

- **A prévia sempre aparece antes de instalar.** Você vê os drivers agrupados por categoria, com fabricante e versão, e só então confirma.
- **Nada é apagado.** O Windows adiciona o driver ao repositório e escolhe o mais adequado entre o que já existia e o novo.
- **O backup salva o driver, não o aplicativo.** Depois de restaurar, a placa de vídeo funciona, mas o painel da NVIDIA e o console de áudio da Realtek não voltam — esses precisam ser instalados à parte.
- **Placa dedicada merece o pacote oficial.** Para jogos, use o instalador da NVIDIA ou da AMD; a opção 6 abre a página certa.
- **O backup é uma fotografia de hoje**, não uma busca por versão nova. Quem busca novidade é a opção 5.
- Driver exportado de um Windows costuma servir em outro, mas não entre arquiteturas diferentes (32 e 64 bits).
- Se alguns drivers falharem na restauração, o programa refaz um por um e diz o nome de cada um. Falha aqui costuma ser driver de hardware que não existe nessa máquina.
- **Restaurar na mesma máquina não é erro.** O que já estava no repositório aparece como "Já existiam", separado dos instalados.
- Quando algum driver pede reinicialização, o programa avisa no fim.
- **A busca no Microsoft Update Catalog lê a página da Microsoft.** É a única parte do programa que depende do site de terceiro: se a Microsoft mudar o layout, ela para de achar e o programa avisa com o endereço da busca na tela.

---
*Desenvolvido por Pablo Murad - 2026*
