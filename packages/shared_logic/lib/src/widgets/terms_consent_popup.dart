import 'package:flutter/material.dart';

class TermsConsentPopup extends StatefulWidget {
  const TermsConsentPopup({super.key});

  @override
  State<TermsConsentPopup> createState() => _TermsConsentPopupState();
}

class _TermsConsentPopupState extends State<TermsConsentPopup> {
  bool _agreedAll = false;

  // 5 Required
  bool _agreedTerms = false;
  bool _agreedPrivacyCollection = false;
  bool _agreedLocationService = false;
  bool _agreedPrivacyPolicy = false;
  bool _agreedLocationPolicy = false;

  // 1 Optional
  bool _agreedMarketing = false;

  static const String _termsText = '''
[서비스 이용약관]

제1조 (목적)
본 약관은 "알바급여정석"(이하 "서비스")이 제공하는 제반 서비스의 이용과 관련하여 회사와 회원 간의 권리, 의무 및 책임사항, 기타 필요한 사항을 규정함을 목적으로 합니다.

제2조 (데이터 보존 의무 및 면책)
1. 근로계약 서류 및 주요 서류의 법정 보존 의무는 사용자(사장님) 본인에게 있습니다.
2. 본 서비스는 데이터 유실에 대하여 책임을 지지 않습니다.
''';

  static const String _privacyCollectionText = '''
[개인정보 수집 및 이용 동의]

1. 수집 및 이용 목적
회원 가입, 부정이용 방지, 필수 약관 동의 이력 보관, 직원 관리 및 급여/출퇴근 정산

2. 수집하는 정보
성명, 전화번호, 이메일 주소, 사업장 정보, 접속 로그, IP, 기기 정보
''';

  static const String _locationServiceText = '''
[위치기반서비스 이용약관]

1. 목적
본 약관은 회사가 제공하는 위치기반서비스(출퇴근 GPS 인증 등)에 대해 회사와 개인위치정보주체와의 권리, 의무를 규정합니다.

2. 서비스 내용
사용자의 모바일 기기 GPS 정보를 수집하여 지정된 사업장 반경 내에서의 출퇴근 인증 기능을 제공합니다.
''';

  static const String _privacyPolicyText = '''
[개인정보 처리방침]

1. 총칙
회사는 회원의 개인정보를 매우 중요하게 생각하며, 개인정보보호법 등 관련 법령을 준수합니다.

2. 파기 절차 및 방법
이용 목적이 달성된 개인정보는 원칙적으로 지체 없이 파기합니다.
''';

  static const String _locationPolicyText = '''
[개인위치정보 처리방침]

1. 위치정보 수집 방법 및 보유기간
회사는 출퇴근 인증을 위해 실시간 위치정보를 확인하며, 인증 즉시 해당 좌표 데이터는 출퇴근 기록(시간)으로 변환되어 보관되고 타 목적으로 사용되지 않습니다.
''';

  static const String _marketingText = '''
[마케팅 활용 이용동의]

1. 수집 목적
신규 서비스 안내, 프로모션 혜택, 이벤트 안내 송부

2. 개인정보 항목
휴대전화 번호, 이메일

3. 동의 철회
사용자는 언제든 고객센터나 앱 내 설정을 통해 마케팅 수신 동의를 철회할 수 있습니다.
''';

  void _toggleAll(bool? val) {
    final v = val ?? false;
    setState(() {
      _agreedAll = v;
      _agreedTerms = v;
      _agreedPrivacyCollection = v;
      _agreedLocationService = v;
      _agreedPrivacyPolicy = v;
      _agreedLocationPolicy = v;
      _agreedMarketing = v;
    });
  }

