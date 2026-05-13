/// 기술매뉴얼 §4 가산수당 + §5 근로자의날 + §3.2 월급제 일할계산 증명 테스트
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_logic/shared_logic.dart';

void main() {
  Attendance att({
    required DateTime cin, required DateTime cout,
    String? schedStart, String? schedEnd,
    String status = 'Normal', bool otApproved = false,
  }) => Attendance(
    id: 'a_${cin.hashCode}', staffId: 'w1', storeId: 's1',
    clockIn: cin, clockOut: cout, type: AttendanceType.web,
    attendanceStatus: status, overtimeApproved: otApproved,
    scheduledShiftStartIso: schedStart, scheduledShiftEndIso: schedEnd,
  );

  group('[§4.1] 연장·야간 가산수당 (5인 분기)', () {
    // 14:00~24:00 (10h 체류, 1h 휴게, 9h 순수)
    // 연장: 8h 초과 1h, 야간: 22~24 2h
    PayrollWorkerData worker() => PayrollWorkerData(
      weeklyHoursPure: 40, weeklyTotalStayMinutes: 2700,
      breakMinutesPerShift: 60, isPaidBreak: false,
      joinDate: DateTime(2025, 1, 1),
      scheduledWorkDays: [1,2,3,4,5],
      manualWeeklyHolidayApproval: false,
      weeklyHolidayDay: 0, isVirtual: true, graceMinutes: 0,
      wageHistoryJson: '[{"effectiveDate":"2025-01-01","hourlyWage":10320}]',
    );

    final d = DateTime(2026, 7, 6);
    final a = att(
      cin: DateTime(d.year, d.month, d.day, 14, 0),
      cout: DateTime(d.year, d.month, d.day + 1, 0, 0), // 자정
      schedStart: DateTime(d.year, d.month, d.day, 14, 0).toIso8601String(),
      schedEnd: DateTime(d.year, d.month, d.day + 1, 0, 0).toIso8601String(),
      otApproved: true,
    );

    test('5인 이상: 연장+야간 가산 → premiumPay > 0', () {
      final result = PayrollCalculator.calculate(
        workerData: worker(), shifts: [a], hourlyRate: 10320,
        periodStart: d, periodEnd: DateTime(2026, 7, 12),
        isFiveOrMore: true, allHistoricalAttendances: [a],
      );
      expect(result.premiumPay, greaterThan(0),
          reason: '5인 이상: 연장 1h + 야간 2h → 가산수당 발생');
      print('✅ 5인 이상 가산: ${result.premiumPay.round()}원');
    });

    test('5인 미만: 가산 0원', () {
      final result = PayrollCalculator.calculate(
        workerData: worker(), shifts: [a], hourlyRate: 10320,
        periodStart: d, periodEnd: DateTime(2026, 7, 12),
        isFiveOrMore: false, allHistoricalAttendances: [a],
      );
      expect(result.premiumPay, equals(0.0),
          reason: '5인 미만: 가산수당 의무 없음 → 0원');
    });

    test('5인 이상 vs 5인 미만 → 가산수당 차이 존재', () {
      final r5 = PayrollCalculator.calculate(
        workerData: worker(), shifts: [a], hourlyRate: 10320,
        periodStart: d, periodEnd: DateTime(2026, 7, 12),
        isFiveOrMore: true, allHistoricalAttendances: [a],
      );
      final r4 = PayrollCalculator.calculate(
        workerData: worker(), shifts: [a], hourlyRate: 10320,
        periodStart: d, periodEnd: DateTime(2026, 7, 12),
        isFiveOrMore: false, allHistoricalAttendances: [a],
      );
      expect(r5.totalPay, greaterThan(r4.totalPay),
          reason: '동일 근무시간, 5인 이상이 급여 더 높음');
      print('  5인이상: ${r5.totalPay.round()}원 vs 5인미만: ${r4.totalPay.round()}원');
    });
  });

  group('[§5.3] 근로자의 날(5/1) 유급휴일 비례', () {
    test('시급제 주 40h: 미출근 시 8h × 시급 유급', () {
      final worker = PayrollWorkerData(
        weeklyHoursPure: 40, weeklyTotalStayMinutes: 2700,
        breakMinutesPerShift: 60, isPaidBreak: false,
        joinDate: DateTime(2025, 1, 1),
        scheduledWorkDays: [1,2,3,4,5],
        manualWeeklyHolidayApproval: true,
        weeklyHolidayDay: 0, isVirtual: true, graceMinutes: 0,
        wageHistoryJson: '[{"effectiveDate":"2025-01-01","hourlyWage":10320}]',
      );
      // 4/28~5/2 주간, 5/1 출근 안 함
      final atts = <Attendance>[];
      for (final day in [28, 29, 30]) {
        final d = DateTime(2026, 4, day);
        atts.add(att(
          cin: DateTime(d.year, d.month, d.day, 9, 0),
          cout: DateTime(d.year, d.month, d.day, 18, 0),
          schedStart: DateTime(d.year, d.month, d.day, 9, 0).toIso8601String(),
          schedEnd: DateTime(d.year, d.month, d.day, 18, 0).toIso8601String(),
        ));
      }
      final d2 = DateTime(2026, 5, 2);
      atts.add(att(
        cin: DateTime(d2.year, d2.month, d2.day, 9, 0),
        cout: DateTime(d2.year, d2.month, d2.day, 18, 0),
        schedStart: DateTime(d2.year, d2.month, d2.day, 9, 0).toIso8601String(),
        schedEnd: DateTime(d2.year, d2.month, d2.day, 18, 0).toIso8601String(),
      ));

      final result = PayrollCalculator.calculate(
        workerData: worker, shifts: atts, hourlyRate: 10320,
        periodStart: DateTime(2026, 4, 16), periodEnd: DateTime(2026, 5, 15),
        isFiveOrMore: true, allHistoricalAttendances: atts,
      );
      // 5/1 미출근이어도 유급: (40/40) × 8 × 10320 = 82,560원
      expect(result.laborDayAllowancePay, closeTo(82560.0, 1.0),
          reason: '근로자의 날 유급: 8h × 10,320 = 82,560원');
      print('✅ 근로자의 날 유급: ${result.laborDayAllowancePay.round()}원');
    });

    test('초단시간 주 14h: 비례 유급 = (14/40)×8×시급', () {
      final worker = PayrollWorkerData(
        weeklyHoursPure: 14, weeklyTotalStayMinutes: 840 + 60,
        breakMinutesPerShift: 0, isPaidBreak: false,
        joinDate: DateTime(2025, 1, 1),
        scheduledWorkDays: [1, 3],
        manualWeeklyHolidayApproval: false,
        weeklyHolidayDay: 0, isVirtual: true, graceMinutes: 0,
        wageHistoryJson: '[{"effectiveDate":"2025-01-01","hourlyWage":10320}]',
      );
      final result = PayrollCalculator.calculate(
        workerData: worker, shifts: [], hourlyRate: 10320,
        periodStart: DateTime(2026, 4, 16), periodEnd: DateTime(2026, 5, 15),
        isFiveOrMore: true, allHistoricalAttendances: [],
      );
      // (14/40) × 8 × 10320 = 28,896원
      final expected = (14.0 / 40.0) * 8.0 * 10320.0;
      expect(result.laborDayAllowancePay, closeTo(expected, 1.0),
          reason: '초단시간 비례: (14/40)×8×10320 = ${expected.round()}원');
      print('✅ 초단시간 근로자의 날: ${result.laborDayAllowancePay.round()}원');
    });
  });

  group('[§3.2] 월급제 일할계산 (Pro-rata)', () {
    test('중도 입사 → proRataRatio < 1.0', () {
      // 7/16 입사, 정산기간 7/1~7/31 → 16일/31일
      final worker = PayrollWorkerData(
        weeklyHoursPure: 40, weeklyTotalStayMinutes: 2700,
        breakMinutesPerShift: 60, isPaidBreak: false,
        joinDate: DateTime(2026, 7, 16),
        scheduledWorkDays: [1,2,3,4,5],
        manualWeeklyHolidayApproval: true,
        weeklyHolidayDay: 0, isVirtual: true, graceMinutes: 0,
        wageType: 'monthly', monthlyWage: 2500000,
        mealAllowance: 200000,
        wageHistoryJson: '',
      );
      // 7/16~7/31 출근 기록 생성 (평일만)
      final atts = <Attendance>[];
      for (int d = 16; d <= 31; d++) {
        final date = DateTime(2026, 7, d);
        if (date.weekday == DateTime.saturday || date.weekday == DateTime.sunday) continue;
        atts.add(att(
          cin: DateTime(2026, 7, d, 9, 0),
          cout: DateTime(2026, 7, d, 18, 0),
          schedStart: DateTime(2026, 7, d, 9, 0).toIso8601String(),
          schedEnd: DateTime(2026, 7, d, 18, 0).toIso8601String(),
        ));
      }

      final result = PayrollCalculator.calculate(
        workerData: worker, shifts: atts, hourlyRate: 10320,
        periodStart: DateTime(2026, 7, 1), periodEnd: DateTime(2026, 7, 31),
        isFiveOrMore: true, allHistoricalAttendances: atts,
      );
      expect(result.proRataRatio, lessThan(1.0),
          reason: '중도 입사 → 일할 비율 < 1.0');
      expect(result.totalPay, lessThan(2500000),
          reason: '일할 계산으로 250만원 미만');
      print('✅ 월급제 일할: ratio=${result.proRataRatio.toStringAsFixed(3)}, total=${result.totalPay.round()}원');
    });
  });

  group('[§2.4] 스케줄 없는 날 출근 (Unscheduled)', () {
    test('스케줄 없는 출근 → 보정 없이 실시간 인정', () {
      final worker = PayrollWorkerData(
        weeklyHoursPure: 40, weeklyTotalStayMinutes: 2700,
        breakMinutesPerShift: 60, isPaidBreak: false,
        joinDate: DateTime(2025, 1, 1),
        scheduledWorkDays: [1,2,3,4,5],
        manualWeeklyHolidayApproval: false,
        weeklyHolidayDay: 0, isVirtual: true, graceMinutes: 0,
        wageHistoryJson: '[{"effectiveDate":"2025-01-01","hourlyWage":10320}]',
      );
      // 스케줄 없음(schedStart/schedEnd = null) → 8:30~17:00 그대로
      final a = att(
        cin: DateTime(2026, 7, 6, 8, 30),
        cout: DateTime(2026, 7, 6, 17, 0),
        status: 'UnplannedApproved', // 승인됨
      );
      final result = PayrollCalculator.calculate(
        workerData: worker, shifts: [a], hourlyRate: 10320,
        periodStart: DateTime(2026, 7, 6), periodEnd: DateTime(2026, 7, 12),
        isFiveOrMore: true, allHistoricalAttendances: [a],
      );
      // 8:30~17:00 = 8.5h 체류, 1h 법정 휴게 → 7.5h
      expect(result.basePay, closeTo(7.5 * 10320, 1.0),
          reason: '스케줄 없음 → 실시간 8:30~17:00 인정');
    });
  });
}
