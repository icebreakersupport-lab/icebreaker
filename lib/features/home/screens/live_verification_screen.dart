import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/dev/dev_account_gate.dart';
import '../../../core/models/live_session_model.dart';
import '../../../core/services/camera_service.dart';
import '../../../core/state/user_profile.dart';
import '../../../core/state/live_session.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/live_avatar_crop.dart';

// ── Step enum ────────────────────────────────────────────────────────────────

enum _Step {
  preparing,
  cameraReady,
  cameraError,
  cameraPermissionDenied,
  libraryReady,
  // After shutter (or library pick): captured image stays in the frame while
  // the square-avatar crop derivation and the authoritative go-live batch run
  // in series.  No theatrical delay — the screen looks the same as the
  // moment of capture, just with the shutter hidden and the back button
  // disabled, so the user does not perceive a separate "verifying" screen.
  submitting,
  // The captured selfie was accepted locally, but the authoritative go-live
  // batch (live_sessions write + users mirror update + verification audit)
  // failed.  We stay on this screen with the captured image preserved so
  // the user can retry without re-capturing — the alternative (popping to
  // Home) would silently drop the user onto the non-live UI even though
  // their photo capture was fine.
  goLiveFailed,
}

/// Live-selfie capture + verification screen.
///
/// Flow:
///   camera ready → tap shutter → submitting (avatar crop + goLive write)
///   → pop on success, or → goLiveFailed → retry.
///   Redo path is identical except the submitting step calls
///   [LiveSession.updateSelfie] and pops immediately.
///
/// Capture source:
///   • iPhone / Android  → front camera, always.  No library fallback.
///   • macOS, but only when [macLibraryFallbackForThisAccount] returns true →
///     photo library, because that machine has no camera.  The submitting
///     step runs identically after the image is chosen.
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

