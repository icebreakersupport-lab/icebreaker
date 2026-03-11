import 'package:flutter/widgets.dart';

/// Holds the single source of truth for whether the user has an active
/// Live session, when it expires, and which selfie is currently live.
///
/// Consumed via [LiveSessionScope] anywhere in the widget tree.
/// The notifier is owned by [IcebreakerApp] and lives for the app lifetime.
///
/// End-session behaviour (demo): the selfie file path is intentionally
/// kept cached after the session ends. Going live again reuses the last
/// selfie unless the user picks a new one in the verification flow.
class LiveSession extends ChangeNotifier {
  bool _isLive = false;
  DateTime? _expiresAt;

  /// Local file path of the most-recently verified live selfie.
  /// Null until the first successful go-live verification.
  String? _selfieFilePath;

  bool get isLive => _isLive;
  DateTime? get expiresAt => _expiresAt;
  String? get selfieFilePath => _selfieFilePath;

  /// Time remaining in the current session. Zero when not live or expired.
  Duration get remainingDuration {
    if (_expiresAt == null || !_isLive) return Duration.zero;
    final remaining = _expiresAt!.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// Activate a live session. Optionally stores a new selfie path.
  /// Called by [LiveVerificationScreen] after successful verification.
  void goLive({String? selfieFilePath}) {
    _isLive = true;
    _expiresAt = DateTime.now().add(const Duration(hours: 1));
    if (selfieFilePath != null) _selfieFilePath = selfieFilePath;
    notifyListeners();
  }

  /// End the active session. Selfie path is preserved for the demo session.
  void endSession() {
    _isLive = false;
    _expiresAt = null;
    notifyListeners();
  }
}

/// InheritedNotifier that exposes [LiveSession] to the entire widget tree.
///
/// Any widget that reads via [LiveSessionScope.of] rebuilds automatically
/// when the live state changes.
///
/// Usage (read):
///   final isLive = LiveSessionScope.isLive(context);
///   final session = LiveSessionScope.of(context);
///
/// Usage (mutate — Home screen + LiveVerificationScreen only):
///   LiveSessionScope.of(context).goLive(selfieFilePath: path);
///   LiveSessionScope.of(context).endSession();
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
