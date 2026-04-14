/// Google Sign-In / Firebase Auth 연동용 설정.
///
/// Android에서는 [AuthService]가 `GoogleSignIn.instance.initialize`에
/// **서버(Web) OAuth 클라이언트 ID**를 넘겨야 ID 토큰을 받을 수 있습니다.
/// (Firebase 콘솔 → 프로젝트 설정 → 일반 → 내 앱 → Android 와 연결된 OAuth 클라이언트,
/// 또는 `google-services.json`의 `client_type: 3` 항목)
class GoogleAuthConfig {
  GoogleAuthConfig._();

  static const String serverClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue:
        '824353133931-t6jd5iugoe2r5hi5pdnkoq6e61jurj8k.apps.googleusercontent.com',
  );
}
