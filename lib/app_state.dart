import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/instrument.dart';
import 'models/song.dart';
import 'music/builtin_songs.dart';
import 'music/pitch.dart';
import 'song_loader.dart';

/// Options shared by the practice, play-along and tuner screens.
class PlaySettings {
  NoteNaming naming = NoteNaming.solfege;

  /// Seconds between producing a sound and the app hearing it.
  double latency = 0.12;
  int deviceId = -1;
  bool guideTone = false;
  double accompanimentVolume = 0.8;

  /// Practice: show the note names under the staff.
  bool showNames = true;

  /// Practice: only accept notes within 25 cents.
  bool strictTuning = false;
}

/// The app's tabs.
enum AppTab { songs, practice, tuner }

/// A song in the library: one that comes with the app or a file.
class LibraryEntry {
  const LibraryEntry.builtin(Song this.song) : path = null;
  const LibraryEntry.file(String this.path) : song = null;

  final Song? song;
  final String? path;

  String get title {
    final s = song;
    if (s != null) return s.title;
    final name = File(path!).uri.pathSegments.last;
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  bool get isFile => path != null;

  @override
  bool operator ==(Object other) =>
      other is LibraryEntry && other.song == song && other.path == path;

  @override
  int get hashCode => Object.hash(song, path);
}

/// Library, selection and settings, shared by all tabs.
class AppState extends ChangeNotifier {
  final settings = PlaySettings();
  AppTab tab = AppTab.songs;

  final List<String> files = [];
  LibraryEntry? selected;
  Song? song;
  int partIndex = 0;
  Instrument instrument = instruments.first;

  /// Message while a song is being opened.
  String? loading;
  String? error;

  final _cache = <String, Song>{};
  SharedPreferences? _prefs;

  List<LibraryEntry> get builtins => [
    for (final s in builtinSongs) LibraryEntry.builtin(s),
  ];

  /// The part to practice, moved to the instrument's octave.
  Part? get part {
    final s = song;
    if (s == null || s.parts.isEmpty) return null;
    return instrument.fit(s.parts[partIndex]);
  }

  Future<void> load() async {
    final prefs = _prefs = await SharedPreferences.getInstance();
    files
      ..clear()
      ..addAll(prefs.getStringList('files') ?? const []);
    settings
      ..naming = NoteNaming.values[prefs.getInt('naming') ?? 0]
      ..latency = prefs.getDouble('latency') ?? settings.latency
      ..deviceId = prefs.getInt('deviceId') ?? -1
      ..guideTone = prefs.getBool('guideTone') ?? false
      ..accompanimentVolume = prefs.getDouble('volume') ?? 0.8
      ..showNames = prefs.getBool('showNames') ?? true
      ..strictTuning = prefs.getBool('strictTuning') ?? false;
    final name = prefs.getString('instrument');
    instrument = instruments.firstWhere(
      (i) => i.name == name,
      orElse: () => instruments.first,
    );
    notifyListeners();
  }

  /// Saves the settings and library; call after changing [settings].
  void save() {
    final prefs = _prefs;
    notifyListeners();
    if (prefs == null) return;
    prefs
      ..setStringList('files', files)
      ..setInt('naming', settings.naming.index)
      ..setDouble('latency', settings.latency)
      ..setInt('deviceId', settings.deviceId)
      ..setBool('guideTone', settings.guideTone)
      ..setDouble('volume', settings.accompanimentVolume)
      ..setBool('showNames', settings.showNames)
      ..setBool('strictTuning', settings.strictTuning)
      ..setString('instrument', instrument.name);
  }

  void goTo(AppTab tab) {
    this.tab = tab;
    notifyListeners();
  }

  Future<void> addFile(String path) async {
    if (!files.contains(path)) {
      files.insert(0, path);
      save();
    }
    await select(LibraryEntry.file(path));
  }

  void removeFile(String path) {
    files.remove(path);
    _cache.remove(path);
    if (selected?.path == path) {
      selected = null;
      song = null;
    }
    save();
  }

  Future<void> select(LibraryEntry entry) async {
    selected = entry;
    error = null;
    final builtin = entry.song;
    if (builtin != null) {
      _setSong(builtin);
      return;
    }
    final path = entry.path!;
    final cached = _cache[path];
    if (cached != null) {
      _setSong(cached);
      return;
    }
    song = null;
    loading = 'Abrindo…';
    notifyListeners();
    try {
      final loaded = await loadSong(
        path,
        onProgress: (p) {
          loading = p;
          notifyListeners();
        },
      );
      _cache[path] = loaded;
      if (selected == entry) _setSong(loaded);
    } catch (e) {
      error = 'Não foi possível abrir a música: $e';
    } finally {
      loading = null;
      notifyListeners();
    }
  }

  void _setSong(Song s) {
    song = s;
    partIndex = _defaultPart(s);
    notifyListeners();
  }

  void setInstrument(Instrument i) {
    instrument = i;
    final s = song;
    if (s != null) partIndex = _defaultPart(s);
    save();
  }

  void setPart(int i) {
    partIndex = i;
    notifyListeners();
  }

  /// Chords for chord instruments; otherwise the part transcribed from the
  /// instrument's own stem (the bass for a bass...), else the melody.
  int _defaultPart(Song s) {
    if (instrument.chords) {
      final i = s.parts.indexWhere((p) => p.kind == PartKind.chords);
      if (i >= 0) return i;
    }
    for (final stem in instrument.stems) {
      final i = s.parts.indexWhere((p) => p.stem == stem);
      if (i >= 0) return i;
    }
    final i = s.parts.indexWhere((p) => p.kind == PartKind.melody);
    return i < 0 ? 0 : i;
  }
}

/// Gives the widgets below access to the [AppState].
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
    : super(notifier: state);

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  /// Without listening for changes (for callbacks).
  static AppState read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
