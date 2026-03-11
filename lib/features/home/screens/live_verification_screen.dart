import 'dart:io';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../../core/state/live_session.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

// ── Demo assets ──────────────────────────────────────────────────────────────

/// Generates and caches three distinct coloured-circle PNG demo selfies in the
/// system temp directory using [dart:ui] canvas — no extra packages or bundled
/// image assets required. Each 200×200 PNG has a unique radial gradient so
/// they're visually distinguishable in the 36 px profile icon.
///
/// Used exclusively by [_DemoModePanel] to let developers test the full
/// verification → profile icon → expanded selfie → redo flow without a camera.
class _DemoAssets {
  _DemoAssets._();

  static const _configs = [
    (Color(0xFFFF6B9D), Color(0xFFFF8E53), 'Demo 1'),
    (Color(0xFF00D4FF), Color(0xFF0055FF), 'Demo 2'),
    (Color(0xFF8B5CF6), Color(0xFFD946EF), 'Demo 3'),
  ];

  static final Map<int, String> _cache = {};

  static int get count => _configs.length;
  static String label(int i) => _configs[i].$3;
  static Color accent(int i) => _configs[i].$1;

  /// Returns the local file path for demo selfie [index], generating it on
  /// first call. Subsequent calls return the cached path immediately.
  static Future<String> filePath(int index) async {
    assert(index >= 0 && index < count);
    if (_cache.containsKey(index)) return _cache[index]!;

    const sz = 200.0;
    final (c1, c2, _) = _configs[index];

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, sz, sz));

    // Radial gradient fill
    canvas.drawCircle(
      const Offset(sz / 2, sz / 2),
      sz / 2,
      Paint()
        ..shader = ui.Gradient.radial(
          const Offset(sz * 0.38, sz * 0.35),
          sz * 0.80,
          [c1, c2],
        ),
    );

    // Soft inner highlight to give depth
    canvas.drawCircle(
      const Offset(sz * 0.38, sz * 0.35),
      sz * 0.22,
      Paint()..color = const Color(0x20FFFFFF),
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(200, 200);
    final byteData =
        await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();

    final path =
        '${Directory.systemTemp.path}/icebreaker_demo_$index.png';
    await File(path)
        .writeAsBytes(byteData!.buffer.asUint8List(), flush: true);

    _cache[index] = path;
    return path;
  }
}

// ── Step enum ────────────────────────────────────────────────────────────────

enum _Step { preparing, cameraReady, cameraError, verifying, verified }

/// Immersive live-selfie capture + mock verification screen.
///
/// Layout (matches reference mockup):
///   • Minimal dark header: back icon / "icebreaker •" / close icon
///   • Large square selfie frame with neon border glow (camera live or captured photo)
///   • Status area below:
///       idle     — "Position your face in the frame"
///       verifying — green ✓  "Verifying…"  neon gradient progress bar
///       verified  — "Verified!"
///   • Circular shutter capture button (visible in camera-ready state only)
///
/// Flow:
///   camera ready → tap shutter → auto-verifying (1.5 s) → verified (0.6 s)
///   → [LiveSession.goLive] → pop.
///
/// Camera: uses front-facing camera via [camera] package (camera_avfoundation
/// on macOS). No gallery fallback — fresh live selfie required.
class LiveVerificationScreen extends StatefulWidget {
  const LiveVerificationScreen({super.key, this.isRedo = false});

  /// When true, a successful capture calls [LiveSession.updateSelfie] instead
  /// of [LiveSession.goLive], preserving the current live state and expiry.
  final bool isRedo;

  @override
  State<LiveVerificationScreen> createState() => _LiveVerificationScreenState();
}

class _LiveVerificationScreenState extends State<LiveVerificationScreen> {
  _Step _step = _Step.preparing;
  CameraController? _camController;
  String? _capturedPath;
  String? _errorMessage;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  @override
  void dispose() {
    _camController?.dispose();
    super.dispose();
  }

