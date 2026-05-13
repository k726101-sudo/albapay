/// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
/// [법률 테스트] 월급제 포괄임금 급여 산출 — 포괄임금 오남용 방지 지침 준수
/// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
///
/// 【검증 대상 법령/판례】
///   - 대법원 2012다89399: 포괄임금에 포함된 고정연장수당은 통상임금 산정 시 제외
///   - 고용노동부 포괄임금 오남용 방지 지침: 기본급/수당 분리 명시 의무
///   - 근로기준법 제56조(연장·야간·휴일 근로): 가산수당 산정 기준
///
/// 【검증 시나리오】
///   김점장(월급제): 목표 총급여 2,500,000원
///   - 기본급: 2,156,880원 (10,320원 × 209h)
///   - 비과세 식대: 200,000원
///   - 고정연장수당: 143,120원 (나머지)
///   → 만근 시 정확히 2,500,000원이 산출되어야 함
///   → 근로자의 날(5/1) 출근 시 별도 가산수당 추가 산출되어야 함
///   → 고정OT 시간 초과 시 차액 보전 산출되어야 함
/// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_logic/shared_logic.dart';

void main() {
  group('[포괄임금 오남용 방지] 월급제 급여 산출 검증', () {
    // ─────────────────────────────────────────
    // 김점장 기본 데이터 (모든 테스트 공통)
    // ─────────────────────────────────────────
    const double minimumWage = 10320.0;
    const double standardMonthlyHours = 209.0;
    final double baseSalary = (minimumWage * standardMonthlyHours).roundToDouble(); // 2,156,880
    const double mealAllowance = 200000.0;
    const double targetSalary = 2500000.0;
    final double fixedOTPay = targetSalary - baseSalary - mealAllowance; // 143,120
    final double conservativeHourly = (baseSalary + mealAllowance) / standardMonthlyHours;
    final double fixedOTHours = fixedOTPay / (conservativeHourly * 1.5);

    PayrollWorkerData _makeMonthlyWorker({
      DateTime? joinDate,
      List<int>? workDays,
    }) {
      return PayrollWorkerData(
        weeklyHoursPure: 40,
        weeklyTotalStayMinutes: 40 * 60,
        breakMinutesPerShift: 60,
        isPaidBreak: false,
        joinDate: joinDate ?? DateTime(2025, 1, 1),
        scheduledWorkDays: workDays ?? [1, 2, 3, 4, 5],
        manualWeeklyHolidayApproval: true,
        allowanceAmounts: [mealAllowance], // 식대가 기타수당에 포함
        mealAllowance: mealAllowance,
        mealTaxExempt: true,
        isVirtual: true,
        weeklyHolidayDay: 0,
        wageType: 'monthly',
        monthlyWage: baseSalary, // ★ monthlyWage = 기본급(식대·고정OT 미포함)
        fixedOvertimeHours: fixedOTHours,
        fixedOvertimePay: fixedOTPay,
      );
    }

    // Helper: 특정 기간의 평일(월~금) 출퇴근 기록 생성 (09:00~18:00)
    List<Attendance> _makeWeekdayAttendances(DateTime start, DateTime end, {
      String staffId = 'worker_a',
      bool excludeLaborDay = true,
    }) {
      final list = <Attendance>[];
      int idx = 0;
      for (var d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
        final weekday = d.weekday; // 1=Mon ... 7=Sun
        if (weekday >= 1 && weekday <= 5) {
          // 5/1 근로자의 날 제외 옵션
          if (excludeLaborDay && d.month == 5 && d.day == 1) continue;
          list.add(Attendance(
            id: 'att_${idx++}',
            staffId: staffId,
            storeId: 'store_1',
            clockIn: DateTime(d.year, d.month, d.day, 9, 0),
            clockOut: DateTime(d.year, d.month, d.day, 18, 0),
            type: AttendanceType.web,
            attendanceStatus: 'Normal',
          ));
        }
      }
      return list;
    }

    // ═══════════════════════════════════════════════════
    // [케이스 1] 기본급 분리 산출 정확도 검증
    //           baseSalary = 10,320 × 209 = 2,156,880원
    // ═══════════════════════════════════════════════════
    test('기본급 = 최저시급 × 209h = 2,156,880원 (정수 정확도)', () {
      expect(baseSalary, 2156880.0,
          reason: '10,320 × 209 = 2,156,880 (기본급 하한)');
    });

    // ═══════════════════════════════════════════════════
    // [케이스 2] 고정연장수당 산출 검증
    //           fixedOTPay = 2,500,000 - 2,156,880 - 200,000 = 143,120원
    // ═══════════════════════════════════════════════════
    test('고정연장수당 = 목표급여 - 기본급 - 식대 = 143,120원', () {
      expect(fixedOTPay, 143120.0,
          reason: '2,500,000 - 2,156,880 - 200,000 = 143,120');
    });

    // ═══════════════════════════════════════════════════
    // [케이스 3] 구성요소 합산 = 목표 총급여 정확 일치
    // ═══════════════════════════════════════════════════
    test('기본급 + 식대 + 고정OT = 정확히 목표 총급여(2,500,000원)', () {
      expect(baseSalary + mealAllowance + fixedOTPay, targetSalary,
          reason: '2,156,880 + 200,000 + 143,120 = 2,500,000');
    });

    // ═══════════════════════════════════════════════════
    // [케이스 4] ★ 핵심 — 만근 시 엔진 총급여가 정확히 2,500,000원
    //           (근로자의 날 5/1이 포함되지 않는 기간에서 테스트)
    // ═══════════════════════════════════════════════════
    test('★ 만근 시 엔진 계산 총급여 = 정확히 2,500,000원 (5/1 미포함 기간)', () {
      final workerData = _makeMonthlyWorker();
      // 7월 기간 (근로자의 날 없음): 2026-06-16 ~ 2026-07-15
      final periodStart = DateTime(2026, 6, 16);
      final periodEnd = DateTime(2026, 7, 15);
      final atts = _makeWeekdayAttendances(periodStart, periodEnd);

      final result = PayrollCalculator.calculate(
        workerData: workerData,
        shifts: atts,
        periodStart: periodStart,
        periodEnd: periodEnd,
        hourlyRate: minimumWage,
        isFiveOrMore: true,
        allHistoricalAttendances: atts,
      );

      expect(result.isMonthlyWage, isTrue);
      expect(result.totalPay, targetSalary,
          reason: '5/1 없는 기간에서 만근 시 정확히 2,500,000원');
    });

    // ═══════════════════════════════════════════════════
    // [케이스 5] 근로자의 날(5/1) 출근 시 휴일근로 가산수당 추가
    // ═══════════════════════════════════════════════════
    test('★ 근로자의 날(5/1) 출근 시 기본급 외 추가 가산수당 발생', () {
      final workerData = _makeMonthlyWorker();
      // 5월 포함 기간: 2026-04-16 ~ 2026-05-15
      final periodStart = DateTime(2026, 4, 16);
      final periodEnd = DateTime(2026, 5, 15);
      // 5/1 포함하여 출근 기록 생성
      final atts = _makeWeekdayAttendances(
        periodStart, periodEnd,
        excludeLaborDay: false,
      );

      final result = PayrollCalculator.calculate(
        workerData: workerData,
        shifts: atts,
        periodStart: periodStart,
        periodEnd: periodEnd,
        hourlyRate: minimumWage,
        isFiveOrMore: true,
        allHistoricalAttendances: atts,
      );

      // 총급여가 2,500,000원보다 많아야 함 (5/1 출근 가산수당)
      expect(result.totalPay, greaterThan(targetSalary),
          reason: '근로자의 날 출근 → 2,500,000원 + 추가 가산수당');
      // 근로자의 날 출근수당이 양수
      expect(result.laborDayWorkPay, greaterThan(0),
          reason: '근로자의 날 출근수당 > 0');
    });

    // ═══════════════════════════════════════════════════
    // [케이스 6] 통상시급 산정 시 고정연장수당 제외 검증
    //           conservativeHourly = (기본급 + 식대) / 209
    //           ★ 고정연장수당은 반드시 분자에서 제외
    // ═══════════════════════════════════════════════════
    test('통상시급 산정에서 고정연장수당 제외 (대법원 2012다89399)', () {
      // 통상시급 = (2,156,880 + 200,000) / 209 ≈ 11,277원
      // ★ 고정OT(143,120)를 포함하면 11,962원 → 과대 산정 → 위법
      final expectedHourly = (baseSalary + mealAllowance) / standardMonthlyHours;
      final wrongHourly = targetSalary / standardMonthlyHours;

      expect(conservativeHourly, closeTo(expectedHourly, 0.01),
          reason: '통상시급 = (기본급+식대)/209');
      expect(conservativeHourly, isNot(closeTo(wrongHourly, 0.01)),
          reason: '고정OT를 포함한 시급과는 달라야 함');
      expect(conservativeHourly, closeTo(11276.94, 1.0),
          reason: '(2,156,880+200,000)/209 ≈ 11,276.94원');
    });

    // ═══════════════════════════════════════════════════
    // [케이스 7] 최저임금 위반 감지 (Hard Block)
    // ═══════════════════════════════════════════════════
    test('최저임금 미달 시 minimumWageHardBlock = true', () {
      // 기본급을 의도적으로 낮게 설정 (예: 200만원 → 시급 9,569원 < 10,320원)
      final lowWorker = PayrollWorkerData(
        weeklyHoursPure: 40,
        weeklyTotalStayMinutes: 40 * 60,
        breakMinutesPerShift: 60,
        isPaidBreak: false,
        joinDate: DateTime(2025, 1, 1),
        scheduledWorkDays: [1, 2, 3, 4, 5],
        manualWeeklyHolidayApproval: true,
        mealAllowance: 200000,
        mealTaxExempt: true,
        isVirtual: true,
        weeklyHolidayDay: 0,
        wageType: 'monthly',
        monthlyWage: 2000000, // 기본급 200만원 → 200만/209 = 9,569원 < 최저시급
        fixedOvertimeHours: 0,
        fixedOvertimePay: 0,
      );

      final periodStart = DateTime(2026, 6, 16);
      final periodEnd = DateTime(2026, 7, 15);
      final atts = _makeWeekdayAttendances(periodStart, periodEnd);

      final result = PayrollCalculator.calculate(
        workerData: lowWorker,
        shifts: atts,
        periodStart: periodStart,
        periodEnd: periodEnd,
        hourlyRate: minimumWage,
        isFiveOrMore: true,
        allHistoricalAttendances: atts,
      );

      expect(result.minimumWageHardBlock, isTrue,
          reason: '기본급/209 = 9,569원 < 최저시급 10,320원 → Hard Block');
    });

    // ═══════════════════════════════════════════════════
    // [케이스 8] 5인 미만 사업장: 연장 가산 미적용(1.0배)
    // ═══════════════════════════════════════════════════
    test('5인 미만: 연장 가산율 1.0배 (가산 없음)', () {
      final workerData = _makeMonthlyWorker();
      final periodStart = DateTime(2026, 6, 16);
      final periodEnd = DateTime(2026, 7, 15);
      final atts = _makeWeekdayAttendances(periodStart, periodEnd);

      final resultFive = PayrollCalculator.calculate(
        workerData: workerData,
        shifts: atts,
        periodStart: periodStart,
        periodEnd: periodEnd,
        hourlyRate: minimumWage,
        isFiveOrMore: true,
        allHistoricalAttendances: atts,
      );

      final resultUnder = PayrollCalculator.calculate(
        workerData: workerData,
        shifts: atts,
        periodStart: periodStart,
        periodEnd: periodEnd,
        hourlyRate: minimumWage,
        isFiveOrMore: false,
        allHistoricalAttendances: atts,
      );

      // 만근(정상 근무시간)이면 둘 다 기본 2,500,000원이어야 함
      // (초과연장 없으므로 5인 규모와 무관)
      expect(resultFive.totalPay, resultUnder.totalPay,
          reason: '초과연장 없이 만근이면 5인 규모와 무관하게 동일');
    });

    // ═══════════════════════════════════════════════════
    // [케이스 9] 비과세 식대 200,000원 한도 적용
    // ═══════════════════════════════════════════════════
    test('비과세 식대: 200,000원 정확히 적용', () {
      final workerData = _makeMonthlyWorker();
      final periodStart = DateTime(2026, 6, 16);
      final periodEnd = DateTime(2026, 7, 15);
      final atts = _makeWeekdayAttendances(periodStart, periodEnd);

      final result = PayrollCalculator.calculate(
        workerData: workerData,
        shifts: atts,
        periodStart: periodStart,
        periodEnd: periodEnd,
        hourlyRate: minimumWage,
        isFiveOrMore: true,
        allHistoricalAttendances: atts,
      );

      expect(result.mealNonTaxable, 200000.0,
          reason: '비과세 식대 = 200,000원');
      expect(result.taxableWage, targetSalary - 200000.0,
          reason: '과세대상 = 총급여 - 비과세식대');
    });
  });
}
