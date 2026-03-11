import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// Icebreaker 4-tab bottom navigation bar.
///
/// Tabs (left → right):
///   0: Home / Go Live   (heart + bolt icon)
///   1: Nearby           (compass / nearby icon)
///   2: Messages         (chat bubble icon)
///   3: Profile          (person icon)
///
/// Active tab tinted with [AppColors.brandPink].
/// Inactive tabs use [AppColors.textMuted].
/// A 1px top border separates the bar from screen content.
class AppBottomNavBar extends StatelessWidget {
  const AppBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  static const _items = <_NavItem>[
    _NavItem(
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
      label: 'Home',
    ),
    _NavItem(
      icon: Icons.explore_outlined,
      activeIcon: Icons.explore_rounded,
      label: 'Carousel',
    ),
    _NavItem(
      icon: Icons.chat_bubble_outline_rounded,
      activeIcon: Icons.chat_bubble_rounded,
      label: 'Messages',
    ),
    _NavItem(
      icon: Icons.person_outline_rounded,
      activeIcon: Icons.person_rounded,
      label: 'Profile',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.bgBase,
        border: Border(
          top: BorderSide(color: AppColors.navBorder, width: 1),
        ),
      ),
      height: 64,
      child: Row(
        children: List.generate(_items.length, (i) {
          final item = _items[i];
          final isActive = i == currentIndex;
          return Expanded(
            child: GestureDetector(
              onTap: () => onTap(i),
              behavior: HitTestBehavior.opaque,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        isActive ? item.activeIcon : item.icon,
                        key: ValueKey(isActive),
                        color: isActive
                            ? AppColors.brandPink
                            : AppColors.textMuted,
                        size: 24,
                      ),
                    ),
                    const SizedBox(height: 3),
                    AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 200),
                      style: TextStyle(
                        fontFamily: 'PlusJakartaSans',
                        fontSize: 10,
                        fontWeight: isActive
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: isActive
                            ? AppColors.brandPink
                            : AppColors.textMuted,
                        letterSpacing: 0.2,
                      ),
                      child: Text(item.label),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}


class _NavItem {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
  final IconData icon;
  final IconData activeIcon;
  final String label;
}