class _LiveVerificationScreenState extends State<LiveVerificationScreen>
    with WidgetsBindingObserver {
  _Step _step = _Step.preparing;
  CameraController? _camController;
  final ImagePicker _picker = ImagePicker();
  String? _capturedPath;
  String? _errorMessage;

  /// Square-cropped avatar derived from [_capturedPath].  Held on state so
  /// the [goLiveFailed] retry path can re-submit without re-deriving.
  String? _capturedAvatarPath;

  /// Verification method used for the captured selfie — held on state for
  /// the same retry reason.
  LiveVerificationMethod? _capturedMethod;

  /// Re-entrancy guard for [_submitGoLive].  Stops a fast double-tap on
  /// "Try Again" from issuing two concurrent goLive writes (which would
  /// race the in-memory rollback in [LiveSession.goLive] on failure).
  bool _isSubmitting = false;

  /// True when the active [_camController] is bound to a front-facing lens.
  /// Drives the preview-only un-mirror transform so the live preview matches
  /// the un-mirrored sensor orientation that `takePicture()` writes to disk
  /// — see [_buildFrameContent] for the policy and rationale.  Defaults to
  /// false so a non-front fallback (rear lens, no front available) renders
  /// the preview untransformed.
  bool _isFrontCamera = false;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _useMacLibraryFallback = macLibraryFallbackForThisAccount();
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _camController?.dispose();
    super.dispose();
  }

  /// Re-checks camera permission when the app returns to the foreground —
  /// closes the recovery loop after the user opens system Settings from the
  /// blocked-permission step, toggles Camera on, and swipes back.  Without
  /// this, the screen would still read "Camera access is blocked" until the
  /// user manually taps Try Again.
  ///
  /// Intentionally narrow: only acts when the screen is currently parked on
  /// the permission-denied step.  Other steps (cameraReady, submitting,
  /// libraryReady, cameraError) should not be perturbed by a
  /// background/foreground cycle — re-running [_initCamera] from cameraReady
  /// would leak the live controller; re-running from cameraError would
  /// silently mask a hardware-level failure.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (_step != _Step.cameraPermissionDenied) return;
    _recheckPermissionAfterResume();
  }

  /// Re-runs [_initCamera] when the app returns to the foreground while the
  /// screen is parked on the permission-denied step.  Deliberately does NOT
  /// pre-check `permission_handler` first: on iOS, `Permission.camera.status`
  /// can disagree with the `camera` plugin's AVFoundation authorization read
  /// (the user can have a working camera elsewhere in the app while
  /// permission_handler still reports `permanentlyDenied`).  Letting the
  /// camera plugin be the source of truth — the same way the profile
  /// camera-capture screen does — is what makes recovery actually work.
  Future<void> _recheckPermissionAfterResume() async {
    if (!mounted) return;
    setState(() => _step = _Step.preparing);
    _initCamera();
  }

  // ── Camera ────────────────────────────────────────────────────────────────

  /// Latest camera permission status — drives the action area copy on the
  /// permission-denied step.  Null only during the first read.
  CameraStatus? _cameraStatus;

  /// Cached at `initState` so the gate can't change mid-session if the user
  /// signs out from another tab, etc.  Read-only after init.
  late final bool _useMacLibraryFallback;

  /// True when running inside the iOS Simulator (Xcode sets the
  /// `SIMULATOR_DEVICE_NAME` env var).  Used purely to make the
  /// "no camera hardware" copy honest about why the camera can't open —
  /// the simulator exposes the permission API but never exposes a camera
  /// device, so a granted permission still lands the user on the
  /// no-hardware path.
  static bool get _isIosSimulator =>
      !kIsWeb &&
      Platform.isIOS &&
      Platform.environment.containsKey('SIMULATOR_DEVICE_NAME');

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

  /// Camera initialization, aligned with the working profile-camera flow
  /// (`camera_capture_screen.dart`): the `camera` plugin itself is the
  /// source of truth.  We do NOT pre-gate on `permission_handler` —
  /// `Permission.camera.status` on iOS can disagree with the AVFoundation
  /// authorization the camera plugin actually reads, so a working camera
  /// elsewhere in the app could still cause this screen to show "blocked"
  /// if we trusted permission_handler first.
  ///
  /// Order of operations:
  ///   0. Mac library fallback (preserved exemption).
  ///   1. iOS Simulator fast-path (no hardware regardless of permission).
  ///   2. Non-mobile, non-fallback platforms — explicit unavailable.
  ///   3. `availableCameras()` + `CameraController.initialize()`.
  ///       On iOS this triggers the system prompt on first launch and
  ///       throws on denial.  On success we are unambiguously granted.
  ///   4. Classify the failure.  Permission-shaped exceptions move to the
  ///       perm-denied step; permission_handler is consulted *only here*,
  ///       and only to pick the right CTA copy (Allow vs Open Settings).
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

    if (_isIosSimulator) {
      _handleCameraUnavailable(
        'iPhone Simulator has no camera.\nRun on a real device to verify.',
      );
      return;
    }

    if (kIsWeb || !(Platform.isIOS || Platform.isAndroid)) {
      _handleCameraUnavailable(
          'Camera capture is not available on this platform.');
      return;
    }

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        _handleCameraUnavailable('No camera detected on this device.');
        return;
      }

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
        _isFrontCamera = desc.lensDirection == CameraLensDirection.front;
        _cameraStatus = CameraStatus.granted;
        _step = _Step.cameraReady;
      });
    } on CameraException catch (e) {
      if (_isPermissionException(e)) {
        // Camera plugin rejected for permission reasons.  Now — and only
        // now — ask permission_handler what CTA to render.  If it agrees
        // we're requestable, offer the in-app prompt; for anything else
        // (including the iOS divergence where permission_handler reports
        // granted but AVFoundation just denied), route to Open Settings,
        // which is the only path that actually moves the needle.
        final fresh = await CameraPermissionService.currentStatus();
        if (!mounted) return;
        final uiStatus = fresh == CameraStatus.requestable
            ? CameraStatus.requestable
            : CameraStatus.blockedForever;
        setState(() {
          _cameraStatus = uiStatus;
          _step = _Step.cameraPermissionDenied;
        });
      } else {
        _handleCameraUnavailable('Camera unavailable. Please try again.');
      }
    } catch (e) {
      _handleCameraUnavailable('Camera unavailable. Please try again.');
    }
  }

  /// Identifies [CameraException]s that mean the OS withheld camera access,
  /// as opposed to a hardware / configuration failure.  Covers the codes
  /// emitted by both the iOS (`camera_avfoundation`) and Android
  /// (`camera_android_camerax`) implementations of the `camera` plugin.
  static bool _isPermissionException(CameraException e) {
    switch (e.code) {
      case 'CameraAccessDenied':
      case 'CameraAccessDeniedWithoutPrompt':
      case 'CameraAccessRestricted':
      case 'cameraPermission':
        return true;
      default:
        return false;
    }
  }

  Future<void> _pickFromPhotoLibrary() async {
    if (_step == _Step.submitting) return;
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

      // Critical lifecycle ordering — DO NOT REORDER.
      //
      // 1) Leave _Step.cameraReady and clear _camController in the SAME
      //    setState as seeding the captured state.  After this frame the
      //    build tree no longer contains `CameraPreview(ctrl)`, so any
      //    subsequent listener fire from the controller's teardown cannot
      //    paint a disposed controller.
      // 2) ONLY THEN dispose the local `ctrl` reference.  Done as
      //    fire-and-forget — awaiting here would yield to the event loop
      //    while CameraPreview could still be in the tree on slower
      //    rebuild paths, and `dispose()` doesn't surface errors we'd act
      //    on.
      // 3) Continue into the shared submit logic via [_continueSubmit],
      //    which skips the seeding setState that [_verifySelectedPhoto]
      //    would otherwise run for non-camera entry points.
      //
      // The earlier ordering (`await ctrl.dispose(); _camController = null;
      // await _verifySelectedPhoto(...)`) left _step on cameraReady through
      // the disposal await, which is when the red "Disposed CameraController,
      // buildPreview() was called on a disposed CameraController" frame
      // landed.
      setState(() {
        _capturedPath = xFile.path;
        _capturedAvatarPath = null;
        _capturedMethod = LiveVerificationMethod.liveSelfie;
        _errorMessage = null;
        _step = _Step.submitting;
        _camController = null;
      });

      unawaited(ctrl.dispose());

      await _continueSubmit(
        xFile.path,
        verificationMethod: LiveVerificationMethod.liveSelfie,
      );
    } catch (e) {
      _setError('Capture failed: ${e.runtimeType}');
    }
  }

  /// Library / profile-photo entry point.  No camera controller exists on
  /// these paths, so the seed-then-dispose dance from [_captureAndVerify]
  /// does not apply — we can seed `_step = submitting` here and forward to
  /// the shared submit logic in [_continueSubmit].
  Future<void> _verifySelectedPhoto(
    String path, {
    required LiveVerificationMethod verificationMethod,
  }) async {
    if (!mounted) return;
    setState(() {
      _capturedPath = path;
      _capturedAvatarPath = null;
      _capturedMethod = verificationMethod;
      _errorMessage = null;
      _step = _Step.submitting;
    });
    await _continueSubmit(path, verificationMethod: verificationMethod);
  }

  /// Shared submit logic used by both the camera and library paths.  Assumes
  /// `_step` is already [_Step.submitting] and `_capturedPath` /
  /// `_capturedMethod` have been seeded — the camera path seeds those in the
  /// same setState that nulls `_camController` (so disposal cannot race a
  /// rebuild on `_Step.cameraReady`); the library path seeds them in
  /// [_verifySelectedPhoto].
  Future<void> _continueSubmit(
    String path, {
    required LiveVerificationMethod verificationMethod,
  }) async {
    // Derive the square avatar crop synchronously with the submit step.  No
    // artificial hold: the captured image stays in the frame, the shutter is
    // hidden, and the user sees a subtle inline indicator while the (typically
    // <100 ms) crop runs and the goLive batch is awaited.  The raw portrait
    // remains the source of truth for the verification frame; the derived
    // crop is what circular avatar surfaces fill from.
    final avatarPath = await deriveSquareAvatar(path);
    if (!mounted) return;
    _capturedAvatarPath = avatarPath;

    // Redo: the in-memory selfie/avatar swap is what Home reads, and the
    // durable redo write inside [LiveSession.updateSelfie] is fire-and-forget
    // (it does not change presence state).  Failure there does not put the
    // user on the wrong screen, so we can pop immediately.
    if (widget.isRedo) {
      final session = LiveSessionScope.of(context);
      session.updateSelfie(
        path,
        avatarPath: avatarPath,
        verificationMethod: verificationMethod,
      );
      Navigator.of(context).pop();
      return;
    }

    // Initial go-live: must NOT pop until the LiveSession has actually
    // published the live-state flip.  [LiveSession.goLive] awaits a
    // discovery-snapshot read BEFORE flipping `_isLive = true`, so popping
    // immediately would rebuild Home against the pre-flip state and land
    // the user on the non-live UI.  Awaiting here guarantees Home only
    // rebuilds once, with `isLive == true`.
    await _submitGoLive();
  }

  /// Awaits the authoritative go-live write and pops on success.  On
  /// failure, transitions to [_Step.goLiveFailed] so the user can retry
  /// without re-capturing — the captured selfie path / avatar / method are
  /// preserved on state.
  ///
  /// Reused by the retry button on [_Step.goLiveFailed].  Re-entrancy is
  /// guarded by [_isSubmitting].
  Future<void> _submitGoLive() async {
    if (_isSubmitting) return;
    final path = _capturedPath;
    final method = _capturedMethod;
    if (path == null || method == null) return;
    _isSubmitting = true;

    if (mounted && _step != _Step.submitting) {
      setState(() {
        _step = _Step.submitting;
        _errorMessage = null;
      });
    }

    final session = LiveSessionScope.of(context);
    try {
      await session.goLive(
        selfieFilePath: path,
        avatarFilePath: _capturedAvatarPath,
        verificationMethod: method,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e, st) {
      // Log the real exception so the failure mode is diagnosable.  A
      // generic "check your connection" hid the real cause for too long
      // when the new verificationAttempts rule wasn't deployed yet.
      debugPrint('[LiveVerificationScreen] goLive failed: $e\n$st');
      if (!mounted) return;
      setState(() {
        _step = _Step.goLiveFailed;
        _errorMessage = _messageForGoLiveError(e);
      });
    } finally {
      _isSubmitting = false;
    }
  }

  /// Maps the exception thrown by [LiveSession.goLive] to user-facing copy.
  /// The Firebase code is also surfaced when known, so a real failure is
  /// distinguishable from a generic "try again" — particularly important
  /// for `permission-denied`, which usually means a Firestore rule has not
  /// been deployed.
  static String _messageForGoLiveError(Object e) {
    if (e is FirebaseException) {
      switch (e.code) {
        case 'permission-denied':
          return "Couldn't go live: permission denied. The app may need an "
              'update or the server rules are not yet deployed.';
        case 'unavailable':
        case 'deadline-exceeded':
        case 'cancelled':
          return "Couldn't reach the server. Check your connection and try "
              'again.';
        case 'failed-precondition':
          return "Couldn't go live: server precondition failed. Try again "
              'in a moment.';
        case 'unauthenticated':
          return 'Your session expired. Sign in again and retry.';
        default:
          return "Couldn't go live (${e.code}). Try again.";
      }
    }
    return "Couldn't go live. Check your connection and try again.";
  }

  // ── Mac fallback: reuse in-memory profile photo ───────────────────────────

  /// Convenience for the Mac account: if the user has already picked a main
  /// profile photo this session, reuse that local file instead of opening the
  /// library a second time.  Strictly local — reads `UserProfile.mainPhoto`
  /// (an [XFile] on disk).  When no local photo exists this method is not
  /// reachable — the panel hides the button entirely.
  Future<void> _useProfilePhoto() async {
    if (_step == _Step.submitting) return;
    final localPath = UserProfileScope.of(context).mainPhoto?.path;
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
            onTap: _step == _Step.submitting
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final mq = MediaQuery.of(context).size;
        final isTightHeight = constraints.maxHeight < 760;
        // Shrink the square frame a bit on shorter phone layouts so the
        // permission / no-camera states do not overflow vertically.
        final frameHeightFactor = isTightHeight ? 0.42 : 0.48;
        final frameSize = (mq.width - 40).clamp(0.0, mq.height * frameHeightFactor);

        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              children: [
                const SizedBox(height: 8),
                _buildIntroCopy(),
                SizedBox(height: isTightHeight ? 16 : 20),

                // ── Selfie frame ──────────────────────────────────────────
                _SelfieFrame(size: frameSize, child: _buildFrameContent(frameSize)),

                SizedBox(height: isTightHeight ? 20 : 28),

                // ── Status section ────────────────────────────────────────
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: _buildStatusSection(),
                ),

                SizedBox(height: isTightHeight ? 20 : 28),

                // ── Action area ───────────────────────────────────────────
                _buildActionArea(),

                const SizedBox(height: 36),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildIntroCopy() {
    final title = switch (_step) {
      _Step.libraryReady => 'Pick a clear face photo',
      _Step.submitting =>
        widget.isRedo ? 'Updating your live photo' : 'Going live',
      _Step.cameraError => 'Camera unavailable',
      _Step.goLiveFailed => "Couldn't go live",
      _ => 'Show us it’s really you',
    };
    final subtitle = switch (_step) {
      _Step.libraryReady =>
        'Choose a recent photo from your library. We’ll use it for this live session.',
      _Step.submitting => 'Hang tight…',
      _Step.cameraError => _isIosSimulator
          ? 'iPhone Simulator has no camera. Run on a real iPhone or Android device to verify.'
          : 'We couldn’t start the camera on this device. This isn’t a permission issue — try again, or restart Icebreaker.',
      _Step.goLiveFailed => _errorMessage ??
          "We couldn't go live. Check your connection and try again.",
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
                  _cameraStatus == CameraStatus.blockedForever
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
        final profile = UserProfileScope.of(context);
        final localPath = profile.mainPhoto?.path;
        return Stack(
          fit: StackFit.expand,
          children: [
            if (localPath != null)
              ColoredBox(
                color: const Color(0xFF05000E),
                child: Image.file(
                  File(localPath),
                  width: frameSize,
                  height: frameSize,
                  fit: BoxFit.contain,
                ),
              )
            else
              const _LibraryPlaceholder(),
            const _VerificationGuideOverlay(),
          ],
        );

      case _Step.cameraReady:
        final ctrl = _camController;
        if (ctrl == null || !ctrl.value.isInitialized) {
          return const SizedBox.shrink();
        }
        // The `camera` plugin reports `value.aspectRatio` as the SENSOR's
        // native aspect (`previewSize.width / previewSize.height`), which on
        // iOS is always the landscape orientation of the sensor (e.g.,
        // 1920x1080 → 1.78) regardless of the device orientation in which
        // it is displayed.  In a portrait UI the `CameraPreview` widget
        // paints rotated portrait content, so to lay it out at the correct
        // displayed aspect we need the inverse: 1080/1920 = 0.5625, i.e.
        // `1 / ctrl.value.aspectRatio`.  Using `aspectRatio` directly is
        // what produced the squat-horizontal band with large top/bottom
        // bars — `AspectRatio` was being asked to make a 1.78-wide box
        // inside a square, so it shrank vertically to fit width.
        //
        // Square framing is preserved (`_SelfieFrame` is still square).
        // Letterbox bars sit on the LEFT and RIGHT, in the same near-black
        // as the screen background, so the gradient frame still reads as a
        // single composed surface.
        //
        // ── Front-camera orientation policy ────────────────────────────
        // The Flutter `camera` plugin renders front-camera output in a
        // mirrored "selfie convention" (what you'd see in a real mirror)
        // while `takePicture()` writes the un-mirrored sensor frame to
        // disk.  That two-track behavior is the source of the horizontal
        // flip surprise on shutter press: preview shows mirrored, the
        // saved file (and every downstream avatar/Nearby/profile surface
        // built from it) shows un-mirrored.  See flutter/flutter#108745
        // (iOS) and #156974 (Android regressions).
        //
        // The captured file is canonical — `deriveSquareAvatar` and every
        // live-selfie consumer (Nearby `_LiveSelfieFrame`, profile photo
        // strip, [LiveSelfieCircleImage]) paint it untransformed.  So we
        // un-mirror the preview to match the file rather than mirroring
        // every downstream surface to match the preview.  One rule, one
        // place: a horizontal flip applied to the live preview only, and
        // only when the active lens is front-facing.
        final displayAspect = ctrl.value.aspectRatio <= 0
            ? 1.0
            : 1 / ctrl.value.aspectRatio;
        Widget preview = CameraPreview(ctrl);
        if (_isFrontCamera) {
          preview = Transform.flip(flipX: true, child: preview);
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Color(0xFF05000E)),
            Center(
              child: AspectRatio(
                aspectRatio: displayAspect,
                child: preview,
              ),
            ),
            const _VerificationGuideOverlay(),
          ],
        );

      case _Step.submitting:
      case _Step.goLiveFailed:
        final path = _capturedPath;
        if (path == null) return const SizedBox.shrink();
        // Match the live-preview composition exactly: BoxFit.contain on the
        // captured file, with the same dark fill behind, so the transition
        // from `cameraReady` → `submitting` doesn't visually re-crop the
        // image.  Parent `_SelfieFrame` already provides the rounded clip,
        // so no inner ClipRRect is needed.  No scan sweep — capturing the
        // photo is the meaningful event, and the goLive batch is fast
        // enough that an animated overlay would feel like a fake hold.
        return Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: const Color(0xFF05000E),
              child: Image.file(File(path), fit: BoxFit.contain),
            ),
            const _VerificationGuideOverlay(),
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
              _isIosSimulator
                  ? 'Live verification needs real camera hardware.'
                  : 'If this keeps happening, restart Icebreaker.',
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

      case _Step.submitting:
        return SizedBox(
          key: const ValueKey('submitting'),
          height: 88,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(AppColors.brandCyan),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  widget.isRedo ? 'Updating…' : 'Going live…',
                  style: AppTextStyles.bodyS.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        );

      case _Step.goLiveFailed:
        return SizedBox(
          key: const ValueKey('go-live-failed'),
          height: 88,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  color: AppColors.textSecondary,
                  size: 28,
                ),
                const SizedBox(height: 8),
                Text(
                  'Tap Try Again to retry going live.',
                  style: AppTextStyles.bodyS.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
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
        // Branch on the unified status:
        //   requestable    → "Allow Camera" (in-app OS prompt) — avoids the
        //                    iOS dead-end where Settings has no Camera row
        //                    yet because the prompt was never shown.
        //   blockedForever → "Open Settings" + "Try Again" (recovery requires
        //                    the system Settings page).
        if (_cameraStatus == CameraStatus.requestable) {
          return _PermissionActionButton(
            label: 'Allow Camera',
            icon: Icons.camera_alt_outlined,
            onTap: () {
              setState(() => _step = _Step.preparing);
              _initCamera();
            },
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PermissionActionButton(
              label: 'Open Settings',
              icon: Icons.settings_rounded,
              onTap: () => CameraPermissionService.openSettings(),
            ),
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
        );

      case _Step.submitting:
        return const SizedBox(height: 72);

      case _Step.goLiveFailed:
        return _PermissionActionButton(
          label: 'Try Again',
          icon: Icons.refresh_rounded,
          onTap: () {
            _submitGoLive();
          },
        );

      case _Step.libraryReady:
        final hasLocalProfilePhoto =
            UserProfileScope.of(context).mainPhoto != null;
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
  const _VerificationGuideOverlay();

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
