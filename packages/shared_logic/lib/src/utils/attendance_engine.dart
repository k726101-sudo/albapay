import '../models/store_model.dart';
import '../models/shift_model.dart';

class AttendanceEngine {
  /// Processes a clock-in event and returns the (potentially) corrected time and approval status.
  static AttendanceResult processClockIn({
    required DateTime actualTime,
    required Shift? scheduledShift,
    required Store store,
  }) {
    if (scheduledShift == null) {
      // No scheduled shift: marked for review by default unless owner allows free work
      return AttendanceResult(
        correctedTime: actualTime,
        isAutoApproved: false,
        reason: '예정된 근무 스케줄이 없습니다.',
      );
    }

    final diff = actualTime.difference(scheduledShift.startTime).inMinutes.abs();
    
    if (diff <= store.attendanceGracePeriodMinutes) {
      // Within grace period: normalize to scheduled start time
      return AttendanceResult(
        correctedTime: scheduledShift.startTime,
        isAutoApproved: true,
        reason: '정상 (자동 보정 완료)',
      );
    } else {
      // Outside grace period
      final isEarly = actualTime.isBefore(scheduledShift.startTime);
      return AttendanceResult(
        correctedTime: actualTime,
        isAutoApproved: false,
        reason: isEarly ? '조기 출근 (승인 필요)' : '지각 (승인 필요)',
      );
    }
  }

  /// Processes a clock-out event.
  static AttendanceResult processClockOut({
    required DateTime actualTime,
    required Shift? scheduledShift,
    required Store store,
  }) {
    if (scheduledShift == null) {
      return AttendanceResult(
        correctedTime: actualTime,
        isAutoApproved: false,
        reason: '예정된 근무 스케줄이 없습니다.',
      );
    }

    final diff = actualTime.difference(scheduledShift.endTime).inMinutes.abs();

    if (diff <= store.attendanceGracePeriodMinutes) {
      // Within grace period: normalize to scheduled end time
      return AttendanceResult(
        correctedTime: scheduledShift.endTime,
        isAutoApproved: true,
        reason: '정상 (자동 보정 완료)',
      );
    } else {
      final isLate = actualTime.isAfter(scheduledShift.endTime);
      return AttendanceResult(
        correctedTime: actualTime,
        isAutoApproved: false,
        reason: isLate ? '연장 근무 (승인 필요)' : '조기 퇴근 (승인 필요)',
      );
    }
  }
}

class AttendanceResult {
  final DateTime correctedTime;
  final bool isAutoApproved;
  final String reason;

  AttendanceResult({
    required this.correctedTime,
    required this.isAutoApproved,
    required this.reason,
  });
}
