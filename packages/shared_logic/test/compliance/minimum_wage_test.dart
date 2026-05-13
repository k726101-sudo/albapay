/// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
/// [법률 테스트] 최저임금 검증 — 최저임금법 제6조
/// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
///
/// 【검증 대상 법령】
///   - 최저임금법 제6조: 사용자는 최저임금 이상의 임금을 지급하여야 함
///   - 2026년 최저시급: 10,320원
///   - 월 소정근로시간: 209시간 (주 40+8주휴) × 4.345주
///   - 최저 월급: 10,320 × 209 = 2,156,880원
///
/// 【검증 시나리오】
///   - 기본급 / S_Ref(209h) < 10,320원 → Hard Block (저장 차단)
///   - (기본급 + 식대) / S_Ref < 10,320원 → Warning (경고만)
///   - 시급이 최저시급 미만 → 자동 소급 보정 (시급 올림)
/// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_logic/shared_logic.dart';

void main() {
  group('[최저임금법 제6조] 최저임금 검증', () {
    // ═══════════════════════════════════════════════════
    // [케이스 1] 2026년 최저시급·최저월급 상수 정확도
    // ═══════════════════════════════════════════════════
    test('2026년 최저시급 = 10,320원, 월 209h, 최저월급 = 2,156,880원', () {
      expect(PayrollConstants.legalMinimumWage, 10320.0);
      expect(PayrollConstants.standardMonthlyHours, 209.0);
      expect(PayrollConstants.baseMinimumSalary, 2156880.0);
      expect(PayrollConstants.baseMinimumSalary,
          PayrollConstants.legalMinimumWage * PayrollConstants.standardMonthlyHours,
          reason: '최저월급 = 최저시급 × 209h');
    });

    // ═══════════════════════════════════════════════════
    // [케이스 2] 월급제: 기본급 200만원 → Hard Block
    // ═══════════════════════════════════════════════════
    test('월급제 기본급 2,000,000원 → 최저임금 Hard Block', () {
      final worker = PayrollWorkerData(
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
        monthlyWage: 2000000, // 기본급 200만 → 시급 9,569원
        fixedOvertimeHours: 0,
        fixedOvertimePay: 0,
      );

      final periodStart = DateTime(2026, 7, 1);
      final periodEnd = DateTime(2026, 7, 31);
      final atts = <Attendance>[];
      for (var d = periodStart; !d.isAfter(periodEnd);
          d = d.add(const Duration(days: 1))) {
        if (d.weekday >= 1 && d.weekday <= 5) {
          atts.add(Attendance(
            id: 'a_${d.day}',
            staffId: 'w1',
            storeId: 's1',
            clockIn: DateTime(d.year, d.month, d.day, 9, 0),
            clockOut: DateTime(d.year, d.month, d.day, 18, 0),
            type: AttendanceType.web,
            attendanceStatus: 'Normal',
          ));
        }
      }

      final result = PayrollCalculator.calculate(
        workerData: worker,
        shifts: atts,
        periodStart: periodStart,
        periodEnd: periodEnd,
        hourlyRate: PayrollConstants.legalMinimumWage,
        isFiveOrMore: true,
        allHistoricalAttendances: atts,
      );

      expect(result.minimumWageHardBlock, isTrue,
          reason: '2,000,000/209 = 9,569원 < 10,320원 → Hard Block');
    });

    // ═══════════════════════════════════════════════════
    // [케이스 3] 월급제: 기본급 2,156,880원 → 통과
    // ═══════════════════════════════════════════════════
    test('월급제 기본급 2,156,880원(최저 하한) → 최저임금 통과', () {
      final worker = PayrollWorkerData(
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
        monthlyWage: 2156880, // 정확히 최저
        fixedOvertimeHours: 0,
        fixedOvertimePay: 0,
      );

      final periodStart = DateTime(2026, 7, 1);
      final periodEnd = DateTime(2026, 7, 31);
      final atts = <Attendance>[];
      for (var d = periodStart; !d.isAfter(periodEnd);
          d = d.add(const Duration(days: 1))) {
        if (d.weekday >= 1 && d.weekday <= 5) {
          atts.add(Attendance(
            id: 'a_${d.day}',
            staffId: 'w1',
            storeId: 's1',
            clockIn: DateTime(d.year, d.month, d.day, 9, 0),
            clockOut: DateTime(d.year, d.month, d.day, 18, 0),
            type: AttendanceType.web,
            attendanceStatus: 'Normal',
          ));
        }
      }

      final result = PayrollCalculator.calculate(
        workerData: worker,
        shifts: atts,
        periodStart: periodStart,
        periodEnd: periodEnd,
        hourlyRate: PayrollConstants.legalMinimumWage,
        isFiveOrMore: true,
        allHistoricalAttendances: atts,
      );

      expect(result.minimumWageHardBlock, isFalse,
          reason: '2,156,880/209 = 10,320원 = 최저시급 → 통과');
      expect(result.minimumWageWarning, isFalse,
          reason: '기본급+식대도 충분 → Warning도 없음');
    });

    // ═══════════════════════════════════════════════════
    // [케이스 4] 시급제: 9,000원 → 자동 소급 보정
    // ═══════════════════════════════════════════════════
    test('시급제 9,000원 입력 → 엔진이 10,320원으로 자동 보정', () {
      final worker = PayrollWorkerData(
        weeklyHoursPure: 40,
        weeklyTotalStayMinutes: 40 * 60,
        breakMinutesPerShift: 60,
        isPaidBreak: false,
        joinDate: DateTime(2025, 1, 1),
        scheduledWorkDays: [1, 2, 3, 4, 5],
        manualWeeklyHolidayApproval: true,
        isVirtual: true,
        weeklyHolidayDay: 0,
      );

      final att = Attendance(
        id: 'a1',
        staffId: 'w1',
        storeId: 's1',
        clockIn: DateTime(2026, 7, 6, 9, 0),
        clockOut: DateTime(2026, 7, 6, 18, 0),
        type: AttendanceType.web,
        attendanceStatus: 'Normal',
        scheduledShiftStartIso: DateTime(2026, 7, 6, 9, 0).toIso8601String(),
        scheduledShiftEndIso: DateTime(2026, 7, 6, 18, 0).toIso8601String(),
      );

      final result = PayrollCalculator.calculate(
        workerData: worker,
        shifts: [att],
        periodStart: DateTime(2026, 7, 6),
        periodEnd: DateTime(2026, 7, 6),
        hourlyRate: 9000.0, // ★ 최저시급 미달
        isFiveOrMore: true,
        allHistoricalAttendances: [att],
      );

      // 8시간 × 10,320원(보정) = 82,560원 (9,000 × 8 = 72,000이면 안 됨)
      expect(result.basePay, 8 * PayrollConstants.legalMinimumWage,
          reason: '시급 9,000원 → 10,320원 자동 소급 보정');
      expect(result.basePay, isNot(8 * 9000.0),
          reason: '최저 미달 시급이 그대로 적용되면 안 됨');
    });

    // ═══════════════════════════════════════════════════
    // [케이스 5] 비과세 식대 한도 200,000원 상수 확인
    // ═══════════════════════════════════════════════════
    test('비과세 식대 한도 = 200,000원', () {
      expect(PayrollConstants.mealTaxFreeLimit, 200000.0);
      expect(PayrollConstants.maxTaxFreeMealAllowance, 200000.0);
    });
  });
}
