import 'package:flutter/material.dart';
import '../../services/boss_logout.dart';
import 'package:shared_logic/shared_logic.dart';

class WebAccessDeniedScreen extends StatelessWidget {
  final AuthService _authService = AuthService();

  WebAccessDeniedScreen({super.key});

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
              const Icon(Icons.block, size: 80, color: Colors.redAccent),
              const SizedBox(height: 24),
              const Text(
                '접근 제한',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '현재 접속하신 웹/PC 버전은 사장님 전용 관리 대시보드입니다.\n\n알바 업무(출퇴근 및 급여 확인)는 보안을 위해 스마트폰 전용 앱에서만 가능합니다. 앱을 이용해 주세요.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: Colors.black54, height: 1.5),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.icon(
                  icon: const Icon(Icons.logout),
                  onPressed: () => performBossLogout(_authService),
                  label: const Text('로그아웃 및 돌아가기', style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
