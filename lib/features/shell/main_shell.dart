import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_constants.dart';
import '../../shared/widgets/app_bottom_nav_bar.dart';

/// Root scaffold that hosts the 4-tab bottom navigation experience.
///
/// Receives [child] from go_router's [ShellRoute] — the child is the
/// currently active route widget. Tab navigation is driven via go_router
/// so deep links and back-navigation work correctly.
class MainShell extends StatelessWidget {
  const MainShell({super.key, required this.child});

  final Widget child;

  static const _tabRoutes = [
    AppRoutes.home,
    AppRoutes.nearby,
    AppRoutes.messages,
    AppRoutes.profile,
  ];

  int _currentIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    for (var i = 0; i < _tabRoutes.length; i++) {
      if (location.startsWith(_tabRoutes[i])) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
      bottomNavigationBar: AppBottomNavBar(
        currentIndex: _currentIndex(context),
        onTap: (i) => context.go(_tabRoutes[i]),
      ),
    );
  }
}
