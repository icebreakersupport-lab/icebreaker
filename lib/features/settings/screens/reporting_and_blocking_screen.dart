import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/gradient_scaffold.dart';

/// Reporting & Blocking help screen.
///
/// Apple's App Review Guideline 1.2 (User-Generated Content) requires apps to
/// surface a clear, in-app explanation of how to report and block bad actors,
/// and a contact path for users who feel they've been wronged.  This screen is
/// the documentation surface — the actual report/block actions live on the
/// profile, chat, and Blocked Users screens.
class ReportingAndBlockingScreen extends StatelessWidget {
  const ReportingAndBlockingScreen({super.key});

  static const _supportEmail = 'icebreaker.support@gmail.com';

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Text('Reporting & Blocking', style: AppTextStyles.h3),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppColors.textSecondary, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('How to report someone', style: AppTextStyles.h3),
              const SizedBox(height: 8),
              Text(
                'Tap a user\'s profile — anywhere you see one in Nearby, Messages, '
                'or a chat thread — and use the flag icon in the top right. '
                'Choose a reason: harassment, spam, fake profile, inappropriate '
                'content, or other. Reports are reviewed within 24 hours. '
                'Users with three confirmed reports are auto-suspended for review.',
                style: AppTextStyles.bodyS,
              ),
              const SizedBox(height: 20),
              Text('How to block someone', style: AppTextStyles.h3),
              const SizedBox(height: 8),
              Text(
                'Blocking takes effect immediately and works both ways — they '
                'won\'t see you in Nearby, and any open conversations are '
                'archived. You can review and unblock people anytime from '
                'Settings → Blocked Users.',
                style: AppTextStyles.bodyS,
              ),
              const SizedBox(height: 20),
              Text('What we don\'t allow', style: AppTextStyles.h3),
              const SizedBox(height: 8),
              ..._guidelines.map(
                (line) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Icon(Icons.circle,
                            size: 5, color: AppColors.textSecondary),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(line, style: AppTextStyles.bodyS)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text('Contact us', style: AppTextStyles.h3),
              const SizedBox(height: 8),
              Text(
                'If you need to escalate something — a serious incident, '
                'a safety concern, or you think we made the wrong call on a '
                'report — email us at $_supportEmail and we\'ll respond '
                'within 24 hours.',
                style: AppTextStyles.bodyS,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static const _guidelines = [
    'Harassment, threats, or hate speech',
    'Sexually explicit content or solicitation',
    'Impersonation, fake profiles, or scams',
    'Sharing personal information about other users',
    'Promotion of self-harm, drugs, or violence',
    'Spam, scraping, or any automated activity',
  ];
}
