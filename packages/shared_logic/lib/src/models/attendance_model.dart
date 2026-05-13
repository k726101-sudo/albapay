import 'package:cloud_firestore/cloud_firestore.dart';

enum AttendanceType { mobile, web }

class Attendance {
  final String id;
  final String staffId;
  final String storeId;
  final DateTime clockIn;
  final DateTime? clockOut;
  final DateTime? originalClockIn; // 실제 찍힌 원본 시간
  final DateTime? originalClockOut; // 실제 찍힌 원본 시간
  final DateTime? breakStart;
  final DateTime? breakEnd;
  final String? inWifiBssid;
  final String? outWifiBssid;
  final bool isAutoApproved;
  final String? exceptionReason;
  final AttendanceType type;
  // 유급휴일/법정 간주일 등 "출근으로 간주"할 때 true
  final bool isAttendanceEquivalent;
  // Normal | Unplanned | UnplannedApproved | pending_approval | pending_overtime | early_clock_out | early_leave_pending
  final String attendanceStatus;

  /// 당일 근무표 기준 정시 출근(급여 시작 기준 참고용)
  final String? scheduledShiftStartIso;

  /// 당일 근무표 기준 정시 퇴근
  final String? scheduledShiftEndIso;

  /// 사장님 연장 승인 시 true → 급여 퇴근 시각은 실제 퇴근 그대로
  final bool overtimeApproved;

  /// 연장 근무 신청 사유 (pending_overtime 시)
  final String? overtimeReason;

  /// 자발적으로 정시 퇴근을 선택했을 때 기록될 증거 문구
  final String? voluntaryWaiverNote;

  /// 자발적 선택이 이루어진 정확한 시각
  final DateTime? voluntaryWaiverLogAt;

  /// 사장님이 직접 수정한 기록인지 여부
  final bool isEditedByBoss;

  /// 사장님이 마지막으로 수정한 일시
  final DateTime? editedByBossAt;

  /// 법정 한도 초과 시 사장님이 입력한 특별연장근로 사유
  final String? specialOvertimeReason;

  /// 52시간 초과 예외 승인 여부
  final bool isSpecialOvertime;

  /// 특별연장근로 승인 시각
  final DateTime? specialOvertimeAuthorizedAt;

  /// GPS 출퇴근 검증 결과 (null: 미적용, true: 반경 내, false: 반경 밖)
  final bool? gpsVerified;

  /// GPS 반경 밖 출근 시 사유
  final String? gpsOutOfRangeReason;

