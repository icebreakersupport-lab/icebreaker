import 'package:flutter/widgets.dart';

/// Holds the single source of truth for whether the user has an active
/// Live session.
///
/// Consumed via [LiveSessionScope] anywhere in the widget tree.
/// The notifier is owned by [IcebreakerApp] and lives for the app lifetime.
class LiveSession extends ValueNotifier<bool> {
  LiveSession() : super(false);

  bool get isLive => value;

  void setLive(bool live) {
    if (value != live) value = live;
  }
}

/// InheritedNotifier that exposes [LiveSession] to the entire widget tree.
///
/// Any widget that reads via [LiveSessionScope.of] will rebuild automatically
/// when the live state changes.
///
/// Usage (read):
///   final isLive = LiveSessionScope.isLive(context);
///
/// Usage (mutate — Home screen only for now):
///   LiveSessionScope.of(context).setLive(true);
class LiveSessionScope extends InheritedNotifier<LiveSession> {
  const LiveSessionScope({
    super.key,
    required LiveSession session,
    required super.child,
  }) : super(notifier: session);

  /// Returns the [LiveSession] notifier and subscribes [context] to changes.
  static LiveSession of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<LiveSessionScope>();
    assert(scope != null, 'No LiveSessionScope found in widget tree.');
    return scope!.notifier!;
  }

  /// Convenience accessor for the boolean live flag.
  static bool isLive(BuildContext context) => of(context).isLive;
}
