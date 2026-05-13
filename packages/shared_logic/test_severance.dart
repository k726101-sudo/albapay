import 'package:shared_logic/shared_logic.dart';

void main() {
  final result = SeveranceCalculator.calculateExitSettlement(
    workerName: 'test',
    startDate: '2025-01-01', // random
    exitDate: DateTime(2026, 5, 28), // 1+ year
    usedAnnualLeave: 0,
    annualLeaveManualAdjustment: 0,
    weeklyHours: 40,
    allAttendances: [],
    scheduledWorkDays: [1,2,3,4,5],
    hourlyRate: 10320,
    isFiveOrMore: true,
    wageType: 'monthly',
    monthlyWage: 2156880,
    mealAllowance: 200000,
    fixedOvertimePay: 143123,
    otherAllowances: [],
  );
  
  print("Severance Pay: ${result.severancePay}");
  print("Average Daily Wage: ${result.averageDailyWage}");
  for (var line in result.calculationBasis) {
    print(line);
  }
}
