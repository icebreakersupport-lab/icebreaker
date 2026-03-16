import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/state/demo_profile.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/gradient_scaffold.dart';
import 'camera_capture_screen.dart';

/// My Gallery screen — fully functional photo and video management.
///
/// Photos (up to 6):
///   - Tap an empty slot → bottom sheet: "Choose from Files" / "Take with Camera"
///   - Tap a filled slot → bottom sheet: "Replace", "Set as Main", "Remove"
///   - Long-press drag a filled slot onto any other slot to swap positions.
///   - Slot 0 is always the main profile photo (MAIN badge + pink border).
///
/// Intro Video (1 optional):
///   - Tap empty → "Choose Video File" (file picker only on macOS)
///   - Tap filled → "Replace", "Remove"
///   - macOS: camera video recording is not available; info note explains this.
///
/// [scrollToVideo] jumps to the video section on open (used from checklist).
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

  DemoProfile get _profile => DemoProfileScope.of(context);
  List<XFile?> get _photos => _profile.photos;
  XFile? get _video => _profile.video;
  int get _photoCount => _profile.photoCount;

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

  Future<XFile?> _pickImageFromFiles() =>
      _picker.pickImage(source: ImageSource.gallery, imageQuality: 90);

  Future<XFile?> _pickVideoFromFiles() =>
      _picker.pickVideo(source: ImageSource.gallery);

  Future<XFile?> _takePhotoWithCamera() {
    return Navigator.of(context).push<XFile?>(
      MaterialPageRoute<XFile?>(
        builder: (_) => const CameraPhotoScreen(),
        fullscreenDialog: true,
      ),
    );
  }

  // ── Photo slot handler ─────────────────────────────────────────────────────

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
        showCamera: !Platform.isMacOS,
        onChooseFile: () async {
          Navigator.of(sheetCtx).pop();
          final xFile = await _pickImageFromFiles();
          if (xFile != null && mounted) _profile.setPhoto(index, xFile);
        },
        onTakePhoto: () async {
          Navigator.of(sheetCtx).pop();
          final xFile = await _takePhotoWithCamera();
          if (xFile != null && mounted) _profile.setPhoto(index, xFile);
        },
        onSetAsMain: (isEmpty || index == 0)
            ? null
            : () {
                Navigator.of(sheetCtx).pop();
                _profile.swapPhotos(index, 0);
              },
        onRemove: isEmpty
            ? null
            : () {
                Navigator.of(sheetCtx).pop();
                _profile.setPhoto(index, null);
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
          if (xFile != null && mounted) _profile.setVideo(xFile);
        },
        onRemove: _video == null
            ? null
            : () {
                Navigator.of(sheetCtx).pop();
                _profile.setVideo(null);
              },
      ),
    );
  }

  // ── Photo grid ─────────────────────────────────────────────────────────────

  /// Builds the 3-column (or 2-column on narrow screens) drag-reorderable grid.
  ///
  /// Each cell is wrapped in [DragTarget] (accepts drop) AND [LongPressDraggable]
  /// (initiates drag on filled slots). Swapping is done via [DemoProfile.swapPhotos]
  /// which triggers [notifyListeners] so the entire tree rebuilds.
  Widget _buildPhotoGrid() {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final cols = constraints.maxWidth < 300 ? 2 : 3;
        // Slot dimensions — needed for the floating drag feedback widget.
        final slotW = (constraints.maxWidth - 10.0 * (cols - 1)) / cols;
        final slotH = slotW * (4 / 3);

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
          itemBuilder: (_, i) => _buildPhotoCell(i, slotW, slotH),
        );
      },
    );
  }

  Widget _buildPhotoCell(int index, double slotW, double slotH) {
    final hasPhoto = _photos[index] != null;

    // DragTarget is outermost so every cell can receive a drop regardless of
    // whether it's a drag source. onWillAccept returning false moves the data
    // to rejectedData, keeping candidateData empty for the source slot itself
    // — so isDropHover stays false on the cell being dragged.
    return DragTarget<int>(
      onWillAcceptWithDetails: (details) => details.data != index,
      onAcceptWithDetails: (details) {
        if (details.data != index) _profile.swapPhotos(details.data, index);
      },
      builder: (ctx, candidateData, rejectedData) {
        final isDropHover = candidateData.isNotEmpty;

        final photoSlot = _PhotoSlot(
          index: index,
          xFile: _photos[index],
          onTap: () => _onPhotoSlotTap(index),
          isDropTarget: isDropHover,
        );

        // Empty slots are drop targets only — no dragging from them.
        if (!hasPhoto) return photoSlot;

        return LongPressDraggable<int>(
          data: index,
          delay: const Duration(milliseconds: 350),

          // Floating image that follows the pointer during drag.
          feedback: Material(
            color: Colors.transparent,
            elevation: 10,
            shadowColor: Colors.black.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: slotW,
              height: slotH,
              child: Opacity(
                opacity: 0.92,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.file(
                    File(_photos[index]!.path),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          ),

          // Placeholder shown in the source slot while dragging.
          childWhenDragging: const _DragPlaceholder(),

          child: photoSlot,
        );
      },
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
                const SizedBox(width: 10),
                // Animated photo-count badge
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: _CountBadge(
                    key: ValueKey(_photoCount),
                    count: _photoCount,
                    total: 6,
                  ),
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

            // ── Photo grid ─────────────────────────────────────────────────
            _buildPhotoGrid(),

            // Reorder hint — only when ≥ 2 photos so hint is actionable.
            if (_photoCount >= 2) ...[
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.drag_indicator_rounded,
                    size: 13,
                    color: AppColors.textMuted.withValues(alpha: 0.50),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'Long press to reorder',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textMuted.withValues(alpha: 0.60),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 32),

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
              style: AppTextStyles.caption
                  .copyWith(color: AppColors.textMuted),
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
    this.isDropTarget = false,
  });

  final int index;
  final XFile? xFile;
  final VoidCallback onTap;

  /// Highlight this slot as a valid drop target while a drag hovers over it.
  final bool isDropTarget;

  @override
  Widget build(BuildContext context) {
    final isMain = index == 0;
    final hasPhoto = xFile != null;

    final borderColor = isDropTarget
        ? AppColors.brandCyan.withValues(alpha: 0.85)
        : isMain
            ? AppColors.brandPink
                .withValues(alpha: hasPhoto ? 0.60 : 0.40)
            : hasPhoto
                ? AppColors.success.withValues(alpha: 0.30)
                : AppColors.divider;

    final borderWidth = isDropTarget ? 2.0 : (isMain || hasPhoto) ? 1.5 : 1.0;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: isDropTarget
              ? AppColors.brandCyan.withValues(alpha: 0.08)
              : AppColors.bgSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: borderWidth),
          boxShadow: isDropTarget
              ? [
                  BoxShadow(
                    color: AppColors.brandCyan.withValues(alpha: 0.28),
                    blurRadius: 14,
                    spreadRadius: 0,
                  ),
                ]
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(13),
          child: hasPhoto
              ? _FilledSlot(xFile: xFile!, isMain: isMain)
              : _EmptySlot(index: index),
        ),
      ),
    );
  }
}

