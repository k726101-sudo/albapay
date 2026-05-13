import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:google_sign_in/google_sign_in.dart' as google_sign_in;
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../config/apple_auth_config.dart';
import '../config/google_auth_config.dart';
import 'onboarding_guide_service.dart';

class AuthService {
  final firebase_auth.FirebaseAuth _auth = firebase_auth.FirebaseAuth.instance;
  static bool _isGoogleSignInInitialized = false;

  Stream<firebase_auth.User?> get userStream => _auth.authStateChanges();

  Future<firebase_auth.UserCredential?> _linkOrSignInWithCredential(
    firebase_auth.AuthCredential credential, {
    String? emailForConflictResolution,
  }) async {
    // If already signed in on this device, link to unify providers under one UID.
    final currentUser = _auth.currentUser;
    if (currentUser != null) {
      try {
        return await currentUser.linkWithCredential(credential);
      } on firebase_auth.FirebaseAuthException catch (e) {
        // Already linked or credential is already associated with another account
        if (e.code == 'provider-already-linked') {
          return await _auth.signInWithCredential(credential);
        }
        if (e.code == 'credential-already-in-use') {
          return await _auth.signInWithCredential(credential);
        }
        rethrow;
      }
    }

    try {
      return await _auth.signInWithCredential(credential);
    } on firebase_auth.FirebaseAuthException catch (e) {
      // If an account exists with same email but different provider,
      // we need to sign-in with existing provider, then link the new credential.
      if (e.code == 'account-exists-with-different-credential') {
        final email = emailForConflictResolution ?? e.email;
        if (email == null || email.isEmpty) rethrow;

        // Try to resolve automatically for the common case:
        // user previously used Google with the same email.
        // (We avoid calling fetchSignInMethodsForEmail due to API differences across firebase_auth versions.)
        final existing = await signInWithGoogle();
        final user = existing?.user;
        if (user != null &&
            (user.email ?? '').toLowerCase() == email.toLowerCase()) {
          try {
            return await user.linkWithCredential(credential);
          } catch (_) {
            return existing;
          }
        }

        // If email link is the existing method, we cannot complete it without user providing the link.
        // Surface the original error so UI can instruct the user.
        rethrow;
      }
      rethrow;
    }
  }

  Future<firebase_auth.UserCredential?> signInWithEmail(
    String email,
    String password,
  ) async {
    try {
      return await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } catch (e) {
      print('Sign in error: $e');
      return null;
    }
  }

  Future<firebase_auth.UserCredential?> signUp(
    String email,
    String password,
  ) async {
    try {
      return await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
    } catch (e) {
      print('Sign up error: $e');
      return null;
    }
  }

  Future<void> sendSignInLinkToEmail(
    String email,
    firebase_auth.ActionCodeSettings settings,
  ) async {
    await _auth.sendSignInLinkToEmail(
      email: email,
      actionCodeSettings: settings,
    );
  }

  bool isSignInWithEmailLink(String emailLink) {
    return _auth.isSignInWithEmailLink(emailLink);
  }

  Future<firebase_auth.UserCredential?> signInWithEmailLink(
    String email,
    String emailLink,
  ) async {
    try {
      // If already signed in, link the email-link provider to current user.
      final currentUser = _auth.currentUser;
      if (currentUser != null) {
        final credential = firebase_auth.EmailAuthProvider.credentialWithLink(
          email: email,
          emailLink: emailLink,
        );
        return await _linkOrSignInWithCredential(
          credential,
          emailForConflictResolution: email,
        );
      }
      return await _auth.signInWithEmailLink(
        email: email,
        emailLink: emailLink,
      );
    } catch (e) {
      print('Email link sign in error: $e');
      return null;
    }
  }

  /// Firebase뿐 아니라 **Google Sign-In SDK**도 정리합니다.
  /// Firebase만 `signOut`하면 기기에 Google 세션이 남아, 다음 로그인·다른 제공자 전환 시
  /// 토큰/계정 상태가 꼬이는 경우가 있습니다.
  Future<void> signOut() async {
    await _auth.signOut();
    await _signOutGoogleSdk();
    try {
      await OnboardingGuideService.instance.reset();
    } catch (_) {}
  }

  Future<void> _ensureGoogleSignInInitialized() async {
    if (_isGoogleSignInInitialized) return;
    try {
      if (kIsWeb) {
        // Web requires clientId
        await google_sign_in.GoogleSignIn.instance.initialize(
          clientId: GoogleAuthConfig.serverClientId,
        );
      } else {
        await google_sign_in.GoogleSignIn.instance.initialize(
          serverClientId: GoogleAuthConfig.serverClientId,
        );
      }
    } catch (e) {
      if (e.toString().contains('already been called')) {
        // Ignore initialization collision
      } else {
        rethrow;
      }
    }
    _isGoogleSignInInitialized = true;
  }