  // ── Camera ────────────────────────────────────────────────────────────────

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        _setError('No camera found on this device.');
        return;
      }

      // Prefer front-facing (selfie) camera; fall back to first available.
      final desc = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
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
        _camController = ctrl;
        _step = _Step.cameraReady;
      });
    } catch (e) {
      _setError('Camera unavailable: ${e.runtimeType}');
    }
  }

  void _setError(String message) {
    if (mounted) {
      setState(() {
        _step = _Step.cameraError;
        _errorMessage = message;
      });
    }
  }

  // ── Capture + verify ──────────────────────────────────────────────────────

  Future<void> _captureAndVerify() async {
    final ctrl = _camController;
    if (ctrl == null || !ctrl.value.isInitialized) return;

    try {
      final xFile = await ctrl.takePicture();
      if (!mounted) return;

      setState(() {
        _capturedPath = xFile.path;
        _step = _Step.verifying;
      });

      // Stop the camera feed — we have the captured image.
      await ctrl.dispose();
      _camController = null;

      // Mock verification — 1.5 s
      await Future.delayed(const Duration(milliseconds: 1500));
      if (!mounted) return;
      setState(() => _step = _Step.verified);

      // Brief "Verified!" moment — 0.6 s
      await Future.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;

      final session = LiveSessionScope.of(context);
      if (widget.isRedo) {
        session.updateSelfie(_capturedPath!);
      } else {
        session.goLive(selfieFilePath: _capturedPath);
      }
      Navigator.of(context).pop();
    } catch (e) {
      _setError('Capture failed: ${e.runtimeType}');
    }
  }

  // ── Demo selfie selection ─────────────────────────────────────────────────

  /// Selects a pre-generated demo selfie and runs it through the exact same
  /// mock-verification sequence as a real camera capture.
  Future<void> _useDemoSelfie(int index) async {
    if (_step == _Step.verifying || _step == _Step.verified) return;

    // Dispose any live camera stream before showing the static demo image.
    await _camController?.dispose();
    _camController = null;

    // Generate (or retrieve from cache) the coloured-circle PNG.
    final path = await _DemoAssets.filePath(index);
    if (!mounted) return;

    setState(() {
      _capturedPath = path;
      _step = _Step.verifying;
    });

    // Same timing as the real flow.
    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;
    setState(() => _step = _Step.verified);

    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;

    final session = LiveSessionScope.of(context);
    if (widget.isRedo) {
      session.updateSelfie(path);
    } else {
      session.goLive(selfieFilePath: path);
    }
    Navigator.of(context).pop();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF05000E), // near-black, slightly deeper
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _buildBody(context)),
          ],
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // Back / close
          _HeaderIconButton(
            icon: Icons.arrow_back_ios_new_rounded,
            onTap: (_step == _Step.verifying || _step == _Step.verified)
                ? null
                : () => Navigator.of(context).pop(),
          ),

          // Brand wordmark + live dot
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'icebreaker',
                  style: AppTextStyles.h3.copyWith(
                    letterSpacing: 0.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.success,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          ),

          // Right spacer to balance layout
          const SizedBox(width: 40),
        ],
      ),
    );
  }

  // ── Body ──────────────────────────────────────────────────────────────────

  Widget _buildBody(BuildContext context) {
    final mq = MediaQuery.of(context).size;
    // Cap frame to fit the screen: at most 80% of width or 48% of height.
    // This keeps the layout sane on both phone portrait and wide macOS windows.
    final frameSize = (mq.width - 40).clamp(0.0, mq.height * 0.48);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          const SizedBox(height: 8),

          // ── Selfie frame ────────────────────────────────────────────────
          _SelfieFrame(
            size: frameSize,
            child: _buildFrameContent(frameSize),
          ),

          const SizedBox(height: 28),

          // ── Status section ──────────────────────────────────────────────
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _buildStatusSection(),
          ),

          const Spacer(),

          // ── Action area ─────────────────────────────────────────────────
          _buildActionArea(),

          const SizedBox(height: 36),
        ],
      ),
    );
  }

  // ── Frame content ─────────────────────────────────────────────────────────

  Widget _buildFrameContent(double frameSize) {
    switch (_step) {
      case _Step.preparing:
        return const Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor:
                AlwaysStoppedAnimation<Color>(AppColors.brandCyan),
          ),
        );

      case _Step.cameraError:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.camera_alt_outlined,
                    color: AppColors.textMuted, size: 40),
                const SizedBox(height: 12),
                Text(
                  _errorMessage ?? 'Camera unavailable',
                  style: AppTextStyles.caption,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );

      case _Step.cameraReady:
        final ctrl = _camController;
        if (ctrl == null || !ctrl.value.isInitialized) {
          return const SizedBox.shrink();
        }
        // Fill frame with camera preview, mirrored (selfie mode).
        return ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SizedBox.square(
            dimension: frameSize,
            child: OverflowBox(
              maxWidth: double.infinity,
              maxHeight: double.infinity,
              child: Transform.scale(
                scaleX: -1, // mirror horizontally for selfie feel
                child: CameraPreview(ctrl),
              ),
            ),
          ),
        );

      case _Step.verifying:
      case _Step.verified:
        final path = _capturedPath;
        if (path == null) return const SizedBox.shrink();
        return ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.file(
            File(path),
            width: frameSize,
            height: frameSize,
            fit: BoxFit.cover,
          ),
        );
    }
  }

  // ── Status sections ───────────────────────────────────────────────────────

  Widget _buildStatusSection() {
    switch (_step) {
      case _Step.preparing:
        return const SizedBox(key: ValueKey('preparing'), height: 80);

      case _Step.cameraError:
        return SizedBox(
          key: const ValueKey('error'),
          height: 80,
          child: Center(
            child: Text(
              'Point your camera here and try again.',
              style: AppTextStyles.caption,
              textAlign: TextAlign.center,
            ),
          ),
        );

      case _Step.cameraReady:
        return SizedBox(
          key: const ValueKey('ready'),
          height: 80,
          child: Center(
            child: Text(
              'Position your face in the frame',
              style: AppTextStyles.bodyS.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        );

      case _Step.verifying:
        return _VerifyingStatus(
          key: const ValueKey('verifying'),
          duration: const Duration(milliseconds: 1500),
        );

      case _Step.verified:
        return _VerifiedStatus(
          key: const ValueKey('verified'),
          isRedo: widget.isRedo,
        );
    }
  }

  // ── Action area ───────────────────────────────────────────────────────────

  Widget _buildActionArea() {
    switch (_step) {
      case _Step.cameraReady:
        // Real flow: shutter button. Demo panel shown below as dev shortcut.
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ShutterButton(onTap: _captureAndVerify),
            const SizedBox(height: 24),
            _DemoModePanel(onSelect: _useDemoSelfie),
          ],
        );

      case _Step.preparing:
      case _Step.cameraError:
        // Camera unavailable — demo panel becomes the primary action.
        return _DemoModePanel(onSelect: _useDemoSelfie, asPrimary: true);

      case _Step.verifying:
      case _Step.verified:
        return const SizedBox(height: 72);
    }
  }
}