// ── Filled slot ───────────────────────────────────────────────────────────────

class _FilledSlot extends StatelessWidget {
  const _FilledSlot({required this.xFile, required this.isMain});
  final XFile xFile;
  final bool isMain;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Full-bleed thumbnail
        Image.file(File(xFile.path), fit: BoxFit.cover),

        // Bottom scrim so badges are readable
        Positioned(
          bottom: 0, left: 0, right: 0,
          height: 48,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.62),
                ],
              ),
            ),
          ),
        ),

        // MAIN badge — bottom-left
        if (isMain)
          Positioned(
            bottom: 6,
            left: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
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

        // Edit icon — top-right
        Positioned(
          top: 6, right: 6,
          child: Container(
            width: 26, height: 26,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.52),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.edit_rounded, size: 13, color: Colors.white),
          ),
        ),

        // Drag handle — top-left (visual affordance for reorder)
        Positioned(
          top: 6, left: 6,
          child: Container(
            width: 22, height: 22,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.40),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              Icons.drag_indicator_rounded,
              size: 13,
              color: Colors.white.withValues(alpha: 0.75),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Empty slot ────────────────────────────────────────────────────────────────

class _EmptySlot extends StatelessWidget {
  const _EmptySlot({required this.index});
  final int index;

  @override
  Widget build(BuildContext context) {
    final isMain = index == 0;
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
        // Slot number hint on non-main empty slots
        if (!isMain) ...[
          const SizedBox(height: 3),
          Text(
            '${index + 1} of 6',
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textMuted.withValues(alpha: 0.40),
              fontSize: 9,
            ),
          ),
        ],
      ],
    );
  }
}

// ── Drag placeholder ──────────────────────────────────────────────────────────

