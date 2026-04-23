import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/gradient_scaffold.dart';
import '../../../shared/widgets/pill_button.dart';

// ─── Local settings model ─────────────────────────────────────────────────────

/// Settings subset of users/{uid}.  All fields default to sane values so
/// the screen is usable even on a brand-new account that has never saved
/// preferences.
class _UserSettings {
  _UserSettings({
    this.showMe = 'everyone',
    this.ageRangeMin = 18,
    this.ageRangeMax = 35,
    this.maxDistanceMeters = 30,
    this.discoverable = true,
    this.photosToMatchesOnly = false,
    this.doNotDisturb = false,
    this.subscriptionTier = 'free',
    this.notifIcebreakers = true,
    this.notifMessages = true,
    this.notifMatchConfirmed = true,
    this.notifSession = true,
  });

  // ── Discovery ──────────────────────────────────────────────────────────────

  /// Firestore field: showMe. 'everyone' | 'men' | 'women' | 'non_binary'
  String showMe;

  /// Firestore fields: ageRangeMin, ageRangeMax.
  int ageRangeMin;
  int ageRangeMax;

  /// Firestore field: maxDistanceMeters.
  /// Range: 30–60 m.  Lower end matches the physical detection radius; upper
  /// end lets users see further when conditions allow.
  int maxDistanceMeters;

  /// Firestore field: discoverable.
  /// When false, the user is hidden from all Nearby discovery results even
  /// while live.  Defaults to true.  Does not prevent the user from going
  /// live or receiving icebreakers from people who already know their UID.
  bool discoverable;

  // ── Privacy ────────────────────────────────────────────────────────────────

  /// Firestore field: photosToMatchesOnly.
  bool photosToMatchesOnly;

  /// Firestore field: doNotDisturb.
  /// Silences chat/message push notifications while the user is NOT live.
  /// Auto-cleared to false by LiveSession.goLive() when a session starts.
  /// Has no effect on discovery — discoverability is governed by live session
  /// state only (isLive in users/{uid}, set/unset by the session flow).
  bool doNotDisturb;

  // ── Account ────────────────────────────────────────────────────────────────

  /// Read from Firestore 'plan' field.  Not mutated here — use Shop screen.
  String subscriptionTier;

  // ── Notifications ──────────────────────────────────────────────────────────
  // Firestore fields: notifIcebreakers, notifMessages, notifMatchConfirmed,
  // notifSession.
  // TODO: FCM token topic subscription/unsubscription needed for these to
  // actually suppress push notifications.  Preferences are persisted now so
  // the Cloud Function can gate sends once FCM is wired.
  bool notifIcebreakers;
  bool notifMessages;
  bool notifMatchConfirmed;
  bool notifSession;

  factory _UserSettings.fromFirestore(Map<String, dynamic> data) {
    return _UserSettings(
      showMe: (data['showMe'] as String?) ?? 'everyone',
      ageRangeMin: (data['ageRangeMin'] as num?)?.toInt() ?? 18,
      ageRangeMax: (data['ageRangeMax'] as num?)?.toInt() ?? 35,
      maxDistanceMeters:
          ((data['maxDistanceMeters'] as num?)?.toInt() ?? 30).clamp(30, 60),
      discoverable: (data['discoverable'] as bool?) ?? true,
      photosToMatchesOnly: (data['photosToMatchesOnly'] as bool?) ?? false,
      doNotDisturb: (data['doNotDisturb'] as bool?) ?? false,
      subscriptionTier: (data['plan'] as String?) ?? 'free',
      notifIcebreakers: (data['notifIcebreakers'] as bool?) ?? true,
      notifMessages: (data['notifMessages'] as bool?) ?? true,
      notifMatchConfirmed: (data['notifMatchConfirmed'] as bool?) ?? true,
      notifSession: (data['notifSession'] as bool?) ?? true,
    );
  }
}

// ─── Label / colour helpers ───────────────────────────────────────────────────

String _showMeLabel(String v) => switch (v) {
      'men' => 'Men',
      'women' => 'Women',
      'non_binary' => 'Non-binary',
      _ => 'Everyone',
    };

