class PaySummary {
  final String staffId;
  final String storeId;
  final DateTime periodStart;
  final DateTime periodEnd;
  final int basePay;
  final int paidBreakAllowance;
  final int overtimePay;
  final int nightShiftPay;
  final int holidayPay;
  final int weeklyHolidayAllowance;
  final int totalPay;
  final double totalHours;
  final int annualLeaveAllowance;
  final bool isFullAttendanceForWeeklyHoliday;
  final bool isWeeklyHoursEligible;
  final double weeklyHours;
  final int weeklyHolidayExceptionCount;

  final int bonusPay;
  final int mealAllowancePay;
  final int transportAllowancePay;
  final int customAllowancePay;
  final int otherAllowancePay;

  /// 퇴사일(terminatedAt)이 해당 기간에 들어오는 경우에만 계산(단순 MVP)
  final bool severanceEligible;
  final int severancePay;

  PaySummary({
    required this.staffId,
    required this.storeId,
    required this.periodStart,
    required this.periodEnd,
    required this.basePay,
    this.paidBreakAllowance = 0,
    required this.overtimePay,
    required this.nightShiftPay,
    required this.holidayPay,
    required this.weeklyHolidayAllowance,
    required this.totalPay,
    required this.totalHours,
    this.annualLeaveAllowance = 0,
    this.isFullAttendanceForWeeklyHoliday = false,
    this.isWeeklyHoursEligible = false,
    this.weeklyHours = 0,
    this.weeklyHolidayExceptionCount = 0,
    this.bonusPay = 0,
    this.mealAllowancePay = 0,
    this.transportAllowancePay = 0,
    this.customAllowancePay = 0,
    this.otherAllowancePay = 0,
    this.severanceEligible = false,
    this.severancePay = 0,
  });

  Map<String, dynamic> toJson() => {
        'staffId': staffId,
        'storeId': storeId,
        'periodStart': periodStart.toIso8601String(),
        'periodEnd': periodEnd.toIso8601String(),
        'basePay': basePay,
        'paidBreakAllowance': paidBreakAllowance,
        'overtimePay': overtimePay,
        'nightShiftPay': nightShiftPay,
        'holidayPay': holidayPay,
        'weeklyHolidayAllowance': weeklyHolidayAllowance,
        'totalPay': totalPay,
        'totalHours': totalHours,
        'annualLeaveAllowance': annualLeaveAllowance,
        'isFullAttendanceForWeeklyHoliday': isFullAttendanceForWeeklyHoliday,
        'isWeeklyHoursEligible': isWeeklyHoursEligible,
        'weeklyHours': weeklyHours,
        'weeklyHolidayExceptionCount': weeklyHolidayExceptionCount,
        'bonusPay': bonusPay,
        'mealAllowancePay': mealAllowancePay,
        'transportAllowancePay': transportAllowancePay,
        'customAllowancePay': customAllowancePay,
        'otherAllowancePay': otherAllowancePay,
        'severanceEligible': severanceEligible,
        'severancePay': severancePay,
      };
}
