/// 근무표(기본 계약 + 일별 override)와 출퇴근 시각 판정.
library;

/// `yyyy-MM-dd`
String rosterDateKey(DateTime d) {
  return '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// Firestore `stores/.../rosterDays/{workerId}_{date}` 문서 또는 null(override 없음).
/// [worker]는 `stores/.../workers/{id}` 스냅샷 data.
class EffectiveShift {
  const EffectiveShift({
    required this.hasShift,
    required this.checkInHm,
    required this.checkOutHm,
    required this.scheduledStart,
    required this.scheduledEnd,
  });

  final bool hasShift;
  final String checkInHm;
  final String checkOutHm;
  final DateTime scheduledStart;
  final DateTime scheduledEnd;
}

EffectiveShift? effectiveShiftForDate({
  required Map<String, dynamic> worker,
  required DateTime date,
  Map<String, dynamic>? rosterDayDoc,
}) {
  final baseDay = date.weekday == DateTime.sunday ? 0 : date.weekday;
  final workDays = (worker['workDays'] as List?)?.map((e) {
        if (e is num) return e.toInt();
        return int.tryParse(e.toString()) ?? -1;
      }).toList() ??
      const <int>[];
  final hasBase = workDays.contains(baseDay);

  String? norm(String? raw) {
    if (raw == null) return null;
    final s = raw.toString().trim();
    if (s.length >= 5) return s.substring(0, 5);
    return null;
  }

  String? oIn = norm(rosterDayDoc?['checkIn']?.toString());
  String? oOut = norm(rosterDayDoc?['checkOut']?.toString());

  if (oIn != null && oOut != null) {
    // 해당 날짜에 사장님이 지정한 근무(휴무일에 추가 등)
  } else if (hasBase) {
    oIn = norm(worker['checkInTime']?.toString()) ?? '09:00';
    oOut = norm(worker['checkOutTime']?.toString()) ?? '18:00';
  } else {
    return null;
  }

  final sp = oIn.split(':');
  final ep = oOut.split(':');
  if (sp.length != 2 || ep.length != 2) return null;
  final sh = int.tryParse(sp[0]) ?? 0;
  final sm = int.tryParse(sp[1]) ?? 0;
  final eh = int.tryParse(ep[0]) ?? 0;
  final em = int.tryParse(ep[1]) ?? 0;

  var start = DateTime(date.year, date.month, date.day, sh, sm);
  var end = DateTime(date.year, date.month, date.day, eh, em);
  if (!end.isAfter(start)) {
    end = end.add(const Duration(days: 1));
  }

  return EffectiveShift(
    hasShift: true,
    checkInHm: oIn,
    checkOutHm: oOut,
    scheduledStart: start,
    scheduledEnd: end,
  );
}

/// 출근 버튼 시: 근무표와 시각이 맞으면 즉시 승인, 아니면 사장 승인 대기.
bool shouldAutoApproveClockIn({
  required DateTime now,
  required EffectiveShift shift,
  int earlyAllowanceMinutes = 120,
}) {
  final earlyLimit = shift.scheduledStart.subtract(Duration(minutes: earlyAllowanceMinutes));
  return !now.isBefore(earlyLimit) && now.isBefore(shift.scheduledEnd);
}

/// 급여 시작 시각: 일찍 오면 근무표 정시, 지각이면 실제 출근 시각.
/// 유예 시간(`graceMinutes`) 내 지각 시 예정 시각으로 위로 올려서 급여 인정.
DateTime payrollEffectiveClockIn({
  required DateTime actualClockIn,
  required DateTime scheduledStart,
  bool earlyApproved = false,
  int graceMinutes = 0,
}) {
  if (earlyApproved && actualClockIn.isBefore(scheduledStart)) {
    return actualClockIn;
  }
  if (actualClockIn.isAfter(scheduledStart)) {
    final limit = scheduledStart.add(Duration(minutes: graceMinutes));
    if (!actualClockIn.isAfter(limit)) {
      return scheduledStart; // 지각이긴 하나 유예시간 내이므로 정시 인정
    }
  }
  return actualClockIn.isAfter(scheduledStart) ? actualClockIn : scheduledStart;
}

/// 지각 분 (0 이상). 정시 이전 출근이면 0.
/// '지각 표기는 무조건' 원칙에 따라 유예 시간(graceMinutes)을 적용하지 않고 1분이라도 늦으면 리턴합니다.
int lateMinutes({
  required DateTime actualClockIn,
  required DateTime scheduledStart,
}) {
  if (!actualClockIn.isAfter(scheduledStart)) return 0;
  return actualClockIn.difference(scheduledStart).inMinutes;
}

/// 조기 퇴근 여부: 실제 퇴근이 [scheduledEnd] - [graceMinutes] 보다 이전이면 true.
bool isEarlyClockOut({
  required DateTime actualClockOut,
  required DateTime scheduledEnd,
  int graceMinutes = 0,
}) {
  final limit = scheduledEnd.subtract(Duration(minutes: graceMinutes));
  return actualClockOut.isBefore(limit);
}

/// 급여 정산 퇴근 시각: 원래 분 단위로 칼같이 자르지만, 유예 시간(`graceMinutes`) 안에 조기퇴근/지연퇴근 했다면 정시(`scheduledShiftEndIso`)로 인정해줍니다.
DateTime payrollEffectiveClockOut({
  required DateTime actualClockOut,
  String? scheduledShiftEndIso,
  int graceMinutes = 0,
}) {
  if (scheduledShiftEndIso == null || scheduledShiftEndIso.isEmpty) {
    return actualClockOut;
  }
  final scheduled = DateTime.parse(scheduledShiftEndIso);
  
  if (graceMinutes > 0) {
    final earlyLimit = scheduled.subtract(Duration(minutes: graceMinutes));
    final lateLimit = scheduled.add(Duration(minutes: graceMinutes));
    if (!actualClockOut.isBefore(earlyLimit) && !actualClockOut.isAfter(lateLimit)) {
      return scheduled;
    }
  }
  
  return actualClockOut.isBefore(scheduled) ? actualClockOut : scheduled;
}

/// 급여 정산용 퇴근 시각: [overtimeApproved]이면 실제 퇴근, 아니면 [payrollEffectiveClockOut] 규칙.
DateTime payrollSettlementClockOut({
  required DateTime actualClockOut,
  String? scheduledShiftEndIso,
  bool overtimeApproved = false,
  int graceMinutes = 0,
}) {
  if (overtimeApproved) {
    return actualClockOut;
  }
  return payrollEffectiveClockOut(
    actualClockOut: actualClockOut,
    scheduledShiftEndIso: scheduledShiftEndIso,
    graceMinutes: graceMinutes,
  );
}
