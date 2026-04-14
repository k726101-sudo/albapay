import 'package:flutter/material.dart';
import 'package:boss_mobile/services/backup_service.dart';
import 'package:boss_mobile/services/withdraw_service.dart';
import 'package:local_auth/local_auth.dart';

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
        title: const Text('⚠️ 최후통첩'),
        content: const Text(
          '정말 탈퇴하시겠습니까?\n이 작업은 되돌릴 수 없으며, 사장님의 모든 노무 데이터가 1바이트도 남김없이 영구 소각됩니다.',
          style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('네, 영구 파기합니다'),
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
          localizedReason: '계정 및 데이터를 영구 파기하기 위해 본인 인증을 진행합니다.',
        );
        if (!authenticated) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('생체 인증에 실패하여 취소되었습니다.')));
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('탈퇴 처리 중 오류 발생: $e\n잠시 후 다시 시도해주시거나, 보안을 위해 로그아웃 후 재로그인해주십시오.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('회원 탈퇴 및 데이터 파기'),
        foregroundColor: Colors.red.shade900,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.warning_amber_rounded, size: 64, color: Colors.orange),
            const SizedBox(height: 16),
            const Text(
              '회원을 탈퇴하시면 앱에 보관 중인 모든 근로계약서, 출퇴근 기록, 급여 내역이 즉시 영구 파기됩니다.',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Column(
                children: [
                  const Text('탈퇴 전 반드시 데이터를 저장하세요!', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: _isDeleting ? null : _runBackup,
                      icon: const Icon(Icons.cloud_download),
                      label: const Text('기기에 백업 파일 다운로드 및 저장'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              '강제 면책 확약',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red),
            ),
            const SizedBox(height: 12),
            _buildCheckRow(
              _check1,
              (v) => setState(() => _check1 = v ?? false),
              '백업하지 않은 데이터는 탈퇴 즉시 파기되며, 어떠한 수단으로도 복구가 불가능함에 동의합니다.',
            ),
            _buildCheckRow(
              _check2,
              (v) => setState(() => _check2 = v ?? false),
              '이후 발생하는 노동 분쟁 및 근로감독관 조사 시 증빙 자료 손실에 대한 모든 법적 책임은 전적으로 본인(사업주)에게 있음을 맹세합니다.',
            ),
            _buildCheckRow(
              _check3,
              (v) => setState(() => _check3 = v ?? false),
              '개인정보 보호법에 따라 서버에서 즉시 영구 삭제(소각) 처리 되는 규정에 동의합니다.',
            ),
            const SizedBox(height: 48),
            SizedBox(
              height: 56,
              child: FilledButton(
                onPressed: _isDeleting || !_canDelete ? null : _handleWithdraw,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  disabledBackgroundColor: Colors.grey.shade300,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isDeleting 
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('영구 탈퇴 및 데이터 즉시 파기', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckRow(bool value, ValueChanged<bool?> onChanged, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: Checkbox(
              value: value,
              onChanged: _isDeleting ? null : onChanged,
              activeColor: Colors.red,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
