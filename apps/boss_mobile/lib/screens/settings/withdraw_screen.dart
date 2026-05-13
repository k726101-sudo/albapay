import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart' as google_sign_in;
import 'package:boss_mobile/services/backup_service.dart';
import 'package:boss_mobile/services/withdraw_service.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_logic/shared_logic.dart' show OnboardingGuideService;

class WithdrawScreen extends StatefulWidget {
  final String storeId;
  const WithdrawScreen({super.key, required this.storeId});

  @override
  State<WithdrawScreen> createState() => _WithdrawScreenState();
}

class _WithdrawScreenState extends State<WithdrawScreen> {
  final LocalAuthentication _auth = LocalAuthentication();
  bool _check1 = false;
  bool _check2 = false;
  bool _check3 = false;
  bool _isDeleting = false;

  bool get _canDelete => _check1 && _check2 && _check3;

  void _runBackup() async {
    try {
      await BackupService.runBackup(silent: false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('백업이 완료되었습니다. 이제 안전하게 탈퇴하실 수 있습니다.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('백업 중 오류가 발생했습니다: $e')),
        );
      }
    }
  }

  void _handleWithdraw() async {
    if (!_canDelete) return;
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: Color(0xFF1565C0), size: 24),
            SizedBox(width: 8),
            Text('탈퇴 확인', style: TextStyle(fontSize: 18)),
          ],
        ),
        content: const Text(
          '정말 탈퇴하시겠어요?\n\n탈퇴하시면 저장된 데이터가 모두 삭제되며,\n이후 복구가 어렵습니다.',
          style: TextStyle(fontSize: 15, height: 1.5, color: Color(0xFF444444)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('다시 생각할게요', style: TextStyle(fontSize: 15)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE57373),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('탈퇴할게요', style: TextStyle(fontSize: 15)),
          ),
        ],
      ),
    );



    if (confirm != true || !mounted) return;

    // 생체 인증 거치기 (Face ID / Touch ID)
    try {
      final canCheckBiometrics = await _auth.canCheckBiometrics;
      final isDeviceSupported = await _auth.isDeviceSupported();
      if (canCheckBiometrics && isDeviceSupported) {
        final authenticated = await _auth.authenticate(
          localizedReason: '본인 확인을 위해 인증해 주세요.',
        );
        if (!authenticated) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('인증에 실패하여 취소되었습니다.')));
          return;
        }
      }
    } catch (e) {
      debugPrint('Biometric error: $e');
    }

    if (!mounted) return;
    setState(() => _isDeleting = true);
    
    try {
      // 탈퇴 프로세스 호출
      await WithdrawService.deleteAccountAndData(widget.storeId);
      
      if (!mounted) return;
      // 강제 로그아웃 후 로그인 화면으로 떨어지게 됨
      Navigator.of(context).popUntil((route) => route.isFirst);
      
    } catch (e) {
      if (mounted) {
        setState(() => _isDeleting = false);
        final String errorStr = e.toString().replaceFirst('Exception: ', '').replaceFirst('FirebaseAuthException: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('탈퇴 실패: $errorStr'),
            duration: const Duration(seconds: 7),
            behavior: SnackBarBehavior.floating,
            action: errorStr.contains('보안을 위해') 
              ? SnackBarAction(
                  label: '로그아웃 하기',
                  textColor: Colors.yellow,
                  onPressed: () async {
                    try {
                      await FirebaseAuth.instance.signOut();
                      await google_sign_in.GoogleSignIn.instance.signOut();
                      await OnboardingGuideService.instance.reset();
                    } catch (_) {}
                    if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
                  },
                )
              : null,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('회원 탈퇴'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.sentiment_dissatisfied_outlined, size: 56, color: Color(0xFF9E9E9E)),
            const SizedBox(height: 12),
            const Text(
              '정말 떠나시나요?',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFF333333)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              '탈퇴하시면 앱에 보관 중인 근로계약서, 출퇴근 기록,\n급여 내역이 모두 삭제됩니다.',
              style: TextStyle(fontSize: 14, color: Color(0xFF888888), height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),

            // 백업 안내
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F7FF),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFBBDEFB)),
              ),
              child: Column(
                children: [
                  const Row(
                    children: [
                      Icon(Icons.cloud_download_outlined, color: Color(0xFF1565C0), size: 22),
                      SizedBox(width: 8),
                      Text('탈퇴 전 데이터를 백업하세요', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Color(0xFF1565C0))),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: FilledButton.icon(
                      onPressed: _isDeleting ? null : _runBackup,
                      icon: const Icon(Icons.download, size: 18),
                      label: const Text('기기에 백업 파일 저장'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF1565C0),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // 동의 항목
            const Text(
              '아래 내용을 확인해 주세요',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF555555)),
            ),
            const SizedBox(height: 12),
            _buildCheckRow(
              _check1,
              (v) => setState(() => _check1 = v ?? false),
              '백업하지 않은 데이터는 탈퇴 후 복구할 수 없음을 이해했습니다.',
            ),
            _buildCheckRow(
              _check2,
              (v) => setState(() => _check2 = v ?? false),
              '탈퇴 후 근로 관련 증빙 자료가 필요할 경우, 별도로 보관한 백업 파일을 활용해야 함을 이해했습니다.',
            ),
            _buildCheckRow(
              _check3,
              (v) => setState(() => _check3 = v ?? false),
              '개인정보 보호법에 따라 서버의 모든 데이터가 삭제되는 것에 동의합니다.',
            ),
            const SizedBox(height: 40),

            // 탈퇴 버튼
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: _isDeleting || !_canDelete ? null : _handleWithdraw,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFE57373),
                  disabledBackgroundColor: Colors.grey.shade300,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isDeleting 
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('탈퇴하기', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckRow(bool value, ValueChanged<bool?> onChanged, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: _isDeleting ? null : () => onChanged(!value),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: value ? const Color(0xFFFFF3E0) : const Color(0xFFFAFAFA),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: value ? const Color(0xFFFFB74D) : const Color(0xFFE0E0E0),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: Checkbox(
                  value: value,
                  onChanged: _isDeleting ? null : onChanged,
                  activeColor: const Color(0xFFFF9800),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: value ? const Color(0xFF795548) : Colors.grey.shade600,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
