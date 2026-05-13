import re

with open('apps/boss_mobile/lib/screens/alba/alba_main_screen.dart', 'r') as f:
    content = f.read()

# Replace earlyUpdated
early_old = """        final earlyUpdated = Attendance(
          id: open.id,
          staffId: open.staffId,
          storeId: open.storeId,
          clockIn: open.clockIn,
          clockOut: now,
          originalClockIn: open.originalClockIn ?? open.clockIn,
          originalClockOut: now,
          breakStart: open.breakStart,
          breakEnd: open.breakEnd,
          inWifiBssid: open.inWifiBssid,
          outWifiBssid: open.outWifiBssid,
          isAutoApproved: open.isAutoApproved,
          exceptionReason: reason,
          type: open.type,
          isAttendanceEquivalent: open.isAttendanceEquivalent,
          attendanceStatus: 'early_leave_pending',
          scheduledShiftStartIso: open.scheduledShiftStartIso,
          scheduledShiftEndIso: open.scheduledShiftEndIso,
          overtimeApproved: false,
          overtimeReason: open.overtimeReason,
        );"""
early_new = """        final earlyUpdated = open.copyWith(
          clockOut: now,
          originalClockOut: now,
          outWifiBssid: open.outWifiBssid ?? _currentWifiBssid,
          attendanceStatus: 'early_leave_pending',
          exceptionReason: reason,
          scheduledShiftEndIso: open.scheduledShiftEndIso ?? schedEnd?.toIso8601String(),
        );"""

# Replace overtimeUpdated
overtime_old = """          final overtimeUpdated = Attendance(
            id: open.id,
            staffId: open.staffId,
            storeId: open.storeId,
            clockIn: open.clockIn,
            clockOut: now,
            originalClockIn: open.originalClockIn ?? open.clockIn,
            originalClockOut: now,
            breakStart: open.breakStart,
            breakEnd: open.breakEnd,
            inWifiBssid: open.inWifiBssid,
            outWifiBssid: open.outWifiBssid,
            isAutoApproved: open.isAutoApproved,
            exceptionReason: open.exceptionReason,
            type: open.type,
            isAttendanceEquivalent: open.isAttendanceEquivalent,
            attendanceStatus: 'pending_overtime',
            scheduledShiftStartIso: open.scheduledShiftStartIso,
            scheduledShiftEndIso: open.scheduledShiftEndIso,
            overtimeApproved: false,
            overtimeReason: reason,
          );"""
overtime_new = """          final overtimeUpdated = open.copyWith(
            clockOut: now,
            originalClockOut: now,
            outWifiBssid: open.outWifiBssid ?? _currentWifiBssid,
            attendanceStatus: 'pending_overtime',
            scheduledShiftEndIso: open.scheduledShiftEndIso ?? schedEnd?.toIso8601String(),
            overtimeReason: reason,
          );"""

# Replace updated 1
updated1_old = """          final updated = Attendance(
            id: open.id,
            staffId: open.staffId,
            storeId: open.storeId,
            clockIn: open.clockIn,
            clockOut: now,
            originalClockIn: open.originalClockIn ?? open.clockIn,
            originalClockOut: now,
            breakStart: open.breakStart,
            breakEnd: open.breakEnd,
            inWifiBssid: open.inWifiBssid,
            outWifiBssid: open.outWifiBssid,
            isAutoApproved: open.isAutoApproved,
            exceptionReason: open.exceptionReason,
            type: open.type,
            isAttendanceEquivalent: open.isAttendanceEquivalent,
            attendanceStatus: open.attendanceStatus,
            scheduledShiftStartIso: open.scheduledShiftStartIso,
            scheduledShiftEndIso: open.scheduledShiftEndIso,
            overtimeApproved: false,
            voluntaryWaiverNote: '사용자가 자발적으로 연장 수당 미신청을 선택함 (개인 사유)',
            voluntaryWaiverLogAt: now,
          );"""
updated1_new = """          final updated = open.copyWith(
            clockOut: now,
            originalClockOut: now,
            outWifiBssid: open.outWifiBssid ?? _currentWifiBssid,
            scheduledShiftEndIso: open.scheduledShiftEndIso ?? schedEnd?.toIso8601String(),
            voluntaryWaiverNote: '사용자가 자발적으로 연장 수당 미신청을 선택함 (개인 사유)',
            voluntaryWaiverLogAt: now,
          );"""

# Replace updated 2
updated2_old = """      final updated = Attendance(
        id: open.id,
        staffId: open.staffId,
        storeId: open.storeId,
        clockIn: open.clockIn,
        clockOut: now,
        originalClockIn: open.originalClockIn ?? open.clockIn,
        originalClockOut: now,
        breakStart: open.breakStart,
        breakEnd: open.breakEnd,
        inWifiBssid: open.inWifiBssid,
        outWifiBssid: open.outWifiBssid,
        isAutoApproved: open.isAutoApproved,
        exceptionReason: open.exceptionReason,
        type: open.type,
        isAttendanceEquivalent: open.isAttendanceEquivalent,
        attendanceStatus: open.attendanceStatus,
        scheduledShiftStartIso: open.scheduledShiftStartIso,
        scheduledShiftEndIso: open.scheduledShiftEndIso,
        overtimeApproved: open.overtimeApproved,
        overtimeReason: open.overtimeReason,
      );"""
updated2_new = """      final updated = open.copyWith(
        clockOut: now,
        originalClockOut: now,
        outWifiBssid: open.outWifiBssid ?? _currentWifiBssid,
        scheduledShiftEndIso: open.scheduledShiftEndIso ?? schedEnd?.toIso8601String(),
      );"""

content = content.replace(early_old, early_new)
content = content.replace(overtime_old, overtime_new)
content = content.replace(updated1_old, updated1_new)
content = content.replace(updated2_old, updated2_new)

with open('apps/boss_mobile/lib/screens/alba/alba_main_screen.dart', 'w') as f:
    f.write(content)

