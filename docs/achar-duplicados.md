# Achar duplicados

Programa que encontra arquivos iguais pelo conteúdo (não só pelo nome) dentro de uma pasta e subpastas.

## Como abrir

Abra o arquivo `achar-duplicados.cmd` na pasta `Organizar` (duplo clique ou Execute).

## Passo a passo

1. Cole o caminho da pasta a analisar.
2. Aguarde a análise (pastas grandes podem demorar).
3. Se houver duplicados, veja o resumo: grupos de iguais, cópias extras e espaço que dá para recuperar. Até 15 grupos são listados na tela; o primeiro de cada grupo é marcado como manter.
4. Escolha o que fazer:
   - **Só listar** (Enter = padrão) — nada é alterado.
   - **Mover as cópias extras** para a subpasta `_Duplicados`.
   - **Apagar as cópias extras** — pede confirmação digitando `APAGAR`; sempre mantém 1 original.

## Dicas

- Pastas com muitos arquivos iguais de tamanho passam por uma comparação mais profunda — paciência.
- A opção de apagar é permanente; se tiver dúvida, use só listar ou mover.
- Pressione Enter no final para fechar a janela.
