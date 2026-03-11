import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// A scaffold with the Icebreaker dark purple-black background.
/// Optionally renders a subtle top radial glow for the "live" screens.
class GradientScaffold extends StatelessWidget {
  const GradientScaffold({
    super.key,
    required this.body,
    this.appBar,
    this.bottomNavigationBar,
    this.showTopGlow = false,
    this.resizeToAvoidBottomInset = true,
    this.extendBodyBehindAppBar = false,
    this.floatingActionButton,
  });

  final Widget body;
  final PreferredSizeWidget? appBar;
  final Widget? bottomNavigationBar;
  final bool showTopGlow;
  final bool resizeToAvoidBottomInset;
  final bool extendBodyBehindAppBar;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      extendBodyBehindAppBar: extendBodyBehindAppBar,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      appBar: appBar,
      bottomNavigationBar: bottomNavigationBar,
      floatingActionButton: floatingActionButton,
      body: showTopGlow
          ? Stack(
              children: [
                // Top radial glow (subtle brand ambient)
                Positioned(
                  top: -80,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      width: 560,
                      height: 560,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            AppColors.brandPink.withValues(alpha: 0.30),
                            AppColors.brandPurple.withValues(alpha: 0.18),
                            Colors.transparent,
                          ],
                          stops: const [0.0, 0.5, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),
                body,
              ],
            )
          : body,
    );
  }
}
