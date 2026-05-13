import 'package:flutter/material.dart';

class LegalScreen extends StatelessWidget {
  final String type; // 'terms' 또는 'privacy'

  const LegalScreen({super.key, required this.type});

  @override
  Widget build(BuildContext context) {
    final bool isPrivacy = type == 'privacy';
    final String title = isPrivacy ? '개인정보처리방침' : '면책 고지';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            isPrivacy ? _buildPrivacyContent() : _buildTermsContent(),
            const SizedBox(height: 60),
            const Center(
              child: Text(
                'ⓒ 2024 알바급여정석 All rights reserved.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTermsContent() {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle('제1조 (목적)'),
        _SectionBody('본 고지 및 이용약관은 "알바급여정석"(이하 "앱")이 제공하는 노무 관리, 출퇴근 기록, 급여 계산 등 제반 서비스(이하 "서비스")를 이용함에 있어, 회사와 사용자 간의 권리, 의무 및 책임 사항, 기타 필요한 사항을 규정함을 목적으로 합니다.'),
        
        _SectionTitle('제2조 (정보의 정확성 및 면책 사항)'),
        _SectionBody('1. 본 앱은 최신 근로기준법 및 시행령을 바탕으로 한 내부 알고리즘을 통해 급여 계산, 가산 수당 판독, 5인 이상 사업장 여부 등을 산출합니다. 그러나 이는 사용자의 편의를 돕기 위한 **"단순 참고용 데이터"**입니다.\n'
            '2. 개별 사업장의 취업규칙, 포괄임금제, 특수 고용 형태 등 복합적인 예외 구역에 대해서는 완벽히 대응할 수 없으므로, **앱이 도출한 결과값은 어떠한 법적 효력이나 보증을 갖지 않습니다.**\n'
            '3. 사용자의 잘못된 근무 시간 입력, 시급 설정 오류, 누락 등으로 인해 발생한 직접적/간접적 손해 및 임금 체불 등 법적 분쟁에 대하여 서비스 제공자(개발사)는 일체의 법적 책임을 지지 않습니다.'),
        
        _SectionTitle('제3조 (전문가 자문 권고 및 증거 효력 제약)'),
        _SectionBody('앱에서 제공하는 전자 근로계약서 및 임금명세서는 노동부 표준 양식을 차용하였으나, 실제 노무 분쟁 발생 시 해당 문건의 법적 인정 여부는 관계 기관의 최종 판단에 따릅니다. 사용자는 중대한 노무 결정 전 반드시 노무사, 변호사 등 국가 공인 전문가의 자문을 받아야 합니다.'),
        
        _SectionTitle('제4조 (계정 관리 및 보호 위반 조치)'),
        _SectionBody('사용자는 자신의 계정(비밀번호 제외, 인증 토큰 등) 및 기기를 안전하게 관리할 책임이 있습니다. 애플 앱스토어 및 구글 플레이스토어 정책에 따라 타인의 명의를 도용하거나, 불법적인 목적으로 서비스를 악용하는 경우 사전 통보 없이 계정이 영구 정지 및 파기될 수 있습니다.'),
        
        _SectionTitle('제5조 (서비스의 변경 및 중단)'),
        _SectionBody('천재지변, 서버(Firebase 등)의 물리적/소프트웨어적 오류, 정기 점검 등의 불가항력적 사유로 서비스가 중단되거나 저장된 데이터가 손실될 수 있습니다. 회사는 백업 및 복구(공유) 기능을 제공하므로, 사용자는 주기적으로 데이터를 기기에 백업할 의무가 있습니다.'),
      ],
    );
  }

