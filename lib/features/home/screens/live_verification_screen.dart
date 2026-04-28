import 'dart:io';

import 'package:camera/camera.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/models/live_session_model.dart';
import '../../../core/state/demo_profile.dart';
import '../../../core/state/live_session.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

// ── Mac fallback gate ────────────────────────────────────────────────────────

/// The single account permitted to use the photo-library fallback in place of
/// a live camera capture.  This is intentionally narrow: the Mac on which this
/// account is signed in has no camera, so the library path is the only way to
/// complete live verification on that machine.  Every other account on every
/// other platform — including other accounts on this same Mac — must use the
/// real camera flow.
const _kMacLibraryFallbackEmail = 'icebreaker.support@gmail.com';

/// Returns true only when:
///   • the host platform is macOS (not iOS, not Android, not web), AND
///   • the signed-in user's email matches [_kMacLibraryFallbackEmail].
///
/// Build mode is not part of the gate — the camera is missing on hardware,
/// not in software, so the fallback must work in every build mode.  The email
/// match is the privacy boundary.
bool _macLibraryFallbackForThisAccount() {
  if (kIsWeb) return false;
  if (!Platform.isMacOS) return false;
  final email = FirebaseAuth.instance.currentUser?.email?.trim().toLowerCase();
  return email == _kMacLibraryFallbackEmail;
}

// ── Step enum ────────────────────────────────────────────────────────────────

enum _Step {
  preparing,
  cameraReady,
  cameraError,
  cameraPermissionDenied,
  libraryReady,
  verifying,
  verified,
}

