import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/gradient_scaffold.dart';
import 'camera_capture_screen.dart';

/// My Gallery screen — fully functional photo and video management.
///
/// Photos (up to 6):
///   - Tap an empty slot → bottom sheet: "Choose from Files" or "Take with Camera"
///   - Tap a filled slot → bottom sheet: "Replace", "Set as Main", "Remove"
///   - Slot 0 is always the main profile photo (shown with MAIN badge)
///   - Real thumbnails displayed via [Image.file]
///
/// Intro Video (1 optional):
///   - Tap empty → bottom sheet: "Choose Video File"
///   - Tap filled → bottom sheet: "Replace", "Remove"
///   - On macOS, camera video recording is not available (file picker only).
///     The action sheet explains this clearly rather than silently failing.
///
/// [scrollToVideo] jumps to the video section on open — used when the
/// user taps the "Intro Video" checklist item.
///
/// macOS sandbox:
///   Requires com.apple.security.files.user-selected.read-write entitlement.
///   [image_picker] opens NSOpenPanel; [camera] uses AVFoundation for photos.
class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key, this.scrollToVideo = false});
  final bool scrollToVideo;

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  final ScrollController _scroll = ScrollController();
  final _videoKey = GlobalKey();
  final _picker = ImagePicker();

  // Six photo slots — null means the slot is empty.
  final _photos = <XFile?>[null, null, null, null, null, null];

  // Single optional intro video.
  XFile? _video;

  int get _photoCount => _photos.where((p) => p != null).length;

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

  // ── Media actions ──────────────────────────────────────────────────────────

  /// Opens the system file picker and returns a picked image, or null.
  Future<XFile?> _pickImageFromFiles() =>
      _picker.pickImage(source: ImageSource.gallery, imageQuality: 90);

  /// Opens the system file picker and returns a picked video, or null.
  Future<XFile?> _pickVideoFromFiles() =>
      _picker.pickVideo(source: ImageSource.gallery);

  /// Navigates to [CameraPhotoScreen] and returns the captured [XFile], or null.
  Future<XFile?> _takePhotoWithCamera() {
    return Navigator.of(context).push<XFile?>(
      MaterialPageRoute<XFile?>(
        builder: (_) => const CameraPhotoScreen(),
        fullscreenDialog: true,
      ),
    );
  }

  // ── Photo slot handlers ────────────────────────────────────────────────────

  void _onPhotoSlotTap(int index) {
    final isEmpty = _photos[index] == null;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => _PhotoActionSheet(
        isEmpty: isEmpty,
        isMainSlot: index == 0,
        onChooseFile: () async {
          Navigator.of(sheetCtx).pop();
          final xFile = await _pickImageFromFiles();
          if (xFile != null && mounted) {
            setState(() => _photos[index] = xFile);
          }
        },
        onTakePhoto: () async {
          Navigator.of(sheetCtx).pop();
          final xFile = await _takePhotoWithCamera();
          if (xFile != null && mounted) {
            setState(() => _photos[index] = xFile);
          }
        },
        onSetAsMain: (isEmpty || index == 0)
            ? null
            : () {
                Navigator.of(sheetCtx).pop();
                setState(() {
                  final tmp = _photos[index];
                  _photos[index] = _photos[0];
                  _photos[0] = tmp;
                });
              },
        onRemove: isEmpty
            ? null
            : () {
                Navigator.of(sheetCtx).pop();
                setState(() => _photos[index] = null);
              },
      ),
    );
  }

  // ── Video slot handler ─────────────────────────────────────────────────────

  void _onVideoTap() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => _VideoActionSheet(
        hasVideo: _video != null,
        onChooseFile: () async {
          Navigator.of(sheetCtx).pop();
          final xFile = await _pickVideoFromFiles();
          if (xFile != null && mounted) {
            setState(() => _video = xFile);
          }
        },
        onRemove: _video == null
            ? null
            : () {
                Navigator.of(sheetCtx).pop();
                setState(() => _video = null);
              },
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

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
            // ── Photos header ──────────────────────────────────────────────
            Row(
              children: [
                Text('Photos', style: AppTextStyles.h3),
                const SizedBox(width: 8),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: Text(
                    '$_photoCount / 6',
                    key: ValueKey(_photoCount),
                    style: AppTextStyles.caption.copyWith(
                      color: _photoCount > 0
                          ? AppColors.success
                          : AppColors.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'First photo is your main profile photo. Up to 6 total.',
              style: AppTextStyles.caption.copyWith(color: AppColors.textMuted),
            ),
            const SizedBox(height: 14),

            // ── Photo grid ─────────────────────────────────────────────────
            LayoutBuilder(
              builder: (ctx, constraints) {
                final cols = constraints.maxWidth < 300 ? 2 : 3;
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cols,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 3 / 4,
                  ),
                  itemCount: 6,
                  itemBuilder: (_, i) => _PhotoSlot(
                    index: i,
                    xFile: _photos[i],
                    onTap: () => _onPhotoSlotTap(i),
                  ),
                );
              },
            ),

            const SizedBox(height: 28),

            // ── Video header ───────────────────────────────────────────────
            Row(
              key: _videoKey,
              children: [
                Text('Intro Video', style: AppTextStyles.h3),
                const SizedBox(width: 10),
                _OptionalBadge(),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'A short intro video (up to 30 s) shows on your profile card.',
              style: AppTextStyles.caption.copyWith(color: AppColors.textMuted),
            ),
            const SizedBox(height: 14),

            // ── Video slot ─────────────────────────────────────────────────
            _VideoSlot(video: _video, onTap: _onVideoTap),
          ],
        ),
      ),
    );
  }
}