  void _checkIndividual() {
    setState(() {
      _agreedAll =
          _agreedTerms &&
          _agreedPrivacyCollection &&
          _agreedLocationService &&
          _agreedPrivacyPolicy &&
          _agreedLocationPolicy &&
          _agreedMarketing;
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
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: Text(
                    content,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1a1a2e),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('닫기'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConsentRow({
    required bool isRequired,
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
    required String contentText,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              onChanged(!value);
            },
            icon: Icon(
              value ? Icons.check_box : Icons.check_box_outline_blank,
              color: value ? const Color(0xFF1a1a2e) : Colors.grey.shade500,
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => onChanged(!value),
              child: Text(
                '[${isRequired ? '필수' : '선택'}] $title',
                style: const TextStyle(fontSize: 15),
              ),
            ),
          ),
          TextButton(
            onPressed: () => _showDetail(title, contentText),
            child: const Text(
              '보기',
              style: TextStyle(
                color: Colors.grey,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool canProceed =
        _agreedTerms &&
        _agreedPrivacyCollection &&
        _agreedLocationService &&
        _agreedPrivacyPolicy &&
        _agreedLocationPolicy;

    return Dialog.fullscreen(
      backgroundColor: Colors.transparent,
      child: Container(
        color: const Color(0xFFF2F2F7),
        child: Column(
          children: [
            AppBar(
              title: const Text(
                '서비스 이용 동의',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
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
                    const Text(
                      '환영합니다!\n원활한 서비스 이용을 위해\n약관에 동의해 주세요.',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 32),

                    // 전체 동의
                    InkWell(
                      onTap: () => _toggleAll(!_agreedAll),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 16,
                          horizontal: 16,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _agreedAll
                                ? const Color(0xFF1a1a2e)
                                : Colors.grey.shade300,
                            width: 2,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _agreedAll
                                  ? Icons.check_circle
                                  : Icons.circle_outlined,
                              color: _agreedAll
                                  ? const Color(0xFF1a1a2e)
                                  : Colors.grey.shade400,
                              size: 28,
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              '약관에 모두 동의합니다.',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        children: [
                          _buildConsentRow(
                            isRequired: true,
                            title: '서비스 이용약관',
                            value: _agreedTerms,
                            onChanged: (v) {
                              setState(() {
                                _agreedTerms = v;
                                _checkIndividual();
                              });
                            },
                            contentText: _termsText,
                          ),
                          _buildConsentRow(
                            isRequired: true,
                            title: '개인정보 수집 이용동의',
                            value: _agreedPrivacyCollection,
                            onChanged: (v) {
                              setState(() {
                                _agreedPrivacyCollection = v;
                                _checkIndividual();
                              });
                            },
                            contentText: _privacyCollectionText,
                          ),
                          _buildConsentRow(
                            isRequired: true,
                            title: '위치기반서비스 이용약관',
                            value: _agreedLocationService,
                            onChanged: (v) {
                              setState(() {
                                _agreedLocationService = v;
                                _checkIndividual();
                              });
                            },
                            contentText: _locationServiceText,
                          ),
                          _buildConsentRow(
                            isRequired: true,
                            title: '개인정보 처리방침',
                            value: _agreedPrivacyPolicy,
                            onChanged: (v) {
                              setState(() {
                                _agreedPrivacyPolicy = v;
                                _checkIndividual();
                              });
                            },
                            contentText: _privacyPolicyText,
                          ),
                          _buildConsentRow(
                            isRequired: true,
                            title: '개인위치정보 처리방침',
                            value: _agreedLocationPolicy,
                            onChanged: (v) {
                              setState(() {
                                _agreedLocationPolicy = v;
                                _checkIndividual();
                              });
                            },
                            contentText: _locationPolicyText,
                          ),
                          const Divider(height: 1),
                          _buildConsentRow(
                            isRequired: false,
                            title: '마케팅 활용 이용동의',
                            value: _agreedMarketing,
                            onChanged: (v) {
                              setState(() {
                                _agreedMarketing = v;
                                _checkIndividual();
                              });
                            },
                            contentText: _marketingText,
                          ),
                        ],
                      ),
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
                  onPressed: canProceed
                      ? () => Navigator.of(context).pop(true)
                      : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF1a1a2e),
                    disabledBackgroundColor: Colors.grey.shade300,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
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