  Widget _buildPrivacyContent() {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle('제 1 조 (수집하는 개인정보의 항목 및 수집 방법)'),
        _SectionBody('회사는 서비스 제공을 위해 아래와 같은 개인정보를 수집하고 있습니다.\n'
            '- 필수 수집 항목: 성명, 휴대폰 번호, 소속 사업장(매장) 식별 정보, 출퇴근 기록\n'
            '- 자동 수집 항목: 접속 IP 주소, 기기정보(운영체제, 모델명, 브라우저 버전), 서비스 이용 기록(접속 로그)\n'
            '- 선택 수집 항목: **서면 계약 시 GPS 기반 위치 데이터** (사장님 전용 네이티브 앱을 통한 대면 전자서명 시 사용자 화면 내 직접 동의를 거친 경우에 한함)\n'
            '- 알바용 웹(Web) 앱 정책: 알바생 본인이 사용하는 웹 앱 환경에서는 실시간 백그라운드 위치 정보 및 GPS 추적 기능을 일절 포함하거나 수집하지 않습니다.'),

        _SectionTitle('제 2 조 (개인정보의 수집 및 이용 목적)'),
        _SectionBody('수집된 개인정보는 다음의 목적 내에서만 이용됩니다.\n'
            '1. 전자 근로계약서 교부, 임금 명세서 발송 및 제증명서 발급 등 법적 의무 이행\n'
            '2. SMS 또는 알림톡을 통한 본인 인증 체계(Passwordless Auth) 운영\n'
            '3. 악의적 위변조 식별(IP, 기기 메타데이터) 및 노무 분쟁 발생 시 당사자 간의 증빙 보조\n'
            '4. 서비스 안정성 확보를 위한 오류 통계 처리 및 앱스토어 장애 대응 (Firebase Analytics 등)'),

        _SectionTitle('제 3 조 (제3자 정보 제공 및 클라우드 서비스 연동)'),
        _SectionBody('앱은 원활한 서비스 안정성을 향상하기 위해 다음과 같은 글로벌 클라우드 서비스에 데이터를 위탁하여 처리합니다.\n'
            '- Google Firebase (Firestore, Storage, Authentication): 클라우드 데이터베이스 저장, 사진/서명 이미지 암호화 보관, 본인 식별 인증 토큰 관리\n'
            '회사는 정보 주체의 별도 동의 없이는 원칙적으로 수집 목적 외로 외부(제3자)에 정보를 제공하지 않으나, 관련 법령에 따른 국가 기관의 적법한 수사 협조 요청이 있을 경우는 예외로 합니다.'),

        _SectionTitle('제 4 조 (개인정보의 보유, 보존 및 파기 기간)'),
        _SectionBody('① 회사는 이용자가 회원 자격을 유지하는 동안 개인정보를 보유합니다.\n'
            '② 단, 근로기준법 제42조에 근거하여 "근로자 명부 및 대통령령으로 정하는 중요 서류"는 고용 관계가 종료된 시점으로부터 **3년 동안 보존**할 의무가 있으므로, 해당 기간 동안 안전하게 분리 보관한 뒤 파기합니다.\n'
            '③ 1년 이상 서비스를 이용하지 않은 장기 휴면 계정은 사전 통지 후 관계 법령에 따라 모든 정보를 "0바이트 오버라이트" 처리하여 영구 파기합니다.'),

        _SectionTitle('제 5 조 (동의 철회, 회원 탈퇴 및 정보 파기 방법)'),
        _SectionBody('사용자(사업주 및 근로자)는 본인 인증 절차를 거친 후 당사에 개인정보 처리 정지 및 회원 탈퇴를 요청할 수 있습니다.\n'
            '- 탈퇴 경로: 사장님 전용 앱 내 **[설정] > [계정 : 회원 탈퇴]**를 클릭하여 실행.\n'
            '탈퇴 신청 시 시스템은 클라우드 상에 기록된 사용자의 모든 하위 매장 및 직원 데이터를 복구 불가능한 상태로 영구 삭제(Drop)합니다.'),

        _SectionTitle('제 6 조 (개인정보 보호책임자 안내)'),
        _SectionBody('본 앱은 개인정보 처리에 관한 업무를 총괄해서 책임지고, 관련 불만 처리 및 피해 구제를 위해 아래와 같이 개인정보 보호책임자를 지정하고 있습니다.\n'
            '- 책임자명: [개발사 책임자 이름/직급 입력]\n'
            '- 연락처: [고객센터 이메일 등 연락처 입력]\n'
            'App Store 및 Google Play Store의 법적 운영 지침에 따라, 사용자의 개인정보 관리와 관련된 모든 문의는 해당 연락처를 통해 가장 신속하게 처리됩니다.'),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.indigo),
      ),
    );
  }
}

class _SectionBody extends StatelessWidget {
  final String body;
  const _SectionBody(this.body);

  @override
  Widget build(BuildContext context) {
    return Text(
      body,
      style: const TextStyle(fontSize: 14, height: 1.6, color: Colors.black87),
    );
  }
}
