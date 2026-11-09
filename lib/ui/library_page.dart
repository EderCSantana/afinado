import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../audio/mic_listener.dart';
import '../models/instrument.dart';
import '../models/song.dart';
import '../music/pitch.dart';
import '../song_loader.dart';
import 'play_page.dart';

/// The songs tab: the library on the left, the chosen song on the right.
class LibraryTab extends StatelessWidget {
  const LibraryTab({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 340, child: _SongList(state: state)),
        const VerticalDivider(width: 1),
        Expanded(child: _SongDetails(state: state)),
      ],
    );
  }
}

class _SongList extends StatelessWidget {
  const _SongList({required this.state});

  final AppState state;

  Future<void> _add() async {
    final picked = await FilePicker.pickFile(
      dialogTitle: 'Escolha uma música',
      type: FileType.custom,
      allowedExtensions: [...midiExtensions, ...audioExtensions],
    );
    final path = picked?.path;
    if (path != null) await state.addFile(path);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget tile(LibraryEntry entry) => ListTile(
      selected: state.selected == entry,
      leading: Icon(
        entry.isFile
            ? (entry.path!.toLowerCase().endsWith('.mid') ||
                      entry.path!.toLowerCase().endsWith('.midi')
                  ? Icons.piano
                  : Icons.audio_file)
            : entry.song!.parts.every((p) => p.kind == PartKind.chords)
            ? Icons.grid_view
            : Icons.music_note,
      ),
      title: Text(entry.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: entry.isFile
          ? IconButton(
              tooltip: 'Tirar da lista',
              icon: const Icon(Icons.close, size: 18),
              onPressed: () => state.removeFile(entry.path!),
            )
          : null,
      onTap: () => state.select(entry),
    );

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text('Suas músicas', style: theme.textTheme.titleMedium),
              const Spacer(),
              FilledButton.icon(
                onPressed: state.loading == null ? _add : null,
                icon: const Icon(Icons.add),
                label: const Text('Adicionar'),
              ),
            ],
          ),
        ),
        if (state.files.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Adicione arquivos MIDI (notas exatas) ou MP3/WAV/OGG/FLAC '
              '(melodia e acordes estimados pelo som).',
              style: theme.textTheme.bodySmall,
            ),
          ),
        for (final path in state.files) tile(LibraryEntry.file(path)),
        const Divider(height: 32),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            'Exercícios e músicas de domínio público',
            style: theme.textTheme.titleMedium,
          ),
        ),
        for (final entry in state.builtins) tile(entry),
      ],
    );
  }
}

class _SongDetails extends StatelessWidget {
  const _SongDetails({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final song = state.song;
    final settings = state.settings;

    if (state.loading != null) {
      return Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text(state.loading!),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        if (state.error != null)
          Text(state.error!, style: TextStyle(color: theme.colorScheme.error)),
        if (song == null)
          Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Text(
              'Escolha uma música na lista.',
              style: theme.textTheme.titleLarge,
            ),
          )
        else ...[
          Text(song.title, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(
            song.stems.isNotEmpty
                ? 'Áudio separado por instrumento (Demucs) e transcrito (Basic Pitch) · ${_formatTime(song.duration)}'
                : song.audioPath != null
                ? 'Áudio: melodia e acordes estimados pelo som · ${_formatTime(song.duration)}'
                : '${song.parts.length} parte${song.parts.length > 1 ? 's' : ''} · ${_formatTime(song.duration)}',
            style: theme.textTheme.bodyMedium,
          ),
          if (song.notice != null) ...[
            const SizedBox(height: 8),
            Text(
              song.notice!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.tertiary,
              ),
            ),
          ],
          const SizedBox(height: 24),
        ],
        Text('Instrumento', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final instrument in instruments)
              ChoiceChip(
                label: Text('${instrument.icon}  ${instrument.name}'),
                selected: instrument == state.instrument,
                onSelected: (_) => state.setInstrument(instrument),
              ),
          ],
        ),
        if (song != null && song.parts.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('O que tocar', style: theme.textTheme.titleMedium),
          RadioGroup<int>(
            groupValue: state.partIndex,
            onChanged: (i) => state.setPart(i!),
            child: Column(
              children: [
                for (final (i, part) in song.parts.indexed)
                  RadioListTile<int>(
                    value: i,
                    title: Text(part.name),
                    subtitle: Text(_describe(part, settings.naming)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 16,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 20,
                  ),
                ),
                onPressed: () => state.goTo(AppTab.practice),
                icon: const Icon(Icons.school),
                label: const Text('Praticar'),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 20,
                  ),
                ),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PlayPage(
                      song: song,
                      part: state.part!,
                      instrument: state.instrument,
                      settings: settings,
                    ),
                  ),
                ),
                icon: const Icon(Icons.timer_outlined),
                label: const Text('Tocar junto (no tempo)'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Praticar: a música espera você acertar cada nota, no seu ritmo. '
            'Tocar junto: as notas seguem o tempo da música.',
            style: theme.textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 24),
        ExpansionTile(
          title: const Text('Configurações'),
          tilePadding: EdgeInsets.zero,
          children: [_SettingsPanel(state: state)],
        ),
      ],
    );
  }

  String _describe(Part part, NoteNaming naming) {
    final range = part.range;
    final kind = part.kind == PartKind.chords
        ? 'acordes'
        : part.events.any((e) => e.isChord)
        ? 'notas e acordes'
        : 'notas';
    final names = range == null || part.kind == PartKind.chords
        ? ''
        : ' · de ${noteName(range.$1, naming)} a ${noteName(range.$2, naming)}';
    return '${part.events.length} $kind$names';
  }
}

class _SettingsPanel extends StatelessWidget {
  const _SettingsPanel({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final settings = state.settings;
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
              onSelectionChanged: (s) {
                settings.naming = s.single;
                state.save();
              },
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
            onSelected: (v) {
              settings.deviceId = v ?? -1;
              state.save();
            },
          ),
        const SizedBox(height: 16),
        Text('Tocar junto', style: Theme.of(context).textTheme.titleSmall),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Tom guia'),
          subtitle: const Text(
            'Toca baixinho a nota que você deve tocar (use fones para não confundir o microfone).',
          ),
          value: settings.guideTone,
          onChanged: (v) {
            settings.guideTone = v;
            state.save();
          },
        ),
        Text(
          'Volume do acompanhamento: ${(settings.accompanimentVolume * 100).round()}%',
        ),
        Slider(
          value: settings.accompanimentVolume,
          onChanged: (v) {
            settings.accompanimentVolume = v;
            state.save();
          },
        ),
        Text('Atraso do microfone: ${(settings.latency * 1000).round()} ms'),
        Slider(
          value: settings.latency,
          max: 0.4,
          divisions: 40,
          onChanged: (v) {
            settings.latency = v;
            state.save();
          },
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
