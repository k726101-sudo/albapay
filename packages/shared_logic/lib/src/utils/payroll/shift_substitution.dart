/// 대근/교대 처리 엔진
///
/// [payroll_calculator.dart]에서 분리된 교대근무(Shift Swap) 및 대체근무(Substitution) 로직입니다.
library;

import '../../models/attendance_model.dart';
import '../../models/shift_model.dart';
import '../roster_attendance.dart';
import 'payroll_models.dart';
import '../payroll_calculator.dart';

class ShiftSubstitutionCalculator {
  const ShiftSubstitutionCalculator();

  static ShiftSwapResult processShiftSwap({
    required Shift firstAssignedShift,
    required Shift secondAssignedShift,
    required List<Attendance> attendances,
  }) {
    final firstSwapped = _copyShift(
      firstAssignedShift,
      staffId: secondAssignedShift.staffId,
    );
    final secondSwapped = _copyShift(
      secondAssignedShift,
      staffId: firstAssignedShift.staffId,
    );

    final payrollOwnerByShiftId = <String, String>{};
    payrollOwnerByShiftId[firstAssignedShift.id] =
        _actualRecorderForShift(firstAssignedShift, attendances) ??
        firstSwapped.staffId;
    payrollOwnerByShiftId[secondAssignedShift.id] =
        _actualRecorderForShift(secondAssignedShift, attendances) ??
        secondSwapped.staffId;

    return ShiftSwapResult(
      firstSwapped: firstSwapped,
      secondSwapped: secondSwapped,
      payrollOwnerByShiftId: payrollOwnerByShiftId,
    );
  }

  static Shift _copyShift(Shift original, {String? staffId}) {
    return Shift(
      id: original.id,
      staffId: staffId ?? original.staffId,
      storeId: original.storeId,
      startTime: original.startTime,
      endTime: original.endTime,
    );
  }

  static SubstitutionProcessResult processSubstitution({
    required Shift substitutionShift,
    required List<Attendance> substituteWeeklyAttendances,
    required bool isFiveOrMoreStore,
    int defaultBreakMinutesPerShift = 0,
    void Function(String message)? notifyOwner,
  }) {
    final allAttendances = [...substituteWeeklyAttendances];
    final alreadyCovered = substituteWeeklyAttendances.any(
      (a) =>
          a.clockIn.isAtSameMomentAs(substitutionShift.startTime) &&
          a.clockOut?.isAtSameMomentAs(substitutionShift.endTime) == true,
    );
    if (!alreadyCovered) {
      allAttendances.add(
        Attendance(
          id: 'virtual_sub_${substitutionShift.id}',
          staffId: substitutionShift.staffId,
          storeId: substitutionShift.storeId,
          clockIn: substitutionShift.startTime,
          clockOut: substitutionShift.endTime,
          type: AttendanceType.web,
        ),
      );
    }

    double totalPureHours = 0;
    for (final att in allAttendances) {
      if (att.clockOut == null) continue;
      final effectiveOut = payrollSettlementClockOut(
        actualClockOut: att.clockOut!,
        scheduledShiftEndIso: att.scheduledShiftEndIso,
        overtimeApproved: att.overtimeApproved || att.isEditedByBoss,
      );
      final stayMinutes = effectiveOut.difference(att.clockIn).inMinutes;
      if (stayMinutes <= 0) continue;
      final breakMinutes = PayrollCalculator.calculateAppliedBreak(
        att: att,
        effectiveIn: att.clockIn,
        effectiveOut: effectiveOut,
        fallbackMinutes: defaultBreakMinutesPerShift,
        breakStartTimeStr: '',
        breakEndTimeStr: '',
      ).clamp(0, stayMinutes);
      totalPureHours += (stayMinutes - breakMinutes) / 60.0;
    }

    final weeklyEligible = totalPureHours >= 15.0;
    final alerts = <String>[];
    if (weeklyEligible) {
      alerts.add('대체근무 반영 후 주 15시간 이상으로 주휴수당 검토 대상입니다.');
    }
    if (isFiveOrMoreStore) {
      alerts.add('5인 이상 사업장 기준으로 연장/야간/휴일 가산수당 적용 여부를 확인하세요.');
    }
    for (final msg in alerts) {
      notifyOwner?.call(msg);
    }

    return SubstitutionProcessResult(
      updatedActualHours: totalPureHours,
      isWeeklyHolidayEligible: weeklyEligible,
      isFiveOrMore: isFiveOrMoreStore,
      riskAlerts: alerts,
    );
  }

  static FinalPayrollResult calculateFinalPayroll({
    required double totalPureLaborHours,
    required double totalPaidBreakHours,
    required double overtimeHours,
    required double hourlyRate,
    required bool isFiveOrMore,
    required bool isWeeklyHolidayEligible,
    required double Function() calculateHolidayPay,
  }) {
    final basePay = totalPureLaborHours * hourlyRate;
    final breakPay = totalPaidBreakHours * hourlyRate;
    final extraPay = isFiveOrMore ? (overtimeHours * hourlyRate * 0.5) : 0.0;
    final weeklyHolidayPay = isWeeklyHolidayEligible
        ? calculateHolidayPay()
        : 0.0;
    final totalPay = basePay + breakPay + extraPay + weeklyHolidayPay;
    return FinalPayrollResult(
      basePay: basePay,
      breakPay: breakPay,
      extraPay: extraPay,
      weeklyHolidayPay: weeklyHolidayPay,
      totalPay: totalPay,
    );
  }

  static DateTime _parseTimeOnDate(DateTime date, String timeStr) {
    try {
      final parts = timeStr.split(':');
      if (parts.length == 2) {
        final h = int.parse(parts[0]);
        final m = int.parse(parts[1]);
        return DateTime(date.year, date.month, date.day, h, m);
      }
    } catch (_) {}
    return date;
  }

  static String? _actualRecorderForShift(
    Shift shift,
    List<Attendance> attendances,
  ) {
    for (final att in attendances) {
      final out = att.clockOut;
      if (out == null) continue;
      final sameWindow =
          att.clockIn.isAtSameMomentAs(shift.startTime) &&
          out.isAtSameMomentAs(shift.endTime);
      if (sameWindow) return att.staffId;
    }
    return null;
  }
}