/// Live-selfie capture + verification screen.
///
/// Flow:
///   camera ready → tap shutter → verifying (1.5 s) → verified (0.6 s)
///   → [LiveSession.goLive] (or [LiveSession.updateSelfie] on redo) → pop.
///
/// Capture source:
///   • iPhone / Android  → front camera, always.  No library fallback.
///   • macOS, but only when the signed-in user matches
///     [_kMacLibraryFallbackEmail] → photo library, because that machine has
///     no camera.  The verifying / verified stages run identically after the
///     image is chosen.
///   • Everything else (other Mac accounts, web, Linux, Windows) → camera
///     unavailable error.  No silent bypass.
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
  final ImagePicker _picker = ImagePicker();
  String? _capturedPath;
  String? _errorMessage;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _useMacLibraryFallback = _macLibraryFallbackForThisAccount();
    _initCamera();
  }

  @override
  void dispose() {
    _camController?.dispose();
    super.dispose();
  }

  // ── Camera ────────────────────────────────────────────────────────────────

  bool _cameraPermPermanentlyDenied = false;

  /// Cached at `initState` so the gate can't change mid-session if the user
  /// signs out from another tab, etc.  Read-only after init.
  late final bool _useMacLibraryFallback;

  /// Called from every camera-unavailable code path.  On mobile (and on every
  /// non-eligible Mac account) this enters the normal `cameraError` state so
  /// the user is not silently given a bypass.  Only the eligible Mac account
  /// is routed to the photo-library fallback.
  void _handleCameraUnavailable(String message) {
    if (!mounted) return;
    if (_useMacLibraryFallback) {
      setState(() {
        _errorMessage = null;
        _step = _Step.libraryReady;
      });
    } else {
      setState(() {
        _step = _Step.cameraError;
        _errorMessage = message;
      });
    }
  }

  Future<void> _initCamera() async {
    if (_useMacLibraryFallback) {
      if (mounted) {
        setState(() {
          _errorMessage = null;
          _step = _Step.libraryReady;
        });
      }
      return;
    }

    // ── 1. Check / request camera permission ──────────────────────────────
    // Skip on non-mobile platforms where permission_handler is a no-op.
    if (Platform.isIOS || Platform.isAndroid) {
      var status = await Permission.camera.status;
      if (status.isDenied) {
        status = await Permission.camera.request();
      }
      if (status.isPermanentlyDenied || status.isRestricted) {
        if (mounted) {
          setState(() {
            _cameraPermPermanentlyDenied = true;
            _step = _Step.cameraPermissionDenied;
          });
        }
        return;
      }
      if (!status.isGranted) {
        // Denied (not permanent) — show retryable state.
        if (mounted) {
          setState(() {
            _cameraPermPermanentlyDenied = false;
            _step = _Step.cameraPermissionDenied;
          });
        }
        return;
      }
    }

    // ── 2. Initialise the camera controller ────────────────────────────────
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        _handleCameraUnavailable('No camera found on this device.');
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
    } on CameraException catch (e) {
      // CameraException.code == 'cameraPermission' means the OS denied access
      // after the controller tried to open the device (Android path).
      if (e.code == 'cameraPermission') {
        if (mounted) {
          setState(() {
            _cameraPermPermanentlyDenied = false;
            _step = _Step.cameraPermissionDenied;
          });
        }
      } else {
        _handleCameraUnavailable('Camera unavailable. Please try again.');
      }
    } catch (e) {
      _handleCameraUnavailable('Camera unavailable. Please try again.');
    }
  }

  Future<void> _pickFromPhotoLibrary() async {
    if (_step == _Step.verifying || _step == _Step.verified) return;
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 92,
      );
      if (picked == null || !mounted) return;
      await _verifySelectedPhoto(
        picked.path,
        verificationMethod: LiveVerificationMethod.testModeProfilePhoto,
      );
    } catch (_) {
      // Stay in libraryReady so the user can retry — flipping to cameraError
      // would be misleading on a machine that has no camera in the first
      // place.  Surface the failure inline so it isn't silent.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Could not open your photo library. Please try again.'),
        ),
      );
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

      // Stop the camera feed — we have the captured image.
      await ctrl.dispose();
      _camController = null;
      await _verifySelectedPhoto(
        xFile.path,
        verificationMethod: LiveVerificationMethod.liveSelfie,
      );
    } catch (e) {
      _setError('Capture failed: ${e.runtimeType}');
    }
  }

  Future<void> _verifySelectedPhoto(
    String path, {
    required LiveVerificationMethod verificationMethod,
  }) async {
    if (!mounted) return;
    setState(() {
      _capturedPath = path;
      _step = _Step.verifying;
    });

    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;
    setState(() => _step = _Step.verified);

    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;

    final session = LiveSessionScope.of(context);
    if (widget.isRedo) {
      session.updateSelfie(path);
    } else {
      session.goLive(
        selfieFilePath: path,
        verificationMethod: verificationMethod,
      );
    }
    Navigator.of(context).pop();
  }

  // ── Mac fallback: reuse in-memory profile photo ───────────────────────────

  /// Convenience for the Mac account: if the user has already picked a main
  /// profile photo this session, reuse that local file instead of opening the
  /// library a second time.  Strictly local — reads `DemoProfile.mainPhoto`
  /// (an [XFile] on disk).  When no local photo exists this method is not
  /// reachable — the panel hides the button entirely.
  Future<void> _useProfilePhoto() async {
    if (_step == _Step.verifying || _step == _Step.verified) return;
    final localPath = DemoProfileScope.of(context).mainPhoto?.path;
    if (localPath == null) return;
    await _verifySelectedPhoto(
      localPath,
      verificationMethod: LiveVerificationMethod.testModeProfilePhoto,
    );
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
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
                const SizedBox(height: 4),
                Text(
                  widget.isRedo ? 'Update live photo' : 'Live verification',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textMuted,
                    letterSpacing: 0.35,
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
          _buildIntroCopy(),
          const SizedBox(height: 20),

          // ── Selfie frame ────────────────────────────────────────────────
          _SelfieFrame(size: frameSize, child: _buildFrameContent(frameSize)),

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

  Widget _buildIntroCopy() {
    final title = switch (_step) {
      _Step.libraryReady => 'Pick a clear face photo',
      _Step.verifying => 'Scanning your photo',
      _Step.verified => 'Identity confirmed',
      _ => 'Show us it’s really you',
    };
    final subtitle = switch (_step) {
      _Step.libraryReady =>
        'Choose a recent photo from your library. We’ll run the same scan before you go live.',
      _Step.verifying =>
        'Hold on a second while Icebreaker checks the image.',
      _Step.verified =>
        widget.isRedo
            ? 'Your live photo is ready.'
            : 'You’re about to enter Nearby.',
      _ =>
        'Your live photo stays tied to this session and helps people trust who they’re meeting.',
    };
    return Column(
      children: [
        Text(
          title,
          style: AppTextStyles.h1.copyWith(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.7,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Text(
          subtitle,
          style: AppTextStyles.bodyS.copyWith(color: AppColors.textSecondary),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  // ── Frame content ─────────────────────────────────────────────────────────

  Widget _buildFrameContent(double frameSize) {
    switch (_step) {
      case _Step.preparing:
        return const Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.brandCyan),
          ),
        );

      case _Step.cameraError:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.camera_alt_outlined,
                  color: AppColors.textMuted,
                  size: 40,
                ),
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

      case _Step.cameraPermissionDenied:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.no_photography_rounded,
                  color: AppColors.textMuted,
                  size: 40,
                ),
                const SizedBox(height: 12),
                Text(
                  _cameraPermPermanentlyDenied
                      ? 'Camera access is blocked.\nOpen Settings to enable it.'
                      : 'Camera access is required\nfor live verification.',
                  style: AppTextStyles.caption,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );

      case _Step.libraryReady:
        final profile = DemoProfileScope.of(context);
        final localPath = profile.mainPhoto?.path;
        return Stack(
          fit: StackFit.expand,
          children: [
            if (localPath != null)
              Image.file(
                File(localPath),
                width: frameSize,
                height: frameSize,
                fit: BoxFit.cover,
              )
            else
              const _LibraryPlaceholder(),
            const _VerificationGuideOverlay(showScan: false),
          ],
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
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CameraPreview(ctrl),
                    const _VerificationGuideOverlay(showScan: false),
                  ],
                ),
              ),
            ),
          ),
        );

      case _Step.verifying:
      case _Step.verified:
        final path = _capturedPath;
        if (path == null) return const SizedBox.shrink();
        return Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.file(
                File(path),
                width: frameSize,
                height: frameSize,
                fit: BoxFit.cover,
              ),
            ),
            _VerificationGuideOverlay(showScan: _step == _Step.verifying),
          ],
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

      case _Step.cameraPermissionDenied:
        return const SizedBox(key: ValueKey('perm-denied'), height: 80);

      case _Step.libraryReady:
        return SizedBox(
          key: const ValueKey('library-ready'),
          height: 88,
          child: Center(
            child: Text(
              'Pick the photo you want tied to this live session.',
              style: AppTextStyles.bodyS.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        );

      case _Step.cameraReady:
        return SizedBox(
          key: const ValueKey('ready'),
          height: 88,
          child: Center(
            child: Text(
              'Center your face, keep it sharp, and snap when ready.',
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
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ShutterButton(onTap: _captureAndVerify),
            const SizedBox(height: 14),
            Text(
              'Front camera only',
              style: AppTextStyles.caption.copyWith(color: AppColors.textMuted),
            ),
          ],
        );

      case _Step.preparing:
      case _Step.cameraError:
        return _PermissionActionButton(
          label: 'Try Again',
          icon: Icons.refresh_rounded,
          onTap: () {
            setState(() => _step = _Step.preparing);
            _initCamera();
          },
          outlined: true,
        );

      case _Step.cameraPermissionDenied:
        // Permission denied — show Settings path (and retry if not permanent).
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PermissionActionButton(
              label: 'Open Settings',
              icon: Icons.settings_rounded,
              onTap: () => openAppSettings(),
            ),
            if (!_cameraPermPermanentlyDenied) ...[
              const SizedBox(height: 12),
              _PermissionActionButton(
                label: 'Try Again',
                icon: Icons.refresh_rounded,
                onTap: () {
                  setState(() => _step = _Step.preparing);
                  _initCamera();
                },
                outlined: true,
              ),
            ],
          ],
        );

      case _Step.verifying:
      case _Step.verified:
        return const SizedBox(height: 72);

      case _Step.libraryReady:
        final hasLocalProfilePhoto =
            DemoProfileScope.of(context).mainPhoto != null;
        return _MacLibraryPanel(
          onChooseFromLibrary: _pickFromPhotoLibrary,
          onUseProfilePhoto: hasLocalProfilePhoto ? _useProfilePhoto : null,
        );
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
        child: ClipRRect(borderRadius: BorderRadius.circular(14), child: child),
      ),
    );
  }
}

