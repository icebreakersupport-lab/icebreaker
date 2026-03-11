import 'package:flutter/material.dart';
import 'core/router/app_router.dart';
import 'core/state/live_session.dart';
import 'core/theme/app_theme.dart';

/// Root application widget.
///
/// Owns the [LiveSession] notifier and exposes it app-wide via
/// [LiveSessionScope] so every [IcebreakerLogo] instance reacts to live-state
/// changes without per-screen wiring.
class IcebreakerApp extends StatefulWidget {
  const IcebreakerApp({super.key});

  @override
  State<IcebreakerApp> createState() => _IcebreakerAppState();
}

class _IcebreakerAppState extends State<IcebreakerApp> {
  final LiveSession _session = LiveSession();

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LiveSessionScope(
      session: _session,
      child: MaterialApp.router(
        title: 'Icebreaker',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        routerConfig: appRouter,
      ),
    );
  }
}
