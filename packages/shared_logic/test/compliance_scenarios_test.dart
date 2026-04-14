import 'package:flutter_test/flutter_test.dart';
import 'package:shared_logic/shared_logic.dart';

void main() {
  group('7 Compliance Scenarios Detailed Validation', () {
    final joinDate = DateTime(2024, 1, 30); // scenario 1: Join Jan 30
    final scheduledDays = [1, 2, 3, 4, 5]; // Mon-Fri
    final hourlyRate = 10000.0;

    // 📅 [시나리오 1] 신입 사원 '연차 생성' 테스트
    test('Scenario 1: New Employee Monthly Accrual (Months 1-11)', () {
      final attendances = <Attendance>[];
      // Simulate perfect attendance for 5 months
      final settlementPoint = DateTime(2024, 7, 1);
      
      final summary = PayrollCalculator.calculateAnnualLeaveSummary(
        joinDate: joinDate,
        endDate: null,
        allAttendances: attendances, // Empty will be treated as perfect if it's virtual/auto-passed
        scheduledWorkDays: scheduledDays,
        isFiveOrMore: true,
        settlementPoint: settlementPoint,
        usedAnnualLeave: 0,
        weeklyHoursPure: 40,
        hourlyRate: hourlyRate,
        isVirtual: true,
      );

      // Jan 30 -> Feb 29 (1), Mar 30 (2), Apr 30 (3), May 30 (4), June 30 (5).
      // July 1st means 5 full months passed.
      expect(summary.totalGenerated, 5.0);
    });

    // 🎂 [시나리오 2] '1년 차의 대도약' 테스트
    test('Scenario 2: 1-Year Anniversary Lump Sum Update (+15)', () {
      final oneYearLater = DateTime(2025, 1, 31);
      final summary = PayrollCalculator.calculateAnnualLeaveSummary(
        joinDate: joinDate,
        endDate: null,
        allAttendances: [],
        scheduledWorkDays: scheduledDays,
        isFiveOrMore: true,
        settlementPoint: oneYearLater,
        usedAnnualLeave: 0,
        weeklyHoursPure: 40,
        hourlyRate: hourlyRate,
        isVirtual: true,
      );

      // 11 (max for <1yr) + 15 (at 1yr) = 26.0
      expect(summary.totalGenerated, 26.0);
      
      // Severance pay check (Scenario 2 sub-point)
      final exitSettlement = PayrollCalculator.calculateExitSettlement(
        workerName: 'Tester',
        startDate: '2024-01-30',
        usedAnnualLeave: 0,
        annualLeaveManualAdjustment: 0,
        weeklyHours: 40,
        allAttendances: [],
        scheduledWorkDays: scheduledDays,
        exitDate: oneYearLater,
        hourlyRate: hourlyRate,
        isFiveOrMore: true,
        isVirtual: true,
      );
      // Severance pay should be calculated for >365 days
      expect(exitSettlement.isSeveranceEligible, isTrue);
    });

    // 💰 [시나리오 3] '식대 비과세 & 보험료' 정밀 테스트
    test('Scenario 3: 200k Meal Non-taxable & 9.4% Insurance Deduction', () {
      final workerData = PayrollWorkerData(
        weeklyHoursPure: 40,
        weeklyTotalStayMinutes: 40 * 60,
        breakMinutesPerShift: 0,
        isPaidBreak: false,
        joinDate: joinDate,
        scheduledWorkDays: scheduledDays,
        mealAllowance: 300000.0, // Scenario: 300k input (should cap at 200k)
      );

      // Simulate 5 days * 9h = 45h
      final result = PayrollCalculator.calculate(
        workerData: workerData,
        shifts: List.generate(5, (i) => Attendance(
          id: '$i', staffId: 'w1', storeId: 's1',
          clockIn: DateTime(2024, 2, 5 + i, 9), clockOut: DateTime(2024, 2, 5 + i, 18),
          type: AttendanceType.web,
        )),
        periodStart: DateTime(2024, 2, 5),
        periodEnd: DateTime(2024, 2, 11),
        hourlyRate: 10000.0,
        isFiveOrMore: false,
      );

      // totalPay = 45h * 10k = 450,000 KRW
      expect(result.totalPay, 450000.0);
      expect(result.mealNonTaxable, 200000.0); // Capped at 200k
      expect(result.taxableWage, 250000.0); // 450k - 200k = 250k
      expect(result.insuranceDeduction, 250000.0 * 0.094); // 23,500 KRW
      expect(result.netPay, 450000.0 - 23500.0); // 426,500 KRW
    });

    // 📈 [시나리오 4] '가산 연차' 테스트 (입사 3년 차 이상)
    test('Scenario 4: Long-term Additional Leave (+1 day every 2 years)', () {
      final joinDateLong = DateTime(2021, 1, 30);
      final checkDate = DateTime(2024, 1, 31); // 3 full years passed
      
      final summary = PayrollCalculator.calculateAnnualLeaveSummary(
        joinDate: joinDateLong,
        endDate: null,
        allAttendances: [],
        scheduledWorkDays: scheduledDays,
        isFiveOrMore: true,
        settlementPoint: checkDate,
        usedAnnualLeave: 0,
        weeklyHoursPure: 40,
        hourlyRate: hourlyRate,
        isVirtual: true,
      );

      // Year 1: 15, Year 2: 15, Year 3: 16 (Additional days starts from 3rd year)
      // Cumulative: 11 (newbie) + 15 (yr1) + 15 (yr2) + 16 (yr3) = 57
      expect(summary.totalGenerated, 57.0);
    });

    // 📂 [시나리오 5] '데이터 소급 및 이월' 테스트
    test('Scenario 5: Manual Adjustment Integrity', () {
      final summary = PayrollCalculator.calculateAnnualLeaveSummary(
        joinDate: joinDate,
        endDate: null,
        allAttendances: [],
        scheduledWorkDays: scheduledDays,
        isFiveOrMore: true,
        settlementPoint: DateTime(2024, 3, 1),
        usedAnnualLeave: 0,
        weeklyHoursPure: 40,
        hourlyRate: hourlyRate,
        manualAdjustment: 5.5, // Manual entry of 5.5 starting balance
        isVirtual: true,
      );

      // Jan 30 -> Feb 29 (1) + 5.5 (manual) = 6.5
      expect(summary.totalGenerated, 6.5);
    });

    // 🚨 [시나리오 7] '중도 퇴사' 정산 테스트
    test('Scenario 7: Mid-month Resignation Pro-rata', () {
      final exitDate = DateTime(2024, 3, 1);
      final exitSettlement = PayrollCalculator.calculateExitSettlement(
        workerName: 'Leaver',
        startDate: '2024-01-30',
        usedAnnualLeave: 0,
        annualLeaveManualAdjustment: 0,
        weeklyHours: 40,
        allAttendances: [],
        scheduledWorkDays: scheduledDays,
        exitDate: exitDate,
        hourlyRate: hourlyRate,
        isFiveOrMore: true,
        isVirtual: true,
      );
      // Jan 30 -> Feb 29 (passed). Accrued = 1.0.
      expect(exitSettlement.remainingLeaveDays, 1.0);
      expect(exitSettlement.annualLeavePayout, 8.0 * hourlyRate); // 1 day * 8h * 10k
    });
  });
}