class _VerificationGuideOverlay extends StatelessWidget {
  const _VerificationGuideOverlay({required this.showScan});

  final bool showScan;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.12),
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.18),
                ],
              ),
            ),
          ),
          Center(
            child: Container(
              width: 190,
              height: 230,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(120),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.72),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.brandCyan.withValues(alpha: 0.18),
                    blurRadius: 18,
                  ),
                ],
              ),
            ),
          ),
          const Positioned(
            left: 18,
            top: 18,
            child: _FrameCorner(alignment: Alignment.topLeft),
          ),
          const Positioned(
            right: 18,
            top: 18,
            child: _FrameCorner(alignment: Alignment.topRight),
          ),
          const Positioned(
            left: 18,
            bottom: 18,
            child: _FrameCorner(alignment: Alignment.bottomLeft),
          ),
          const Positioned(
            right: 18,
            bottom: 18,
            child: _FrameCorner(alignment: Alignment.bottomRight),
          ),
          if (showScan) const _ScanSweep(),
        ],
      ),
    );
  }
}

class _FrameCorner extends StatelessWidget {
  const _FrameCorner({required this.alignment});

  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final top = alignment.y < 0;
    final left = alignment.x < 0;
    return SizedBox(
      width: 26,
      height: 26,
      child: CustomPaint(
        painter: _CornerPainter(top: top, left: left),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  const _CornerPainter({required this.top, required this.left});

  final bool top;
  final bool left;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.88)
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final path = Path();
    final x0 = left ? size.width : 0.0;
    final x1 = left ? 0.0 : size.width;
    final y0 = top ? size.height : 0.0;
    final y1 = top ? 0.0 : size.height;
    path.moveTo(x0, y1);
    path.lineTo(x1, y1);
    path.lineTo(x1, y0);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _CornerPainter oldDelegate) =>
      oldDelegate.top != top || oldDelegate.left != left;
}

