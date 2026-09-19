# Dependências

A maioria dos programas **não precisa de nada**. Os que precisam avisam na tela e mostram o comando de instalação.

## Tabela

| Ferramenta | Para que serve | Como instalar | Usada por |
|---|---|---|---|
| **FFmpeg** | Tudo de vídeo e áudio | `winget install Gyan.FFmpeg` | transcodificar, extrair-audio, criar-gif, cortar-video, juntar-videos, marca-dagua-video, info-midia, normalizar-audio, baixar-videos, limpar-metadados |
| **ImageMagick** | Tudo de imagem | `winget install ImageMagick.ImageMagick` | converter-imagens, marca-dagua, imagens-e-pdf, limpar-metadados, renomear-em-lote (data da foto) |
| **Ghostscript** | Ler e comprimir PDF | `winget install ArtifexSoftware.GhostScript` | comprimir-pdf, imagens-e-pdf (PDF → imagens) |
| **yt-dlp** | Baixar de sites | *baixado automaticamente* | baixar-videos |
| **7-Zip** *(opcional)* | `.rar`, `.7z` e mais velocidade | `winget install 7zip.7zip` | compactar-zip |
| **smartmontools** *(opcional)* | Detalhes SMART avançados | `winget install smartmontools` | verificar-discos |

## Observações

- **O yt-dlp se instala sozinho.** Se não existir na máquina, o `baixar-videos` baixa a versão oficial mais recente em `%LOCALAPPDATA%\fast-scripts` e ainda a mantém atualizada.
- **O Ghostscript costuma não ficar no PATH.** Os programas procuram também em `C:\Program Files\gs`, então funciona mesmo assim.
- **Placa NVIDIA** não é uma dependência, mas é aproveitada automaticamente quando existe (transcodificar e marca-dagua-video).
- Programas que **não precisam de nada**: organizar-por-tipo, achar-duplicados, limpar-nomes, backup-espelhado, analisar-espaco, verificar-integridade, relatorio-sistema, limpeza-segura, verificar-discos, canivete.

---
*Desenvolvido por Pablo Murad - 2026*