String _tierLabel(String tier) => switch (tier) {
      'plus' => 'Plus',
      'gold' => 'Gold',
      _ => 'Free',
    };

Color _tierColor(String tier) => switch (tier) {
      'plus' => AppColors.brandCyan,
      'gold' => AppColors.warning,
      _ => AppColors.textMuted,
    };

// ─── SettingsScreen ───────────────────────────────────────────────────────────

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  _UserSettings? _settings;
  bool _loadError = false;

  /// True while sendEmailVerification() is in flight.
  bool _emailSending = false;

  /// True after a verification email was sent this session — changes CTA copy
  /// from "Tap to send" to "Check your inbox — tap to resend".
  bool _emailJustSent = false;

  /// Seconds remaining on the client-side resend cooldown.
  /// Prevents spam-tapping that triggers Firebase too-many-requests.
  /// Starts at 60 after a successful send, or after a too-many-requests error.
  int _emailCooldownSeconds = 0;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cooldownTimer?.cancel();
    super.dispose();
  }

  /// Starts (or restarts) a countdown that disables the resend button for
  /// [seconds] seconds. Prevents rapid re-sends that trigger Firebase
  /// too-many-requests.
  void _startEmailCooldown(int seconds) {
    _cooldownTimer?.cancel();
    setState(() => _emailCooldownSeconds = seconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _emailCooldownSeconds--;
        if (_emailCooldownSeconds <= 0) {
          _emailCooldownSeconds = 0;
          t.cancel();
        }
      });
    });
  }

  /// On app resume, reload the Firebase Auth user so [emailVerified] reflects
  /// any verification the user completed outside the app (e.g. clicking the
  /// link in their inbox).  Then rebuild so the row updates immediately, and
  /// surface a confirmation snackbar if verification just flipped to true.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final beforeVerified =
          FirebaseAuth.instance.currentUser?.emailVerified ?? false;
      FirebaseAuth.instance.currentUser
          ?.reload()
          .then((_) {
            if (!mounted) return;
            final afterVerified =
                FirebaseAuth.instance.currentUser?.emailVerified ?? false;
            setState(() {});
            if (!beforeVerified && afterVerified) {
              debugPrint('[verifyEmail] ✅ flipped to verified on resume');
              _cooldownTimer?.cancel();
              _emailCooldownSeconds = 0;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Email verified — you\'re all set.'),
                ),
              );
            }
          })
          .catchError((Object e) {
            debugPrint('[Settings] user reload failed: $e');
            return null;
          });
    }
  }

  /// Reloads the current user and refreshes the UI.  Used by the explicit
  /// "Refresh status" action so the user can confirm a clicked link without
  /// having to background-and-foreground the app.
  Future<void> _refreshVerificationStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final before = user.emailVerified;
    debugPrint('[verifyEmail] refresh-status: before=$before');
    try {
      await user.reload();
      final fresh = FirebaseAuth.instance.currentUser;
      final after = fresh?.emailVerified ?? false;
      debugPrint('[verifyEmail] refresh-status: after=$after');
      if (!mounted) return;
      setState(() {});
      if (!before && after) {
        _cooldownTimer?.cancel();
        _emailCooldownSeconds = 0;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Email verified — you\'re all set.'),
          ),
        );
      } else if (!after) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Not verified yet. Open the link in your inbox, then try again.'),
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      debugPrint('[verifyEmail] refresh-status failed:'
          '\n  code=${e.code}'
          '\n  message=${e.message}');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.code == 'network-request-failed'
                ? 'No network connection. Check your connection and try again.'
                : 'Could not refresh status (${e.code}).',
          ),
        ),
      );
    }
  }

  // ── Firestore I/O ──────────────────────────────────────────────────────────

  Future<void> _loadSettings() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _loadError = true);
      return;
    }
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      if (!mounted) return;
      setState(() => _settings = snap.exists
          ? _UserSettings.fromFirestore(snap.data()!)
          : _UserSettings());
    } catch (e) {
      debugPrint('[Settings] load failed: $e');
      if (mounted) setState(() => _loadError = true);
    }
  }

  /// Optimistic single-field persist.  Shows a snackbar only on write failure.
  void _save(String field, dynamic value) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .update({field: value}).catchError((Object e) {
      debugPrint('[Settings] save $field failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save. Please try again.')),
        );
      }
    });
  }

  /// Optimistic multi-field persist.
  void _saveAll(Map<String, dynamic> fields) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .update(fields).catchError((Object e) {
      debugPrint('[Settings] saveAll failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save. Please try again.')),
        );
      }
    });
  }

  // ── Email verification ─────────────────────────────────────────────────────

  /// Sends a Firebase verification email to the current user's address.
  ///
  /// Guards:
  ///   • Already verified → no-op (button should be hidden by then, but safe).
  ///   • Already sending → no-op (prevents double-tap).
  ///
  /// On success: sets [_emailJustSent] so subtitle changes to "Check your
  /// inbox — tap to resend" until the screen is disposed or email is verified.
  /// On failure: shows a snackbar; does not set [_emailJustSent].
  Future<void> _sendVerificationEmail() async {
    final user = FirebaseAuth.instance.currentUser;

    // ── Pre-flight diagnostics ─────────────────────────────────────────────
    debugPrint('[verifyEmail] pre-flight:'
        '\n  uid=${user?.uid}'
        '\n  email=${user?.email}'
        '\n  emailVerified=${user?.emailVerified}'
        '\n  isAnonymous=${user?.isAnonymous}');

    if (user == null || user.emailVerified || _emailSending) return;

    if (user.email == null || user.email!.isEmpty) {
      debugPrint('[verifyEmail] no email address on account — cannot send');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No email address found on your account.'),
          ),
        );
      }
      return;
    }

    setState(() => _emailSending = true);

    try {
      // Reload first so the auth token is fresh — a stale token causes
      // sendEmailVerification to fail with user-token-expired.
      await user.reload();

      // Re-read currentUser after reload: reload() can replace the instance
      // internally, making the old reference stale.
      final freshUser = FirebaseAuth.instance.currentUser;
      debugPrint('[verifyEmail] after reload:'
          '\n  freshUser=${freshUser?.uid}'
          '\n  emailVerified=${freshUser?.emailVerified}');

      if (freshUser == null) {
        debugPrint('[verifyEmail] user is null after reload — session ended');
        if (mounted) setState(() => _emailSending = false);
        return;
      }

      if (freshUser.emailVerified) {
        // Verified while we reloaded — update UI without sending.
        debugPrint('[verifyEmail] already verified after reload');
        if (mounted) setState(() => _emailSending = false);
        return;
      }

      await freshUser.sendEmailVerification();
      debugPrint('[verifyEmail] ✅ sent to ${freshUser.email}');

      if (mounted) {
        setState(() {
          _emailSending = false;
          _emailJustSent = true;
        });
        // 60-second cooldown prevents rapid re-sends.
        _startEmailCooldown(60);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Email sent to ${freshUser.email} — check your inbox (and spam folder)',
            ),
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      // Log the exact Firebase error code so we can diagnose it.
      debugPrint('[verifyEmail] ❌ FirebaseAuthException:'
          '\n  code=${e.code}'
          '\n  message=${e.message}');
      if (mounted) {
        setState(() => _emailSending = false);
        final msg = switch (e.code) {
          'too-many-requests' =>
            'Firebase temporarily blocked this device. Wait a few minutes before trying again.',
          'user-token-expired' || 'invalid-user-token' =>
            'Session expired — please sign out and sign back in.',
          'network-request-failed' =>
            'No network connection. Check your connection and try again.',
          _ =>
            'Could not send verification email (${e.code}). Please try again.',
        };
        // On too-many-requests, impose the same 60-second client-side cooldown
        // to stop the user hammering the button further.
        if (e.code == 'too-many-requests') _startEmailCooldown(60);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      }
    } catch (e, st) {
      debugPrint('[verifyEmail] ❌ unexpected error: $e\n$st');
      if (mounted) {
        setState(() => _emailSending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unexpected error. Please try again.')),
        );
      }
    }
  }

  // ── Pickers ────────────────────────────────────────────────────────────────

  void _showShowMePicker() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _ShowMePicker(
        current: _settings!.showMe,
        onSelected: (value) {
          // Picker closes itself before calling this.
          setState(() => _settings!.showMe = value);
          _save('showMe', value);
        },
      ),
    );
  }

  void _showAgeRangePicker() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _AgeRangePicker(
        initialMin: _settings!.ageRangeMin.toDouble(),
        initialMax: _settings!.ageRangeMax.toDouble(),
        onSaved: (min, max) {
          // Picker closes itself before calling this.
          setState(() {
            _settings!.ageRangeMin = min.round();
            _settings!.ageRangeMax = max.round();
          });
          _saveAll({'ageRangeMin': min.round(), 'ageRangeMax': max.round()});
        },
      ),
    );
  }

  void _showMaxDistancePicker() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _MaxDistancePicker(
        initialValue: _settings!.maxDistanceMeters.toDouble(),
        onSaved: (value) {
          // Picker closes itself before calling this.
          setState(() => _settings!.maxDistanceMeters = value.round());
          _save('maxDistanceMeters', value.round());
        },
      ),
    );
  }

  // ── Auth dialogs ───────────────────────────────────────────────────────────

  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgElevated,
        title: Text('Log out?',
            style: AppTextStyles.h3.copyWith(color: AppColors.textPrimary)),
        content: Text(
          'You will need to sign back in to use Icebreaker.',
          style: AppTextStyles.bodyS,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel',
                style:
                    AppTextStyles.body.copyWith(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Log Out',
                style: AppTextStyles.body.copyWith(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await FirebaseAuth.instance.signOut();
    } catch (e) {
      debugPrint('[Settings] signOut failed: $e');
    }
    if (mounted) context.go(AppRoutes.signIn);
  }

  Future<void> _confirmDeleteAccount() async {
    // Step 1 — explain consequences.
    final step1 = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgElevated,
        title: Text('Delete account?',
            style: AppTextStyles.h3.copyWith(color: AppColors.danger)),
        content: Text(
          'This permanently deletes your profile, photos, matches, and messages. '
          'Your data will be removed within 30 days. '
          'This cannot be undone.',
          style: AppTextStyles.bodyS,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel',
                style:
                    AppTextStyles.body.copyWith(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Continue',
                style: AppTextStyles.body.copyWith(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (step1 != true) return;

    // Step 2 — final irreversible confirmation.
    if (!mounted) return;
    final step2 = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgElevated,
        title: Text('Are you sure?',
            style: AppTextStyles.h3.copyWith(color: AppColors.danger)),
        content: Text(
          'Tap "Delete Forever" to permanently close your account. '
          'There is no way to recover it after this.',
          style: AppTextStyles.bodyS,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel',
                style:
                    AppTextStyles.body.copyWith(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Delete Forever',
                style: AppTextStyles.body.copyWith(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (step2 != true) return;

    // Mark the user as offline in Firestore before deleting Auth so they
    // immediately disappear from discovery and other users' feeds.
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'isLive': false,
        'deleted': true,
        'deletedAt': FieldValue.serverTimestamp(),
      }).catchError((Object e) {
        debugPrint('[Settings] pre-delete Firestore update failed (non-fatal): $e');
      });
    }

    try {
      await FirebaseAuth.instance.currentUser?.delete();
    } on FirebaseAuthException catch (e) {
      debugPrint('[Settings] delete account failed: ${e.code}');
      if (mounted) {
        final msg = e.code == 'requires-recent-login'
            ? 'For security, please sign out and sign back in before deleting your account.'
            : 'Could not delete account (${e.code}). Please try again.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      }
      return;
    } catch (e) {
      debugPrint('[Settings] delete account unexpected error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not delete account. Please try again.'),
          ),
        );
      }
      return;
    }
    if (mounted) context.go(AppRoutes.signIn);
  }

  // ── URL launcher ───────────────────────────────────────────────────────────

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open $url')),
        );
      }
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Text('Settings', style: AppTextStyles.h3),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppColors.textSecondary, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        top: false,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loadError) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Could not load settings', style: AppTextStyles.bodyS),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () {
                setState(() => _loadError = false);
                _loadSettings();
              },
              child: Text('Retry',
                  style:
                      AppTextStyles.body.copyWith(color: AppColors.brandCyan)),
            ),
          ],
        ),
      );
    }

    if (_settings == null) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.brandPink),
      );
    }

    final s = _settings!;

    // Verification status from FirebaseAuth — read-only, cannot be forged.
    final currentUser = FirebaseAuth.instance.currentUser;
    final emailVerified = currentUser?.emailVerified ?? false;
    final phone = currentUser?.phoneNumber;
    final phoneVerified = phone != null && phone.isNotEmpty;
    final maskedPhone = (phone == null || phone.isEmpty)
        ? null
        : (phone.length <= 4 ? phone : '••••${phone.substring(phone.length - 4)}');

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 48),
      children: [
        // ── Account ─────────────────────────────────────────────────────────
        const _SectionHeader(title: 'Account'),
        _SettingsCard(items: [
          _SettingsRow(
            icon: Icons.person_outline_rounded,
            iconColor: AppColors.brandPink,
            label: 'Edit Profile',
            onTap: () => context.push(AppRoutes.editProfile),
          ),
          _SettingsRow(
            icon: Icons.verified_outlined,
            iconColor: AppColors.brandCyan,
            label: 'Live Verification',
            onTap: () => context.push(AppRoutes.liveVerify, extra: false),
          ),
          _SettingsRow(
            icon: Icons.workspace_premium_outlined,
            iconColor: AppColors.warning,
            label: 'Subscription',
            onTap: () => context.push(AppRoutes.shop),
            trailing: _ValueChip(
              label: _tierLabel(s.subscriptionTier),
              labelColor: _tierColor(s.subscriptionTier),
            ),
          ),
          // Email Verification: tappable when unverified — sends a Firebase
          // verification email.  During cooldown, the row still taps through to
          // a status refresh so the user can confirm a clicked link without
          // waiting for the resend timer or backgrounding the app.  Chip
          // updates to "Verified" once the user clicks the link and returns.
          _SettingsRow(
            icon: Icons.email_outlined,
            iconColor:
                emailVerified ? AppColors.success : AppColors.brandCyan,
            label: 'Email Verification',
            subtitle: emailVerified
                ? null
                : _emailCooldownSeconds > 0
                    ? 'Check your inbox — retry in ${_emailCooldownSeconds}s · tap to refresh'
                    : _emailJustSent
                        ? 'Check your inbox — tap to resend'
                        : 'Tap to send a verification email',
            onTap: emailVerified || _emailSending
                ? null
                : _emailCooldownSeconds > 0
                    ? _refreshVerificationStatus
                    : _sendVerificationEmail,
            trailing: _emailSending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.brandCyan,
                    ),
                  )
                : _ValueChip(
                    label: emailVerified ? 'Verified' : 'Not verified',
                    labelColor:
                        emailVerified ? AppColors.success : AppColors.danger,
                  ),
          ),
          // Phone Verification: display-only until the OTP flow is built.
          // A phone number stored in Firebase Auth is always OTP-verified,
          // so presence == verified.
          _SettingsRow(
            icon: Icons.phone_outlined,
            iconColor:
                phoneVerified ? AppColors.success : AppColors.textSecondary,
            label: 'Phone Verification',
            subtitle: phoneVerified ? maskedPhone : 'Coming soon',
            onTap: null,
            showChevron: false,
            trailing: _ValueChip(
              label: phoneVerified ? 'Verified' : 'Coming soon',
              labelColor: phoneVerified ? AppColors.success : AppColors.textMuted,
            ),
          ),
        ]),
        const SizedBox(height: 24),

        // ── Discovery ────────────────────────────────────────────────────────
        const _SectionHeader(title: 'Discovery'),
        _SettingsCard(items: [
          _SettingsRow(
            icon: Icons.explore_outlined,
            iconColor: AppColors.brandPurple,
            label: 'Show Me',
            onTap: _showShowMePicker,
            trailing: _ValueChip(label: _showMeLabel(s.showMe)),
          ),
          _SettingsRow(
            icon: Icons.cake_outlined,
            iconColor: AppColors.brandPink,
            label: 'Age Range',
            onTap: _showAgeRangePicker,
            trailing: _ValueChip(label: '${s.ageRangeMin} – ${s.ageRangeMax}'),
          ),
          _SettingsRow(
            icon: Icons.location_on_outlined,
            iconColor: AppColors.brandCyan,
            label: 'Max Distance',
            onTap: _showMaxDistancePicker,
            trailing: _ValueChip(label: '${s.maxDistanceMeters} m'),
          ),
          _SettingsToggleRow(
            icon: Icons.travel_explore_rounded,
            iconColor: AppColors.brandPurple,
            label: 'Discoverable',
            subtitle: 'Show me to people nearby while live',
            value: s.discoverable,
            onChanged: (v) {
              setState(() => s.discoverable = v);
              _save('discoverable', v);
            },
          ),
        ]),
        const SizedBox(height: 24),

        // ── Privacy & Safety ─────────────────────────────────────────────────
        const _SectionHeader(title: 'Privacy & Safety'),
        _SettingsCard(items: [
          _SettingsRow(
            icon: Icons.block_rounded,
            iconColor: AppColors.danger,
            label: 'Blocked Users',
            onTap: () => context.push(AppRoutes.blockedUsers),
          ),
          _SettingsRow(
            icon: Icons.flag_outlined,
            iconColor: AppColors.warning,
            label: 'Reporting & Blocking',
            onTap: () => context.push(AppRoutes.reportingAndBlocking),
          ),
          _SettingsToggleRow(
            icon: Icons.photo_outlined,
            iconColor: AppColors.textSecondary,
            label: 'Show Photos to Matches Only',
            value: s.photosToMatchesOnly,
            onChanged: (v) {
              setState(() => s.photosToMatchesOnly = v);
              _save('photosToMatchesOnly', v);
            },
          ),
        ]),
        const SizedBox(height: 24),

        // ── Notifications ─────────────────────────────────────────────────────
        // Values are persisted to Firestore immediately.
        // TODO: FCM topic subscribe/unsubscribe needed for these to suppress
        // push notifications.  Cloud Function must read these fields before sending.
        const _SectionHeader(title: 'Notifications'),
        _SettingsCard(items: [
          // Do Not Disturb: silences chat/message push notifications while the
          // user is not live.  Auto-cleared to false when a session starts
          // (LiveSession.goLive writes doNotDisturb: false to Firestore).
          // Has no effect on discoverability — that is governed by live session
          // state only.
          _SettingsToggleRow(
            icon: Icons.do_not_disturb_on_outlined,
            iconColor: AppColors.brandPurple,
            label: 'Do Not Disturb',
            subtitle: 'Silence chats when not live',
            value: s.doNotDisturb,
            onChanged: (v) {
              setState(() => s.doNotDisturb = v);
              _save('doNotDisturb', v);
            },
          ),
          _SettingsToggleRow(
            icon: Icons.notifications_outlined,
            iconColor: AppColors.brandPink,
            label: 'New Icebreakers',
            value: s.notifIcebreakers,
            onChanged: (v) {
              setState(() => s.notifIcebreakers = v);
              _save('notifIcebreakers', v);
            },
          ),
          _SettingsToggleRow(
            icon: Icons.chat_bubble_outline_rounded,
            iconColor: AppColors.brandCyan,
            label: 'New Messages',
            value: s.notifMessages,
            onChanged: (v) {
              setState(() => s.notifMessages = v);
              _save('notifMessages', v);
            },
          ),
          _SettingsToggleRow(
            icon: Icons.favorite_border_rounded,
            iconColor: AppColors.success,
            label: 'Match Confirmed',
            value: s.notifMatchConfirmed,
            onChanged: (v) {
              setState(() => s.notifMatchConfirmed = v);
              _save('notifMatchConfirmed', v);
            },
          ),
          _SettingsToggleRow(
            icon: Icons.bolt_outlined,
            iconColor: AppColors.warning,
            label: 'Session Starting',
            value: s.notifSession,
            onChanged: (v) {
              setState(() => s.notifSession = v);
              _save('notifSession', v);
            },
          ),
        ]),
        const SizedBox(height: 24),

        // ── Help & Legal ──────────────────────────────────────────────────────
        const _SectionHeader(title: 'Help & Legal'),
        _SettingsCard(items: [
          _SettingsRow(
            icon: Icons.help_outline_rounded,
            iconColor: AppColors.brandCyan,
            label: 'Help Center',
            onTap: () => _launchUrl('https://icebreakerlive.com/support.html'),
          ),
          _SettingsRow(
            icon: Icons.privacy_tip_outlined,
            iconColor: AppColors.textSecondary,
            label: 'Privacy Policy',
            onTap: () => _launchUrl('https://icebreakerlive.com/privacy.html'),
          ),
          _SettingsRow(
            icon: Icons.description_outlined,
            iconColor: AppColors.textSecondary,
            label: 'Terms of Service',
            onTap: () => _launchUrl('https://icebreakerlive.com/terms.html'),
          ),
          _SettingsRow(
            icon: Icons.info_outline_rounded,
            iconColor: AppColors.textMuted,
            label: 'App Version',
            onTap: null,
            showChevron: false,
            trailing: Text('1.0.0', style: AppTextStyles.bodyS),
          ),
        ]),
        const SizedBox(height: 24),

        // ── Danger zone ───────────────────────────────────────────────────────
        _SettingsCard(items: [
          _SettingsRow(
            icon: Icons.logout_rounded,
            iconColor: AppColors.danger,
            label: 'Log Out',
            labelColor: AppColors.danger,
            onTap: _confirmSignOut,
          ),
          _SettingsRow(
            icon: Icons.delete_outline_rounded,
            iconColor: AppColors.danger,
            label: 'Delete Account',
            labelColor: AppColors.danger,
            onTap: _confirmDeleteAccount,
            showChevron: false,
          ),
        ]),
      ],
    );
  }
}

