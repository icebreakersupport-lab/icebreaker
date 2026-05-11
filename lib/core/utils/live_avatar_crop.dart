import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Center-crops the captured live verification selfie at [sourcePath] to a
/// square, downscales it to a fixed avatar size, writes the result alongside
/// the source as `<source>_avatar.jpg`, and returns the new file path.
///
/// The portrait original is the source of truth for the verification frame;
/// the derived crop is only used by circular avatar surfaces (Profile hero,
/// Nearby cards) where a centred square is the correct shape.  Keeping the
/// crop as a separate file means the round-trip is cheap to redo if the user
/// re-captures, and the original is never destructively modified.
///
/// Returns the source path unchanged if anything fails — the caller treats
/// the avatar path as best-effort and falls back to the portrait on null.
Future<String> deriveSquareAvatar(String sourcePath) async {
  const targetSize = 512;
  const jpegQuality = 88;

  try {
    final source = File(sourcePath);
    if (!await source.exists()) return sourcePath;

    final bytes = await source.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return sourcePath;

    // Center square crop.
    final shortSide = decoded.width < decoded.height
        ? decoded.width
        : decoded.height;
    final cropX = (decoded.width - shortSide) ~/ 2;
    final cropY = (decoded.height - shortSide) ~/ 2;
    final cropped = img.copyCrop(
      decoded,
      x: cropX,
      y: cropY,
      width: shortSide,
      height: shortSide,
    );

    // Downscale to the avatar target.  Skipped if already small enough so we
    // don't blow up a thumbnail.
    final scaled = cropped.width > targetSize
        ? img.copyResize(
            cropped,
            width: targetSize,
            height: targetSize,
            interpolation: img.Interpolation.cubic,
          )
        : cropped;

    final outBytes = img.encodeJpg(scaled, quality: jpegQuality);

    // Write to the system temp directory.  These files are short-lived —
    // they get uploaded to Storage in the goLive batch and the on-device
    // copy is only needed for the in-session avatar surface.
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final outFile = File('${Directory.systemTemp.path}/live_avatar_$stamp.jpg');
    await outFile.writeAsBytes(outBytes, flush: true);
    return outFile.path;
  } catch (e) {
    debugPrint('[liveAvatarCrop] failed: $e — falling back to source');
    return sourcePath;
  }
}
