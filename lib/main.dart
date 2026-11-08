import 'package:flutter/material.dart';

import 'ui/home_page.dart';

void main() => runApp(const AfinadoApp());

class AfinadoApp extends StatelessWidget {
  const AfinadoApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Afinado',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorSchemeSeed: Colors.teal, brightness: Brightness.dark),
    home: const HomePage(),
  );
}
