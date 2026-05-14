import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/verify_theme.dart';

/// 접근코드 게이트 화면 — 노무법인이 발급받은 코드를 입력하는 진입점
class AccessGateScreen extends StatefulWidget {
  const AccessGateScreen({super.key});

  @override
  State<AccessGateScreen> createState() => _AccessGateScreenState();
}

class _AccessGateScreenState extends State<AccessGateScreen> {
  final _codeController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _verifyCode() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.isEmpty) {
      setState(() => _errorMessage = '접근 코드를 입력해주세요.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final doc = await FirebaseFirestore.instance
          .collection('verify_access')
          .doc(code)
          .get();

      if (!doc.exists) {
        setState(() => _errorMessage = '유효하지 않은 코드입니다.');
        return;
      }

      final data = doc.data()!;
      final enabled = data['enabled'] as bool? ?? false;

      if (!enabled) {
        setState(() => _errorMessage = '이 코드는 현재 비활성 상태입니다.');
        return;
      }

      // 유효기간 확인
      final expiresAt = data['expiresAt'] as Timestamp?;
      if (expiresAt != null && expiresAt.toDate().isBefore(DateTime.now())) {
        setState(() => _errorMessage = '이 코드의 유효기간이 만료되었습니다.');
        return;
      }

      // 사용 로그 기록
      await FirebaseFirestore.instance
          .collection('verify_access')
          .doc(code)
          .collection('usage_logs')
          .add({
        'accessedAt': FieldValue.serverTimestamp(),
        'firmName': data['firmName'] ?? '',
      });

      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/verify');
    } catch (e) {
      setState(() => _errorMessage = '서버 연결에 실패했습니다. 잠시 후 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 로고 영역
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [VerifyTheme.accentPrimary, VerifyTheme.accentSecondary],
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.verified_outlined, size: 40, color: Colors.white),
                ),
                const SizedBox(height: 24),
                const Text(
                  'AlbaPay 급여 검증기',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: VerifyTheme.textPrimary),
                ),
                const SizedBox(height: 8),
                const Text(
                  'AlbaPay 급여 계산 검증 도구',
                  style: TextStyle(fontSize: 14, color: VerifyTheme.textSecondary),
                ),
                const SizedBox(height: 48),

                // 접근코드 입력 카드
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          '접근 코드 입력',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: VerifyTheme.textPrimary),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '발급받은 접근 코드를 입력하세요.',
                          style: TextStyle(fontSize: 13, color: VerifyTheme.textSecondary),
                        ),
                        const SizedBox(height: 24),
                        TextField(
                          controller: _codeController,
                          textCapitalization: TextCapitalization.characters,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 4,
                            color: VerifyTheme.textPrimary,
                          ),
                          textAlign: TextAlign.center,
                          decoration: const InputDecoration(
                            hintText: 'CODE-001',
                            hintStyle: TextStyle(color: VerifyTheme.textSecondary, letterSpacing: 4),
                          ),
                          onSubmitted: (_) => _verifyCode(),
                        ),
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: VerifyTheme.accentRed.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: VerifyTheme.accentRed.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline, color: VerifyTheme.accentRed, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _errorMessage!,
                                    style: const TextStyle(color: VerifyTheme.accentRed, fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: _isLoading ? null : _verifyCode,
                          child: _isLoading
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Text('확인'),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),
                // 관리자 링크
                TextButton(
                  onPressed: () => Navigator.pushNamed(context, '/admin'),
                  child: const Text(
                    '관리자 로그인 →',
                    style: TextStyle(color: VerifyTheme.textSecondary, fontSize: 12),
                  ),
                ),

                const SizedBox(height: 32),
                // 안내
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: VerifyTheme.accentPrimary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: VerifyTheme.accentPrimary.withValues(alpha: 0.2)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.lock_outline, color: VerifyTheme.accentPrimary, size: 18),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '모든 계산은 브라우저 내에서 처리됩니다.\n입력하신 데이터는 서버에 저장되지 않습니다.',
                          style: TextStyle(color: VerifyTheme.textSecondary, fontSize: 12, height: 1.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
