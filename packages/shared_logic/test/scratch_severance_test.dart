import 'package:flutter_test/flutter_test.dart';
import 'package:shared_logic/shared_logic.dart';

void main() {
  test('Severance Edge Cases', () {
    print('=== 퇴직금 정산 엣지 케이스 테스트 ===\n');

    final case1 = SeveranceCalculator.calculateExitSettlement(
      workerName: '알바1 (정확히 1년)',
      startDate: '2023-01-01',
      exitDate: DateTime.parse('2023-12-31'),
      usedAnnualLeave: 0,
      annualLeaveManualAdjustment: 0,
      weeklyHours: 15,
      allAttendances: [],
      scheduledWorkDays: [1, 2, 3, 4, 5],
      hourlyRate: 10000,
      isFiveOrMore: true,
      isVirtual: true,
    );
    print('Case 1 [딱 365일]: ${case1.totalWorkingDays}일 근무, 대상 여부: ${case1.isSeveranceEligible}, 퇴직금: ${case1.severancePay.toInt()}원');

    final case2 = SeveranceCalculator.calculateExitSettlement(
      workerName: '알바2 (하루 부족)',
      startDate: '2023-01-01',
      exitDate: DateTime.parse('2023-12-30'),
      usedAnnualLeave: 0,
      annualLeaveManualAdjustment: 0,
      weeklyHours: 15,
      allAttendances: [],
      scheduledWorkDays: [1, 2, 3, 4, 5],
      hourlyRate: 10000,
      isFiveOrMore: true,
      isVirtual: true,
    );
    print('Case 2 [364일]: ${case2.totalWorkingDays}일 근무, 대상 여부: ${case2.isSeveranceEligible}, 퇴직금: ${case2.severancePay.toInt()}원');

    final case3 = SeveranceCalculator.calculateExitSettlement(
      workerName: '알바3 (주 14시간)',
      startDate: '2022-01-01',
      exitDate: DateTime.parse('2023-12-31'),
      usedAnnualLeave: 0,
      annualLeaveManualAdjustment: 0,
      weeklyHours: 14,
      allAttendances: [],
      scheduledWorkDays: [1, 2],
      hourlyRate: 10000,
      isFiveOrMore: true,
      isVirtual: true,
    );
    print('Case 3 [주 14시간 초단시간]: ${case3.totalWorkingDays}일 근무, 대상 여부: ${case3.isSeveranceEligible}, 퇴직금: ${case3.severancePay.toInt()}원');

    final case4 = SeveranceCalculator.calculateExitSettlement(
      workerName: '알바4 (통상임금 하한선 방어)',
      startDate: '2021-01-01',
      exitDate: DateTime.parse('2023-12-31'),
      usedAnnualLeave: 0,
      annualLeaveManualAdjustment: 0,
      weeklyHours: 40,
      allAttendances: [],
      scheduledWorkDays: [1, 2, 3, 4, 5],
      hourlyRate: 10000,
      isFiveOrMore: false,
      isVirtual: true,
    );
    print('Case 4 [통상임금 하한선]: ${case4.totalWorkingDays}일 근무, 대상 여부: ${case4.isSeveranceEligible}');
    print(' -> 산정된 평균 일급(통상임금 하한선 8만 반영됨): ${case4.averageDailyWage.toInt()}원');
    print(' -> 최종 퇴직금: ${case4.severancePay.toInt()}원');

    final case5 = SeveranceCalculator.calculateExitSettlement(
      workerName: '알바5 (연차수당 포함 평균임금 증가)',
      startDate: '2020-01-01',
      exitDate: DateTime.parse('2023-12-31'),
      usedAnnualLeave: 0,
      annualLeaveManualAdjustment: 0,
      weeklyHours: 40,
      allAttendances: [],
      scheduledWorkDays: [1, 2, 3, 4, 5],
      hourlyRate: 10000,
      isFiveOrMore: true,
      isVirtual: true,
    );
    print('Case 5 [장기근속+5인이상+연차수당가산]: ${case5.totalWorkingDays}일 근무, 대상 여부: ${case5.isSeveranceEligible}');
    print(' -> 산정된 평균 일급(연차수당 반영으로 통상임금보다 높음): ${case5.averageDailyWage.toInt()}원');
    print(' -> 최종 퇴직금: ${case5.severancePay.toInt()}원');
  });
}
