import 'package:flutter/widgets.dart';

import 'data.dart';

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
      : super(notifier: state);

  static AppState? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()?.notifier;

  static AppState of(BuildContext context) {
    final state = maybeOf(context);
    assert(state != null, 'AppScope is missing above this widget.');
    return state!;
  }
}