// ─── Bottom sheet pickers ─────────────────────────────────────────────────────

class _ShowMePicker extends StatelessWidget {
  const _ShowMePicker({required this.current, required this.onSelected});

  final String current;
  final ValueChanged<String> onSelected;

  static const List<(String, String)> _options = [
    ('everyone', 'Everyone'),
    ('men', 'Men'),
    ('women', 'Women'),
    ('non_binary', 'Non-binary'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _PickerHandle(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Text('Show Me', style: AppTextStyles.h3),
        ),
        for (int i = 0; i < _options.length; i++) ...[
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            title: Text(
              _options[i].$2,
              style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
            ),
            trailing: current == _options[i].$1
                ? const Icon(Icons.check_rounded, color: AppColors.brandPink)
                : null,
            onTap: () {
              Navigator.of(context).pop();
              onSelected(_options[i].$1);
            },
          ),
          if (i < _options.length - 1)
            const Divider(
                height: 1,
                color: AppColors.divider,
                indent: 20,
                endIndent: 20),
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}

class _AgeRangePicker extends StatefulWidget {
  const _AgeRangePicker({
    required this.initialMin,
    required this.initialMax,
    required this.onSaved,
  });

  final double initialMin;
  final double initialMax;
  final void Function(double min, double max) onSaved;

  @override
  State<_AgeRangePicker> createState() => _AgeRangePickerState();
}

class _AgeRangePickerState extends State<_AgeRangePicker> {
  late RangeValues _range;

  @override
  void initState() {
    super.initState();
    _range = RangeValues(widget.initialMin, widget.initialMax);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _PickerHandle(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Age Range', style: AppTextStyles.h3),
              Text(
                '${_range.start.round()} – ${_range.end.round()}',
                style:
                    AppTextStyles.h3.copyWith(color: AppColors.brandPink),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: RangeSlider(
            values: _range,
            min: 18,
            max: 65,
            divisions: 47,
            activeColor: AppColors.brandPink,
            inactiveColor: AppColors.divider,
            onChanged: (v) => setState(() => _range = v),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('18', style: AppTextStyles.caption),
              Text('65', style: AppTextStyles.caption),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: PillButton.primary(
            label: 'Save',
            width: double.infinity,
            height: 52,
            onTap: () {
              Navigator.of(context).pop();
              widget.onSaved(_range.start, _range.end);
            },
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _MaxDistancePicker extends StatefulWidget {
  const _MaxDistancePicker({
    required this.initialValue,
    required this.onSaved,
  });

  final double initialValue;
  final ValueChanged<double> onSaved;

  @override
  State<_MaxDistancePicker> createState() => _MaxDistancePickerState();
}

class _MaxDistancePickerState extends State<_MaxDistancePicker> {
  late double _value;

  @override
  void initState() {
    super.initState();
    // Clamp to the new 30–60 m range, migrating any legacy value.
    _value = widget.initialValue.clamp(30.0, 60.0);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _PickerHandle(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Max Distance', style: AppTextStyles.h3),
              Text(
                '${_value.round()} m',
                style:
                    AppTextStyles.h3.copyWith(color: AppColors.brandCyan),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Slider(
            value: _value,
            min: 30,
            max: 60,
            // 3 divisions → stops at 30, 40, 50, 60 m
            divisions: 3,
            activeColor: AppColors.brandCyan,
            inactiveColor: AppColors.divider,
            onChanged: (v) => setState(() => _value = v),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('30 m', style: AppTextStyles.caption),
              Text('60 m', style: AppTextStyles.caption),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: PillButton.cyan(
            label: 'Save',
            width: double.infinity,
            height: 52,
            onTap: () {
              Navigator.of(context).pop();
              widget.onSaved(_value);
            },
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _PickerHandle extends StatelessWidget {
  const _PickerHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        margin: const EdgeInsets.only(top: 12, bottom: 20),
        decoration: BoxDecoration(
          color: AppColors.divider,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

// ─── Layout widgets ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(title.toUpperCase(), style: AppTextStyles.overline),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.items});
  final List<Widget> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (int i = 0; i < items.length; i++) ...[
            items[i],
            if (i < items.length - 1)
              const Divider(
                height: 1,
                indent: 62,
                endIndent: 0,
                color: AppColors.divider,
              ),
          ],
        ],
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    this.labelColor,
    this.subtitle,
    this.onTap,
    this.trailing,
    this.showChevron = true,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final Color? labelColor;

  /// Optional secondary line below the label (e.g. "Coming soon").
  final String? subtitle;

  final VoidCallback? onTap;
  final Widget? trailing;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            _IconBox(icon: icon, color: iconColor),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: AppTextStyles.body.copyWith(
                      fontWeight: FontWeight.w600,
                      color: labelColor ?? AppColors.textPrimary,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: AppTextStyles.caption),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing!,
            ],
            if (showChevron && onTap != null) ...[
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textMuted,
                size: 20,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Controlled toggle row — parent owns the value and calls setState on change.
class _SettingsToggleRow extends StatelessWidget {
  const _SettingsToggleRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          _IconBox(icon: icon, color: iconColor),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style:
                      AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: AppTextStyles.caption),
                ],
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppColors.brandPink,
            trackColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return AppColors.brandPink.withValues(alpha: 0.3);
              }
              return AppColors.divider;
            }),
          ),
        ],
      ),
    );
  }
}

class _IconBox extends StatelessWidget {
  const _IconBox({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(9),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: color, size: 18),
    );
  }
}

class _ValueChip extends StatelessWidget {
  const _ValueChip({required this.label, this.labelColor});

  final String label;
  final Color? labelColor;

  @override
  Widget build(BuildContext context) {
    final color = labelColor ?? AppColors.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: AppTextStyles.caption.copyWith(color: color),
      ),
    );
  }
}
