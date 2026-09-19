# Compactar / Extrair

Compacta uma pasta num ZIP, ou extrai vários arquivos compactados de uma vez.

## Como abrir

Dê um duplo-clique em `Organizar\compactar-zip.cmd` — ou abra o `canivete.cmd` na raiz e escolha pelo número.

## O que precisa

- Nenhum programa extra (usa o compactador do Windows)
- *(opcional)* **7-Zip** — `winget install 7zip.7zip` — mais rápido e abre `.rar` e `.7z`

## Passo a passo

1. Escolha **[1] Compactar** ou **[2] Extrair**.
2. Informe a pasta (ou os arquivos compactados).
3. Dê o nome do arquivo e confirme a **pasta de saída**.


## Onde salva

Na pasta de saída escolhida. Ao extrair, cada arquivo vai para uma subpasta com o nome dele.

## Dicas

- Sem o 7-Zip, só funciona com `.zip`. Com ele, abre também `.rar`, `.7z` e `.tar`.
- O 7-Zip usa todos os núcleos do processador, então é bem mais rápido em pastas grandes.

---
*Desenvolvido por Pablo Murad - 2026*