# Baixar Vídeos

Baixa vídeos ou só o áudio de YouTube, Instagram, TikTok, X, Vimeo, Facebook e mais de mil outros sites.

## Como abrir

Dê um duplo-clique em `Vídeos\baixar-videos.cmd` — ou abra o `canivete.cmd` na raiz e escolha pelo número.

## O que precisa

- **yt-dlp** — *o programa baixa sozinho se não existir* (versão oficial mais recente)
- **FFmpeg** — para juntar vídeo+áudio em alta qualidade e converter áudio

## Passo a passo

1. Cole o **link** (pode colar vários separados por espaço).
2. Escolha a **qualidade/formato** (1 a 7).
3. Diga se quer a **playlist inteira** ou só o vídeo.
4. Confirme a **pasta de saída**.

## Opções

| # | Formato |
|---|---------|
| 1 | Melhor qualidade disponível |
| 2 | 1080p |
| 3 | 720p |
| 4 | 480p |
| 5 | 360p (compacto) |
| 6 | Só áudio — MP3 |
| 7 | Só áudio — M4A |

## Onde salva

Na pasta que você escolher (padrão: `Downloads\Baixados`). O nome do arquivo vem do título do vídeo.

## Dicas

- Já baixados são **pulados** automaticamente.
- Embute capa e informações (título, autor) no arquivo.
- A cópia do yt-dlp que o programa baixa **se atualiza sozinha** a cada 15 dias.
- Se o yt-dlp da máquina estiver com mais de 60 dias, o programa **avisa e oferece atualizar** logo ao abrir.

## Problemas comuns

**Falhou no YouTube?** Atualize o yt-dlp — é a causa mais comum. O YouTube muda com frequência e derruba versões antigas. O programa oferece a atualização ao abrir.

**aria2c:** se estiver instalado, é usado para acelerar o download nos outros sites, mas **não no YouTube** — lá o site bloqueia baixadores de múltiplas conexões (o "experimento SABR"), e o download falha com erro de rede. Se mesmo assim algo falhar com o aria2c, o programa **refaz sozinho no modo normal**.

**Aviso "No supported JavaScript runtime":** o YouTube passou a exigir JavaScript para entregar todos os formatos. Instale o Deno para destravar os formatos que faltam:

```
winget install DenoLand.Deno
```

---
*Desenvolvido por Pablo Murad - 2026*