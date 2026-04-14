import 'package:flutter/material.dart';

class TermsConsentPopup extends StatefulWidget {
  const TermsConsentPopup({super.key});

  @override
  State<TermsConsentPopup> createState() => _TermsConsentPopupState();
}

class _TermsConsentPopupState extends State<TermsConsentPopup> {
  bool _agreedAll = false;
  bool _agreedTerms = false;
  bool _agreedPrivacy = false;

  static const String _termsText = '''
[서비스 이용약관]

제1조 (목적)
본 약관은 "알바급여정석"(이하 "서비스")이 제공하는 제반 서비스의 이용과 관련하여 회사와 회원(실사용자) 간의 권리, 의무 및 책임사항, 기타 필요한 사항을 규정함을 목적으로 합니다.

제2조 (데이터 보존 의무 및 면책)
1. 근로기준법 제42조에 따른 근로계약 서류 및 주요 서류의 3년 보존 의무는 사용자(사장님) 본인에게 있습니다.
2. 본 서비스는 기록의 편의를 돕는 도구일 뿐이며, 기기 고장, 데이터 유실, 백업 미비로 인한 결과에 대하여 서비스는 어떠한 법적 책임도 지지 않습니다.
3. 클라우드 연동 기능을 사용하지 않을 경우 발생하는 데이터 유실의 책임은 전적으로 사용자에게 있습니다.

제3조 (서비스 이용의 제한)
회사는 회원이 본 약관의 의무를 위반하거나 서비스의 정상적인 운영을 방해하는 경우, 서비스 이용을 즉시 제한하거나 계정을 삭제할 수 있습니다.
''';

  static const String _privacyText = '''
[개인정보 수집 및 이용 동의]

1. 수집 및 이용 목적
회원 가입, 서비스 부정이용 방지, 필수 약관 동의 이력 보관, 직원 관리 및 급여/출퇴근 정산 등 앱 서비스의 기본 기능 제공

2. 수집하는 개인정보 항목
성명, 전화번호, 이메일 주소, 사업장 정보, 접속 IP 주소, 기기 모델명, OS 버전 및 접속 로그

3. 개인정보의 보유 및 이용 기간
회원 탈퇴 시 또는 1년 이상 장기 미이용 시 지체 없이 안전하게 파기됩니다. (단, 사용증명, 전자문서 확인 이력 등 관계 법령에 의거 보존할 필요가 있는 경우 3년 등 해당 법령이 정한 기간 동안 보존)

4. 동의 거부 안내
귀하는 본 개인정보 수집 및 이용 동의를 거부할 권리가 있습니다. 단, 본 정보는 원활한 앱 서비스 제공을 위한 필수 정보이므로, 동의 거부 시 앱 서비스 이용이 제한됩니다.
''';

  void _toggleAll(bool? val) {
    setState(() {
      _agreedAll = val ?? false;
      _agreedTerms = _agreedAll;
      _agreedPrivacy = _agreedAll;
    });
  }

  void _checkIndividual() {
    setState(() {
      _agreedAll = _agreedTerms && _agreedPrivacy;
    });
  }

  void _showDetail(String title, String content) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: Text(content, style: const TextStyle(fontSize: 14, height: 1.5, color: Colors.black87)),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1a1a2e),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('닫기'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool canProceed = _agreedTerms && _agreedPrivacy;

    return Dialog.fullscreen(
      backgroundColor: Colors.transparent,
      child: Container(
        color: const Color(0xFFF2F2F7),
        child: Column(
          children: [
            AppBar(
              title: const Text('서비스 이용 동의', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(false),
              ),
              elevation: 0,
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 20),
                    const Text(
                      '환영합니다!\n서비스 이용을 위해 약관에 동의해 주세요.',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, height: 1.4),
                    ),
                    const SizedBox(height: 48),
                    
                    // 전체 동의
                    InkWell(
                      onTap: () => _toggleAll(!_agreedAll),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _agreedAll ? const Color(0xFF1a1a2e) : Colors.grey.shade300, width: 2),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _agreedAll ? Icons.check_circle : Icons.circle_outlined,
                              color: _agreedAll ? const Color(0xFF1a1a2e) : Colors.grey.shade400,
                              size: 28,
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              '약관에 모두 동의합니다.',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    // 개별 동의: 서비스 이용약관
                    Row(
                      children: [
                        IconButton(
                          onPressed: () {
                            setState(() {
                              _agreedTerms = !_agreedTerms;
                              _checkIndividual();
                            });
                          },
                          icon: Icon(
                            _agreedTerms ? Icons.check_box : Icons.check_box_outline_blank,
                            color: _agreedTerms ? const Color(0xFF1a1a2e) : Colors.grey.shade500,
                          ),
                        ),
                        const Expanded(
                          child: Text(
                            '[필수] 서비스 이용약관 동의',
                            style: TextStyle(fontSize: 16),
                          ),
                        ),
                        TextButton(
                          onPressed: () => _showDetail('서비스 이용약관', _termsText),
                          child: const Text('보기', style: TextStyle(color: Colors.grey, decoration: TextDecoration.underline)),
                        ),
                      ],
                    ),
                    
                    // 개별 동의: 개인정보 처리방침
                    Row(
                      children: [
                        IconButton(
                          onPressed: () {
                            setState(() {
                              _agreedPrivacy = !_agreedPrivacy;
                              _checkIndividual();
                            });
                          },
                          icon: Icon(
                            _agreedPrivacy ? Icons.check_box : Icons.check_box_outline_blank,
                            color: _agreedPrivacy ? const Color(0xFF1a1a2e) : Colors.grey.shade500,
                          ),
                        ),
                        const Expanded(
                          child: Text(
                            '[필수] 개인정보 수집 및 이용 동의',
                            style: TextStyle(fontSize: 16),
                          ),
                        ),
                        TextButton(
                          onPressed: () => _showDetail('개인정보 수집 및 이용 동의', _privacyText),
                          child: const Text('보기', style: TextStyle(color: Colors.grey, decoration: TextDecoration.underline)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    offset: const Offset(0, -4),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  onPressed: canProceed ? () => Navigator.of(context).pop(true) : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF1a1a2e),
                    disabledBackgroundColor: Colors.grey.shade300,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text(
                    '동의하고 시작하기',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
