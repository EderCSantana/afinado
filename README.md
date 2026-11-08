# Afinado

Jogo para tocar ou cantar junto com uma música: você abre a música, escolhe
o instrumento (ou a voz) e o que vai tocar; as próximas notas e acordes vêm
rolando na tela e o microfone confere se cada nota está **certa** e
**afinada**.

Feito em Flutter (Windows, macOS, Linux e Android).

## Como funciona

1. **Abrir uma música**
   - **MIDI** (`.mid`): cada faixa vira uma parte com as notas exatas
     (melodia, baixo, piano...). É o modo mais preciso.
   - **Áudio** (`.mp3`, `.wav`, `.ogg`, `.flac`): o app estima a
     **melodia** (altura de cada instante com o algoritmo YIN, juntada em
     notas) e os **acordes** (cromagrama por FFT comparado com modelos de
     acordes maiores, menores, com sétima, sus4, diminutos e power chords).
     Funciona melhor quando a voz ou o instrumento principal se destaca; numa
     mixagem cheia a melodia segue o que soar mais forte. O áudio toca como
     acompanhamento.
2. **Escolher o instrumento**: voz, violão, guitarra, ukulele, piano,
   contrabaixo, violino, violoncelo, flauta, saxofones, trompete, clarinete,
   gaita. A parte é levada para a oitava do instrumento; os de transposição
   (sax em Mi♭, trompete e clarinete em Si♭) mostram as notas escritas; para
   a voz vale a nota certa em qualquer oitava.
3. **Tocar**: as notas correm da direita para a esquerda até a linha. O
   microfone mostra o caminho da sua afinação sobre elas e, embaixo, a nota
   a tocar, a nota ouvida e um afinador em cents.
   - Nota **certa**: até 50 cents (meio semitom) da nota esperada.
   - **Afinada**: média até 12 cents → *Perfeito*; até 25 → *Bom*; acima →
     *Desafinado*.
   - Acordes: o acorde ouvido (cromagrama do microfone) precisa bater com o
     esperado; a afinação vem dos picos do espectro.
   - No fim aparecem a pontuação e se você tende a ficar alto ou baixo.

Configurações: nomes Dó Ré Mi ou C D E, microfone, tom guia (toca a nota a
tocar, use fones), volume do acompanhamento e atraso do microfone.

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
  game/judge.dart        # Compara o que é ouvido com a parte e dá as notas
  audio/
    mic_listener.dart    # Microfone (flutter_recorder) → leituras de altura
    playback.dart        # Acompanhamento, decodificação e tom guia (SoLoud)
  song_loader.dart       # Abre MIDI ou áudio
  ui/                    # Tela inicial e tela de jogo
```

## Próximos passos

- Separar a voz/instrumento de uma mixagem (ex. modelos como Demucs ou
  Spleeter) e transcrição polifônica (ex. Basic Pitch) para melhorar a
  leitura de MP3.
- Tocar as outras faixas de um MIDI como acompanhamento.
- Velocidade reduzida para estudar e repetir trechos.
- Calibração automática do atraso do microfone.
