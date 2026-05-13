import 'package:share_plus/share_plus.dart';

class InvitationService {
  /// iOS Safari / Chrome WebOTP·자동완성용 (문자 마지막 줄, 도메인은 실제 접속 origin 과 일치해야 함)
  static const String _albaWebOriginHost = 'standard-albapay.web.app';

  /// 직원 초대 코드 공유(카카오톡 공유창은 공유 시 선택 메뉴에서 제공)
  static Future<void> shareInviteLink({
    required String storeName,
    required String storeId,
    required String staffName,
    required String inviteCode,
  }) async {
    final text = [
      '직원 초대 코드 -',
      '안녕하세요.',
      "[$storeName] 매장에 초대합니다. 🎉",
      '',
      '1️⃣ 먼저 앱을 설치해 주세요.',
      '👉 https://standard-albapay.web.app/download',
      '(안드로이드·아이폰 자동 연결)',
      '',
      '2️⃣ 설치가 끝났다면, 꼭 아래 링크를 눌러서 앱을 실행해 주세요! (초대코드가 자동 입력됩니다)',
      '👉 접속 링크: https://standard-albapay.web.app/invite?code=$inviteCode',
      '',
      '※ 수동 입력용 번호: $inviteCode (알바생: $staffName)',
      '',
      // WebOTP 자동완성 트리거용 (보이지 않거나 무시됨)
      '@$_albaWebOriginHost #$inviteCode',
    ].join('\n');

    await SharePlus.instance.share(ShareParams(text: text, subject: '직원 초대 코드'));
  }
}

