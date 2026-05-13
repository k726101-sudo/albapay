import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// 웹 브라우저(카카오톡 인앱 브라우저 포함)에서 /invite 링크를 열었을 때 보여주는 화면.
/// 앱이 이미 설치되어 있는 경우 "앱에서 열기" 버튼으로 네이티브 앱을 직접 실행할 수 있도록 합니다.
class WebInviteLandingScreen extends StatelessWidget {
  const WebInviteLandingScreen({super.key, this.inviteCode});

  final String? inviteCode;

  Future<void> _launchURL(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// 설치된 앱을 직접 실행 (카카오톡 인앱 브라우저 우회)
  Future<void> _openInApp() async {
    final code = inviteCode ?? '';

    // Android: intent:// 스킴으로 앱 직접 호출
    // iOS: 유니버셜 링크를 외부 브라우저로 열어서 앱 전환 유도
    if (defaultTargetPlatform == TargetPlatform.android) {
      // Android intent URL: 카카오톡 인앱 브라우저에서도 네이티브 앱 호출 가능
      final intentUrl = 'intent://invite?code=$code'
          '#Intent;'
          'scheme=https;'
          'host=standard-albapay.web.app;'
          'package=com.standard.albapay;'
          'end;';
      final uri = Uri.parse(intentUrl);
      try {
        await launchUrl(uri, mode: LaunchMode.externalNonBrowserApplication);
      } catch (_) {
        // intent 실패 시 일반 https로 외부 브라우저 열기
        await _launchURL('https://standard-albapay.web.app/invite?code=$code');
      }
    } else {
      // iOS: 외부 Safari에서 유니버셜 링크로 앱 연결
      await launchUrl(
        Uri.parse('https://standard-albapay.web.app/invite?code=$code'),
        mode: LaunchMode.externalApplication,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.smartphone, size: 80, color: Colors.blueAccent),
              const SizedBox(height: 24),
              const Text(
                '알바급여정석',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '출퇴근 체크 및 근로계약서 확인 등 알바 시스템은 보안을 위해 전용 모바일 앱에서만 지원됩니다.\n아래 스토어에서 앱을 설치한 후 다시 링크를 눌러주세요!',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: Colors.black54, height: 1.5),
              ),
              if (inviteCode != null && inviteCode!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F7FF),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFBBDEFB)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.vpn_key, size: 16, color: Color(0xFF1976D2)),
                      const SizedBox(width: 8),
                      Text(
                        '초대코드: $inviteCode',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1976D2),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 28),

              // ★ 이미 설치한 경우: 앱에서 열기 (카카오톡 인앱 브라우저 우회)
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  icon: const Icon(Icons.open_in_new_rounded),
                  onPressed: _openInApp,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  label: const Text(
                    '✅ 설치 완료! 앱에서 열기',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ),

              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 8),
              const Text(
                '아직 설치하지 않으셨나요?',
                style: TextStyle(fontSize: 13, color: Colors.black45),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.icon(
                  icon: const Icon(Icons.android),
                  onPressed: () => _launchURL('https://play.google.com/store/apps/details?id=com.standard.albapay'),
                  label: const Text('Google Play 다운로드', style: TextStyle(fontSize: 16)),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: Colors.black),
                  icon: const Icon(Icons.apple),
                  onPressed: () => _launchURL('https://apps.apple.com/app/id6762085252'),
                  label: const Text('App Store 다운로드', style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
