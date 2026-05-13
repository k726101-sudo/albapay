import 'package:flutter_test/flutter_test.dart';
import 'package:shared_logic/shared_logic.dart';

void main() {
  group('Annual Leave Calculation Accuracy Tests', () {
    final joinDate = DateTime(2023, 1, 1);
    final scheduledDays = [1, 2, 3, 4, 5]; // Mon-Fri

    test('1년 미만 매달 만근 시 연차 1개씩 정상 적립 (최대 11개)', () {
      final attendances = <Attendance>[];
      // 11개월 동안 전 평일 출근 시뮬레이션
      for (int m = 0; m < 11; m++) {
        final mStart = DateTime(2023, 1 + m, 1);
        final mEnd = DateTime(
          2023,
          1 + m + 1,
          1,
        ).subtract(const Duration(days: 1));

        for (
          var d = mStart;
          !d.isAfter(mEnd);
          d = d.add(const Duration(days: 1))
        ) {
          if (d.weekday >= 1 && d.weekday <= 5) {
            attendances.add(
              Attendance(
                id: 'att_${d.millisecondsSinceEpoch}',
                staffId: 'worker1',
                storeId: 'store1',
                clockIn: DateTime(d.year, d.month, d.day, 9),
                clockOut: DateTime(d.year, d.month, d.day, 18),
                type: AttendanceType.web,
              ),
            );
          }
        }
      }

      final summary = PayrollCalculator.calculateAnnualLeaveSummary(
        joinDate: joinDate,
        endDate: null,
        allAttendances: attendances,
        scheduledWorkDays: scheduledDays,
        isFiveOrMore: true,
        settlementPoint: DateTime(2023, 12, 1),
        usedAnnualLeave: 0,
        weeklyHoursPure: 40,
        hourlyRate: 10000,
      );

      // 11개월 만근 시 11개 발생
      expect(summary.totalGenerated, 11.0);
      expect(
        summary.calculationBasis.any((s) => s.contains('2023-11-01 ~ 2023-11-30: 만근 (+1개)')),
        isTrue,
      );
    });

    test('1년 시점 80% 이상 출근 시 15개 추가 부여 확인 (총 11+15=26개)', () {
      final attendances = <Attendance>[];
      // 1년치 모든 평일 출근
      for (int d = 0; d < 365; d++) {
        final date = joinDate.add(Duration(days: d));
        if (date.weekday >= 1 && date.weekday <= 5) {
          attendances.add(
            Attendance(
              id: 'att_${date.millisecondsSinceEpoch}',
              staffId: 'worker1',
              storeId: 'store1',
              clockIn: DateTime(date.year, date.month, date.day, 9),
              clockOut: DateTime(date.year, date.month, date.day, 18),
              type: AttendanceType.web,
            ),
          );
        }
      }

      final summary = PayrollCalculator.calculateAnnualLeaveSummary(
        joinDate: joinDate,
        endDate: null,
        allAttendances: attendances,
        scheduledWorkDays: scheduledDays,
        isFiveOrMore: true,
        settlementPoint: DateTime(2024, 1, 2),
        usedAnnualLeave: 0,
        weeklyHoursPure: 40,
        hourlyRate: 10000,
      );

      // 11 (1년 미만) + 15 (1년차 기념일) = 26
      expect(summary.totalGenerated, 26.0);
      expect(
        summary.calculationBasis.any((s) => s.contains('출근율 100.0%')),
        isTrue,
      );
    });

    test('관리자 수동 조정값 반영 확인', () {
      final summary = PayrollCalculator.calculateAnnualLeaveSummary(
        joinDate: joinDate,
        endDate: null,
        allAttendances: [],
        scheduledWorkDays: scheduledDays,
        isFiveOrMore: true,
        settlementPoint: DateTime(2024, 1, 2),
        usedAnnualLeave: 0,
        weeklyHoursPure: 40,
        hourlyRate: 10000,
        manualAdjustment: 3.5,
      );

      expect(summary.totalGenerated, 3.5);
      expect(
        summary.calculationBasis.any((s) => s.contains('관리자 수동 조정: +3.5개')),
        isTrue,
      );
    });

    test('퇴사 시 잔여 연차 수당 환산 검증 (1원 오차 없음)', () {
      // 잔여 연차 1개, 일일소정근로 8시간, 시급 10,000원 -> 80,000원
      final summary = PayrollCalculator.calculateAnnualLeaveSummary(
        joinDate: joinDate,
        endDate: DateTime(2023, 6, 1),
        allAttendances: [],
        scheduledWorkDays: scheduledDays,
        isFiveOrMore: true,
        settlementPoint: DateTime(2023, 6, 1),
        usedAnnualLeave: 0,
        weeklyHoursPure: 40, // 40/5 = 8시간
        hourlyRate: 10000,
        manualAdjustment: 1.0,
      );

      expect(summary.annualLeaveAllowancePay, 80000.0);
    });
  });
}