// ── Photo slot ────────────────────────────────────────────────────────────────

class _PhotoSlot extends StatelessWidget {
  const _PhotoSlot({
    required this.index,
    required this.xFile,
    required this.onTap,
  });

  final int index;
  final XFile? xFile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isMain = index == 0;
    final hasPhoto = xFile != null;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isMain
                ? AppColors.brandPink.withValues(alpha: hasPhoto ? 0.60 : 0.40)
                : hasPhoto
                    ? AppColors.success.withValues(alpha: 0.30)
                    : AppColors.divider,
            width: (isMain || hasPhoto) ? 1.5 : 1.0,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(13),
          child: hasPhoto ? _FilledSlot(xFile: xFile!, isMain: isMain) : _EmptySlot(isMain: isMain),
        ),
      ),
    );
  }
}

class _FilledSlot extends StatelessWidget {
  const _FilledSlot({required this.xFile, required this.isMain});
  final XFile xFile;
  final bool isMain;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Thumbnail
        Image.file(File(xFile.path), fit: BoxFit.cover),

        // Scrim so overlays are readable
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          height: 40,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.55),
                ],
              ),
            ),
          ),
        ),

        // MAIN badge
        if (isMain)
          Positioned(
            bottom: 6,
            left: 6,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                gradient: AppColors.brandGradient,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'MAIN',
                style: AppTextStyles.caption.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 9,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),

        // Edit icon
        Positioned(
          top: 6,
          right: 6,
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.50),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.edit_rounded,
                size: 12, color: Colors.white),
          ),
        ),
      ],
    );
  }
}

class _EmptySlot extends StatelessWidget {
  const _EmptySlot({required this.isMain});
  final bool isMain;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          isMain ? Icons.add_photo_alternate_rounded : Icons.add_rounded,
          size: isMain ? 28 : 22,
          color: isMain ? AppColors.brandPink : AppColors.textMuted,
        ),
        const SizedBox(height: 6),
        Text(
          isMain ? 'Main photo' : 'Add photo',
          style: AppTextStyles.caption.copyWith(
            color: isMain
                ? AppColors.brandPink.withValues(alpha: 0.80)
                : AppColors.textMuted,
            fontSize: 10,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

// ── Video slot ────────────────────────────────────────────────────────────────

class _VideoSlot extends StatelessWidget {
  const _VideoSlot({required this.video, required this.onTap});
  final XFile? video;
  final VoidCallback onTap;

  String get _filename {
    if (video == null) return '';
    return video!.path.split(Platform.pathSeparator).last;
  }

  @override
  Widget build(BuildContext context) {
    final hasVideo = video != null;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: hasVideo
            ? const EdgeInsets.all(16)
            : const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
        decoration: BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: hasVideo
                ? AppColors.brandCyan.withValues(alpha: 0.55)
                : AppColors.brandCyan.withValues(alpha: 0.30),
            width: hasVideo ? 1.5 : 1.0,
          ),
        ),
        child: hasVideo ? _VideoPresent(filename: _filename) : _VideoEmpty(),
      ),
    );
  }
}

