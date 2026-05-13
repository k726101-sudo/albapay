/// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
/// [법률 테스트] 연장·야간·휴일 가산수당 — 근로기준법 제56조
/// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
///
/// 【검증 대상 법령】
///   - 근로기준법 제56조 제1항: 연장근로 → 통상임금의 50% 이상 가산
///   - 근로기준법 제56조 제2항: 야간근로(22:00~06:00) → 50% 가산
///   - 근로기준법 제56조 제3항: 휴일근로 → 50% 가산
///   - 근로기준법 제11조: 5인 미만 사업장은 가산수당 의무 면제
///
/// 【테스트 의의】
///   시급제 직원의 가산수당 산출 정확도 검증.
///   5인 이상/미만 분기에 따른 가산율(1.5배 vs 1.0배) 정확 적용 여부.
/// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_logic/shared_logic.dart';

void main() {
  group('[근로기준법 제56조] 연장·야간·휴일 가산수당', () {
    const hourlyRate = 12000.0;
    final joinDate = DateTime(2025, 1, 1);
    final scheduledDays = [1, 2, 3, 4, 5]; // 월~금

    PayrollWorkerData _makeHourlyWorker({
      double weeklyHours = 40,
      bool isPaidBreak = false,
    }) {
      return PayrollWorkerData(
        weeklyHoursPure: weeklyHours,
        weeklyTotalStayMinutes: (weeklyHours * 60).round(),
        breakMinutesPerShift: 60,
        isPaidBreak: isPaidBreak,
        joinDate: joinDate,
        scheduledWorkDays: scheduledDays,
        manualWeeklyHolidayApproval: true,
        isVirtual: true,
        weeklyHolidayDay: 0,
      );
    }

    // ═══════════════════════════════════════════════════
    // [케이스 1] 정상 근무(8시간) — 가산수당 0원
    // ═══════════════════════════════════════════════════
    test('정상 8시간 근무 → 연장수당 0원', () {
      final worker = _makeHourlyWorker();
      final att = Attendance(
        id: 'a1',
        staffId: 'w1',
        storeId: 's1',
        clockIn: DateTime(2026, 7, 6, 9, 0),  // 월요일
        clockOut: DateTime(2026, 7, 6, 18, 0), // 9시간 체류, 1시간 휴게 = 8시간 순수
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
        hourlyRate: hourlyRate,
        isFiveOrMore: true,
        allHistoricalAttendances: [att],
      );

      // 8시간 × 12,000원 = 96,000원 (가산 없음)
      expect(result.basePay, 8 * hourlyRate);
      expect(result.premiumPay, 0.0, reason: '8시간 이내 → 가산수당 0원');
    });

    // ═══════════════════════════════════════════════════
    // [케이스 2] 5인 이상: 연장근로 가산(1.5배) 적용
    // ═══════════════════════════════════════════════════
    test('5인 이상: 10시간 근무(2시간 연장) → 연장분 1.5배', () {
      final worker = _makeHourlyWorker();
      // 09:00 ~ 20:00 (11시간 체류, 1시간 휴게 = 10시간 순수, 2시간 연장)
      final att = Attendance(
        id: 'a1',
        staffId: 'w1',
        storeId: 's1',
        clockIn: DateTime(2026, 7, 6, 9, 0),
        clockOut: DateTime(2026, 7, 6, 20, 0),
        type: AttendanceType.web,
        attendanceStatus: 'Normal',
        scheduledShiftStartIso: DateTime(2026, 7, 6, 9, 0).toIso8601String(),
        scheduledShiftEndIso: DateTime(2026, 7, 6, 18, 0).toIso8601String(),
        overtimeApproved: true,
      );

      final result = PayrollCalculator.calculate(
        workerData: worker,
        shifts: [att],
        periodStart: DateTime(2026, 7, 6),
        periodEnd: DateTime(2026, 7, 6),
        hourlyRate: hourlyRate,
        isFiveOrMore: true,
        allHistoricalAttendances: [att],
      );

      // basePay = 10h × 12,000 = 120,000원
      // premiumPay = 2h × 12,000 × 0.5 = 12,000원 (가산분만)
      expect(result.basePay, 10 * hourlyRate);
      expect(result.premiumPay, closeTo(2 * hourlyRate * 0.5, 1.0),
          reason: '5인 이상: 2시간 연장 × 12,000 × 0.5 = 12,000원 가산');
    });

    // ═══════════════════════════════════════════════════
    // [케이스 3] 5인 미만: 연장근로 가산 면제(0원)
    // ═══════════════════════════════════════════════════
    test('5인 미만: 10시간 근무(2시간 연장) → 가산수당 0원', () {
      final worker = _makeHourlyWorker();
      final att = Attendance(
        id: 'a1',
        staffId: 'w1',
        storeId: 's1',
        clockIn: DateTime(2026, 7, 6, 9, 0),
        clockOut: DateTime(2026, 7, 6, 20, 0),
        type: AttendanceType.web,
        attendanceStatus: 'Normal',
        scheduledShiftStartIso: DateTime(2026, 7, 6, 9, 0).toIso8601String(),
        scheduledShiftEndIso: DateTime(2026, 7, 6, 18, 0).toIso8601String(),
        overtimeApproved: true,
      );

      final result = PayrollCalculator.calculate(
        workerData: worker,
        shifts: [att],
        periodStart: DateTime(2026, 7, 6),
        periodEnd: DateTime(2026, 7, 6),
        hourlyRate: hourlyRate,
        isFiveOrMore: false,
        allHistoricalAttendances: [att],
      );

      // basePay = 10h × 12,000 = 120,000원
      // premiumPay = 0원 (5인 미만 가산 면제)
      expect(result.basePay, 10 * hourlyRate);
      expect(result.premiumPay, 0.0,
          reason: '5인 미만: 가산수당 의무 면제');
    });

    // ═══════════════════════════════════════════════════
    // [케이스 4] 야간근로(22:00~06:00) 가산 검증
    // ═══════════════════════════════════════════════════
    test('5인 이상: 야간근로(22:00~06:00) → 야간분 0.5배 가산', () {
      final worker = _makeHourlyWorker(weeklyHours: 40);
      // 22:00 ~ 06:00 (8시간 체류, 1시간 휴게 = 7시간 순수, 전부 야간)
      final att = Attendance(
        id: 'a1',
        staffId: 'w1',
        storeId: 's1',
        clockIn: DateTime(2026, 7, 6, 22, 0),
        clockOut: DateTime(2026, 7, 7, 6, 0),
        type: AttendanceType.web,
        attendanceStatus: 'Normal',
        scheduledShiftStartIso: DateTime(2026, 7, 6, 22, 0).toIso8601String(),
        scheduledShiftEndIso: DateTime(2026, 7, 7, 6, 0).toIso8601String(),
      );

      final result = PayrollCalculator.calculate(
        workerData: worker,
        shifts: [att],
        periodStart: DateTime(2026, 7, 6),
        periodEnd: DateTime(2026, 7, 7),
        hourlyRate: hourlyRate,
        isFiveOrMore: true,
        allHistoricalAttendances: [att],
      );

      // 야간 가산수당이 0보다 커야 함
      expect(result.premiumPay, greaterThan(0),
          reason: '5인 이상: 야간근로 → 가산수당 발생');
    });

    // ═══════════════════════════════════════════════════
    // [케이스 5] 5인 미만: 야간근로 가산 면제
    // ═══════════════════════════════════════════════════
    test('5인 미만: 야간근로 → 가산수당 0원', () {
      final worker = _makeHourlyWorker(weeklyHours: 40);
      final att = Attendance(
        id: 'a1',
        staffId: 'w1',
        storeId: 's1',
        clockIn: DateTime(2026, 7, 6, 22, 0),
        clockOut: DateTime(2026, 7, 7, 6, 0),
        type: AttendanceType.web,
        attendanceStatus: 'Normal',
        scheduledShiftStartIso: DateTime(2026, 7, 6, 22, 0).toIso8601String(),
        scheduledShiftEndIso: DateTime(2026, 7, 7, 6, 0).toIso8601String(),
      );

      final result = PayrollCalculator.calculate(
        workerData: worker,
        shifts: [att],
        periodStart: DateTime(2026, 7, 6),
        periodEnd: DateTime(2026, 7, 7),
        hourlyRate: hourlyRate,
        isFiveOrMore: false,
        allHistoricalAttendances: [att],
      );

      expect(result.premiumPay, 0.0,
          reason: '5인 미만: 야간 가산 면제');
    });

    // ═══════════════════════════════════════════════════
    // [케이스 6] 휴무일(대타) 출근 — 휴일근로 가산
    // ═══════════════════════════════════════════════════
    test('5인 이상: 토요일(휴무일) 대타 출근 → 휴일근로 가산', () {
      final worker = _makeHourlyWorker(); // 월~금 근무
      // 토요일 출근 = 휴무일 근무
      final att = Attendance(
        id: 'a1',
        staffId: 'w1',
        storeId: 's1',
        clockIn: DateTime(2026, 7, 11, 9, 0),  // 토요일
        clockOut: DateTime(2026, 7, 11, 18, 0),
        type: AttendanceType.web,
        attendanceStatus: 'Normal',
        scheduledShiftStartIso: DateTime(2026, 7, 11, 9, 0).toIso8601String(),
        scheduledShiftEndIso: DateTime(2026, 7, 11, 18, 0).toIso8601String(),
      );

      final result = PayrollCalculator.calculate(
        workerData: worker,
        shifts: [att],
        periodStart: DateTime(2026, 7, 11),
        periodEnd: DateTime(2026, 7, 11),
        hourlyRate: hourlyRate,
        isFiveOrMore: true,
        allHistoricalAttendances: [att],
      );

      // 휴일근로 → 가산수당 발생
      expect(result.premiumPay, greaterThan(0),
          reason: '5인 이상: 토요일(휴무일) 출근 → 휴일근로 가산');
    });
  });
}
