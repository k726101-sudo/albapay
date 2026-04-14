import 'package:shared_logic/shared_logic.dart';

void main() {
  final workerData = PayrollWorkerData(
    weeklyHoursPure: 8*4,
    weeklyTotalStayMinutes: 8*4*60,
    breakMinutesPerShift: 60,
    isPaidBreak: true,
    joinDate: DateTime(2025, 4, 1),
    scheduledWorkDays: [1, 2, 3, 4],
    manualWeeklyHolidayApproval: true,
    allowanceAmounts: [],
    usedAnnualLeave: 0,
    isVirtual: true,
  );

  final inDt = DateTime(2026, 4, 1, 9, 0); // April 1 (Wed)
  final outDt = DateTime(2026, 4, 1, 18, 0);

  final att = Attendance(
      id: '1',
      staffId: '1',
      storeId: 'demo',
      clockIn: inDt,
      clockOut: outDt,
      originalClockIn: inDt,
      originalClockOut: outDt,
      type: AttendanceType.web,
      attendanceStatus: 'Normal',
      scheduledShiftStartIso: inDt.toIso8601String(),
      scheduledShiftEndIso: outDt.toIso8601String(),
      isAutoApproved: true,
  );

  final periodStart = DateTime(2026, 4, 1);
  final periodEnd = DateTime(2026, 4, 30, 23, 59, 59);

  final result = PayrollCalculator.calculate(
    workerData: workerData,
    shifts: [att],
    periodStart: periodStart,
    periodEnd: periodEnd,
    hourlyRate: 12000,
    isFiveOrMore: true,
    allHistoricalAttendances: [att],
  );

  print('Total Pay: ${result.totalPay}');
}
