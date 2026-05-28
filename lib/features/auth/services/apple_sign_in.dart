import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// Drives the native Sign in with Apple flow and exchanges the returned
/// identity token for a Firebase Auth session.
///
/// Apple's `ASAuthorizationController` only surfaces the user's full name
/// on the FIRST authorization for a given Apple ID — every subsequent
/// sign-in returns null for [AuthorizationCredentialAppleID.givenName].
/// We therefore opportunistically copy that one-shot name into the
/// Firebase Auth `displayName` so it survives the rest of the user's
/// lifetime on the app.
///
/// Returns the resulting [UserCredential] on success.  Throws on
/// failure — callers are responsible for mapping the error code to
/// user-facing copy.  A user-initiated cancellation surfaces as
/// [SignInWithAppleAuthorizationException] with `code == canceled`
/// and should be treated as a silent no-op.
class AppleSignIn {
  AppleSignIn._();

  /// Length of the cryptographic nonce passed to Apple.  Apple recommends
  /// at least 32 chars from a URL-safe alphabet.  We SHA-256 this value
  /// before sending and forward the raw nonce to Firebase, which
  /// re-hashes server-side to verify the token wasn't replayed.
  static const int _nonceLength = 32;

  static const String _nonceAlphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._';

  static Future<UserCredential> signIn() async {
    final rawNonce = _generateNonce();
    final hashedNonce = _sha256(rawNonce);

    final appleCredential = await SignInWithApple.getAppleIDCredential(
      scopes: const [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: hashedNonce,
    );

    final oauthCredential = OAuthProvider('apple.com').credential(
      idToken: appleCredential.identityToken,
      rawNonce: rawNonce,
    );

    final userCredential =
        await FirebaseAuth.instance.signInWithCredential(oauthCredential);

    final displayName = [
      appleCredential.givenName,
      appleCredential.familyName,
    ]
        .where((part) => part != null && part.trim().isNotEmpty)
        .join(' ')
        .trim();
    if (displayName.isNotEmpty) {
      try {
        await userCredential.user?.updateDisplayName(displayName);
      } catch (_) {
        // Non-fatal: the displayName is convenience metadata; onboarding
        // will collect the user's first name regardless.
      }
    }

    return userCredential;
  }

  static String _generateNonce() {
    final rng = Random.secure();
    return List.generate(
      _nonceLength,
      (_) => _nonceAlphabet[rng.nextInt(_nonceAlphabet.length)],
    ).join();
  }

  static String _sha256(String input) =>
      sha256.convert(utf8.encode(input)).toString();
}