/// Shown in-place in the original grid cell while a photo is being dragged.
/// Fills the grid cell (no explicit dimensions — constrained by grid delegate).
class _DragPlaceholder extends StatelessWidget {
  const _DragPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.brandPink.withValues(alpha: 0.40),
          width: 1.5,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.swap_vert_rounded,
            size: 22,
            color: AppColors.brandPink.withValues(alpha: 0.50),
          ),
          const SizedBox(height: 6),
          Text(
            'Moving…',
            style: AppTextStyles.caption.copyWith(
              color: AppColors.brandPink.withValues(alpha: 0.55),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Count badge ───────────────────────────────────────────────────────────────

class _CountBadge extends StatelessWidget {
  const _CountBadge({super.key, required this.count, required this.total});
  final int count;
  final int total;

  @override
  Widget build(BuildContext context) {
    final filled = count > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: filled
            ? AppColors.success.withValues(alpha: 0.12)
            : AppColors.bgElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: filled
              ? AppColors.success.withValues(alpha: 0.35)
              : AppColors.divider,
        ),
      ),
      child: Text(
        '$count / $total',
        style: AppTextStyles.caption.copyWith(
          color: filled ? AppColors.success : AppColors.textMuted,
          fontWeight: FontWeight.w700,
        ),
      ),
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
            : const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
        decoration: BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: hasVideo
                ? AppColors.brandCyan.withValues(alpha: 0.55)
                : AppColors.brandCyan.withValues(alpha: 0.28),
            width: hasVideo ? 1.5 : 1.0,
          ),
          boxShadow: hasVideo
              ? [
                  BoxShadow(
                    color: AppColors.brandCyan.withValues(alpha: 0.10),
                    blurRadius: 18,
                    spreadRadius: 0,
                  ),
                ]
              : null,
        ),
        child: hasVideo
            ? _VideoPresent(filename: _filename)
            : const _VideoEmpty(),
      ),
    );
  }
}

// ── Video present state ───────────────────────────────────────────────────────

class _VideoPresent extends StatelessWidget {
  const _VideoPresent({required this.filename});
  final String filename;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Gradient video icon box — signals the file is active
        Container(
          width: 54, height: 54,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.brandCyan, AppColors.brandPurple],
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.videocam_rounded,
              color: Colors.white, size: 26),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.check_circle_rounded,
                      color: AppColors.success, size: 15),
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
              const SizedBox(height: 4),
              Text(
                filename,
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.textMuted),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 3),
              Text(
                'Tap to replace or remove',
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textMuted.withValues(alpha: 0.50),
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Icon(Icons.edit_rounded,
            size: 16,
            color: AppColors.textMuted.withValues(alpha: 0.55)),
      ],
    );
  }
}

// ── Video empty state ─────────────────────────────────────────────────────────

class _VideoEmpty extends StatelessWidget {
  const _VideoEmpty();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 54, height: 54,
          decoration: BoxDecoration(
            color: AppColors.brandCyan.withValues(alpha: 0.10),
            shape: BoxShape.circle,
            border: Border.all(
              color: AppColors.brandCyan.withValues(alpha: 0.28),
            ),
          ),
          child: Icon(
            Icons.videocam_rounded,
            size: 26,
            color: AppColors.brandCyan.withValues(alpha: 0.65),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Add an intro video',
          style: AppTextStyles.bodyS.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Max 30 seconds · MP4 or MOV',
          style: AppTextStyles.caption.copyWith(color: AppColors.textMuted),
        ),
        const SizedBox(height: 3),
        Text(
          'Plays on your profile card',
          style: AppTextStyles.caption.copyWith(
            color: AppColors.textMuted.withValues(alpha: 0.55),
            fontSize: 10,
          ),
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
        border: Border.all(
          color: AppColors.brandCyan.withValues(alpha: 0.30),
        ),
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
    required this.showCamera,
    required this.onChooseFile,
    required this.onTakePhoto,
    this.onSetAsMain,
    this.onRemove,
  });

  final bool isEmpty;
  final bool isMainSlot;

  /// False on macOS — camera photo capture is not available on desktop.
  final bool showCamera;

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
            if (showCamera)
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
            // Platform-specific info note
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
                        Platform.isMacOS
                            ? 'Camera video recording is not available in '
                                'this macOS demo build. Use "Choose Video File" '
                                'to select a local MP4 or MOV file.'
                            : 'For best results, use a short clip under 30 s '
                                'in MP4 or MOV format.',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.textMuted,
                          height: 1.45,
                        ),
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

// ── Shared sheet components ───────────────────────────────────────────────────

class _Handle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40, height: 4,
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
        width: 38, height: 38,
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
