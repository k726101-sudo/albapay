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
    final inviteUrl =
        'https://$_albaWebOriginHost/?invite_code=${Uri.encodeComponent(inviteCode)}&store_id=${Uri.encodeComponent(storeId)}';

    final text = [
      '안녕하세요.',
      '아래 정보로 앱에 접속해 주세요.',
      '매장: $storeName',
      '알바생: $staffName',
      '초대 코드: $inviteCode',
      '초대 링크: $inviteUrl',
      // WebOTP / iOS 키보드 "메시지에서 코드" 자동완성 트리거
      '@$_albaWebOriginHost #$inviteCode',
    ].join('\n');

    await SharePlus.instance.share(ShareParams(text: text, subject: '직원 초대 코드'));
  }
}

