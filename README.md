# fast-scripts

Programas rápidos para Windows, em lote e com interface no terminal.
**26 programas** que você abre com um duplo-clique — sem instalar nada, sem linha de comando.

![PowerShell](https://img.shields.io/badge/PowerShell-5391FE?style=flat&logo=powershell&logoColor=white)
![Batch](https://img.shields.io/badge/Batch-.cmd-4D4D4D?style=flat)
![Windows](https://img.shields.io/badge/Windows-0078D6?style=flat&logo=windows&logoColor=white)

## Começando

Abra o **`canivete.cmd`** na raiz: ele lista todos os programas e abre o que você escolher.
Ou vá direto na pasta e dê um duplo-clique no programa que quiser.

Todos seguem a mesma lógica: perguntam a **pasta ou o arquivo**, as **opções**, e a **pasta de saída** — lembrando suas escolhas da próxima vez e criando a pasta se ela não existir. Nada destrutivo acontece sem prévia e confirmação.

## Os programas

### 🎬 Vídeos

| Programa | O que faz |
|---|---|
| [transcodificar](docs/transcodificar.md) | Converte vídeos em lote, com GPU e 5 níveis de qualidade |
| [baixar-videos](docs/baixar-videos.md) | Baixa vídeos e áudio de mais de mil sites (yt-dlp) |
| [extrair-audio](docs/extrair-audio.md) | Tira o áudio de vídeos (MP3/M4A/WAV) |
| [cortar-video](docs/cortar-video.md) | Corta um trecho do vídeo — instantâneo |
| [juntar-videos](docs/juntar-videos.md) | Junta vários vídeos num só |
| [criar-gif](docs/criar-gif.md) | Vídeo vira GIF, ou fotos viram slideshow |
| [marca-dagua-video](docs/marca-dagua-video.md) | Marca d'água de texto ou logo em vídeos |
| [normalizar-audio](docs/normalizar-audio.md) | Padroniza o volume (EBU R128) |
| [info-midia](docs/info-midia.md) | Relatório de codec, resolução e bitrate + planilha |

### 🖼️ Imagens

| Programa | O que faz |
|---|---|
| [converter-imagens](docs/converter-imagens.md) | Redimensiona e converte imagens em lote |
| [marca-dagua](docs/marca-dagua.md) | Marca d'água de texto ou logo em fotos |
| [imagens-e-pdf](docs/imagens-e-pdf.md) | Junta imagens num PDF ou explode PDF em imagens |
| [comprimir-pdf](docs/comprimir-pdf.md) | Reduz o tamanho de PDFs |

### 🗂️ Organizar

| Programa | O que faz |
|---|---|
| [renomear-em-lote](docs/renomear-em-lote.md) | Renomeia por sequência, data ou localizar/substituir |
| [achar-duplicados](docs/achar-duplicados.md) | Acha arquivos iguais por conteúdo e libera espaço |
| [organizar-por-tipo](docs/organizar-por-tipo.md) | Separa a bagunça em subpastas por categoria |
| [compactar-zip](docs/compactar-zip.md) | Compacta e extrai arquivos |
| [limpar-metadados](docs/limpar-metadados.md) | Remove EXIF e GPS de fotos e vídeos |
| [limpar-nomes](docs/limpar-nomes.md) | Deixa os nomes de arquivo seguros para web |

### 🧹 Úteis

| Programa | O que faz |
|---|---|
| [backup-espelhado](docs/backup-espelhado.md) | Backup incremental e rápido com robocopy |
| [verificar-discos](docs/verificar-discos.md) | Saúde dos HDs e SSDs (SMART) |
| [verificar-integridade](docs/verificar-integridade.md) | Detecta arquivos corrompidos silenciosamente |
| [analisar-espaco](docs/analisar-espaco.md) | Descobre o que está enchendo o disco |
| [limpeza-segura](docs/limpeza-segura.md) | Limpa temporários e lixeira, com prévia |
| [relatorio-sistema](docs/relatorio-sistema.md) | Specs do PC, memória, discos e espaço |

### 🔪 Raiz

| Programa | O que faz |
|---|---|
| [canivete](docs/canivete.md) | Menu central que abre todos os outros |

## Instalação

Não tem instalação: é só copiar a pasta. O que alguns programas precisam:

```
winget install Gyan.FFmpeg                    # vídeo e áudio
winget install ImageMagick.ImageMagick        # imagens
winget install ArtifexSoftware.GhostScript    # PDF
winget install 7zip.7zip                      # opcional: .rar e .7z
winget install smartmontools                  # opcional: SMART avançado
```

O **yt-dlp se instala sozinho** quando necessário. Cada programa avisa na tela se faltar algo — veja a lista completa em **[docs/DEPENDENCIAS.md](docs/DEPENDENCIAS.md)**.

## Velocidade

Os programas que trabalham em lote processam **vários arquivos ao mesmo tempo**, ajustando o número de processos ao tipo de trabalho. Em imagens o ganho medido chega a **4,2×**. O `transcodificar` e o `marca-dagua-video` usam a **placa NVIDIA** quando ela existe, e o `extrair-audio` **copia o áudio sem recodificar** quando o formato já é o certo — nesse caso é quase instantâneo.

## Para quem for mexer no código

As regras técnicas da coleção (cabeçalho polyglot, codificação, paralelismo e as armadilhas já mapeadas) estão em **[docs/PADROES.md](docs/PADROES.md)**.

---

**Pablo Murad** — pablomurad[at]pm[dot]me
*Desenvolvido por Pablo Murad - 2026*