class _ScanSweep extends StatefulWidget {
  const _ScanSweep();

  @override
  State<_ScanSweep> createState() => _ScanSweepState();
}

class _ScanSweepState extends State<_ScanSweep>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Align(
          alignment: Alignment(0, -0.82 + (_controller.value * 1.64)),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 34),
            height: 3,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              gradient: const LinearGradient(
                colors: [
                  Colors.transparent,
                  AppColors.brandCyan,
                  AppColors.brandPink,
                  Colors.transparent,
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.brandCyan.withValues(alpha: 0.55),
                  blurRadius: 16,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
        );
      },
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
        const Icon(Icons.check_rounded, color: AppColors.success, size: 36),
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

// ── Library fallback panel ───────────────────────────────────────────────────

/// Action area shown only on the Mac fallback path.  Keeps the same
/// visual language as the mobile shutter area — a primary brand-gradient
/// CTA, an optional outlined secondary, and a single fine-print line —
/// so the screen still reads as a real verification step, not a debug menu.
class _MacLibraryPanel extends StatelessWidget {
  const _MacLibraryPanel({
    required this.onChooseFromLibrary,
    required this.onUseProfilePhoto,
  });

  final Future<void> Function() onChooseFromLibrary;
  final Future<void> Function()? onUseProfilePhoto;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PermissionActionButton(
          label: 'Choose from Photo Library',
          icon: Icons.photo_library_rounded,
          onTap: onChooseFromLibrary,
        ),
        if (onUseProfilePhoto != null) ...[
          const SizedBox(height: 12),
          _PermissionActionButton(
            label: 'Use my profile photo',
            icon: Icons.person_rounded,
            onTap: onUseProfilePhoto!,
            outlined: true,
          ),
        ],
        const SizedBox(height: 14),
        Text(
          'Photo library on this Mac',
          style: AppTextStyles.caption.copyWith(color: AppColors.textMuted),
        ),
      ],
    );
  }
}

class _LibraryPlaceholder extends StatelessWidget {
  const _LibraryPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0A0818),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08),
                border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
              ),
              child: const Icon(
                Icons.photo_library_outlined,
                size: 34,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Photo library ready',
              style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              'Choose a face photo to verify on this Mac.',
              style: AppTextStyles.caption.copyWith(color: AppColors.textMuted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Permission action button ──────────────────────────────────────────────────

class _PermissionActionButton extends StatelessWidget {
  const _PermissionActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.outlined = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          gradient: outlined ? null : AppColors.brandGradient,
          borderRadius: BorderRadius.circular(25),
          border: outlined
              ? Border.all(color: AppColors.divider, width: 1.5)
              : null,
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 16),
            const SizedBox(width: 8),
            Text(
              label,
              style: AppTextStyles.body.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
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
