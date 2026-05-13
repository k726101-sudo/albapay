class DocumentTemplates {
  static String getLaborContract(Map<String, String> data) {
    final wageType = data['wageType'] ?? 'hourly';
    final isMonthly = wageType == 'monthly';

    // 임금 섹션 분기
    final String wageSection;
    if (isMonthly) {
      final baseSalary = data['monthlyWage'] ?? '0';
      final mealAllowance = data['mealAllowance'] ?? '0';
      final fixedOTPay = data['fixedOTPay'] ?? '0';
      final fixedOTHours = data['fixedOTHours'] ?? '0';
      final wageTotal = data['wageTotal'] ?? '0';
      final hourlyRate = data['baseWage'] ?? '0';

      final buf = StringBuffer();
      buf.writeln('6. 임금 : 월급제');
      buf.writeln('  - 기본급 : ${baseSalary}원');
      if (int.tryParse(mealAllowance.replaceAll(',', '')) != null &&
          int.parse(mealAllowance.replaceAll(',', '')) > 0) {
        buf.writeln('  - 식대(비과세) : ${mealAllowance}원');
      }
      if (int.tryParse(fixedOTHours.replaceAll(',', '')) != null &&
          int.parse(fixedOTHours.replaceAll(',', '')) > 0) {
        buf.writeln('  - 고정연장수당 : ${fixedOTPay}원 (월 ${fixedOTHours}시간분)');
      }
      buf.writeln('  - 임금 합계 : ${wageTotal}원');
      buf.writeln('  - 통상시급(역산) : ${hourlyRate}원');
      wageSection = buf.toString().trimRight();
    } else {
      wageSection = '6. 임금 : 시간급 ${data['baseWage']}원';
    }

    // 상여금/기타급여
    final bonusLine = '  - 상여금 : ${data['bonus'] ?? '없음'}';
    final extraPayLine = '  - 기타급여 : ${data['extraPay'] ?? '없음'}';

    // 특약 섹션 (월급제 전용)
    final String shieldClauses;
    if (isMonthly) {
      final buf = StringBuffer();
      buf.writeln('');
      buf.writeln('[특약 1] 주휴수당');
      buf.writeln('기본급은 유급주휴수당을 포함하여 산정된 금액입니다.');
      buf.writeln('단, 소정근로일을 개근하지 않은 경우 해당 주휴수당은 지급되지 않으며,');
      buf.writeln('이에 해당하는 금액은 공제될 수 있습니다.');

      final otPayRaw =
          int.tryParse((data['fixedOTPay'] ?? '0').replaceAll(',', '')) ?? 0;
      final otHours =
          int.tryParse((data['fixedOTHours'] ?? '0').replaceAll(',', '')) ?? 0;
      final isFiveOrMore = data['isFiveOrMore'] == 'true';

      if (otHours > 0 && otPayRaw > 0) {
        // 통상시급 = (기본급 + 식대) / S_Ref (직원별 소정근로시간)
        final basicPayRaw =
            int.tryParse((data['monthlyWage'] ?? '0').replaceAll(',', '')) ?? 0;
        final mealRaw =
            int.tryParse((data['mealAllowance'] ?? '0').replaceAll(',', '')) ??
            0;
        final sRef = double.tryParse(data['sRef'] ?? '209') ?? 209.0;
        final conservativeHourly = sRef > 0
            ? (basicPayRaw + mealRaw) / sRef
            : 0.0;

        // 고정OT 시간 역산 (5인 이상은 분모에 1.5배 가산율 적용)
        final fixedOTHoursCalc = isFiveOrMore
            ? otPayRaw / (conservativeHourly * 1.5)
            : otPayRaw / conservativeHourly;
        // ★ 소수점 1자리 보수적 내림 (ex: 9.76h → 9.7h)
        final fixedOTHoursDisplay = (fixedOTHoursCalc * 10).floor() / 10.0;

        // 법정 가산 시급 (원 단위 절사)
        final premiumHourly = (conservativeHourly * 1.5).floor();
        final overtimeHourly = (conservativeHourly * 2.0).floor();

        buf.writeln('');
        buf.writeln('[특약 2] 고정연장수당 합의');
        buf.writeln('');
        buf.writeln(
          '고정연장수당 ${otPayRaw}원은 월 ${fixedOTHoursDisplay.toStringAsFixed(1)}시간의 연장근로에 대한 사전 정액 지급분입니다.',
        );

        if (isFiveOrMore) {
          buf.writeln('본 사업장은 상시 근로자 5인 이상으로 근로기준법 제56조에 따른 가산수당이 적용됩니다.');
          buf.writeln('');
          buf.writeln(
            '① 실제 연장근로가 월 ${fixedOTHoursDisplay.toStringAsFixed(1)}시간 이하인 경우:',
          );
          buf.writeln('   고정연장수당 전액 지급 (차액 공제 없음)');
          buf.writeln('');
          buf.writeln(
            '② 실제 연장근로가 월 ${fixedOTHoursDisplay.toStringAsFixed(1)}시간을 초과하는 경우:',
          );
          buf.writeln('   초과시간 × ${premiumHourly}원(1.5배 가산)을 익월 급여에 별도 지급');
          buf.writeln('');
          buf.writeln('③ 휴일 및 휴무일 근무 시:');
          buf.writeln('   - 8시간 이내: 시간당 ${premiumHourly}원(1.5배)');
          buf.writeln('   - 8시간 초과: 시간당 ${overtimeHourly}원(2.0배)');
          buf.writeln('   익월 급여에 별도 지급 (고정연장시간에서 차감 불가)');
        } else {
          buf.writeln('본 사업장은 상시 근로자 5인 미만으로 근로기준법 제56조(가산수당)가 적용되지 않습니다.');
          buf.writeln('');
          buf.writeln(
            '① 실제 연장근로가 월 ${fixedOTHoursDisplay.toStringAsFixed(1)}시간 이하인 경우:',
          );
          buf.writeln('   고정연장수당 전액 지급 (차액 공제 없음)');
          buf.writeln('');
          buf.writeln(
            '② 실제 연장근로가 월 ${fixedOTHoursDisplay.toStringAsFixed(1)}시간을 초과하는 경우:',
          );
          buf.writeln('   초과시간 × ${conservativeHourly.floor()}원을 익월 급여에 별도 지급');
          buf.writeln('');
          buf.writeln('③ 휴일 및 휴무일 근무 시:');
          buf.writeln('   근무시간 × ${conservativeHourly.floor()}원을 별도 지급');
          buf.writeln('   (고정연장시간에서 차감 불가, 원 단위 절사 적용)');
        }
      }

      buf.writeln('');
      buf.writeln('[특약 ${otHours > 0 && otPayRaw > 0 ? "3" : "2"}] 평균 주수 합의');
      buf.writeln('본 급여는 1개월 평균 주수(4.345주)를 기준으로 산정된 금액이며,');
      buf.writeln('실제 근로 제공 여부에 따라 결근·지각·조퇴 시간에 대해서는');
      buf.writeln('관련 법령 및 내부 기준에 따라 공제될 수 있습니다.');
      shieldClauses = buf.toString().trimRight();
    } else {
      shieldClauses = '';
    }

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
$wageSection
$bonusLine
$extraPayLine
  - 임금지급일 : 매월 ${data['payday']}일
  - 지급방법 : 근로자 명의 예금계좌로 입금
7. 연차유급휴가 : 근로기준법에서 정하는 바에 따라 부여
8. 사회보험 적용여부 : 고용보험, 산재보험, 국민연금, 건강보험 가입
9. 근로계약서 교부 : 사업주는 근로계약을 체결함과 동시에 본 계약서를 작성하여 근로자에게 교부함
  - 이 계약에 정함이 없는 사항은 근로기준법령에 의함$shieldClauses

${data['contractDate'] ?? '20XX년 XX월 XX일'}

사업주 : ${data['ownerName']} (인)
근로자 : ${data['staffName']} (인)
''';
  }

  static String getNightHolidayConsent(
    String staffName, {
    String? consentDate,
  }) {
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

  static String getPledge(Map<String, String> data) {
    return '''
서 약 서

본인 ${data['name']}은(는) 귀사에 근무함에 있어 제반 사규 및 규정을 성실히 준수하며
특히 다음 사항을 어길 시에는 회사의 여하한 조치에도 이의를 제기하지 않을 것을 서약합니다.

1. 본인은 업무상 지득한 회사의 기밀 및 제반 사항을 재직 중은 물론 퇴직 후에도 절대 누설하지 않는다.
2. 본인은 고의 또는 중대한 과실로 인하여 회사에 손해를 끼쳤을 경우에는 지체 없이 변상한다.
3. 본인은 회사 내규 및 질서를 위반하여 해고 등 어떠한 징계처분을 받더라도 이를 감수하며 하등의 민·형사상 이의를 제기하지 않는다.

${data['date'] ?? '20XX년 XX월 XX일'}

서약자: ${data['name']} (서명)
''';
  }

  static String getResignationLetter(Map<String, String> data) {
    return '''
사 직 서

1. 소속 (사업장명) : ${data['storeName']}
2. 성명 : ${data['workerName']}
3. 퇴직 예정일 : ${data['exitDate']}
4. 퇴직 사유 : ${data['reason']}

본인은 위와 같은 사유로 퇴직하고자 하오니, 이 사직서를 수리하여 주시기 바랍니다.

${data['date'] ?? '20XX년 XX월 XX일'}

작성자: ${data['workerName']} (서명)
''';
  }

  static String getWageAmendment(Map<String, String> data) {
    return '''
임금 계약 변경서

본 변경서는 사업주와 근로자 간 기존 체결된 근로계약의 일부(임금)를 아래와 같이 변경함을 목적으로 합니다.

1. 대상 근로자
  - 성명 : ${data['staffName']}
  - 담당 업무 : ${data['jobDescription']}

2. 변경 사항 (임금)
  - 기존 시간급 : ${data['oldBaseWage']}원
  - 변경 시간급 : ${data['newBaseWage']}원
  - 변경 적용일 : ${data['effectiveDate']}

3. 기타 근로 조건
  - 위 항목을 제외한 소정근로시간, 휴일, 기타 근로조건은 기존 근로계약 및 관련 법령에 따릅니다.

4. 서류의 교부
  - 사업주는 본 변경서를 작성하고 서명일 당일 근로자에게 교부합니다.

${data['contractDate'] ?? '20XX년 XX월 XX일'}

사업주 : ${data['ownerName']} (인)
근로자 : ${data['staffName']} (인)
''';
  }

  /// 연차 사용촉진 통보서 텍스트 템플릿 (근로기준법 제61조)
  static String getLeavePromotionNotice(int step, Map<String, String> data) {
    final leaveType = data['leaveType'] ?? '정기 연차';
    final legalBasis = data['legalBasis'] ?? '근로기준법 제61조 제1항';
    final grantDate = data['grantDate'] ?? '-';
    final expiryDate = data['expiryDate'] ?? '-';
    final unusedDays = data['unusedDays'] ?? '0';
    final deadlineType = data['deadlineType'] ?? '6개월/2개월';

    if (step == 1) {
      return '''
연차유급휴가 사용촉진 통보서 (제1차)
[$legalBasis]

수 신 : ${data['staffName']} 귀하
발 신 : ${data['storeName']} 대표 ${data['ownerName']}
발신일 : ${data['date'] ?? '20XX년 XX월 XX일'}

제목: 미사용 연차유급휴가 사용 시기 지정 요청

귀하의 $leaveType 중 미사용 연차가 아래와 같이 있으므로, $legalBasis에 의거하여 사용 시기를 정하여 통보하여 주시기 바랍니다.

■ 미사용 연차 내역
  - 연차 유형 : $leaveType
  - 연차 발생일 : $grantDate
  - 연차 소멸 예정일 : $expiryDate
  - 미사용 연차 수 : ${unusedDays}일
  - 촉진 기한 유형 : 소멸일 기준 $deadlineType 전

※ 본 통보서 수령 후 10일 이내에 미사용 연차의 사용 시기를 서면으로 통보하여 주십시오.
※ 10일 이내에 통보하지 않을 경우, 사용자가 직접 사용 시기를 지정하여 서면 통보합니다.

사업주 : ${data['ownerName']} (인)
근로자 : ${data['staffName']} (수령 확인)
''';
    } else {
      final designatedDates = data['designatedDates'] ?? '(지정 날짜 없음)';
      return '''
연차유급휴가 사용시기 지정 통보서 (제2차)
[$legalBasis]

수 신 : ${data['staffName']} 귀하
발 신 : ${data['storeName']} 대표 ${data['ownerName']}
발신일 : ${data['date'] ?? '20XX년 XX월 XX일'}

제목: 미사용 연차유급휴가 사용 시기 지정 통보

귀하가 제1차 촉진 통보($leaveType) 수령 후 10일 이내에 사용 시기를 통보하지 않았으므로, $legalBasis에 의거하여 사용자가 아래와 같이 미사용 연차의 사용 시기를 직접 지정합니다.

■ 미사용 연차 내역
  - 연차 유형 : $leaveType
  - 연차 발생일 : $grantDate
  - 연차 소멸 예정일 : $expiryDate
  - 미사용 연차 수 : ${unusedDays}일

■ 지정된 사용 날짜
$designatedDates

사업주 : ${data['ownerName']} (인)
근로자 : ${data['staffName']} (수령 확인)
''';
    }
  }

  /// 친권자(법정대리인) 동의서 텍스트 템플릿 (근로기준법 제66조)
  static String getMinorConsent(Map<String, String> data) {
    return '''
친권자(법정대리인) 동의서

[근로기준법 제66조, 제67조에 의거]

1. 연소 근로자 (미성년자)

  - 성    명 : ${data['staffName'] ?? '                    '}
  - 생년월일 : ${data['birthDate'] ?? '        년      월      일'}
  - 연 락 처 : ${data['staffPhone'] ?? '                    '}
  - 주    소 : ${data['staffAddress'] ?? '                                        '}

2. 근무처 정보

  - 사 업 장 명 : ${data['storeName'] ?? '                    '}
  - 사업장 주소 : ${data['storeAddress'] ?? '                                        '}
  - 대 표 자 명 : ${data['ownerName'] ?? '                    '}
  - 연  락  처 : ${data['storePhone'] ?? '                    '}

3. 근로 조건

  - 업무 내용 : ${data['jobDescription'] ?? '매장 관리 및 고객 응대'}
  - 근로계약 기간 : ${data['startDate'] ?? '      년    월    일'} ~ ${data['endDate'] ?? '      년    월    일'}
  - 근무 시간 : ${data['workingHours'] ?? '      시    분 ~ '} (1일 7시간, 주 35시간 이내)
  - 시    급 : ${data['hourlyWage'] ?? '              '}원
  - 근무 요일 : ${data['workDays'] ?? '                    '}
  - 휴  게 : ${data['breakTime'] ?? '                    '}

4. 동의 내용

  본인은 위 연소자의 법정대리인(친권자/후견인)으로서, 위 연소자가 위 사업장에서 
  위와 같은 조건으로 근로하는 것에 동의합니다.

  ※ 근로기준법 제66조에 따라 18세 미만의 자에 대하여는 친권자 또는 후견인의 
     동의서와 가족관계증명서를 사업장에 비치하여야 합니다.
  ※ 연소자의 근로시간은 1일 7시간, 1주 35시간을 초과할 수 없습니다 (제69조).
  ※ 연소자에 대하여는 오후 10시부터 오전 6시까지의 시간 및 휴일에 근로시키지 
     못합니다. 다만, 본인의 동의와 고용노동부장관의 인가를 받은 경우에는 
     예외로 합니다 (제70조).

5. 첨부 서류 (반드시 함께 제출)

  □ 가족관계증명서 1부
  □ 주민등록등본 또는 등·초본 1부 (주소 확인용)

동의 일자 : ${data['consentDate'] ?? '      년      월      일'}

법정대리인(친권자/후견인)

  성    명 :                                        (서명 또는 인)
  연소자와의 관계 :
  연 락 처 :
  주    소 :

─────────────────────────────────────────────
사업주 확인 :                                        (서명 또는 인)
''';
  }
}
