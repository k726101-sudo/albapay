import 'dart:io';
import 'package:shared_logic/shared_logic.dart';

void main() {
  final joinDate = DateTime(2023, 1, 1);
  final scheduledDays = [1, 2, 3, 4, 5]; // Mon-Fri
  final attendances = <Attendance>[];
  for (int m = 0; m < 11; m++) {
    final mStart = DateTime(2023, 1 + m, 1);
    final mEnd = DateTime(2023, 1 + m + 1, 1).subtract(Duration(days: 1));
    for (var d = mStart; !d.isAfter(mEnd); d = d.add(Duration(days: 1))) {
      if (d.weekday >= 1 && d.weekday <= 5) {
        attendances.add(Attendance(id: '', staffId: '', storeId: '', clockIn: DateTime(d.year, d.month, d.day, 9), clockOut: DateTime(d.year, d.month, d.day, 18), type: AttendanceType.web));
      }
    }
  }
  final summary = AnnualLeaveCalculator.calculateAnnualLeaveSummary(joinDate: joinDate, endDate: null, allAttendances: attendances, scheduledWorkDays: scheduledDays, isFiveOrMore: true, settlementPoint: DateTime(2023, 12, 1), usedAnnualLeave: 0, weeklyHoursPure: 40, hourlyRate: 10000);
  print(summary.calculationBasis);
}