// ── Selfie frame ─────────────────────────────────────────────────────────────

/// Square frame with neon gradient border and multi-layer glow,
/// matching the reference UI.
class _SelfieFrame extends StatelessWidget {
  const _SelfieFrame({required this.size, required this.child});

  final double size;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.12),
            blurRadius: 12,
            spreadRadius: 0,
          ),
          BoxShadow(
            color: AppColors.brandPink.withValues(alpha: 0.35),
            blurRadius: 40,
            spreadRadius: 2,
          ),
          BoxShadow(
            color: AppColors.brandPurple.withValues(alpha: 0.30),
            blurRadius: 70,
            spreadRadius: 8,
          ),
        ],
      ),
      // Gradient border via nested containers
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFFFFFFF), // bright white top-left corner
              Color(0xFFBBCCFF), // cool blue
              AppColors.brandCyan,
              AppColors.brandPurple,
              AppColors.brandPink,
              Color(0xFFFFFFFF), // bright white bottom-right
            ],
            stops: [0.0, 0.2, 0.4, 0.6, 0.8, 1.0],
          ),
        ),
        padding: const EdgeInsets.all(2),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: child,
        ),
      ),
    );
  }
}

// ── Verifying status ──────────────────────────────────────────────────────────

class _VerifyingStatus extends StatelessWidget {
  const _VerifyingStatus({super.key, required this.duration});
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.check_rounded,
          color: AppColors.success,
          size: 36,
        ),
        const SizedBox(height: 10),
        Text(
          'Verifying…',
          style: AppTextStyles.h2.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 16),
        _NeonProgressBar(duration: duration),
      ],
    );
  }
}

