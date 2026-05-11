import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// Branded text field used by the Sign In + Sign Up flows.
///
/// Wraps a stock [TextField] with the app's surface treatment (rounded
/// border, brand-pink focus tint, uppercase ALL-CAPS label rendered above
/// the field).  Password fields render an inline show/hide eye toggle so
/// callers don't have to track obscure-text state themselves.
class AuthTextField extends StatefulWidget {
  const AuthTextField({
    super.key,
    required this.controller,
    required this.label,
    this.focusNode,
    this.hint,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.isPassword = false,
    this.enabled = true,
    this.onSubmitted,
    this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final String label;
  final String? hint;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final bool isPassword;
  final bool enabled;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;

  @override
  State<AuthTextField> createState() => _AuthTextFieldState();
}

class _AuthTextFieldState extends State<AuthTextField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    final isPwd = widget.isPassword;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: AppTextStyles.caption.copyWith(
            color: AppColors.textSecondary,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: widget.controller,
          focusNode: widget.focusNode,
          enabled: widget.enabled,
          obscureText: isPwd && _obscure,
          keyboardType: widget.keyboardType,
          textInputAction: widget.textInputAction,
          autofillHints: widget.autofillHints?.toList(),
          onSubmitted: widget.onSubmitted,
          onChanged: widget.onChanged,
          style: AppTextStyles.body.copyWith(color: AppColors.textPrimary),
          cursorColor: AppColors.brandPink,
          decoration: InputDecoration(
            hintText: widget.hint,
            hintStyle:
                AppTextStyles.body.copyWith(color: AppColors.textMuted),
            filled: true,
            fillColor: AppColors.bgSurface,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
            border: _border(AppColors.divider),
            enabledBorder: _border(AppColors.divider),
            focusedBorder: _border(AppColors.brandPink, width: 1.5),
            disabledBorder: _border(AppColors.divider),
            suffixIcon: isPwd
                ? IconButton(
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: AppColors.textMuted,
                      size: 20,
                    ),
                    splashRadius: 18,
                  )
                : null,
          ),
        ),
      ],
    );
  }

  OutlineInputBorder _border(Color color, {double width = 1.0}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: color, width: width),
    );
  }
}