class _VideoPresent extends StatelessWidget {
  const _VideoPresent({required this.filename});
  final String filename;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: AppColors.brandCyan.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.videocam_rounded,
              color: AppColors.brandCyan, size: 28),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.check_circle_rounded,
                      color: AppColors.success, size: 14),
                  const SizedBox(width: 5),
                  Text(
                    'Intro video added',
                    style: AppTextStyles.bodyS.copyWith(
                      color: AppColors.success,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                filename,
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.textMuted),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Icon(Icons.edit_rounded,
            size: 16,
            color: AppColors.textMuted.withValues(alpha: 0.70)),
      ],
    );
  }
}

class _VideoEmpty extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.videocam_rounded,
            size: 32, color: AppColors.brandCyan.withValues(alpha: 0.55)),
        const SizedBox(height: 10),
        Text(
          'Tap to add an intro video',
          style: AppTextStyles.bodyS.copyWith(color: AppColors.textMuted),
        ),
        const SizedBox(height: 4),
        Text(
          'Max 30 seconds · MP4 or MOV',
          style: AppTextStyles.caption.copyWith(color: AppColors.textMuted),
        ),
      ],
    );
  }
}

// ── Optional badge ────────────────────────────────────────────────────────────

class _OptionalBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.brandCyan.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border:
            Border.all(color: AppColors.brandCyan.withValues(alpha: 0.30)),
      ),
      child: Text(
        'Optional',
        style: AppTextStyles.caption.copyWith(
          color: AppColors.brandCyan,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ── Action sheets ─────────────────────────────────────────────────────────────

class _PhotoActionSheet extends StatelessWidget {
  const _PhotoActionSheet({
    required this.isEmpty,
    required this.isMainSlot,
    required this.onChooseFile,
    required this.onTakePhoto,
    this.onSetAsMain,
    this.onRemove,
  });

  final bool isEmpty;
  final bool isMainSlot;
  final VoidCallback onChooseFile;
  final VoidCallback onTakePhoto;
  final VoidCallback? onSetAsMain;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Handle(),
            const SizedBox(height: 18),
            Text(
              isEmpty ? 'Add Photo' : 'Edit Photo',
              style: AppTextStyles.h3,
            ),
            const SizedBox(height: 8),
            _ActionTile(
              icon: Icons.folder_open_rounded,
              label: 'Choose from Files',
              color: AppColors.brandCyan,
              onTap: onChooseFile,
            ),
            _ActionTile(
              icon: Icons.camera_alt_rounded,
              label: 'Take with Camera',
              color: AppColors.brandPink,
              onTap: onTakePhoto,
            ),
            if (onSetAsMain != null)
              _ActionTile(
                icon: Icons.star_rounded,
                label: 'Set as Main Photo',
                color: AppColors.warning,
                onTap: onSetAsMain!,
              ),
            if (onRemove != null)
              _ActionTile(
                icon: Icons.delete_outline_rounded,
                label: 'Remove Photo',
                color: AppColors.danger,
                onTap: onRemove!,
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _VideoActionSheet extends StatelessWidget {
  const _VideoActionSheet({
    required this.hasVideo,
    required this.onChooseFile,
    this.onRemove,
  });

  final bool hasVideo;
  final VoidCallback onChooseFile;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Handle(),
            const SizedBox(height: 18),
            Text(
              hasVideo ? 'Edit Intro Video' : 'Add Intro Video',
              style: AppTextStyles.h3,
            ),
            const SizedBox(height: 8),
            _ActionTile(
              icon: Icons.folder_open_rounded,
              label: hasVideo ? 'Replace with File' : 'Choose Video File',
              color: AppColors.brandCyan,
              onTap: onChooseFile,
            ),
            // macOS demo note — honest about limitation
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.bgElevated,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline_rounded,
                        color: AppColors.textMuted, size: 15),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Camera video recording is not available in '
                        'this demo build on macOS. Use "Choose Video '
                        'File" to pick a local MP4 or MOV.',
                        style: AppTextStyles.caption
                            .copyWith(color: AppColors.textMuted, height: 1.45),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (onRemove != null)
              _ActionTile(
                icon: Icons.delete_outline_rounded,
                label: 'Remove Video',
                color: AppColors.danger,
                onTap: onRemove!,
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ── Shared components ─────────────────────────────────────────────────────────

class _Handle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: AppColors.divider,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(
        label,
        style: AppTextStyles.bodyS.copyWith(color: AppColors.textPrimary),
      ),
      onTap: onTap,
    );
  }
}
