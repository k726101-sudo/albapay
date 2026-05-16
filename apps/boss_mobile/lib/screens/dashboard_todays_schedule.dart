import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:shared_logic/shared_logic.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/worker.dart';
import '../services/negative_attendance_service.dart';
import 'dashboard_exception_dialogs.dart';
import '../services/negative_attendance_service.dart';

class DashboardTodaysSchedule extends StatefulWidget {
  final String storeId;
  final List<Worker> workers;

  const DashboardTodaysSchedule({
    Key? key,
    required this.storeId,
    required this.workers,
  }) : super(key: key);

  @override
  State<DashboardTodaysSchedule> createState() =>
      _DashboardTodaysScheduleState();
}

class _DashboardTodaysScheduleState extends State<DashboardTodaysSchedule> {
  @override
  void initState() {
    super.initState();
    // 앱(대시보드) 접속 시 과거 빈 날짜에 대해 온디맨드 자동 생성 트리거
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.storeId.isNotEmpty) {
        final startDate = AppClock.now().subtract(
          const Duration(days: 30),
        ); // 최근 30일치 스캔
        NegativeAttendanceService().generateMissingAttendances(
          storeId: widget.storeId,
          activeWorkers: widget.workers,
          startDate: startDate,
          endDate: AppClock.now(),
        );
      }
    });
  }

  // 스케줄 시간 파싱 (main_screen.dart에서 추출된 _parseWorkerSchedule과 동일 로직)
  Map<int, ({String start, String end})> _parseWorkerSchedule(Worker w) {
    if (w.workScheduleJson.isEmpty) return {};
    try {
      final List<dynamic> list = jsonDecode(w.workScheduleJson);
      final map = <int, ({String start, String end})>{};
      for (final e in list) {
        if (e is Map<String, dynamic>) {
          final wd = e['weekday'] as int?;
          final s = e['start'] as String?;
          final end = e['end'] as String?;
          if (wd != null && s != null && end != null) {
            map[wd] = (start: s, end: end);
          }
        }
      }
      return map;
    } catch (_) {
      return {};
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.storeId.isEmpty) {
      return _buildCardWrapper(child: _buildEmptyState('가게가 등록되지 않았습니다.'));
    }

    return StreamBuilder<List<Attendance>>(
      stream: DatabaseService().streamAttendance(widget.storeId),
      builder: (context, snap) {
        final allAttendances = snap.data ?? const <Attendance>[];
        final now = AppClock.now();
        final todayYmd = rosterDateKey(now);
        final weekday = now.weekday == DateTime.sunday ? 0 : now.weekday;

        // 오늘 발생한 기록 필터링
        final todayLogs = allAttendances.where((a) {
          return rosterDateKey(a.clockIn) == todayYmd;
        }).toList();

        final rows = <Widget>[];

        for (final worker in widget.workers) {
          if (worker.workerType == 'dispatch') continue;

          bool isScheduled = false;
          String? checkInTime;
          String? checkOutTime;

          // RosterDay는 기본적으로 앱에서 worker.workScheduleJson을 파싱해서 fallback으로 사용 (기존과 동일)
          final parsedSchedule = _parseWorkerSchedule(worker);
          if (parsedSchedule.containsKey(weekday)) {
            isScheduled = true;
            checkInTime = parsedSchedule[weekday]!.start;
            checkOutTime = parsedSchedule[weekday]!.end;
          } else if (worker.workDays.contains(weekday)) {
            isScheduled = true;
            checkInTime = worker.checkInTime;
            checkOutTime = worker.checkOutTime;
          }

          final myLogs = todayLogs
              .where((a) => a.staffId == worker.id)
              .toList();

          // 오늘 스케줄이 있거나, 스케줄이 없는데 출근 기록(추가근무)이 있는 경우만 표시
          if (isScheduled || myLogs.isNotEmpty) {
            rows.add(
              _buildWorkerRow(
                worker: worker,
                isScheduled: isScheduled,
                checkInTime: checkInTime,
                checkOutTime: checkOutTime,
                attendances: myLogs,
              ),
            );
          }
        }

        if (rows.isEmpty) {
          return _buildCardWrapper(
            child: _buildEmptyState('오늘 예정된 근무자가 없습니다.'),
          );
        }

        return _buildCardWrapper(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...rows.asMap().entries.map((entry) {
                final isLast = entry.key == rows.length - 1;
                return Column(
                  children: [
                    entry.value,
                    if (!isLast)
                      const Divider(
                        height: 1,
                        thickness: 0.5,
                        indent: 14,
                        endIndent: 14,
                        color: Color(0xFFE0E0E0),
                      ),
                  ],
                );
              }).toList(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCardWrapper({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE0E0E0), width: 0.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                const Icon(
                  Icons.calendar_today_rounded,
                  size: 16,
                  color: Color(0xFF0032A0),
                ),
                const SizedBox(width: 8),
                const Text(
                  '오늘의 스케줄',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF333333),
                  ),
                ),
                const Spacer(),
                const Text(
                  '기록 클릭 시 예외 처리',
                  style: TextStyle(fontSize: 11, color: Color(0xFF888888)),
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 0.5, color: Color(0xFFE0E0E0)),
          child,
        ],
      ),
    );
  }

  Widget _buildEmptyState(String text) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: Text(text, style: const TextStyle(color: Color(0xFF888888))),
      ),
    );
  }

  Widget _buildWorkerRow({
    required Worker worker,
    required bool isScheduled,
    required String? checkInTime,
    required String? checkOutTime,
    required List<Attendance> attendances,
  }) {
    final initial = worker.name.isEmpty ? '-' : worker.name.substring(0, 1);

    // 예외 상태 분석 (Negative UX)
    String statusLabel = '정상 출근 간주';
    Color statusColor = const Color(0xFF286b3a); // Green
    Color statusBg = const Color(0xFFEAF3DE);

    if (attendances.isNotEmpty) {
      // 기록이 있을 경우 (사장님이 수정한 예외 기록이거나 QR로 찍은 기록)
      // 가장 최근 기록이나 예외가 적용된 기록을 확인
      final lastLog = attendances.last;
      if (lastLog.attendanceStatus == 'LOCKED') {
        statusLabel = '급여 정산 마감 (수정 불가)';
        statusColor = const Color(0xFF666666);
        statusBg = const Color(0xFFF0F0F0);
      } else if (lastLog.attendanceStatus == 'Absent') {
        statusLabel = '결근 처리됨';
        statusColor = const Color(0xFFE24B4A);
        statusBg = const Color(0xFFFCEBEB);
      } else if (lastLog.attendanceStatus.contains('late') ||
          lastLog.attendanceStatus.contains('early')) {
        statusLabel = '지각/조퇴 처리됨';
        statusColor = const Color(0xFFEF9F27);
        statusBg = const Color(0xFFFFF0DC);
      } else if (lastLog.attendanceStatus.contains('Unplanned') ||
          lastLog.attendanceStatus.contains('overtime')) {
        statusLabel = '연장/추가 근무';
        statusColor = const Color(0xFF8E44AD);
        statusBg = const Color(0xFFF4EBF9);
      } else if (lastLog.attendanceStatus == 'AUTO_PENDING' ||
          lastLog.isAutoGenerated == true) {
        statusLabel = '자동생성 (확인 대기)';
        statusColor = const Color(0xFF1a6ebd);
        statusBg = const Color(0xFFE5F0FA);
      } else if (lastLog.attendanceStatus == 'AUTO_CONFIRMED') {
        statusLabel = '정상 출퇴근 (확정 완료)';
        statusColor = const Color(0xFF286b3a);
        statusBg = const Color(0xFFEAF3DE);
      } else {
        statusLabel = '정상 (출/퇴근 완료)';
        statusColor = const Color(0xFF286b3a);
        statusBg = const Color(0xFFEAF3DE);
      }
    } else {
      if (!isScheduled) {
        statusLabel = '추가 근무 (미기록)';
        statusColor = const Color(0xFF888888);
        statusBg = const Color(0xFFF5F5F5);
      }
    }

    final scheduleText = isScheduled
        ? '$checkInTime - $checkOutTime'
        : '스케줄 없음';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: statusColor,
                child: Text(
                  initial,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      worker.name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF333333),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      scheduleText,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF666666),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Negative UX Action Buttons
          if (attendances.isNotEmpty && attendances.last.attendanceStatus == 'LOCKED')
            const SizedBox.shrink()
          else
            Row(
            children: [
              Expanded(
                child: _buildActionButton(
                  icon: Icons.cancel_presentation_rounded,
                  label: '결근',
                  color: const Color(0xFFE24B4A),
                  onTap: () => _handleException(
                    context,
                    worker,
                    'absent',
                    attendances,
                    checkInTime,
                    checkOutTime,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildActionButton(
                  icon: Icons.access_time_filled_rounded,
                  label: '지각/조퇴',
                  color: const Color(0xFFEF9F27),
                  onTap: () => _handleException(
                    context,
                    worker,
                    'late_early',
                    attendances,
                    checkInTime,
                    checkOutTime,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildActionButton(
                  icon: Icons.add_circle_rounded,
                  label: '연장/초과',
                  color: const Color(0xFF8E44AD),
                  onTap: () => _handleException(
                    context,
                    worker,
                    'overtime',
                    attendances,
                    checkInTime,
                    checkOutTime,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildActionButton(
                  icon: Icons.people_alt_rounded,
                  label: '대타',
                  color: const Color(0xFF1a6ebd),
                  onTap: () => _handleException(
                    context,
                    worker,
                    'substitute',
                    attendances,
                    checkInTime,
                    checkOutTime,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildActionButton(
                  icon: Icons.check_circle_rounded,
                  label: '확정',
                  color: const Color(0xFF286B3A),
                  onTap: () => _handleConfirm(
                    context,
                    worker,
                    attendances,
                    checkInTime,
                    checkOutTime,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3), width: 0.5),
        ),
        child: Column(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  DateTime? _parseTime(DateTime now, String? hhmm) {
    if (hhmm == null || hhmm.isEmpty) return null;
    final p = hhmm.split(':');
    if (p.length != 2) return null;
    final h = int.tryParse(p[0]);
    final m = int.tryParse(p[1]);
    if (h == null || m == null) return null;
    return DateTime(now.year, now.month, now.day, h, m);
  }

  Future<void> _handleException(
    BuildContext context,
    Worker worker,
    String type,
    List<Attendance> attendances,
    String? checkInTime,
    String? checkOutTime,
  ) async {
    final now = AppClock.now();
    Attendance target;

    if (attendances.isNotEmpty) {
      target = attendances.last;
    } else {
      final inTime = _parseTime(now, checkInTime ?? worker.checkInTime) ?? now;
      final outTime = _parseTime(now, checkOutTime ?? worker.checkOutTime);

      target = Attendance(
        id: FirebaseFirestore.instance.collection('attendance').doc().id,
        staffId: worker.id,
        storeId: widget.storeId,
        clockIn: inTime,
        clockOut: outTime,
        attendanceStatus: 'AUTO_PENDING',
        exceptionReason: '시스템 자동 생성 기록',
        isAutoGenerated: true,
        type: AttendanceType.mobile,
        isAttendanceEquivalent: false,
        isEditedByBoss: false,
        isAutoApproved: true,
      );
    }

    if (type == 'absent') {
      final reason = await DashboardExceptionDialogs.showReasonDialog(
        context,
        '결근 사유 입력',
      );
      if (reason == null) return;

      final updated = Attendance(
        id: target.id,
        staffId: target.staffId,
        storeId: target.storeId,
        clockIn: target.clockIn,
        clockOut: target.clockOut,
        originalClockIn: target.originalClockIn,
        originalClockOut: target.originalClockOut,
        breakStart: target.breakStart,
        breakEnd: target.breakEnd,
        inWifiBssid: target.inWifiBssid,
        outWifiBssid: target.outWifiBssid,
        isAutoApproved: target.isAutoApproved,
        exceptionReason: reason,
        type: target.type,
        isAttendanceEquivalent: target.isAttendanceEquivalent,
        attendanceStatus: 'Absent',
        scheduledShiftStartIso: target.scheduledShiftStartIso,
        scheduledShiftEndIso: target.scheduledShiftEndIso,
        overtimeApproved: target.overtimeApproved,
        overtimeReason: target.overtimeReason,
        voluntaryWaiverNote: target.voluntaryWaiverNote,
        voluntaryWaiverLogAt: target.voluntaryWaiverLogAt,
        isEditedByBoss: true,
        editedByBossAt: now,
      );
      await DatabaseService().recordAttendance(updated);
    } else if (type == 'late_early') {
      final result = await DashboardExceptionDialogs.showTimeEditDialog(
        context,
        '지각/조퇴 시간 수정',
        target.clockIn,
        target.clockOut,
      );
      if (result == null) return;

      bool overlap = attendances.any((a) {
        if (a.id == target.id) return false;
        if (a.clockOut == null) return false;
        return result.start.isBefore(a.clockOut!) && a.clockIn.isBefore(result.end);
      });
      if (overlap) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚠️ 이미 해당 시간에 다른 근무 기록이 존재합니다. (중복 근무 불가)'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final updated = Attendance(
        id: target.id,
        staffId: target.staffId,
        storeId: target.storeId,
        clockIn: result.start,
        clockOut: result.end,
        originalClockIn: target.originalClockIn,
        originalClockOut: target.originalClockOut,
        breakStart: target.breakStart,
        breakEnd: target.breakEnd,
        inWifiBssid: target.inWifiBssid,
        outWifiBssid: target.outWifiBssid,
        isAutoApproved: target.isAutoApproved,
        exceptionReason: target.exceptionReason,
        type: target.type,
        isAttendanceEquivalent: target.isAttendanceEquivalent,
        attendanceStatus: 'late_early',
        scheduledShiftStartIso: target.scheduledShiftStartIso,
        scheduledShiftEndIso: target.scheduledShiftEndIso,
        overtimeApproved: target.overtimeApproved,
        overtimeReason: target.overtimeReason,
        voluntaryWaiverNote: target.voluntaryWaiverNote,
        voluntaryWaiverLogAt: target.voluntaryWaiverLogAt,
        isEditedByBoss: true,
        editedByBossAt: now,
      );
      await DatabaseService().recordAttendance(updated);
    } else if (type == 'overtime') {
      final result = await DashboardExceptionDialogs.showTimeEditDialog(
        context,
        '연장 시간 수정',
        target.clockIn,
        target.clockOut,
        showReason: true,
      );
      if (result == null) return;

      bool overlap = attendances.any((a) {
        if (a.id == target.id) return false;
        if (a.clockOut == null) return false;
        return result.start.isBefore(a.clockOut!) && a.clockIn.isBefore(result.end);
      });
      if (overlap) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚠️ 이미 해당 시간에 다른 근무 기록이 존재합니다. (중복 근무 불가)'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final updated = Attendance(
        id: target.id,
        staffId: target.staffId,
        storeId: target.storeId,
        clockIn: result.start,
        clockOut: result.end,
        originalClockIn: target.originalClockIn,
        originalClockOut: target.originalClockOut,
        breakStart: target.breakStart,
        breakEnd: target.breakEnd,
        inWifiBssid: target.inWifiBssid,
        outWifiBssid: target.outWifiBssid,
        isAutoApproved: target.isAutoApproved,
        exceptionReason: target.exceptionReason,
        type: target.type,
        isAttendanceEquivalent: target.isAttendanceEquivalent,
        attendanceStatus: 'overtime',
        scheduledShiftStartIso: target.scheduledShiftStartIso,
        scheduledShiftEndIso: target.scheduledShiftEndIso,
        overtimeApproved: true,
        overtimeReason: result.reason,
        voluntaryWaiverNote: target.voluntaryWaiverNote,
        voluntaryWaiverLogAt: target.voluntaryWaiverLogAt,
        isEditedByBoss: true,
        editedByBossAt: now,
      );
      await DatabaseService().recordAttendance(updated);
    } else if (type == 'substitute') {
      final subTargetStart = target.clockIn;
      final subTargetEnd = target.clockOut ?? target.clockIn.add(const Duration(hours: 4));
      final now = AppClock.now();
      final weekday = now.weekday == DateTime.sunday ? 0 : now.weekday;

      final availableWorkers = widget.workers.where((w) {
        if (w.id == worker.id) return false;

        String? wStartStr;
        String? wEndStr;
        try {
          final parsedSchedule = _parseWorkerSchedule(w);
          if (parsedSchedule.containsKey(weekday)) {
            wStartStr = parsedSchedule[weekday]!.start;
            wEndStr = parsedSchedule[weekday]!.end;
          } else if (w.workDays.contains(weekday)) {
            wStartStr = w.checkInTime;
            wEndStr = w.checkOutTime;
          }
        } catch (_) {}

        if (wStartStr != null && wEndStr != null) {
          final wStart = _parseTime(now, wStartStr);
          var wEnd = _parseTime(now, wEndStr);
          if (wStart != null && wEnd != null) {
            if (wEnd.isBefore(wStart)) {
              wEnd = wEnd.add(const Duration(days: 1));
            }
            // 겹치는지 확인 (start1 < end2 && start2 < end1)
            final overlap = subTargetStart.isBefore(wEnd) && wStart.isBefore(subTargetEnd);
            if (overlap) return false; // 이미 같은 시간에 근무 일정이 있으면 제외
          }
        }
        return true;
      }).toList();
      final subId = await DashboardExceptionDialogs.showSubstituteDialog(
        context,
        availableWorkers,
      );
      if (subId == null) return;

      // 이미 생성된 동일한 대타 기록이 있는지 확인 (중복 생성 방지)
      final existingSubSnap = await FirebaseFirestore.instance
          .collection('attendance')
          .where('storeId', isEqualTo: widget.storeId)
          .where('exceptionReason', isEqualTo: '${worker.name} 대타 근무')
          .get();

      Attendance? existingSub;
      for (final doc in existingSubSnap.docs) {
        final a = Attendance.fromJson(doc.data(), id: doc.id);
        if (a.clockIn.isAtSameMomentAs(target.clockIn)) {
          existingSub = a;
          break;
        }
      }

      // 이미 같은 대타 직원을 선택한 경우 아무것도 하지 않음
      if (existingSub != null && existingSub.staffId == subId) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('이미 해당 직원이 대타로 지정되어 있습니다.')),
          );
        }
        return;
      }

      final updatedOrig = Attendance(
        id: target.id,
        staffId: target.staffId,
        storeId: target.storeId,
        clockIn: target.clockIn,
        clockOut: target.clockOut,
        originalClockIn: target.originalClockIn,
        originalClockOut: target.originalClockOut,
        breakStart: target.breakStart,
        breakEnd: target.breakEnd,
        inWifiBssid: target.inWifiBssid,
        outWifiBssid: target.outWifiBssid,
        isAutoApproved: target.isAutoApproved,
        exceptionReason: '대타 근무 발생',
        type: target.type,
        isAttendanceEquivalent: target.isAttendanceEquivalent,
        attendanceStatus: 'Absent',
        scheduledShiftStartIso: target.scheduledShiftStartIso,
        scheduledShiftEndIso: target.scheduledShiftEndIso,
        overtimeApproved: target.overtimeApproved,
        overtimeReason: target.overtimeReason,
        voluntaryWaiverNote: target.voluntaryWaiverNote,
        voluntaryWaiverLogAt: target.voluntaryWaiverLogAt,
        isEditedByBoss: true,
        editedByBossAt: now,
      );

      final subTarget = Attendance(
        id: existingSub?.id ?? FirebaseFirestore.instance.collection('attendance').doc().id,
        staffId: subId,
        storeId: widget.storeId,
        clockIn: target.clockIn,
        clockOut: target.clockOut,
        originalClockIn: null,
        originalClockOut: null,
        breakStart: null,
        breakEnd: null,
        inWifiBssid: null,
        outWifiBssid: null,
        isAutoApproved: true,
        exceptionReason: '${worker.name} 대타 근무',
        type: AttendanceType.mobile,
        isAttendanceEquivalent: false,
        attendanceStatus: 'Unplanned',
        scheduledShiftStartIso: null,
        scheduledShiftEndIso: null,
        overtimeApproved: false,
        overtimeReason: null,
        voluntaryWaiverNote: null,
        voluntaryWaiverLogAt: null,
        isEditedByBoss: true,
        editedByBossAt: now,
      );

      await Future.wait([
        DatabaseService().recordAttendance(updatedOrig),
        DatabaseService().recordAttendance(subTarget),
      ]);
    }
  }

  Future<void> _handleConfirm(
    BuildContext context,
    Worker worker,
    List<Attendance> attendances,
    String? checkInTime,
    String? checkOutTime,
  ) async {
    final now = AppClock.now();
    Attendance target;

    if (attendances.isNotEmpty) {
      target = attendances.last;
      if (target.clockOut == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('아직 퇴근 전이므로 확정할 수 없습니다.')),
        );
        return;
      }
    } else {
      final inTime = _parseTime(now, checkInTime ?? worker.checkInTime) ?? now;
      final outTime = _parseTime(now, checkOutTime ?? worker.checkOutTime);
      if (outTime == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('예정된 퇴근 시간이 없어 확정할 수 없습니다.')),
        );
        return;
      }

      target = Attendance(
        id: FirebaseFirestore.instance.collection('attendance').doc().id,
        staffId: worker.id,
        storeId: widget.storeId,
        clockIn: inTime,
        clockOut: outTime,
        attendanceStatus: 'AUTO_PENDING',
        exceptionReason: '시스템 자동 생성 기록',
        type: AttendanceType.mobile,
        isAttendanceEquivalent: false,
        isAutoApproved: true,
        overtimeApproved: false,
        isEditedByBoss: false,
        isSpecialOvertime: false,
      );
    }

    final updated = Attendance(
      id: target.id,
      staffId: target.staffId,
      storeId: target.storeId,
      clockIn: target.clockIn,
      clockOut: target.clockOut,
      originalClockIn: target.originalClockIn,
      originalClockOut: target.originalClockOut,
      breakStart: target.breakStart,
      breakEnd: target.breakEnd,
      inWifiBssid: target.inWifiBssid,
      outWifiBssid: target.outWifiBssid,
      isAutoApproved: true,
      exceptionReason: target.exceptionReason,
      type: target.type,
      isAttendanceEquivalent: target.isAttendanceEquivalent,
      attendanceStatus: 'AUTO_CONFIRMED',
      scheduledShiftStartIso: target.scheduledShiftStartIso,
      scheduledShiftEndIso: target.scheduledShiftEndIso,
      overtimeApproved: target.overtimeApproved,
      overtimeReason: target.overtimeReason,
      voluntaryWaiverNote: target.voluntaryWaiverNote,
      voluntaryWaiverLogAt: target.voluntaryWaiverLogAt,
      isEditedByBoss: true,
      editedByBossAt: now,
      specialOvertimeReason: target.specialOvertimeReason,
      isSpecialOvertime: target.isSpecialOvertime,
      specialOvertimeAuthorizedAt: target.specialOvertimeAuthorizedAt,
    );

    await DatabaseService().recordAttendance(updated);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('정상 출퇴근으로 확정되었습니다.')),
      );
    }
  }
}
