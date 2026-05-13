/// 기술매뉴얼 §2 출퇴근 보정 + §3 기본급 산정 증명 테스트
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_logic/shared_logic.dart';

void main() {
  // ── 공통 헬퍼 ──
  Attendance att({
    required DateTime cin,
    required DateTime cout,
    String? schedStart,
    String? schedEnd,
    String status = 'Normal',
    bool otApproved = false,
    bool editedByBoss = false,
  }) =>
      Attendance(
        id: 'a_${cin.hashCode}',
        staffId: 'w1',
        storeId: 's1',
        clockIn: cin,
        clockOut: cout,
        type: AttendanceType.web,
        attendanceStatus: status,
        overtimeApproved: otApproved,
        isEditedByBoss: editedByBoss,
        scheduledShiftStartIso: schedStart,
        scheduledShiftEndIso: schedEnd,
      );

  final sched9 = DateTime(2026, 7, 6, 9, 0).toIso8601String();
  final sched18 = DateTime(2026, 7, 6, 18, 0).toIso8601String();

  group('[§2.1] 출퇴근 보정 로직', () {
    test('조기 출근 Cap: 8:40 출근 → 정시 9:00 보정', () {
      final effective = payrollEffectiveClockIn(
        actualClockIn: DateTime(2026, 7, 6, 8, 40),
        scheduledStart: DateTime(2026, 7, 6, 9, 0),
      );
      expect(effective, DateTime(2026, 7, 6, 9, 0));
    });

    test('지각 유예 5분: 9:03 출근 → 9:00 인정', () {
      final effective = payrollEffectiveClockIn(
        actualClockIn: DateTime(2026, 7, 6, 9, 3),
        scheduledStart: DateTime(2026, 7, 6, 9, 0),
        graceMinutes: 5,
      );
      expect(effective, DateTime(2026, 7, 6, 9, 0));
    });

    test('지각 유예 초과 8분: 9:08 출근 → 9:08 그대로', () {
      final effective = payrollEffectiveClockIn(
        actualClockIn: DateTime(2026, 7, 6, 9, 8),
        scheduledStart: DateTime(2026, 7, 6, 9, 0),
        graceMinutes: 5,
      );
      expect(effective, DateTime(2026, 7, 6, 9, 8));
    });

    test('연장 미승인: 18:20 퇴근 → 18:00 절삭', () {
      final effective = payrollSettlementClockOut(
        actualClockOut: DateTime(2026, 7, 6, 18, 20),
        scheduledShiftEndIso: sched18,
        overtimeApproved: false,
      );
      expect(effective, DateTime(2026, 7, 6, 18, 0));
    });

    test('연장 승인: 18:20 퇴근 → 18:20 그대로', () {
      final effective = payrollSettlementClockOut(
        actualClockOut: DateTime(2026, 7, 6, 18, 20),
        scheduledShiftEndIso: sched18,
        overtimeApproved: true,
      );
      expect(effective, DateTime(2026, 7, 6, 18, 20));
    });
  });

  group('[§2.3] 법정 휴게시간 강제', () {
    test('8시간 이상 → 최소 60분 휴게 강제', () {
      final a = att(
        cin: DateTime(2026, 7, 6, 9, 0),
        cout: DateTime(2026, 7, 6, 18, 0),
        schedStart: sched9,
        schedEnd: sched18,
      );
      final applied = PayrollCalculator.calculateAppliedBreak(
        att: a,
        effectiveIn: a.clockIn,
        effectiveOut: a.clockOut!,
        fallbackMinutes: 0, // 사장님이 휴게 미설정
        breakStartTimeStr: '',
        breakEndTimeStr: '',
      );
      expect(applied, greaterThanOrEqualTo(60),
          reason: '9h 체류 ≥ 8h → 법정 60분 강제');
    });

    test('4~8시간 → 최소 30분 휴게 강제', () {
      final a = att(
        cin: DateTime(2026, 7, 6, 9, 0),
        cout: DateTime(2026, 7, 6, 14, 0),
        schedStart: sched9,
        schedEnd: DateTime(2026, 7, 6, 14, 0).toIso8601String(),
      );
      final applied = PayrollCalculator.calculateAppliedBreak(
        att: a,
        effectiveIn: a.clockIn,
        effectiveOut: a.clockOut!,
        fallbackMinutes: 0,
        breakStartTimeStr: '',
        breakEndTimeStr: '',
      );
      expect(applied, greaterThanOrEqualTo(30),
          reason: '5h 체류 ≥ 4h → 법정 30분 강제');
    });
  });

  group('[§2.4] attendanceStatus 필터', () {
    for (final status in ['Unplanned', 'pending_approval', 'pending_overtime', 'early_leave_pending']) {
      test('$status → 급여 제외', () {
        final a = att(
          cin: DateTime(2026, 7, 6, 9, 0),
          cout: DateTime(2026, 7, 6, 18, 0),
          status: status,
        );
        expect(PayrollCalculator.isAttendanceIncludedForPayroll(a), isFalse);
      });
    }

    for (final status in ['Normal', 'UnplannedApproved', 'early_clock_out']) {
      test('$status → 급여 포함', () {
        final a = att(
          cin: DateTime(2026, 7, 6, 9, 0),
          cout: DateTime(2026, 7, 6, 18, 0),
          status: status,
        );
        expect(PayrollCalculator.isAttendanceIncludedForPayroll(a), isTrue);
      });
    }
  });

  group('[§3.1] 시급제 기본급 산정', () {
    test('분 단위 정밀 계산: 7시간 30분 × 10,320 = 77,400원', () {
      final worker = PayrollWorkerData(
        weeklyHoursPure: 40, weeklyTotalStayMinutes: 2700,
        breakMinutesPerShift: 60, isPaidBreak: false,
        joinDate: DateTime(2025, 1, 1),
        scheduledWorkDays: [1, 2, 3, 4, 5],
        manualWeeklyHolidayApproval: false,
        weeklyHolidayDay: 0, isVirtual: true, graceMinutes: 0,
        wageHistoryJson: '[{"effectiveDate":"2025-01-01","hourlyWage":10320}]',
      );
      // 09:00~17:30 (8.5h 체류, 1h 휴게 → 7.5h 순수)
      final a = att(
        cin: DateTime(2026, 7, 6, 9, 0),
        cout: DateTime(2026, 7, 6, 17, 30),
        schedStart: sched9,
        schedEnd: DateTime(2026, 7, 6, 17, 30).toIso8601String(),
      );
      final result = PayrollCalculator.calculate(
        workerData: worker, shifts: [a], hourlyRate: 10320,
        periodStart: DateTime(2026, 7, 6), periodEnd: DateTime(2026, 7, 12),
        isFiveOrMore: true, allHistoricalAttendances: [a],
      );
      expect(result.basePay, closeTo(77400.0, 1.0),
          reason: '7.5h × 10,320 = 77,400');
    });

    test('유급 휴게: breakPay > 0', () {
      final worker = PayrollWorkerData(
        weeklyHoursPure: 40, weeklyTotalStayMinutes: 2700,
        breakMinutesPerShift: 60, isPaidBreak: true,
        joinDate: DateTime(2025, 1, 1),
        scheduledWorkDays: [1, 2, 3, 4, 5],
        manualWeeklyHolidayApproval: false,
        weeklyHolidayDay: 0, isVirtual: true, graceMinutes: 0,
        wageHistoryJson: '[{"effectiveDate":"2025-01-01","hourlyWage":10320}]',
      );
      final a = att(
        cin: DateTime(2026, 7, 6, 9, 0),
        cout: DateTime(2026, 7, 6, 18, 0),
        schedStart: sched9, schedEnd: sched18,
      );
      final result = PayrollCalculator.calculate(
        workerData: worker, shifts: [a], hourlyRate: 10320,
        periodStart: DateTime(2026, 7, 6), periodEnd: DateTime(2026, 7, 12),
        isFiveOrMore: true, allHistoricalAttendances: [a],
      );
      expect(result.breakPay, greaterThan(0),
          reason: 'isPaidBreak=true → 유급 휴게수당 발생');
      expect(result.breakPay, closeTo(10320.0, 1.0),
          reason: '1h 휴게 × 10,320');
    });
  });

  group('[§3.3] 수습기간 90% 감액', () {
    test('수습 기간 시급 = 원래 시급 × 0.9', () {
      final worker = PayrollWorkerData(
        weeklyHoursPure: 40, weeklyTotalStayMinutes: 2700,
        breakMinutesPerShift: 60, isPaidBreak: false,
        joinDate: DateTime(2026, 6, 1),
        scheduledWorkDays: [1, 2, 3, 4, 5],
        manualWeeklyHolidayApproval: false,
        weeklyHolidayDay: 0, isVirtual: true, graceMinutes: 0,
        isProbation: true, probationMonths: 3,
        wageHistoryJson: '[{"effectiveDate":"2026-06-01","hourlyWage":10320}]',
      );
      final a = att(
        cin: DateTime(2026, 7, 6, 9, 0),
        cout: DateTime(2026, 7, 6, 18, 0),
        schedStart: sched9, schedEnd: sched18,
      );
      final result = PayrollCalculator.calculate(
        workerData: worker, shifts: [a], hourlyRate: 10320,
        periodStart: DateTime(2026, 7, 6), periodEnd: DateTime(2026, 7, 12),
        isFiveOrMore: true, allHistoricalAttendances: [a],
      );
      // 수습 90%: floor(10320 * 0.9) = 9288
      final probationRate = (10320 * 0.9).floorToDouble();
      expect(result.basePay, closeTo(8 * probationRate, 1.0),
          reason: '수습 시급 ${probationRate}원 × 8h');
    });
  });

  group('[§7.4.3] 시급 변경 이력 (wageHistoryJson)', () {
    test('월 중간 시급 변경 → 일자별 분할 적용', () {
      final worker = PayrollWorkerData(
        weeklyHoursPure: 40, weeklyTotalStayMinutes: 2700,
        breakMinutesPerShift: 60, isPaidBreak: false,
        joinDate: DateTime(2025, 1, 1),
        scheduledWorkDays: [1, 2, 3, 4, 5],
        manualWeeklyHolidayApproval: false,
        weeklyHolidayDay: 0, isVirtual: true, graceMinutes: 0,
        wageHistoryJson: '[{"effectiveDate":"2025-01-01","hourlyWage":10320},{"effectiveDate":"2026-07-09","hourlyWage":11000}]',
      );
      // 7/6(월) 10320원, 7/7(화) 10320원, 7/8(수) 10320원
      // 7/9(목) 11000원, 7/10(금) 11000원
      final atts = <Attendance>[];
      for (int i = 0; i < 5; i++) {
        final d = DateTime(2026, 7, 6 + i);
        atts.add(att(
          cin: DateTime(d.year, d.month, d.day, 9, 0),
          cout: DateTime(d.year, d.month, d.day, 18, 0),
          schedStart: DateTime(d.year, d.month, d.day, 9, 0).toIso8601String(),
          schedEnd: DateTime(d.year, d.month, d.day, 18, 0).toIso8601String(),
        ));
      }
      final result = PayrollCalculator.calculate(
        workerData: worker, shifts: atts, hourlyRate: 10320,
        periodStart: DateTime(2026, 7, 6), periodEnd: DateTime(2026, 7, 12),
        isFiveOrMore: true, allHistoricalAttendances: atts,
      );
      // 3일 × 8h × 10320 + 2일 × 8h × 11000
      final expected = (3 * 8 * 10320.0) + (2 * 8 * 11000.0);
      expect(result.basePay, closeTo(expected, 1.0),
          reason: '시급 분할: 3일@10320 + 2일@11000 = $expected');

      print('✅ 시급 변경 분할: basePay = ${result.basePay}원 (기대: $expected)');
    });
  });
}
