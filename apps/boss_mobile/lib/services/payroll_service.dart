import '../models/worker.dart';
import 'package:shared_logic/shared_logic.dart';

class PayrollBreakdown {
  final double basePay;
  final double paidBreakAllowance;
  final double otherAllowance;
  final double premiumAllowanceForFivePlus;
  final double premiumHoursForFivePlus;
  final double holidayPay;
  final double totalPay;
  final double pureLaborHours;
  final double stayHours;
  final bool needsBreakSeparationGuide;

  const PayrollBreakdown({
    required this.basePay,
    required this.paidBreakAllowance,
    required this.otherAllowance,
    required this.premiumAllowanceForFivePlus,
    required this.premiumHoursForFivePlus,
    required this.holidayPay,
    required this.totalPay,
    required this.pureLaborHours,
    required this.stayHours,
    required this.needsBreakSeparationGuide,
  });
}

class PayrollService {
  const PayrollService();

  PayrollBreakdown calculateSalary({
    required Worker worker,
    required List<Attendance> attendances,
    required double effectiveHourlyWage,
    required bool isFiveOrMore,
  }) {
    final finished = attendances.where((a) {
      if (a.clockOut == null) return false;
      final s = a.attendanceStatus.trim().toLowerCase();
      return s != 'pending_approval' &&
          s != 'unplanned' &&
          s != 'pending_overtime';
    }).toList();
    int totalStayMinutes = 0;
    int totalPureMinutes = 0;
    int totalPaidBreakMinutes = 0;
    int totalPremiumTargetMinutes = 0;

    final breakPerShift = worker.breakMinutes.toInt();
    for (final a in finished) {
      final effectiveOut = payrollSettlementClockOut(
        actualClockOut: a.clockOut!,
        scheduledShiftEndIso: a.scheduledShiftEndIso,
        overtimeApproved: a.overtimeApproved,
      );
      final stay = effectiveOut.difference(a.clockIn).inMinutes;
      if (stay <= 0) continue;
      totalStayMinutes += stay;
      final appliedBreak = breakPerShift.clamp(0, stay);
      final pure = stay - appliedBreak;
      totalPureMinutes += pure;
      if (worker.isPaidBreak) {
        totalPaidBreakMinutes += appliedBreak;
      }
      if (isFiveOrMore) {
        totalPremiumTargetMinutes += _premiumTargetMinutesForShift(
          clockIn: a.clockIn,
          clockOut: effectiveOut,
          stayMinutes: stay,
          pureMinutes: pure,
        );
      }
    }

    final pureHours = totalPureMinutes / 60.0;
    final stayHours = totalStayMinutes / 60.0;
    final basePay = pureHours * effectiveHourlyWage;
    final paidBreakAllowance = (totalPaidBreakMinutes / 60.0) * effectiveHourlyWage;
    final otherAllowance =
        worker.allowances.fold<double>(0.0, (sum, a) => sum + a.amount);
    final premiumHoursForFivePlus = totalPremiumTargetMinutes / 60.0;
    final premiumAllowanceForFivePlus =
        isFiveOrMore ? premiumHoursForFivePlus * effectiveHourlyWage * 0.5 : 0.0;
    final holidayPay = worker.weeklyHolidayPay
        ? ((worker.weeklyHours / 40.0) * 8.0 * worker.hourlyWage)
        : 0.0;
    final totalPay = basePay +
        paidBreakAllowance +
        otherAllowance +
        premiumAllowanceForFivePlus +
        holidayPay;

    final needsGuide = (worker.weeklyHours < 15) &&
        (worker.totalStayMinutes / 60.0 >= 15);

    return PayrollBreakdown(
      basePay: basePay,
      paidBreakAllowance: paidBreakAllowance,
      otherAllowance: otherAllowance,
      premiumAllowanceForFivePlus: premiumAllowanceForFivePlus,
      premiumHoursForFivePlus: premiumHoursForFivePlus,
      holidayPay: holidayPay,
      totalPay: totalPay,
      pureLaborHours: pureHours,
      stayHours: stayHours,
      needsBreakSeparationGuide: needsGuide,
    );
  }

  int _premiumTargetMinutesForShift({
    required DateTime clockIn,
    required DateTime clockOut,
    required int stayMinutes,
    required int pureMinutes,
  }) {
    if (stayMinutes <= 0 || pureMinutes <= 0) return 0;

    final overtimePure = (pureMinutes - 480).clamp(0, pureMinutes);
    final nightStay = _overlapNightMinutes(clockIn, clockOut);
    final nightPure = ((nightStay * pureMinutes) / stayMinutes).round();
    final isHoliday = clockIn.weekday == DateTime.saturday ||
        clockIn.weekday == DateTime.sunday;
    final holidayPure = isHoliday ? pureMinutes : 0;

    return overtimePure + nightPure + holidayPure;
  }

  int _overlapNightMinutes(DateTime start, DateTime end) {
    int overlap = 0;
    DateTime cursor = DateTime(start.year, start.month, start.day);
    final lastDay = DateTime(end.year, end.month, end.day);

    while (!cursor.isAfter(lastDay)) {
      final nightStart = DateTime(cursor.year, cursor.month, cursor.day, 22);
      final nightEnd = DateTime(cursor.year, cursor.month, cursor.day + 1, 6);
      final from = start.isAfter(nightStart) ? start : nightStart;
      final to = end.isBefore(nightEnd) ? end : nightEnd;
      if (to.isAfter(from)) {
        overlap += to.difference(from).inMinutes;
      }
      cursor = DateTime(cursor.year, cursor.month, cursor.day + 1);
    }
    return overlap;
  }
}

