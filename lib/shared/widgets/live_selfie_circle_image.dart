import 'dart:io';

import 'package:flutter/material.dart';

/// Circular avatar image for the profile hero + live cards.
///
/// Resolves [selfiePath] (or [avatarPath] as fallback) to either a local
/// `FileImage` or a `NetworkImage` based on the string's prefix.  The parent
/// is responsible for clipping to a circle — this widget just provides the
/// image with BoxFit.cover.
class LiveSelfieCircleImage extends StatelessWidget {
  const LiveSelfieCircleImage({
    super.key,
    required this.selfiePath,
    this.avatarPath,
  });

  /// Path or URL of the live verification selfie.  Local file paths start
  /// with `/`; remote URLs start with `http`.
  final String selfiePath;

  /// Optional cropped avatar variant.  Used as a fallback if [selfiePath]
  /// cannot be resolved.
  final String? avatarPath;

  @override
  Widget build(BuildContext context) {
    final image = _resolve(selfiePath) ??
        (avatarPath != null ? _resolve(avatarPath!) : null);
    if (image == null) {
      return const SizedBox.shrink();
    }
    return Image(
      image: image,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      gaplessPlayback: true,
    );
  }

  ImageProvider? _resolve(String pathOrUrl) {
    if (pathOrUrl.isEmpty) return null;
    if (pathOrUrl.startsWith('http://') || pathOrUrl.startsWith('https://')) {
      return NetworkImage(pathOrUrl);
    }
    return FileImage(File(pathOrUrl));
  }
}
