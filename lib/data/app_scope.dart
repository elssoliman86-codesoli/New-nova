import 'package:flutter/widgets.dart';

import 'app_store.dart';

/// Makes the [AppStore] available to the whole widget tree.
///
/// `AppScope.of(context)` rebuilds the caller whenever the store changes.
/// `AppScope.read(context)` returns the store without subscribing, which is
/// what event handlers should use.
class AppScope extends InheritedNotifier<AppStore> {
  const AppScope({
    super.key,
    required AppStore store,
    required super.child,
  }) : super(notifier: store);

  static AppStore of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'No AppScope found in the widget tree.');
    return scope!.notifier!;
  }

  static AppStore read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'No AppScope found in the widget tree.');
    return scope!.notifier!;
  }
}
