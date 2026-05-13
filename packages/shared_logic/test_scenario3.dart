import 'dart:io';
import 'package:shared_logic/shared_logic.dart';

void main() {
  final joinDate = DateTime(2023, 1, 1);
  final scheduledDays = [1, 2, 3, 4, 5]; // Mon-Fri
  final workerData = PayrollWorkerData(
    weeklyHoursPure: 40,
    weeklyTotalStayMinutes: 40 * 60,
    breakMinutesPerShift: 0,
    isPaidBreak: false,
    joinDate: joinDate,
    scheduledWorkDays: scheduledDays,
    mealAllowance: 300000.0,
    weeklyHolidayDay: 0,
    manualWeeklyHolidayApproval: false,
  );

  final result = PayrollCalculator.calculate(
    workerData: workerData,
    shifts: List.generate(
      5,
      (i) => Attendance(
        id: '$i',
        staffId: 'w1',
        storeId: 's1',
        clockIn: DateTime(2024, 2, 5 + i, 9),
        clockOut: DateTime(2024, 2, 5 + i, 18), // 9 hours
        type: AttendanceType.web,
      ),
    ),
    periodStart: DateTime(2024, 2, 5),
    periodEnd: DateTime(2024, 2, 11),
    hourlyRate: 10000.0,
    isFiveOrMore: false,
  );

  print('basePay: \${result.basePay}');
  print('premiumPay: \${result.premiumPay}');
  print('weeklyHolidayPay: \${result.weeklyHolidayPay}');
  print('annualLeaveAllowancePay: \${result.annualLeaveAllowancePay}');
  print('otherAllowancePay: \${result.otherAllowancePay}');
  print('totalPay: \${result.totalPay}');
}
