import 'package:flutter/material.dart';

import 'core/theme.dart';
import 'core/tokens.dart';
import 'core/ui_prefs.dart';
import 'data/app_scope.dart';
import 'data/app_store.dart';
import 'data/storage.dart';
import 'screens/boot_screen.dart';
import 'ui/island.dart';

/// Root widget. Creates the [AppStore], exposes it with [AppScope], and puts
/// the island and the visual preferences above the navigator so they apply
/// to every page, dialog and bottom sheet.
class NovaApp extends StatefulWidget {
  const NovaApp({super.key, this.storage});

  /// Override in tests to avoid touching the platform storage.
  final Storage? storage;

  @override
  State<NovaApp> createState() => _NovaAppState();
}

class _NovaAppState extends State<NovaApp> {
  late final AppStore _store = AppStore(storage: widget.storage);

  @override
  void dispose() {
    _store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      store: _store,
      child: MaterialApp(
        title: 'Nova',
        debugShowCheckedModeBanner: false,
        theme: buildNovaTheme(),
        themeMode: ThemeMode.dark,
        color: NovaColors.bg,
        home: const BootScreen(),
        builder: (context, child) {
          // `child` (the navigator) is passed through untouched, so changes
          // to the store only rebuild this thin wrapper, not the pages.
          return ListenableBuilder(
            listenable: _store,
            builder: (context, _) {
              final settings = _store.settings;
              return UiPrefs(
                reduceBlur: settings.reduceBlur,
                reduceMotion: settings.reduceMotion,
                child: IslandHost(
                  controller: _store.island,
                  child: child ?? const SizedBox.shrink(),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
