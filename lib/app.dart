import 'package:flutter/material.dart';
import 'core/router/app_router.dart';
import 'core/state/demo_profile.dart';
import 'core/state/live_session.dart';
import 'core/theme/app_theme.dart';

/// Root application widget.
///
/// Owns both [LiveSession] and [DemoProfile] notifiers and exposes them
/// app-wide via their respective InheritedNotifier scopes.
class IcebreakerApp extends StatefulWidget {
  const IcebreakerApp({super.key});

  @override
  State<IcebreakerApp> createState() => _IcebreakerAppState();
}

class _IcebreakerAppState extends State<IcebreakerApp> {
  final LiveSession _session = LiveSession();
  final DemoProfile _profile = DemoProfile();

  @override
  void dispose() {
    _session.dispose();
    _profile.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DemoProfileScope(
      profile: _profile,
      child: LiveSessionScope(
        session: _session,
        child: MaterialApp.router(
          title: 'Icebreaker',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.dark,
          routerConfig: appRouter,
        ),
      ),
    );
  }
}
