import 'package:flutter/material.dart';

import '../app_state.dart';
import 'library_page.dart';
import 'practice_page.dart';
import 'tuner_page.dart';

/// The main window: tabs for songs, practice and the tuner.
class Shell extends StatelessWidget {
  const Shell({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: state.tab.index,
            labelType: NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Afinado',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            onDestinationSelected: (i) => state.goTo(AppTab.values[i]),
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.library_music_outlined),
                selectedIcon: Icon(Icons.library_music),
                label: Text('Músicas'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.school_outlined),
                selectedIcon: Icon(Icons.school),
                label: Text('Praticar'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.graphic_eq_outlined),
                selectedIcon: Icon(Icons.graphic_eq),
                label: Text('Afinador'),
              ),
            ],
          ),
          const VerticalDivider(width: 1),
          // Only the visible tab is built, so only one of them holds the
          // microphone.
          Expanded(
            child: switch (state.tab) {
              AppTab.songs => const LibraryTab(),
              AppTab.practice => const PracticeTab(),
              AppTab.tuner => const TunerTab(),
            },
          ),
        ],
      ),
    );
  }
}
