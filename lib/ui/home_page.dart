import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../audio/mic_listener.dart';
import '../models/instrument.dart';
import '../models/song.dart';
import '../music/pitch.dart';
import '../song_loader.dart';
import 'play_page.dart';

/// Options chosen before playing.
class PlaySettings {
  NoteNaming naming = NoteNaming.solfege;

  /// Seconds between producing a sound and the app hearing it.
  double latency = 0.12;
  int deviceId = -1;
  bool guideTone = false;
  double accompanimentVolume = 0.8;
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final settings = PlaySettings();
  Song? _song;
  int _part = 0;
  Instrument _instrument = instruments.first;
  String? _progress;
  String? _error;

  Future<void> _open() async {
    final picked = await FilePicker.pickFile(
      dialogTitle: 'Escolha uma música',
      type: FileType.custom,
      allowedExtensions: [...midiExtensions, ...audioExtensions],
    );
    final path = picked?.path;
    if (path == null) return;
    setState(() {
      _progress = 'Abrindo…';
      _error = null;
    });
    try {
      final song = await loadSong(
        path,
        onProgress: (p) => setState(() => _progress = p),
      );
      setState(() {
        _song = song;
        _part = _defaultPart(song);
      });
    } catch (e) {
      setState(() => _error = 'Não foi possível abrir a música: $e');
    } finally {
      setState(() => _progress = null);
    }
  }

  /// Chords for chord instruments, otherwise the melody.
  int _defaultPart(Song song) {
    final wanted = _instrument.chords ? PartKind.chords : PartKind.melody;
    final i = song.parts.indexWhere((p) => p.kind == wanted);
    return i < 0 ? 0 : i;
  }

  void _play() {
    final song = _song!;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayPage(
          song: song,
          part: _instrument.fit(song.parts[_part]),
          instrument: _instrument,
          settings: settings,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final song = _song;
    return Scaffold(
      appBar: AppBar(title: const Text('Afinado')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('1. Música', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'Arquivos MIDI trazem as notas exatas de cada instrumento. Em MP3/WAV/OGG/FLAC '
            'a melodia e os acordes são estimados pelo som: funciona melhor quando a voz ou '
            'o instrumento principal se destaca.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton.icon(
                onPressed: _progress == null ? _open : null,
                icon: const Icon(Icons.library_music),
                label: Text(song == null ? 'Abrir música' : 'Abrir outra'),
              ),
              const SizedBox(width: 16),
              if (_progress != null) ...[
                const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Text(_progress!),
              ] else if (song != null)
                Expanded(
                  child: Text(
                    '${song.title} · ${_formatTime(song.duration)}',
                    style: theme.textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 32),
          Text('2. Instrumento', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final instrument in instruments)
                ChoiceChip(
                  label: Text('${instrument.icon}  ${instrument.name}'),
                  selected: instrument == _instrument,
                  onSelected: (_) => setState(() {
                    _instrument = instrument;
                    if (song != null) _part = _defaultPart(song);
                  }),
                ),
            ],
          ),
          if (song != null) ...[
            const SizedBox(height: 32),
            Text('3. O que tocar', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            RadioGroup<int>(
              groupValue: _part,
              onChanged: (i) => setState(() => _part = i!),
              child: Column(
                children: [
                  for (final (i, part) in song.parts.indexed)
                    RadioListTile<int>(
                      value: i,
                      title: Text(part.name),
                      subtitle: Text(_describe(part)),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          ExpansionTile(
            title: const Text('Configurações'),
            tilePadding: EdgeInsets.zero,
            children: [_settingsPanel()],
          ),
          const SizedBox(height: 24),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 20,
                ),
              ),
              onPressed: song == null || song.parts.isEmpty ? null : _play,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Tocar'),
            ),
          ),
        ],
      ),
    );
  }

  String _describe(Part part) {
    final range = part.range;
    final kind =
        part.kind == PartKind.chords || part.events.any((e) => e.isChord)
        ? 'acordes/notas'
        : 'notas';
    final names = range == null
        ? ''
        : ' · de ${noteName(range.$1, settings.naming)} a ${noteName(range.$2, settings.naming)}';
    return '${part.events.length} $kind$names';
  }

  Widget _settingsPanel() {
    final devices = MicListener.devices();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Nomes das notas: '),
            const SizedBox(width: 8),
            SegmentedButton<NoteNaming>(
              segments: [
                for (final n in NoteNaming.values)
                  ButtonSegment(value: n, label: Text(n.label)),
              ],
              selected: {settings.naming},
              onSelectionChanged: (s) =>
                  setState(() => settings.naming = s.single),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (devices.isNotEmpty)
          DropdownMenu<int>(
            label: const Text('Microfone'),
            width: 420,
            initialSelection: settings.deviceId,
            dropdownMenuEntries: [
              const DropdownMenuEntry(value: -1, label: 'Padrão do sistema'),
              for (final (i, d) in devices.indexed)
                DropdownMenuEntry(value: i, label: d.name),
            ],
            onSelected: (v) => settings.deviceId = v ?? -1,
          ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Tom guia'),
          subtitle: const Text(
            'Toca baixinho a nota que você deve tocar (use fones para não confundir o microfone).',
          ),
          value: settings.guideTone,
          onChanged: (v) => setState(() => settings.guideTone = v),
        ),
        Text(
          'Volume do acompanhamento: ${(settings.accompanimentVolume * 100).round()}%',
        ),
        Slider(
          value: settings.accompanimentVolume,
          onChanged: (v) => setState(() => settings.accompanimentVolume = v),
        ),
        Text('Atraso do microfone: ${(settings.latency * 1000).round()} ms'),
        Slider(
          value: settings.latency,
          max: 0.4,
          divisions: 40,
          onChanged: (v) => setState(() => settings.latency = v),
        ),
        Text(
          'Aumente se as notas certas aparecem como atrasadas.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

String _formatTime(double seconds) {
  final s = seconds.round();
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}
