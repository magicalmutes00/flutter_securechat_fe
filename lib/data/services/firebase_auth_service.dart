import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'api_client.dart';

/// Result of starting phone verification via Firebase.
sealed class PhoneVerificationResult {
  const PhoneVerificationResult();
}

/// An SMS code was sent; [verificationId] must be presented along with the
/// code the user enters to complete sign-in.
class PhoneCodeSent extends PhoneVerificationResult {
  const PhoneCodeSent(this.verificationId);

  final String verificationId;
}

/// The device was verified automatically (instant verification via Google
/// Play services) without requiring SMS entry. [idToken] is ready to exchange.
class PhoneAutoVerified extends PhoneVerificationResult {
  const PhoneAutoVerified(this.idToken);

  final String idToken;
}

/// Wraps the Firebase phone verification flow and exchanges the resulting
/// Firebase ID token for a SecureChat backend session.
class FirebaseAuthService {
  FirebaseAuthService._();

  static final FirebaseAuthService instance = FirebaseAuthService._();

  final ApiClient _apiClient = ApiClient();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

  String? _verificationId;

  /// Best-effort Firebase initialization. No-ops when the platform has no
  /// Firebase configuration so the app can still run (e.g. desktop builds).
  Future<void> ensureInitialized() async {
    try {
      await Firebase.initializeApp();
    } catch (_) {
      // Firebase not configured on this platform; auth will be unavailable.
    }
  }

  /// Starts phone number verification for [phone] (must be E.164).
  ///
  /// Completes with [PhoneCodeSent] when the SMS has been dispatched, or
  /// [PhoneAutoVerified] when the OS verified the device without user input.
  Future<PhoneVerificationResult> sendCode(String phone) {
    final completer = Completer<PhoneVerificationResult>();

    _auth.verifyPhoneNumber(
      phoneNumber: phone,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (PhoneAuthCredential credential) async {
        try {
          await _auth.signInWithCredential(credential);
          final idToken = await _auth.currentUser?.getIdToken();
          if (idToken == null) {
            throw Exception('Auto-verification failed: no ID token issued');
          }
          if (!completer.isCompleted) {
            completer.complete(PhoneAutoVerified(idToken));
          }
        } catch (e) {
          if (!completer.isCompleted) completer.completeError(e);
        }
      },
      verificationFailed: (FirebaseAuthException error) {
        if (!completer.isCompleted) completer.completeError(error);
      },
      codeSent: (String verificationId, int? resendToken) {
        _verificationId = verificationId;
        if (!completer.isCompleted) {
          completer.complete(PhoneCodeSent(verificationId));
        }
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        // The user will enter the code manually; nothing to do here.
      },
    );

    return completer.future;
  }

  /// Verifies the SMS [smsCode] for the previously requested code and returns
  /// the authenticated user's Firebase ID token.
  Future<String> verifyCode(String smsCode) async {
    final verificationId = _verificationId;
    if (verificationId == null || verificationId.isEmpty) {
      throw Exception('No verification code requested');
    }

    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );
    final result = await _auth.signInWithCredential(credential);
    final idToken = await result.user?.getIdToken();
    if (idToken == null) {
      throw Exception('Failed to obtain Firebase ID token');
    }
    return idToken;
  }

  /// Signs the user in with Firebase email/password and returns the
  /// authenticated Firebase ID token.
  Future<String> loginWithEmail({
    required String email,
    required String password,
  }) async {
    final result = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    final idToken = await result.user?.getIdToken();
    if (idToken == null) {
      throw Exception('Failed to obtain Firebase ID token');
    }
    return idToken;
  }

  /// Registers a new user with Firebase email/password, applies [displayName],
  /// and returns the authenticated Firebase ID token.
  Future<String> registerWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final result = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    final user = result.user;
    if (user != null &&
        displayName != null &&
        displayName.trim().isNotEmpty) {
      await user.updateProfile(displayName: displayName.trim());
      await user.reload();
    }
    final idToken = await result.user?.getIdToken();
    if (idToken == null) {
      throw Exception('Failed to obtain Firebase ID token');
    }
    return idToken;
  }

  /// Signs the user in with Google and returns the authenticated Firebase
  /// ID token ready to exchange for a SecureChat session.
  Future<String> signInWithGoogle() async {
    debugPrint('[GoogleAuth] initializing GoogleSignIn...');
    await _googleSignIn.initialize();
    debugPrint('[GoogleAuth] initialize() done, awaiting authenticate()...');
    final account = await _googleSignIn.authenticate();
    debugPrint('[GoogleAuth] authenticate() returned account: ${account.email}');
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw Exception('Google sign-in failed: no ID token issued');
    }
    debugPrint('[GoogleAuth] Google idToken obtained (${idToken.length} chars)');

    final credential = GoogleAuthProvider.credential(idToken: idToken);
    debugPrint('[GoogleAuth] exchanging with FirebaseAuth...');
    final result = await _auth.signInWithCredential(credential);
    debugPrint('[GoogleAuth] Firebase signInWithCredential succeeded: ${result.user?.uid}');
    final firebaseIdToken = await result.user?.getIdToken();
    if (firebaseIdToken == null) {
      throw Exception('Failed to obtain Firebase ID token');
    }
    debugPrint('[GoogleAuth] Firebase idToken obtained (${firebaseIdToken.length} chars)');
    return firebaseIdToken;
  }

  /// Exchanges the Firebase [idToken] for a SecureChat JWT session.
  Future<Map<String, dynamic>> exchangeToken(String idToken) =>
      _apiClient.exchangeFirebaseToken(idToken);

  /// Signs the current user out of Firebase and Google.
  Future<void> signOut() async {
    _verificationId = null;
    try {
      await _auth.signOut();
    } catch (_) {
      // Best-effort; backend tokens are cleared by the caller regardless.
    }
    try {
      await _googleSignIn.signOut();
    } catch (_) {
      // Best-effort.
    }
  }
}
