import 'package:flutter/material.dart';

import '../core/motion.dart';
import '../data/app_scope.dart';
import '../ui/components.dart';
import '../ui/states.dart';
import 'auth_screen.dart';
import 'shell_screen.dart';

/// First screen: loads saved data, then shows the app (signed in) or the
/// sign in page. Shows a retry screen if loading fails.
class BootScreen extends StatefulWidget {
  const BootScreen({super.key});

  @override
  State<BootScreen> createState() => _BootScreenState();
}

class _BootScreenState extends State<BootScreen> {
  @override
  void initState() {
    super.initState();
    AppScope.read(context).init();
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);

    final Widget child;
    if (store.ready) {
      child = store.profile.signedIn
          ? const ShellScreen(key: ValueKey<String>('shell'))
          : const AuthScreen(key: ValueKey<String>('auth'));
    } else if (store.loadError != null) {
      child = ScreenScaffold(
        key: const ValueKey<String>('error'),
        title: 'Nova',
        header: false,
        body: ErrorState(
          title: 'Could not load your data',
          message: 'Nothing was changed. Check that the device has free '
              'storage and try again.',
          onRetry: () => AppScope.read(context).init(),
        ),
      );
    } else {
      child = const ScreenScaffold(
        key: ValueKey<String>('loading'),
        title: 'Nova',
        header: false,
        body: LoadingState(label: 'Loading Nova'),
      );
    }

    return AnimatedSwitcher(
      duration: motionDuration(context, const Duration(milliseconds: 350)),
      switchInCurve: Curves.easeOut,
      child: child,
    );
  }
}
