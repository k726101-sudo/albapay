import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Apple 로그인 설정 (Services ID, 리다이렉트 URL).
///
/// ### iOS
/// 네이티브 Sign in with Apple — [clientId]·[androidOAuthReturnUrl]은 사용하지 않습니다.
///
/// ### Android (`sign_in_with_apple`)
/// Chrome Custom Tab으로 `appleid.apple.com`을 연 뒤, Apple이 **HTTPS Return URL**로 `form_post`합니다.
/// Firebase `__/auth/handler`만 쓰면 브라우저 **sessionStorage**와 맞지 않아 **Missing Initial State**가 납니다.
/// 그래서 **배포한 Cloud Function**(`appleSignInAndroidBridge`)이 POST를 받아 `intent://`로 앱에 넘깁니다.
///
/// **Apple Developer** → Services ID → Return URLs에 다음을 **둘 다** 넣을 수 있습니다.
/// - Firebase 콘솔(Authentication → Apple)용: [firebaseAuthHandlerUrl]
/// - Android 앱용: [androidOAuthReturnUrl] (배포된 브리지 URL과 동일)
///
/// **Domains**에도 각각 호스트를 등록하세요.
///
/// 빌드 시:
/// `--dart-define=APPLE_ANDROID_BRIDGE_URL=https://...cloudfunctions.net/appleSignInAndroidBridge`
///
/// **동일 Apple ID → 동일 Firebase UID**: `OAuthProvider('apple.com')`로 토큰을 넘기면 동일합니다.
class AppleAuthConfig {
  AppleAuthConfig._();

  /// Services ID (`com.standard.albapay.service`)
  static const String clientId = String.fromEnvironment(
    'CLIENT_ID',
    defaultValue: 'com.standard.albapay.service',
  );

  /// Firebase 콘솔에서 Apple 제공자 설정 시 사용하는 Auth 핸들러 URL.
  static const String firebaseAuthHandlerUrl = String.fromEnvironment(
    'REDIRECT_URL',
    defaultValue: 'https://standard-albapay.firebaseapp.com/__/auth/handler',
  );

  /// Android 전용: Apple이 POST하는 **브리지(Cloud Function) HTTPS URL**. [SignInWithApple] `redirect_uri`.
  /// 배포 후 Firebase 콘솔 / `firebase functions:log` 로 정확한 URL을 확인해 동일하게 두세요.
  static const String androidOAuthReturnUrl = String.fromEnvironment(
    'APPLE_ANDROID_BRIDGE_URL',
    defaultValue: 'https://applesigninandroidbridge-5uhwajbtdq-du.a.run.app',
  );

  @Deprecated('Use firebaseAuthHandlerUrl or androidOAuthReturnUrl')
  static String get redirectUrl => firebaseAuthHandlerUrl;

  static Uri get redirectUri => Uri.parse(firebaseAuthHandlerUrl);

  static bool get useNativeAppleSignIn =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
}
