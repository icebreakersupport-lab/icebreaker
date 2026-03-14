import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/gradient_scaffold.dart';

/// My Gallery screen — stub showing the photo grid (up to 6) and video slot.
///
/// [scrollToVideo] jumps directly to the video section on open,
/// used when the user taps the "Intro Video" checklist item.
class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key, this.scrollToVideo = false});
  final bool scrollToVideo;

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  final ScrollController _scroll = ScrollController();
  final _videoKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (widget.scrollToVideo) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_videoKey.currentContext != null) {
          Scrollable.ensureVisible(
            _videoKey.currentContext!,
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeInOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Text('My Gallery', style: AppTextStyles.h3),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppColors.textSecondary),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
          children: [
            // ── Photos ───────────────────────────────────────────────────
            Row(
              children: [
                Text('Photos', style: AppTextStyles.h3),
                const SizedBox(width: 8),
                Text(
                  '0 / 6',
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.textMuted),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'First photo is your main profile photo. Up to 6 total.',
              style: AppTextStyles.caption
                  .copyWith(color: AppColors.textMuted),
            ),
            const SizedBox(height: 14),

            // 6-slot photo grid
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 3 / 4,
              ),
              itemCount: 6,
              itemBuilder: (_, i) => _PhotoSlot(index: i),
            ),

            const SizedBox(height: 28),

            // ── Video ─────────────────────────────────────────────────────
            Row(
              key: _videoKey,
              children: [
                Text('Intro Video', style: AppTextStyles.h3),
                const SizedBox(width: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.brandCyan.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: AppColors.brandCyan.withValues(alpha: 0.30)),
                  ),
                  child: Text(
                    'Optional',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.brandCyan,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'A short intro video (up to 30 s) shows on your profile card.',
              style: AppTextStyles.caption
                  .copyWith(color: AppColors.textMuted),
            ),
            const SizedBox(height: 14),

            // Video upload slot
            _VideoSlot(),
          ],
        ),
      ),
    );
  }
}

// ── Photo slot ────────────────────────────────────────────────────────────────

class _PhotoSlot extends StatelessWidget {
  const _PhotoSlot({required this.index});
  final int index;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: index == 0
              ? AppColors.brandPink.withValues(alpha: 0.40)
              : AppColors.divider,
          width: index == 0 ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            index == 0
                ? Icons.add_photo_alternate_rounded
                : Icons.add_rounded,
            size: index == 0 ? 28 : 22,
            color: index == 0 ? AppColors.brandPink : AppColors.textMuted,
          ),
          const SizedBox(height: 6),
          Text(
            index == 0 ? 'Main photo' : 'Add photo',
            style: AppTextStyles.caption.copyWith(
              color: index == 0
                  ? AppColors.brandPink.withValues(alpha: 0.80)
                  : AppColors.textMuted,
              fontSize: 10,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ── Video slot ────────────────────────────────────────────────────────────────

class _VideoSlot extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.brandCyan.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.videocam_rounded,
            size: 32,
            color: AppColors.brandCyan.withValues(alpha: 0.60),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap to upload an intro video',
            style: AppTextStyles.bodyS.copyWith(
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Max 30 seconds · MP4 or MOV',
            style: AppTextStyles.caption.copyWith(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}
