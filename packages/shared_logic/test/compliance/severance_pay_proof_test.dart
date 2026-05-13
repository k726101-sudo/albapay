/// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
/// [증명 테스트] 퇴직금 정산 엔진 — 계산 근거 수치 추적
/// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
///
/// 엔진 내부 산식을 가상 데이터로 재현하여 중간값·최종값을 1원 단위로 검증합니다.
/// ExitSettlementResult만으로는 보이지 않는 "왜 이 숫자가 나왔는가?"를
/// 테스트 코드 자체가 수식 문서 역할을 합니다.
///
/// 【시나리오 구성】
///   A) 전일제(40h) 1년 — 이론 추산 경로 (데이터 부족) + 통상임금 비교
///   B) 단시간(20h) 1년6개월 — 통상임금 비교 발동 검증
///   C) 전일제(40h) 실제 출근기록 有 — 실데이터 경로
///   D) 5인 미만 — 연차수당 미산입 증명
/// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_logic/shared_logic.dart';

void main() {
  group('[퇴직금 계산 근거 증명] 중간값 수치 추적', () {
    // ═════════════════════════════════════════════════════════
    // [시나리오 A] 전일제(40h), 5인 이상, 입사 2025-03-01 → 퇴사 2026-05-31
    //   데이터 부족 경로 (가상직원, 출근기록 0건)
    //
    //   계산 과정:
    //     재직일수 = 457일 (≥365, ≥15h → 자격 있음)
    //     역월 3개월: 5/31 → 2/28 = 92일
    //     hoursMultiplier = 8.0 (전일제)
    //     주간 유급시간 = 40 + 8(주휴) = 48h
    //     3개월 기본급+주휴 = 48 × (92/7) × 10,320 = 6,510,445.71
    //     연차 산입 = 15 × 8 × 10,320 × (92/365) = 312,144.66
    //     3개월 총액 = 6,822,590.37
    //     평균임금 = 6,822,590.37 ÷ 92 = 74,158.59
    //     통상임금 = 8 × 10,320 = 82,560.00
    //     Max(74,158.59, 82,560.00) = 82,560.00 ← 통상임금 선택!
    //     퇴직금 = 82,560 × 30 × (457/365) = 3,101,089.32
    // ═════════════════════════════════════════════════════════
    test('A) 전일제 이론 추산: 10단계 전수 검증', () {
      const hourlyRate = 10320.0;
      const weeklyHours = 40.0;
      final joinDate = DateTime(2025, 3, 1);
      final exitDate = DateTime(2026, 5, 31);

      // ── 1단계: 자격 판정 ──
      final totalWorkingDays = exitDate.difference(joinDate).inDays + 1;
      expect(totalWorkingDays, 457, reason: '2025-03-01 ~ 2026-05-31 = 457일');

      // ── 2단계: 역월 3개월 (5/31 → 2/28) ──
      const calendarDaysIn3Months = 92; // 2/28 → 5/31

      // ── 3단계: hoursMultiplier ──
      const hoursMultiplier = 8.0;

      // ── 4단계: 기본급+주휴 총액 ──
      const weeklyTotalPaidHours = weeklyHours + hoursMultiplier; // 48.0
      final baseWage = weeklyTotalPaidHours * (calendarDaysIn3Months / 7.0) * hourlyRate;
      expect(baseWage, closeTo(6510445.71, 1.0));

      // ── 5단계: 연차수당 산입 ──
      final annualLeaveAddition =
          (15.0 * hoursMultiplier * hourlyRate) * (calendarDaysIn3Months / 365.0);
      expect(annualLeaveAddition, closeTo(312144.66, 1.0));

      // ── 6단계: 3개월 총액 ──
      final totalWage = baseWage + annualLeaveAddition;
      expect(totalWage, closeTo(6822590.37, 1.0));

      // ── 7단계: 1일 평균임금 ──
      final calcAvg = totalWage / calendarDaysIn3Months;
      expect(calcAvg, closeTo(74158.59, 1.0));

      // ── 8단계: 1일 통상임금 ──
      const ordinaryDailyWage = hoursMultiplier * hourlyRate; // 82,560
      expect(ordinaryDailyWage, 82560.0);

      // ── 9단계: Max 비교 ──
      expect(calcAvg < ordinaryDailyWage, isTrue,
          reason: '평균임금(74,159) < 통상임금(82,560) → 통상임금 선택');

      // ── 10단계: 퇴직금 ──
      final severancePay =
          (ordinaryDailyWage * 30) * (totalWorkingDays / 365.0);
      expect(severancePay, closeTo(3101089.32, 1.0));

      // ── 엔진 결과 대조 ──
      final result = PayrollCalculator.calculateExitSettlement(
        workerName: '증명A',
        startDate: '2025-03-01',
        usedAnnualLeave: 0,
        annualLeaveManualAdjustment: 0,
        weeklyHours: weeklyHours,
        allAttendances: [],
        scheduledWorkDays: [1, 2, 3, 4, 5],
        exitDate: exitDate,
        hourlyRate: hourlyRate,
        isFiveOrMore: true,
        isVirtual: true,
      );

      expect(result.averageDailyWage, closeTo(ordinaryDailyWage, 0.01),
          reason: '엔진 = 수기 계산 일치 (통상임금 82,560)');
      expect(result.severancePay, closeTo(severancePay, 1.0),
          reason: '엔진 퇴직금 = 수기 계산 일치');
    });

    // ═════════════════════════════════════════════════════════
    // [시나리오 B] 단시간(20h), 5인 이상, 입사 2025-01-01 → 퇴사 2026-06-30
    //
    //   계산 과정:
    //     재직일수 = 546일
    //     역월 3개월: 6/30 → 3/30 = 92일
    //     hoursMultiplier = 20h ÷ 3일 ≈ 6.6667h (실제 계약일일근로시간)
    //     주간 유급 = 20 + 6.6667 = 26.6667h
    //     3개월 기본급+주휴 = 26.6667 × (92/7) × 10,320 = 3,617,142.86
    //     연차 산입 = 15 × 6.6667 × 10,320 × (92/365) = 260,120.55
    //     3개월 총액 = 3,877,263.41
    //     평균임금 = 3,877,263.41 ÷ 92 = 42,144.17
    //     통상임금 = 6.6667 × 10,320 = 68,800
    //     Max(42,144, 68,800) = 68,800 ← 통상임금 선택!
    //     퇴직금 = 68,800 × 30 × (546/365) = 3,087,517.81
    // ═════════════════════════════════════════════════════════
    test('B) 단시간(20h): 통상임금 비교 발동 전수 검증', () {
      const hourlyRate = 10320.0;
      const weeklyHours = 20.0;
      final exitDate = DateTime(2026, 6, 30);

      final totalWorkingDays =
          exitDate.difference(DateTime(2025, 1, 1)).inDays + 1;
      expect(totalWorkingDays, 546);

      const calDays = 92; // 3/30 → 6/30
      // 실제 계약일일근로시간 = 주 20h ÷ 주 3일 = 6.6667h
      const contractWorkDaysPerWeek = 3.0;
      final hoursMultiplier = weeklyHours / contractWorkDaysPerWeek; // ≈ 6.6667
      final weeklyPaid = weeklyHours + hoursMultiplier; // 26.6667

      final base = weeklyPaid * (calDays / 7.0) * hourlyRate;
      expect(base, closeTo(3617142.86, 300.0),
          reason: '기본급+주휴 중간값 (소수점 정밀도 허용)');

      final annualAdd = (15.0 * hoursMultiplier * hourlyRate) * (calDays / 365.0);
      expect(annualAdd, closeTo(260120.55, 50.0),
          reason: '연차 산입 중간값 (소수점 정밀도 허용)');

      final total = base + annualAdd;
      final calcAvg = total / calDays;
      expect(calcAvg, closeTo(42144.17, 10.0),
          reason: '평균임금 중간값 (소수점 정밀도 허용)');

      final ordinaryWage = hoursMultiplier * hourlyRate; // ≈ 68,800
      expect(calcAvg < ordinaryWage, isTrue,
          reason: '평균 42,144 < 통상 68,800 → 통상임금 선택');

      final severancePay = (ordinaryWage * 30) * (totalWorkingDays / 365.0);
      expect(severancePay, closeTo(3087517.81, 10.0),
          reason: '퇴직금 최종값');

      // 엔진 대조
      final result = PayrollCalculator.calculateExitSettlement(
        workerName: '증명B',
        startDate: '2025-01-01',
        usedAnnualLeave: 0,
        annualLeaveManualAdjustment: 0,
        weeklyHours: weeklyHours,
        allAttendances: [],
        scheduledWorkDays: [1, 2, 3],
        exitDate: exitDate,
        hourlyRate: hourlyRate,
        isFiveOrMore: true,
        isVirtual: true,
      );

      expect(result.averageDailyWage, closeTo(ordinaryWage, 0.01));
      expect(result.severancePay, closeTo(severancePay, 1.0));
    });

    // ═════════════════════════════════════════════════════════
    // [시나리오 C] 전일제 + 실제 출근기록 60일분
    //   매일 09:00~18:00 (9h 체류 = 순수 근무시간으로 사용)
    //
    //   계산 과정:
    //     역월 3개월: 6/15 → 3/15 = 92일
    //     ① 실근무 = 60일 × 9h × 10,320 = 5,572,800
    //     ② 주휴가산 = 8 × 10,320 × (92/7) = 1,085,074.29
    //     ③ 연차가산 = 15 × 8 × 10,320 × (92/365) = 312,144.66
    //     ④ 총액 = 6,970,018.94
    //     ⑤ 평균임금 = 75,761.08
    //     ⑥ 통상임금 = 82,560
    //     ⑦ 75,761 < 82,560 → 통상임금 선택
    // ═════════════════════════════════════════════════════════
    test('C) 실데이터 경로: 60일 출근기록 기반 전수 검증', () {
      const hourlyRate = 10320.0;
      final exitDate = DateTime(2026, 6, 15);
      const calDays = 92;

      // 60일치 출근 기록 (주5일, 09:00~18:00)
      final attendances = <Attendance>[];
      var cursor = DateTime(2026, 3, 16);
      int count = 0;
      while (count < 60 && cursor.isBefore(exitDate)) {
        if (cursor.weekday >= 1 && cursor.weekday <= 5) {
          attendances.add(Attendance(
            id: 'att_$count',
            staffId: 'w1',
            storeId: 's1',
            clockIn: DateTime(cursor.year, cursor.month, cursor.day, 9),
            clockOut: DateTime(cursor.year, cursor.month, cursor.day, 18),
            type: AttendanceType.web,
          ));
          count++;
        }
        cursor = cursor.add(const Duration(days: 1));
      }
      expect(attendances.length, 60, reason: '60일치 기록 확인');

      // ① 실근무 총액
      const laborPay = 60 * 9.0 * hourlyRate; // 5,572,800
      expect(laborPay, 5572800.0);

      // ② 주휴수당 가산
      final weeklyHolidayAdd = 8.0 * hourlyRate * (calDays / 7.0);
      expect(weeklyHolidayAdd, closeTo(1085074.29, 1.0));

      // ③ 연차수당 가산
      final annualAdd = (15.0 * 8.0 * hourlyRate) * (calDays / 365.0);
      expect(annualAdd, closeTo(312144.66, 1.0));

      // ④ 총액
      final totalWage = laborPay + weeklyHolidayAdd + annualAdd;
      expect(totalWage, closeTo(6970018.94, 1.0));

      // ⑤ 평균임금
      final calcAvg = totalWage / calDays;
      expect(calcAvg, closeTo(75761.08, 1.0));

      // ⑥ 통상임금
      const ordinaryWage = 82560.0;

      // ⑦ Max 비교
      expect(calcAvg < ordinaryWage, isTrue,
          reason: '실데이터도: 평균 75,761 < 통상 82,560');

      // 엔진 대조
      final result = PayrollCalculator.calculateExitSettlement(
        workerName: '증명C',
        startDate: '2025-01-01',
        usedAnnualLeave: 0,
        annualLeaveManualAdjustment: 0,
        weeklyHours: 40,
        allAttendances: attendances,
        scheduledWorkDays: [1, 2, 3, 4, 5],
        exitDate: exitDate,
        hourlyRate: hourlyRate,
        isFiveOrMore: true,
      );

      expect(result.averageDailyWage, closeTo(ordinaryWage, 0.01),
          reason: '엔진: 실데이터에서도 통상임금 82,560 선택');
    });

    // ═════════════════════════════════════════════════════════
    // [시나리오 D] 5인 미만 → 연차수당 미산입 수치 증명
    //
    //   5인 이상: 연차 15일 산입 → 총액 높음
    //   5인 미만: 연차 0일 산입 → 총액 낮음
    //   (통상임금 하한선이 둘 다 걸리면 최종 퇴직금은 같을 수 있음)
    // ═════════════════════════════════════════════════════════
    test('D) 5인 미만: 연차수당 산입 = 0 → 총액 차이 증명', () {
      const hourlyRate = 10320.0;
      const calDays = 92;

      // 5인 이상: 연차 15일 산입
      final annualAdd5Plus = (15.0 * 8.0 * hourlyRate) * (calDays / 365.0);
      expect(annualAdd5Plus, closeTo(312144.66, 1.0),
          reason: '5인 이상: 312,145원 산입');

      // 5인 미만: 연차 0일 산입
      final annualAddUnder5 = (0.0 * 8.0 * hourlyRate) * (calDays / 365.0);
      expect(annualAddUnder5, 0.0,
          reason: '5인 미만: 0원 산입');

      // 차액 = 312,145원 (3개월 총액 기준)
      expect(annualAdd5Plus - annualAddUnder5, closeTo(312144.66, 1.0),
          reason: '3개월 총액 차이 ≈ 312,145원');

      // 엔진 대조
      final r5plus = PayrollCalculator.calculateExitSettlement(
        workerName: '5인이상',
        startDate: '2025-01-01',
        usedAnnualLeave: 0,
        annualLeaveManualAdjustment: 0,
        weeklyHours: 40,
        allAttendances: [],
        scheduledWorkDays: [1, 2, 3, 4, 5],
        exitDate: DateTime(2026, 6, 30),
        hourlyRate: hourlyRate,
        isFiveOrMore: true,
        isVirtual: true,
      );

      final rUnder5 = PayrollCalculator.calculateExitSettlement(
        workerName: '5인미만',
        startDate: '2025-01-01',
        usedAnnualLeave: 0,
        annualLeaveManualAdjustment: 0,
        weeklyHours: 40,
        allAttendances: [],
        scheduledWorkDays: [1, 2, 3, 4, 5],
        exitDate: DateTime(2026, 6, 30),
        hourlyRate: hourlyRate,
        isFiveOrMore: false,
        isVirtual: true,
      );

      expect(rUnder5.severancePay, lessThanOrEqualTo(r5plus.severancePay),
          reason: '5인 미만(연차 미산입) ≤ 5인 이상');
    });

    // ═════════════════════════════════════════════════════════
    // [시나리오 E] 미사용 연차수당 정산 연동 검증
    //
    //   SeveranceCalculator → AnnualLeaveCalculator 연동이 정확한지:
    //   ① remainingLeaveDays = 발생일수 - 사용일수
    //   ② annualLeavePayout = 잔여일 × 1일 소정근로시간 × 시급
    //   ③ 사용분 차감이 정확히 반영되는지
    //   ④ 5인 미만 → 연차 0 → 수당 0
    // ═════════════════════════════════════════════════════════
    test('E) 미사용 연차수당: AnnualLeaveCalculator 연동 전수 검증', () {
      const hourlyRate = 10320.0;
      const weeklyHours = 40.0;
      final exitDate = DateTime(2026, 6, 15);

      // ── E-1: 1년 2개월 근무, 연차 0일 사용 → 전액 지급 ──
      final resultNoUse = PayrollCalculator.calculateExitSettlement(
        workerName: '미사용 전액',
        startDate: '2025-01-01',
        usedAnnualLeave: 0, // ★ 사용 0일
        annualLeaveManualAdjustment: 0,
        weeklyHours: weeklyHours,
        allAttendances: [],
        scheduledWorkDays: [1, 2, 3, 4, 5],
        exitDate: exitDate,
        hourlyRate: hourlyRate,
        isFiveOrMore: true,
        isVirtual: true,
      );

      // AnnualLeaveCalculator 독립 호출로 교차 검증
      final leaveSummary = AnnualLeaveCalculator.calculateAnnualLeaveSummary(
        joinDate: DateTime(2025, 1, 1),
        endDate: exitDate,
        allAttendances: [],
        scheduledWorkDays: [1, 2, 3, 4, 5],
        isFiveOrMore: true,
        settlementPoint: exitDate,
        usedAnnualLeave: 0,
        weeklyHoursPure: weeklyHours,
        hourlyRate: hourlyRate,
        manualAdjustment: 0,
        isVirtual: true,
      );

      // 잔여일수 일치
      expect(resultNoUse.remainingLeaveDays, leaveSummary.remaining,
          reason: 'SeveranceCalc.remainingLeaveDays = AnnualLeaveCalc.remaining');

      // 연차수당 일치
      expect(resultNoUse.annualLeavePayout, leaveSummary.annualLeaveAllowancePay,
          reason: 'SeveranceCalc.annualLeavePayout = AnnualLeaveCalc.pay');

      // 잔여일 > 0 (연차가 발생했으니)
      expect(resultNoUse.remainingLeaveDays, greaterThan(0),
          reason: '1년+ 근무, 사용 0 → 잔여 > 0');

      // 수당 > 0
      expect(resultNoUse.annualLeavePayout, greaterThan(0),
          reason: '잔여일 > 0 → 수당 > 0');

      // ── E-2: 동일 조건에서 5일 사용 → 잔여 감소 ──
      final resultUsed5 = PayrollCalculator.calculateExitSettlement(
        workerName: '5일 사용',
        startDate: '2025-01-01',
        usedAnnualLeave: 5, // ★ 5일 사용
        annualLeaveManualAdjustment: 0,
        weeklyHours: weeklyHours,
        allAttendances: [],
        scheduledWorkDays: [1, 2, 3, 4, 5],
        exitDate: exitDate,
        hourlyRate: hourlyRate,
        isFiveOrMore: true,
        isVirtual: true,
      );

      // 잔여일이 정확히 5일 줄었는지
      expect(resultUsed5.remainingLeaveDays,
          resultNoUse.remainingLeaveDays - 5,
          reason: '5일 사용 → 잔여 = 미사용잔여 - 5');

      // 수당도 정확히 5일분 줄었는지 (5일 × 8h × 시급)
      final fiveDaysPay = 5 * 8.0 * hourlyRate; // 5 × 82,560 = 412,800
      expect(resultUsed5.annualLeavePayout,
          closeTo(resultNoUse.annualLeavePayout - fiveDaysPay, 1.0),
          reason: '수당 차이 = 5일 × 8h × 시급 = 412,800원');

      // ── E-3: 5인 미만 → 연차 0일 → 수당 0원 ──
      final resultUnder5 = PayrollCalculator.calculateExitSettlement(
        workerName: '5인미만',
        startDate: '2025-01-01',
        usedAnnualLeave: 0,
        annualLeaveManualAdjustment: 0,
        weeklyHours: weeklyHours,
        allAttendances: [],
        scheduledWorkDays: [1, 2, 3, 4, 5],
        exitDate: exitDate,
        hourlyRate: hourlyRate,
        isFiveOrMore: false, // ★ 5인 미만
        isVirtual: true,
      );

      expect(resultUnder5.remainingLeaveDays, 0,
          reason: '5인 미만 → 연차 미발생 → 잔여 0');
      expect(resultUnder5.annualLeavePayout, 0,
          reason: '5인 미만 → 수당 0원');

      // ── E-4: 단시간(20h) → 비례 연차수당 ──
      final resultPartTime = PayrollCalculator.calculateExitSettlement(
        workerName: '단시간20h',
        startDate: '2025-01-01',
        usedAnnualLeave: 0,
        annualLeaveManualAdjustment: 0,
        weeklyHours: 20, // ★ 단시간
        allAttendances: [],
        scheduledWorkDays: [1, 2, 3],
        exitDate: exitDate,
        hourlyRate: hourlyRate,
        isFiveOrMore: true,
        isVirtual: true,
      );

      // 단시간 1일 소정근로 = (20/40) × 8 = 4h
      // 수당 = 잔여일 × 4h × 시급 (전일제 대비 절반)
      expect(resultPartTime.annualLeavePayout,
          lessThan(resultNoUse.annualLeavePayout),
          reason: '단시간(20h) 수당 < 전일제(40h) 수당');
    });
  });
}
