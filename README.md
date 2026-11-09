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
  - **Áudio** (`.mp3`, `.wav`, `.ogg`, `.flac`): o app estima a melodia
    (YIN) e os acordes (cromagrama); funciona melhor quando a voz ou o
    instrumento principal se destaca.

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

Testes:

```bash
flutter test                                  # núcleo musical (sem áudio real)
flutter test integration_test -d windows \
  --dart-define=AUDIO=caminho/para/teste.wav  # decodificação, microfone e jogo
```

O teste de integração espera um arquivo com Dó Ré Mi Fá Sol (0,6 s cada) e
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
  song_loader.dart       # Abre MIDI ou áudio
  ui/                    # Abas (Músicas, Praticar, Afinador), pauta e jogo
```

## Próximos passos

- Separar a voz/instrumento de uma mixagem (ex. modelos como Demucs ou
  Spleeter) e transcrição polifônica (ex. Basic Pitch) para melhorar a
  leitura de MP3.
- Tocar as outras faixas de um MIDI como acompanhamento.
- Velocidade reduzida para estudar e repetir trechos.
- Calibração automática do atraso do microfone.
