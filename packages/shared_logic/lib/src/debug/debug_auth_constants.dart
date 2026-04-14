/// kDebugMode 빠른 로그인·시드 데이터와 맞추기 위한 상수입니다.
///
/// **디버그 빌드**에서 「테스트: 사장님 로그인」은 계정이 없으면 `createUserWithEmailAndPassword`로
/// **자동 생성**합니다. 콘솔에 수동으로 넣지 않아도 됩니다. (단, Authentication에서 **이메일/비밀번호** 제공자는 켜져 있어야 합니다.)
///
/// 이미 콘솔에서 만든 계정이 있으면, 비밀번호가 [bossPassword]와 같아야 로그인됩니다.
/// 다른 비밀번호로 만들었다면 콘솔에서 재설정하거나, 이 파일의 [bossPassword]를 맞추세요.
///
/// 참고: 「이메일 링크」는 테스트용 주소로는 수신되지 않으므로, 디버그 계정은 **이메일/비밀번호**만 사용하세요.
///
/// **도메인**: `*.local` 등은 Firebase Auth에서 `invalid-email`로 거부되는 경우가 많아,
/// `example.com`(RFC 예약)처럼 형식만 유효한 주소를 씁니다.
///
/// **중요**: 실제 **구글 로그인에 쓰는 Gmail과 동일한 이메일**을 여기에 두면,
/// Firebase에서 **같은 사용자(동일 UID)** 로 연결될 수 있어 대시보드·매장이 구글과 똑같이 보입니다.
/// 테스트 전용 주소는 실제 계정과 겹치지 않게 유지하세요.
class DebugAuthConstants {
  DebugAuthConstants._();

  static const String bossEmail = 'debug-boss-v30@example.com';
  static const String bossPassword = 'password123!';

  /// [TestDataSeeder] 첫 번째 직원 초대코드 / 전화번호
  static const String albaInviteCode = 'TST001';
  static const String albaPhone = '01000000001';

  /// 디버그 모드에서 모든 기기가 시간을 동기화할 때 사용하는 공용 테스트 매장 ID
  static const String debugStoreId = 'debug_store_v30';

  /// 앱-웹 통합 테스트용 고정 근무자 ID
  static const String testWorkerId = 'test_worker_v30';
}
