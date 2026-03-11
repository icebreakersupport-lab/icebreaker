import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../core/state/live_session.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/gradient_scaffold.dart';
import '../../../shared/widgets/pill_button.dart';

enum _Step { idle, picked, verifying, verified }

/// Full-screen selfie upload + mock verification flow.
///
/// Flow:
///   1. User taps the circular picker → OS file dialog opens (images only).
///   2. Selected photo previewed in the circle with a pink glow border.
///   3. "Go Live" CTA becomes active.
///   4. Tap "Go Live" → 1.5 s mock verification ("Verifying you're real…").
///   5. "Verified!" moment (0.6 s) → [LiveSession.goLive] fires → screen pops.
///
/// The screen is presented modally via [Navigator.push] from [HomeScreen].
class LiveVerificationScreen extends StatefulWidget {
  const LiveVerificationScreen({super.key});

  @override
  State<LiveVerificationScreen> createState() => _LiveVerificationScreenState();
}

class _LiveVerificationScreenState extends State<LiveVerificationScreen> {
  _Step _step = _Step.idle;
  String? _selfieFilePath;

  bool get _isBusy =>
      _step == _Step.verifying || _step == _Step.verified;

  Future<void> _pickSelfie() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    if (result != null && result.files.single.path != null) {
      setState(() {
        _selfieFilePath = result.files.single.path;
        _step = _Step.picked;
      });
    }
  }

  Future<void> _startVerification() async {
    setState(() => _step = _Step.verifying);

    // Mock verification — 1.5 s
    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;

    setState(() => _step = _Step.verified);

    // Brief "Verified!" moment — 0.6 s
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;

    LiveSessionScope.of(context).goLive(selfieFilePath: _selfieFilePath);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      showTopGlow: true,
      appBar: _buildAppBar(),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const Spacer(flex: 1),
              _buildSelfiePicker(),
              const SizedBox(height: 28),
              _buildStatusArea(),
              const Spacer(flex: 2),
              _buildBottomArea(),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      automaticallyImplyLeading: false,
      leading: _isBusy
          ? const SizedBox.shrink()
          : IconButton(
              icon: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: AppColors.textSecondary,
                size: 20,
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
      title: Text('Go Live', style: AppTextStyles.h3),
    );
  }

  // ── Selfie picker circle ──────────────────────────────────────────────────

  Widget _buildSelfiePicker() {
    const double size = 180;
    final hasSelfie = _selfieFilePath != null;

    return GestureDetector(
      onTap: _isBusy ? null : _pickSelfie,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.bgSurface,
          border: Border.all(
            color: hasSelfie ? AppColors.brandPink : AppColors.divider,
            width: hasSelfie ? 2.5 : 1.5,
          ),
          boxShadow: hasSelfie
              ? [
                  BoxShadow(
                    color: AppColors.brandPink.withValues(alpha: 0.22),
                    blurRadius: 32,
                    spreadRadius: 4,
                  ),
                  BoxShadow(
                    color: AppColors.brandPurple.withValues(alpha: 0.14),
                    blurRadius: 56,
                    spreadRadius: 8,
                  ),
                ]
              : null,
        ),
        child: ClipOval(
          child: hasSelfie
              ? Image.file(File(_selfieFilePath!), fit: BoxFit.cover)
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.add_a_photo_rounded,
                      color: AppColors.textMuted,
                      size: 38,
                    ),
                    const SizedBox(height: 10),
                    Text('Add selfie', style: AppTextStyles.caption),
                  ],
                ),
        ),
      ),
    );
  }

  // ── Status text / verification states ────────────────────────────────────

  Widget _buildStatusArea() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      child: switch (_step) {
        _Step.idle => _StatusIdle(key: const ValueKey('idle')),
        _Step.picked => _StatusPicked(key: const ValueKey('picked')),
        _Step.verifying => _StatusVerifying(key: const ValueKey('verifying')),
        _Step.verified => _StatusVerified(key: const ValueKey('verified')),
      },
    );
  }

  // ── Bottom CTA area ───────────────────────────────────────────────────────

  Widget _buildBottomArea() {
    // Reserve height so layout doesn't jump during verification
    if (_isBusy) return const SizedBox(height: 80);

    return Column(
      children: [
        PillButton.primary(
          label: 'Go Live',
          onTap: _step == _Step.picked ? _startVerification : null,
          width: double.infinity,
          height: 64,
        ),
        const SizedBox(height: 16),
        Text(
          '1 Live session available  ·  3 Icebreakers remaining',
          style: AppTextStyles.caption,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

// ── Status sub-widgets ────────────────────────────────────────────────────────

class _StatusIdle extends StatelessWidget {
  const _StatusIdle({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'Add a selfie to go live',
          style: AppTextStyles.h3,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Your selfie is your live profile photo.\nPeople nearby will see this when you appear.',
          style: AppTextStyles.bodyS,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _StatusPicked extends StatelessWidget {
  const _StatusPicked({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'Looking good',
          style: AppTextStyles.h3.copyWith(color: AppColors.brandPink),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Tap your photo to choose a different one,\nor hit Go Live when you\'re ready.',
          style: AppTextStyles.bodyS,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _StatusVerifying extends StatelessWidget {
  const _StatusVerifying({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            valueColor:
                AlwaysStoppedAnimation<Color>(AppColors.brandCyan),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Verifying you\'re real…',
          style: AppTextStyles.bodyS,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          'This only takes a moment.',
          style: AppTextStyles.caption,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _StatusVerified extends StatelessWidget {
  const _StatusVerified({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.check_circle_rounded,
          color: AppColors.success,
          size: 34,
        ),
        const SizedBox(height: 12),
        Text(
          'Verified!',
          style: AppTextStyles.h3.copyWith(color: AppColors.success),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          'Going live now…',
          style: AppTextStyles.bodyS,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
