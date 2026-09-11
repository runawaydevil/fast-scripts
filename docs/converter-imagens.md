# Converter Imagens

Programa para redimensionar e/ou converter imagens, uma de cada vez ou várias de uma pasta.

## Como abrir

Abra o arquivo `converter-imagens.cmd` na pasta `Imagens` (duplo clique ou Execute).

Na primeira vez, se faltar algo necessário no computador, o programa avisa e mostra o que instalar. Depois de instalar, feche e abra de novo.

## Passo a passo

1. **Pasta ou imagem**  
   Confirme o caminho sugerido (Enter) ou cole/digite o caminho de uma pasta ou de uma imagem.  
   Se a pasta não existir, o programa pergunta se quer criá-la.

2. **Formato de saída**  
   Escolha o número da opção:
   - manter o formato original (só redimensiona)
   - JPG
   - PNG
   - WebP  

   Enter usa a opção marcada como padrão (a última que você usou, quando houver).

3. **Tamanho**  
   Escolha:
   - pixels do maior lado (ex.: 1920)
   - porcentagem (ex.: 50)
   - não redimensionar (só muda o formato)  

   Depois informe o valor, se for o caso. Enter pode repetir o valor usado da última vez.

4. **Aguarde o processamento**  
   O programa lista cada imagem e mostra se foi convertida, ignorada (já existia no destino) ou se deu erro.

5. **Resultado**  
   Os arquivos ficam na pasta `Convertido`, dentro da pasta de origem (ou ao lado da imagem única). A estrutura de subpastas é preservada.

## Dicas

- Você pode processar uma pasta inteira (incluindo subpastas) ou só um arquivo.
- Formatos comuns de entrada são aceitos (fotos e imagens do dia a dia).
- O programa lembra pasta, formato e tamanho usados nas últimas execuções.
- Pressione Enter no final para fechar a janela.