  Future<void> _signOutGoogleSdk() async {
    try {
      await _ensureGoogleSignInInitialized();
      await google_sign_in.GoogleSignIn.instance.signOut();
    } catch (_) {
      // Google 미사용·이미 로그아웃됨 등 — 무시
    }
  }

  Future<void> verifyPhoneNumber({
    required String phoneNumber,
    required Function(firebase_auth.PhoneAuthCredential) verificationCompleted,
    required Function(firebase_auth.FirebaseAuthException) verificationFailed,
    required Function(String, int?) codeSent,
    required Function(String) codeAutoRetrievalTimeout,
  }) async {
    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: verificationCompleted,
      verificationFailed: verificationFailed,
      codeSent: codeSent,
      codeAutoRetrievalTimeout: codeAutoRetrievalTimeout,
    );
  }

  Future<firebase_auth.UserCredential?> signInWithPhoneCredential(
    firebase_auth.PhoneAuthCredential credential,
  ) async {
    try {
      return await _auth.signInWithCredential(credential);
    } catch (e) {
      print('Phone sign in error: $e');
      return null;
    }
  }

  Future<firebase_auth.UserCredential?> signInWithGoogle() async {
    if (kIsWeb) {
      try {
        final googleProvider = firebase_auth.GoogleAuthProvider();
        googleProvider.addScope('email');
        googleProvider.addScope('profile');
        return await _auth.signInWithPopup(googleProvider);
      } catch (e) {
        print('Google Web sign in error: $e');
        return null;
      }
    }

    final googleSignIn = google_sign_in.GoogleSignIn.instance;

    await _ensureGoogleSignInInitialized();

    // NOTE: This can throw GoogleSignInException. Let it bubble so UI can show the real reason.
    final googleUser = await googleSignIn.authenticate();

    final googleAuth = googleUser.authentication;
    final authz = await googleUser.authorizationClient.authorizationForScopes(
      const ['email', 'profile'],
    );

    final firebase_auth.AuthCredential credential =
        firebase_auth.GoogleAuthProvider.credential(
          accessToken: authz?.accessToken,
          idToken: googleAuth.idToken,
        );

    return await _linkOrSignInWithCredential(
      credential,
      emailForConflictResolution: googleUser.email,
    );
  }

  /// Apple sign-in
  /// - **iOS**: `sign_in_with_apple` 네이티브 → [OAuthProvider]로 Firebase 토큰 교환.
  /// - **Android**: `sign_in_with_apple` 웹 플로우. `redirect_uri`는 Firebase **handler가 아니라**
  ///   [AppleAuthConfig.androidOAuthReturnUrl] (Cloud Function 브리지 → `intent://`)를 써야
  ///   **Missing Initial State**를 피합니다. 브리지 배포·Apple Return URL 등록이 필요합니다.
  ///
  /// [webClientId]·[webRedirectUri]: Android에서 `webRedirectUri`가 있으면 [androidOAuthReturnUrl] 대신 사용.
  Future<firebase_auth.UserCredential?> signInWithApple({
    String? webClientId,
    String? webRedirectUri,
  }) async {
    if (kIsWeb) {
      try {
        final appleProvider = firebase_auth.OAuthProvider('apple.com');
        appleProvider.addScope('email');
        appleProvider.addScope('name');
        return await _auth.signInWithPopup(appleProvider);
      } catch (e) {
        print('Apple Web sign in error: $e');
        return null;
      }
    }

    if (AppleAuthConfig.useNativeAppleSignIn) {
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        webAuthenticationOptions: null,
      );

      final oAuth = firebase_auth.OAuthProvider('apple.com');
      final credential = oAuth.credential(
        idToken: appleCredential.identityToken,
        accessToken: appleCredential.authorizationCode,
      );

      return await _linkOrSignInWithCredential(
        credential,
        emailForConflictResolution: appleCredential.email,
      );
    }

    final cid = (webClientId ?? AppleAuthConfig.clientId).trim();
    final bridgeUri = Uri.parse(
      webRedirectUri ?? AppleAuthConfig.androidOAuthReturnUrl,
    );
    if (cid.isEmpty) {
      throw firebase_auth.FirebaseAuthException(
        code: 'apple-android-config',
        message: 'CLIENT_ID(Services ID)가 비어 있습니다.',
      );
    }

    final appleCredential = await SignInWithApple.getAppleIDCredential(
      scopes: const [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      webAuthenticationOptions: WebAuthenticationOptions(
        clientId: cid,
        redirectUri: bridgeUri,
      ),
    );

    final oAuth = firebase_auth.OAuthProvider('apple.com');
    final credential = oAuth.credential(
      idToken: appleCredential.identityToken,
      accessToken: appleCredential.authorizationCode,
    );

    return await _linkOrSignInWithCredential(
      credential,
      emailForConflictResolution: appleCredential.email,
    );
  }
}