  Attendance({
    required this.id,
    required this.staffId,
    required this.storeId,
    required this.clockIn,
    this.clockOut,
    this.originalClockIn,
    this.originalClockOut,
    this.breakStart,
    this.breakEnd,
    this.inWifiBssid,
    this.outWifiBssid,
    this.isAutoApproved = false,
    this.exceptionReason,
    required this.type,
    this.isAttendanceEquivalent = false,
    this.attendanceStatus = 'Normal',
    this.scheduledShiftStartIso,
    this.scheduledShiftEndIso,
    this.overtimeApproved = false,
    this.overtimeReason,
    this.voluntaryWaiverNote,
    this.voluntaryWaiverLogAt,
    this.isEditedByBoss = false,
    this.editedByBossAt,
    this.specialOvertimeReason,
    this.isSpecialOvertime = false,
    this.specialOvertimeAuthorizedAt,
    this.gpsVerified,
    this.gpsOutOfRangeReason,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'staffId': staffId,
    'storeId': storeId,
    'clockIn': clockIn.toIso8601String(),
    'clockOut': clockOut?.toIso8601String(),
    'originalClockIn': originalClockIn?.toIso8601String(),
    'originalClockOut': originalClockOut?.toIso8601String(),
    'breakStart': breakStart?.toIso8601String(),
    'breakEnd': breakEnd?.toIso8601String(),
    'inWifiBssid': inWifiBssid,
    'outWifiBssid': outWifiBssid,
    'isAutoApproved': isAutoApproved,
    'exceptionReason': exceptionReason,
    'type': type.name,
    'isAttendanceEquivalent': isAttendanceEquivalent,
    'attendanceStatus': attendanceStatus,
    // ★ 보안 규칙에서 직원 update 시 변경 차단하는 필드들:
    //   null 값을 명시적으로 보내면 Firestore가 "필드 추가"로 인식 → permission-denied
    //   따라서 값이 있을 때만 포함 (set merge:true 에서 안전)
    if (scheduledShiftStartIso != null) 'scheduledShiftStartIso': scheduledShiftStartIso,
    if (scheduledShiftEndIso != null) 'scheduledShiftEndIso': scheduledShiftEndIso,
    'overtimeApproved': overtimeApproved,
    'overtimeReason': overtimeReason,
    'voluntaryWaiverNote': voluntaryWaiverNote,
    if (voluntaryWaiverLogAt != null) 'voluntaryWaiverLogAt': voluntaryWaiverLogAt!.toIso8601String(),
    // ★ 사장님 전용 필드: 직원 update 시 변경 차단 대상
    if (isEditedByBoss != null && isEditedByBoss!) 'isEditedByBoss': isEditedByBoss,
    if (editedByBossAt != null) 'editedByBossAt': editedByBossAt!.toIso8601String(),
    if (specialOvertimeReason != null) 'specialOvertimeReason': specialOvertimeReason,
    if (isSpecialOvertime != null && isSpecialOvertime!) 'isSpecialOvertime': isSpecialOvertime,
    if (specialOvertimeAuthorizedAt != null) 'specialOvertimeAuthorizedAt': specialOvertimeAuthorizedAt!.toIso8601String(),
    if (gpsVerified != null) 'gpsVerified': gpsVerified,
    if (gpsOutOfRangeReason != null) 'gpsOutOfRangeReason': gpsOutOfRangeReason,
  };

  factory Attendance.fromJson(Map<String, dynamic> json, {String? id}) =>
      Attendance(
        id: json['id'] ?? id ?? '',
        staffId: json['staffId'] ?? '',
        storeId: json['storeId'] ?? '',
        clockIn: _parseDate(json['clockIn']) ?? DateTime.now(),
        clockOut: _parseDate(json['clockOut']),
        originalClockIn: _parseDate(json['originalClockIn']),
        originalClockOut: _parseDate(json['originalClockOut']),
        breakStart: _parseDate(json['breakStart']),
        breakEnd: _parseDate(json['breakEnd']),
        inWifiBssid: json['inWifiBssid'],
        outWifiBssid: json['outWifiBssid'],
        isAutoApproved: json['isAutoApproved'] ?? false,
        exceptionReason: json['exceptionReason'],
        type: json['type'] != null
            ? AttendanceType.values.byName(json['type'])
            : AttendanceType.mobile,
        isAttendanceEquivalent: json['isAttendanceEquivalent'] ?? false,
        attendanceStatus: json['attendanceStatus']?.toString() ?? 'Normal',
        scheduledShiftStartIso: json['scheduledShiftStartIso']?.toString(),
        scheduledShiftEndIso: json['scheduledShiftEndIso']?.toString(),
        overtimeApproved: json['overtimeApproved'] == true,
        overtimeReason: json['overtimeReason']?.toString(),
        voluntaryWaiverNote: json['voluntaryWaiverNote']?.toString(),
        voluntaryWaiverLogAt: _parseDate(json['voluntaryWaiverLogAt']),
        isEditedByBoss: json['isEditedByBoss'] == true,
        editedByBossAt: _parseDate(json['editedByBossAt']),
        specialOvertimeReason: json['specialOvertimeReason']?.toString(),
        isSpecialOvertime: json['isSpecialOvertime'] == true,
        specialOvertimeAuthorizedAt: _parseDate(
          json['specialOvertimeAuthorizedAt'],
        ),
        gpsVerified: json['gpsVerified'] as bool?,
        gpsOutOfRangeReason: json['gpsOutOfRangeReason']?.toString(),
      );

  Attendance copyWith({
    String? id,
    String? staffId,
    String? storeId,
    DateTime? clockIn,
    DateTime? clockOut,
    DateTime? originalClockIn,
    DateTime? originalClockOut,
    DateTime? breakStart,
    DateTime? breakEnd,
    String? inWifiBssid,
    String? outWifiBssid,
    bool? isAutoApproved,
    String? exceptionReason,
    AttendanceType? type,
    bool? isAttendanceEquivalent,
    String? attendanceStatus,
    String? scheduledShiftStartIso,
    String? scheduledShiftEndIso,
    bool? overtimeApproved,
    String? overtimeReason,
    String? voluntaryWaiverNote,
    DateTime? voluntaryWaiverLogAt,
    bool? isEditedByBoss,
    DateTime? editedByBossAt,
    String? specialOvertimeReason,
    bool? isSpecialOvertime,
    DateTime? specialOvertimeAuthorizedAt,
    bool? gpsVerified,
    String? gpsOutOfRangeReason,
  }) {
    return Attendance(
      id: id ?? this.id,
      staffId: staffId ?? this.staffId,
      storeId: storeId ?? this.storeId,
      clockIn: clockIn ?? this.clockIn,
      clockOut: clockOut ?? this.clockOut,
      originalClockIn: originalClockIn ?? this.originalClockIn,
      originalClockOut: originalClockOut ?? this.originalClockOut,
      breakStart: breakStart ?? this.breakStart,
      breakEnd: breakEnd ?? this.breakEnd,
      inWifiBssid: inWifiBssid ?? this.inWifiBssid,
      outWifiBssid: outWifiBssid ?? this.outWifiBssid,
      isAutoApproved: isAutoApproved ?? this.isAutoApproved,
      exceptionReason: exceptionReason ?? this.exceptionReason,
      type: type ?? this.type,
      isAttendanceEquivalent:
          isAttendanceEquivalent ?? this.isAttendanceEquivalent,
      attendanceStatus: attendanceStatus ?? this.attendanceStatus,
      scheduledShiftStartIso:
          scheduledShiftStartIso ?? this.scheduledShiftStartIso,
      scheduledShiftEndIso: scheduledShiftEndIso ?? this.scheduledShiftEndIso,
      overtimeApproved: overtimeApproved ?? this.overtimeApproved,
      overtimeReason: overtimeReason ?? this.overtimeReason,
      voluntaryWaiverNote: voluntaryWaiverNote ?? this.voluntaryWaiverNote,
      voluntaryWaiverLogAt: voluntaryWaiverLogAt ?? this.voluntaryWaiverLogAt,
      isEditedByBoss: isEditedByBoss ?? this.isEditedByBoss,
      editedByBossAt: editedByBossAt ?? this.editedByBossAt,
      specialOvertimeReason:
          specialOvertimeReason ?? this.specialOvertimeReason,
      isSpecialOvertime: isSpecialOvertime ?? this.isSpecialOvertime,
      specialOvertimeAuthorizedAt:
          specialOvertimeAuthorizedAt ?? this.specialOvertimeAuthorizedAt,
      gpsVerified: gpsVerified ?? this.gpsVerified,
      gpsOutOfRangeReason: gpsOutOfRangeReason ?? this.gpsOutOfRangeReason,
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is String) return DateTime.tryParse(value);
    if (value is Timestamp) return value.toDate();
    try {
      dynamic ds = value;
      if (ds.seconds != null && ds.nanoseconds != null) {
        return DateTime.fromMicrosecondsSinceEpoch(
          (ds.seconds as int) * 1000000 + (ds.nanoseconds as int) ~/ 1000,
        );
      }
    } catch (_) {}
    return null;
  }

  int get workedMinutes {
    if (clockOut == null) return 0;
    final stay = clockOut!.difference(clockIn).inMinutes;
    if (stay <= 0) return 0;
    var breakMinutes = 0;
    if (breakStart != null && breakEnd != null) {
      final b = breakEnd!.difference(breakStart!).inMinutes;
      if (b > 0) breakMinutes = b;
    }
    return (stay - breakMinutes).clamp(0, stay);
  }

  int workedMinutesAt(DateTime now) {
    final effectiveEnd = clockOut ?? now;
    final stay = effectiveEnd.difference(clockIn).inMinutes;
    if (stay <= 0) return 0;
    var breakMinutes = 0;
    if (breakStart != null) {
      final bEnd = breakEnd ?? now;
      final b = bEnd.difference(breakStart!).inMinutes;
      if (b > 0) breakMinutes = b;
    }
    return (stay - breakMinutes).clamp(0, stay);
  }
}
