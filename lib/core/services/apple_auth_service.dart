import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// Wraps the Sign in with Apple → Firebase Auth handshake.
///
/// Apple's flow requires a nonce that's hashed (SHA-256) before being passed
/// to Apple, and the raw (un-hashed) nonce sent to Firebase alongside the
/// returned identity token.  Firebase verifies the hash matches the one
/// embedded in the token's `nonce` claim — without this step Firebase
/// rejects the credential with `invalid-credential`.
///
/// Returns the signed-in FirebaseAuth `User` on success, or null when the
/// user cancels the native sheet.  Throws on any unexpected error.
///
/// Caller is responsible for downstream routing (Firestore doc lookup +
/// onboarding-resume gate).  See `_routeAfterAuth` in SignInScreen /
/// SignUpScreen for the canonical post-auth path.
class AppleAuthService {
  AppleAuthService._();

  /// True when Sign in with Apple is *technically* available on the host
  /// platform.  Android + web + desktop will return false here — Apple's
  /// Flutter package only supports the native flow on iOS / macOS.  We hide
  /// the button on unsupported platforms rather than throw at tap time.
  static Future<bool> isAvailable() async {
    if (kIsWeb) return false;
    if (!(Platform.isIOS || Platform.isMacOS)) return false;
    try {
      return await SignInWithApple.isAvailable();
    } catch (_) {
      return false;
    }
  }

  /// Triggers the native Apple sheet and returns the resulting Firebase
  /// `User` on success.  Returns null on user cancellation.  Throws
  /// [FirebaseAuthException] on Firebase-side failures and
  /// [SignInWithAppleAuthorizationException] on Apple-side failures.
  static Future<User?> signIn() async {
    final rawNonce = _generateNonce();
    final hashedNonce = _sha256(rawNonce);

    AuthorizationCredentialAppleID credential;
    try {
      credential = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      // canceled is a normal user action; surface as null.
      if (e.code == AuthorizationErrorCode.canceled) {
        debugPrint('[AppleAuth] user canceled');
        return null;
      }
      rethrow;
    }

    final idToken = credential.identityToken;
    if (idToken == null) {
      debugPrint('[AppleAuth] ❌ Apple returned no identityToken');
      throw FirebaseAuthException(
        code: 'invalid-credential',
        message: 'Apple did not return an identity token.',
      );
    }

    final oauth = OAuthProvider('apple.com').credential(
      idToken: idToken,
      rawNonce: rawNonce,
      accessToken: credential.authorizationCode,
    );

    final userCredential =
        await FirebaseAuth.instance.signInWithCredential(oauth);
    final user = userCredential.user;
    debugPrint('[AppleAuth] ✅ signed in uid=${user?.uid} '
        'email=${user?.email} newUser=${userCredential.additionalUserInfo?.isNewUser}');
    return user;
  }

  // ── Nonce helpers ─────────────────────────────────────────────────────────

  static String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._';
    final rng = Random.secure();
    return List.generate(
      length,
      (_) => charset[rng.nextInt(charset.length)],
    ).join();
  }

  static String _sha256(String input) {
    return sha256.convert(utf8.encode(input)).toString();
  }
}
