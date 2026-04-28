import 'dart:io' show Platform;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// The single account permitted to use the photo-library fallback in place of
/// a live camera capture during live verification.  This is intentionally
/// narrow: the Mac on which this account is signed in has no camera, so the
/// library path is the only way to complete verification on that machine.
/// Every other account on every other platform — including other accounts on
/// this same Mac — must use the real camera flow.
const _kMacLibraryFallbackEmail = 'icebreaker.support@gmail.com';

/// Returns true only when:
///   • the host platform is macOS (not iOS, not Android, not web), AND
///   • the signed-in user's email matches [_kMacLibraryFallbackEmail].
///
/// Build mode is not part of the gate — the camera is missing on hardware,
/// not in software, so the fallback must work in every build mode.  The email
/// match is the privacy boundary.
bool macLibraryFallbackForThisAccount() {
  if (kIsWeb) return false;
  if (!Platform.isMacOS) return false;
  final email = FirebaseAuth.instance.currentUser?.email?.trim().toLowerCase();
  return email == _kMacLibraryFallbackEmail;
}
