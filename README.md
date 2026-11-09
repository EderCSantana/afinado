# Afinado

Jogo para tocar ou cantar junto com uma música: você abre a música, escolhe
o instrumento (ou a voz) e o que vai tocar; as próximas notas e acordes vêm
rolando na tela e o microfone confere se cada nota está **certa** e
**afinada**.

Feito em Flutter (Windows, macOS, Linux e Android).

## Como funciona

O app tem três abas:

- **Músicas** — sua biblioteca. Vem com exercícios e músicas de domínio
  público (escala, notas longas, Brilha brilha, Ode à Alegria, Frei
  Martinho e progressões de acordes) e você adiciona as suas:
  - **MIDI** (`.mid`): cada faixa vira uma parte com as notas exatas.
  - **Áudio** (`.mp3`, `.wav`, `.ogg`, `.flac`): com o **analisador de
    instrumentos** instalado, a música é separada em voz, baixo, guitarra,
    piano e outros (**Demucs**) e as notas de cada um são lidas
    (**Basic Pitch**). Cada instrumento vira uma parte (Voz, Baixo,
    Guitarra / violão, Piano…) e os acordes da música saem das notas da
    harmonia. Sem o analisador, o app só estima uma melodia e os acordes da
    mixagem inteira.

  Escolha o instrumento (a parte vai para a oitava dele; sax, trompete e
  clarinete leem as notas escritas; na voz vale qualquer oitava) e a parte.
- **Praticar** — o centro do app. A música aparece numa **pauta**, nota por
  nota, e **espera você**: só avança quando a nota (ou o acorde) certa é
  sustentada por um instante. Sem relógio e sem "errou": se a nota estiver
  errada ele diz qual ouviu e quantos semitons subir ou descer; se estiver
  certa mostra quantos cents está alta ou baixa.
  - **Ouvir** (espaço) toca a nota ou arpeja o acorde.
  - Toque numa nota da pauta para começar dali; ← → para andar.
  - **Repetir um trecho** em loop.
  - **Nomes das notas** liga/desliga os nomes, para treinar leitura.
  - **Afinação rigorosa**: só avança com a nota a menos de 25 cents.
  - No fim: tempo, afinação média (se tende a ficar alto ou baixo) e os
    trechos mais difíceis, com a opção de treinar só o mais difícil.
- **Afinador** — nota e oitava, frequência, cents com ponteiro, estabilidade
  (gráfico do último segundo), acorde reconhecido e barras com quanto de
  cada nota está soando.

Também há o modo **Tocar junto (no tempo)**, em que as notas correm com a
música e cada uma recebe uma nota (*Perfeito*, *Bom*, *Desafinado*, *Errou*).

## Rodar

```bash
flutter pub get
flutter run -d windows
```

### Analisador de instrumentos (Demucs + Basic Pitch)

Roda em Python, num ambiente próprio em `%LOCALAPPDATA%\afinado\analyzer`
(~1,5 GB). Para instalar:

```powershell
powershell -ExecutionPolicy Bypass -File tools\analyzer\setup.ps1
```

O app chama `tools/analyzer/analyze.py` (também empacotado com o app) e
guarda o resultado em `%LOCALAPPDATA%\afinado\analysis`, então cada música
só é analisada uma vez. Numa CPU sem placa de vídeo, uma música de 3–4
minutos leva uns 5–8 minutos (separação ~4 min, leitura das notas ~1 min
por instrumento). As variáveis `AFINADO_PYTHON` e `AFINADO_ANALYZER` mudam
os caminhos.

O que esperar: voz e baixo saem bem; guitarra e piano razoáveis (muitas
notas, melhor praticar os **Acordes**); instrumentos com menos de 1% da
energia da música são ignorados. Nenhuma transcrição automática é perfeita.

Testes:

```bash
flutter test                                  # núcleo musical (sem áudio real)
flutter test integration_test/audio_test.dart -d windows \
  --dart-define=AUDIO=caminho/para/teste.wav  # decodificação, microfone e jogo
flutter test integration_test/stems_test.dart -d windows \
  --dart-define=SONG=caminho/para/musica.mp3  # separação e transcrição reais
```

O teste de áudio espera um arquivo com Dó Ré Mi Fá Sol (0,6 s cada) e
depois os acordes C, Am e G (2 s cada).

## Estrutura

```
lib/
  music/
    pitch.dart           # MIDI ↔ Hz, cents, nomes das notas
    yin.dart             # Detector de altura YIN (uma voz/linha)
    chords.dart          # Espectro, cromagrama, acordes e afinação
    midi_file.dart       # Leitor de arquivos MIDI (com mudanças de tempo)
    audio_analysis.dart  # Melodia e acordes a partir do áudio
  models/                # Song/Part/NoteEvent, instrumentos
  music/builtin_songs.dart # Exercícios e músicas que vêm com o app
  game/judge.dart        # Tocar junto: compara o ouvido com a parte no tempo
  game/practice.dart     # Praticar: espera cada nota/acorde e dá dicas
  app_state.dart         # Biblioteca, seleção e configurações (salvas)
  audio/
    mic_listener.dart    # Microfone (flutter_recorder) → leituras de altura
    playback.dart        # Acompanhamento, decodificação e tom guia (SoLoud)
  analysis/              # Chama o analisador e transforma em partes/acordes
  song_loader.dart       # Abre MIDI ou áudio
tools/analyzer/          # analyze.py (Demucs + Basic Pitch) e instalação
  ui/                    # Abas (Músicas, Praticar, Afinador), pauta e jogo
```

## Próximos passos

- Tocar junto com a música **sem a sua parte** (as faixas separadas já
  ficam salvas).
- Levar o Basic Pitch para dentro do app (ONNX), sem Python.
- Editar notas e acordes que a transcrição errou.
- Tocar as outras faixas de um MIDI como acompanhamento.
- Velocidade reduzida para estudar e repetir trechos.
- Calibração automática do atraso do microfone.
