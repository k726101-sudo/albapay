class DocumentTemplates {
  static String getLaborContract(Map<String, String> data) {
    return '''
표준근로계약서 (기간의 정함이 없는 경우)

1. 근로계약기간 : ${data['startDate']} 부터 기간의 정함이 없음
2. 근무장소 : ${data['storeName']}
3. 업무의 내용 : ${data['jobDescription']}
3-1. 파견업체 : ${data['dispatchCompany']}
3-2. 파견기간 : ${data['dispatchPeriod']}
3-3. 파견담당자 연락처 : ${data['dispatchContact']}
3-4. 근무 메모 : ${data['dispatchMemo']}
4. 소정근로시간(요일별) :
${data['workingHours']}
5. 근무일/휴일 : ${data['workingDays']} / 주휴일 : ${data['weeklyHoliday'] ?? '별도 정한 바에 따름'}
   - 휴게시간 특약: 소정근로시간 중 ${data['breakClause']}을 휴게시간으로 부여한다.
6. 임금 : 시간급 ${data['baseWage']}원
  - 상여금 : ${data['bonus'] ?? '없음'}
  - 기타급여 : ${data['extraPay'] ?? '없음'}
  - 임금지급일 : 매월 ${data['payday']}일
  - 지급방법 : 근로자 명의 예금계좌로 입금
7. 연차유급휴가 : 근로기준법에서 정하는 바에 따라 부여
8. 사회보험 적용여부 : 고용보험, 산재보험, 국민연금, 건강보험 가입
9. 근로계약서 교부 : 사업주는 근로계약을 체결함과 동시에 본 계약서를 작성하여 근로자에게 교부함

${data['contractDate'] ?? '20XX년 XX월 XX일'}

사업주 : ${data['ownerName']} (인)
근로자 : ${data['staffName']} (인)
''';
  }

  static String getNightHolidayConsent(String staffName, {String? consentDate}) {
    return '''
야간 및 휴일근로 동의서

본인($staffName)은 근로기준법 제70조 및 제71조에 의거하여, 회사의 업무상 필요에 의해 발생하는 야간근로(오후 10시부터 익일 오전 6시 사이의 근로) 및 휴일근로에 대하여 동의합니다.

동의 일자: ${consentDate ?? '20XX년 XX월 XX일'}

동의자: $staffName (서명)
''';
  }

  static String getEmployeeRegistry(Map<String, String> data) {
    return '''
근로자 명부

- 성명: ${data['name']}
- 생년월일: ${data['birthDate']}
- 주소: ${data['address']}
- 이력: ${data['history'] ?? '별도 첨부'}
- 고용일자: ${data['hireDate']}
- 종사 업무: ${data['job']}
- 계약 기간 : ${data['contractPeriod']}

근로기준법 제41조에 의거하여 위와 같이 근로자 명부를 작성합니다.
''';
  }
}
