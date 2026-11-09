import 'package:flutter/material.dart';

import 'app_state.dart';
import 'ui/shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState();
  runApp(AfinadoApp(state: state));
  state.load();
}

class AfinadoApp extends StatelessWidget {
  const AfinadoApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) => AppScope(
    state: state,
    child: MaterialApp(
      title: 'Afinado',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.teal,
        brightness: Brightness.dark,
      ),
      home: const Shell(),
    ),
  );
}