class _VerifiedStatus extends StatelessWidget {
  const _VerifiedStatus({super.key, required this.isRedo});
  final bool isRedo;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.check_circle_rounded,
          color: AppColors.success,
          size: 36,
        ),
        const SizedBox(height: 10),
        Text(
          'Verified!',
          style: AppTextStyles.h2.copyWith(color: AppColors.success),
        ),
        const SizedBox(height: 6),
        Text(
          isRedo ? 'Selfie updated!' : 'Going live…',
          style: AppTextStyles.bodyS,
        ),
      ],
    );
  }
}

// ── Neon progress bar ────────────────────────────────────────────────────────

class _NeonProgressBar extends StatefulWidget {
  const _NeonProgressBar({required this.duration});
  final Duration duration;

  @override
  State<_NeonProgressBar> createState() => _NeonProgressBarState();
}

class _NeonProgressBarState extends State<_NeonProgressBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _progress;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    _progress = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _progress,
      builder: (context, _) {
        return Stack(
          children: [
            // Track
            Container(
              height: 4,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                color: AppColors.divider,
              ),
            ),
            // Fill
            FractionallySizedBox(
              widthFactor: _progress.value,
              child: Container(
                height: 4,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  gradient: const LinearGradient(
                    colors: [AppColors.brandPink, AppColors.brandCyan],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.brandCyan.withValues(alpha: 0.55),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                    BoxShadow(
                      color: AppColors.brandPink.withValues(alpha: 0.40),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── Shutter button ────────────────────────────────────────────────────────────

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
          // Outer ring: gradient
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.brandPink, AppColors.brandCyan],
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.brandPink.withValues(alpha: 0.45),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        padding: const EdgeInsets.all(3),
        child: Container(
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFF05000E),
          ),
          padding: const EdgeInsets.all(3),
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

// ── Demo mode panel ───────────────────────────────────────────────────────────

/// Developer-only panel shown in the Live Verification screen.
///
/// When [asPrimary] is false (camera is working): renders as a subtle row
/// below the shutter button, clearly labelled DEV · DEMO MODE.
///
/// When [asPrimary] is true (no camera available): renders prominently as
/// the only available action so the dev can still test the full flow.
class _DemoModePanel extends StatelessWidget {
  const _DemoModePanel({required this.onSelect, this.asPrimary = false});

  final void Function(int index) onSelect;
  final bool asPrimary;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── DEV label ────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1530),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFF3A3060)),
          ),
          child: Text(
            'DEV · DEMO MODE',
            style: AppTextStyles.overline.copyWith(
              color: const Color(0xFF7A6EA8),
              letterSpacing: 1.6,
            ),
          ),
        ),

        const SizedBox(height: 10),

        Text(
          asPrimary
              ? 'Camera unavailable — select a demo selfie to test the flow'
              : 'or pick a demo selfie to test without a camera',
          style: AppTextStyles.caption.copyWith(
            color: AppColors.textMuted,
          ),
          textAlign: TextAlign.center,
        ),

        const SizedBox(height: 16),

        // ── Demo selfie buttons ───────────────────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (int i = 0; i < _DemoAssets.count; i++) ...[
              if (i > 0) const SizedBox(width: 20),
              _DemoAvatarButton(
                index: i,
                onTap: () => onSelect(i),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// Tappable coloured-circle avatar button for one demo selfie option.
class _DemoAvatarButton extends StatelessWidget {
  const _DemoAvatarButton({required this.index, required this.onTap});
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _DemoAssets.accent(index);
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              // Preview circle matches the generated PNG colour
              gradient: RadialGradient(
                center: const Alignment(-0.3, -0.3),
                radius: 0.9,
                colors: [color, color.withValues(alpha: 0.55)],
              ),
              border: Border.all(
                color: color.withValues(alpha: 0.55),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.35),
                  blurRadius: 14,
                  spreadRadius: 0,
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _DemoAssets.label(index),
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textMuted,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Header icon button ────────────────────────────────────────────────────────

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        opacity: onTap != null ? 1.0 : 0.3,
        duration: const Duration(milliseconds: 150),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.08),
          ),
          child: Icon(icon, color: AppColors.textSecondary, size: 18),
        ),
      ),
    );
  }
}
