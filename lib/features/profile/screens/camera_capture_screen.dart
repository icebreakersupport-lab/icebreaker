import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// Lightweight camera capture screen for profile photos.
///
/// Opens the front-facing camera (falls back to first available).
/// Tapping the shutter calls [CameraController.takePicture] and pops
/// with the resulting [XFile]. Cancelling pops with null.
///
/// Uses the same [camera] package already configured for live-selfie
/// capture; no additional permissions or packages required.
///
/// macOS limitation: only still photos are supported here.
/// Video recording via camera is not implemented in this screen.
class CameraPhotoScreen extends StatefulWidget {
  const CameraPhotoScreen({super.key});

  @override
  State<CameraPhotoScreen> createState() => _CameraPhotoScreenState();
}

enum _CamStep { init, ready, capturing, error }

class _CameraPhotoScreenState extends State<CameraPhotoScreen> {
  _CamStep _step = _CamStep.init;
  CameraController? _ctrl;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  // ── Camera lifecycle ───────────────────────────────────────────────────────

  Future<void> _initCamera() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) {
        _fail('No camera found on this device.');
        return;
      }

      // Prefer front-facing; fall back to first.
      final desc = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cams.first,
      );

      final ctrl = CameraController(
        desc,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await ctrl.initialize();

      if (!mounted) return;
      setState(() {
        _ctrl = ctrl;
        _step = _CamStep.ready;
      });
    } catch (e) {
      _fail('Camera unavailable: ${e.runtimeType}');
    }
  }

  void _fail(String msg) {
    if (mounted) setState(() { _step = _CamStep.error; _error = msg; });
  }

  // ── Capture ────────────────────────────────────────────────────────────────

  Future<void> _capture() async {
    final ctrl = _ctrl;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    if (_step != _CamStep.ready) return;

    setState(() => _step = _CamStep.capturing);

    try {
      final xFile = await ctrl.takePicture();
      // Dispose before popping so the camera is released immediately.
      await ctrl.dispose();
      _ctrl = null;
      if (!mounted) return;
      Navigator.of(context).pop(xFile);
    } catch (e) {
      _fail('Capture failed: $e');
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top bar ─────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(null),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close_rounded,
                          color: Colors.white, size: 18),
                    ),
                  ),
                  const Spacer(),
                  Text('Take Photo', style: AppTextStyles.h3),
                  const Spacer(),
                  const SizedBox(width: 36), // visual balance
                ],
              ),
            ),

            // ── Preview / error area ─────────────────────────────────────────
            Expanded(child: _buildPreview()),

            // ── Bottom controls ──────────────────────────────────────────────
            _buildControls(),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview() {
    final ctrl = _ctrl;

    if (_step == _CamStep.error) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.camera_alt_outlined,
                  color: AppColors.textMuted, size: 48),
              const SizedBox(height: 16),
              Text(
                _error ?? 'Camera unavailable',
                style: AppTextStyles.bodyS
                    .copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              TextButton(
                onPressed: () => Navigator.of(context).pop(null),
                child: Text('Go back',
                    style: AppTextStyles.button
                        .copyWith(color: AppColors.brandPink)),
              ),
            ],
          ),
        ),
      );
    }

    if (ctrl == null || !ctrl.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.brandCyan),
      );
    }

    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: AspectRatio(
          aspectRatio: ctrl.value.aspectRatio,
          child: CameraPreview(ctrl),
        ),
      ),
    );
  }

  Widget _buildControls() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 20, 40, 40),
      child: SizedBox(
        height: 80,
        child: Center(
          child: switch (_step) {
            _CamStep.init => const CircularProgressIndicator(
                color: AppColors.brandCyan,
              ),
            _CamStep.capturing => const CircularProgressIndicator(
                color: AppColors.brandPink,
              ),
            _CamStep.ready => _ShutterButton(onTap: _capture),
            _CamStep.error => const SizedBox.shrink(),
          },
        ),
      ),
    );
  }
}

// ── Shutter button ─────────────────────────────────────────────────────────────

class _ShutterButton extends StatelessWidget {
  const _ShutterButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: AppColors.brandGradient,
          boxShadow: [
            BoxShadow(
              color: AppColors.brandPink.withValues(alpha: 0.45),
              blurRadius: 18,
              spreadRadius: 0,
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Container(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
