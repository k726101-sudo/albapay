import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_logic/shared_logic.dart';

Future<dynamic> showAttendanceEditDialog(BuildContext context, Attendance attendance) async {
  return await showDialog(
    context: context,
    builder: (ctx) => _AttendanceEditDialog(attendance: attendance),
  );
}

class _AttendanceEditDialog extends StatefulWidget {
  final Attendance attendance;
  const _AttendanceEditDialog({required this.attendance});

  @override
  State<_AttendanceEditDialog> createState() => _AttendanceEditDialogState();
}

class _AttendanceEditDialogState extends State<_AttendanceEditDialog> {
  late DateTime _in;
  late DateTime? _out;
  late String _status;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _in = widget.attendance.clockIn;
    _out = widget.attendance.clockOut;
    _status = widget.attendance.attendanceStatus;
  }

  Future<void> _pickTime(bool isIn) async {
    final initial = isIn ? _in : (_out ?? _in);
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: initial.subtract(const Duration(days: 365)),
      lastDate: initial.add(const Duration(days: 365)),
    );
    if (pickedDate == null) return;

    if (!mounted) return;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (pickedTime == null) return;

    setState(() {
      final newDt = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
      if (isIn) {
        _in = newDt;
      } else {
        _out = newDt;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('기록 수정 (사장님 권한)'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('출근 시각', style: TextStyle(fontSize: 12, color: Colors.grey)),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(_formatDt(_in)),
              trailing: const Icon(Icons.edit_calendar, size: 20),
              onTap: () => _pickTime(true),
            ),
            const SizedBox(height: 12),
            const Text('퇴근 시각', style: TextStyle(fontSize: 12, color: Colors.grey)),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(_out != null ? _formatDt(_out!) : '미등록'),
              trailing: const Icon(Icons.edit_calendar, size: 20),
              onTap: () => _pickTime(false),
            ),
            const SizedBox(height: 16),
            const Text('현재 상태', style: TextStyle(fontSize: 12, color: Colors.grey)),
            DropdownButton<String>(
              isExpanded: true,
              value: _status,
              items: const [
                DropdownMenuItem(value: 'Normal', child: Text('정상 (Normal)')),
                DropdownMenuItem(value: 'pending_approval', child: Text('승인 대기')),
                DropdownMenuItem(value: 'pending_overtime', child: Text('연장 신청 대기')),
                DropdownMenuItem(value: 'Unplanned', child: Text('스케줄 외')),
                DropdownMenuItem(value: 'early_clock_out', child: Text('조기 퇴근')),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _status = val);
              },
            ),
          ],
        ),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton(
          onPressed: _isSaving ? null : _confirmDelete,
          child: const Text('삭제', style: TextStyle(color: Colors.red)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving 
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) 
              : const Text('수정 완료'),
        ),
      ],
    );
  }

  String _formatDt(DateTime d) {
    return '${d.year}/${d.month}/${d.day} ${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}';
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      var finalOut = _out;
      // 야간 철야 등으로 수정 시 실수로 퇴근 날짜를 하루 뒤로 설정하지 않았을 경우 자동 보정
      if (finalOut != null && finalOut.isBefore(_in)) {
        finalOut = finalOut.add(const Duration(days: 1));
      }

      final updated = Attendance(
        id: widget.attendance.id,
        staffId: widget.attendance.staffId,
        storeId: widget.attendance.storeId,
        clockIn: _in,
        clockOut: finalOut,
        originalClockIn: widget.attendance.originalClockIn ?? widget.attendance.clockIn,
        originalClockOut: widget.attendance.originalClockOut ?? widget.attendance.clockOut,
        isAutoApproved: true,
        attendanceStatus: _status,
        scheduledShiftStartIso: widget.attendance.scheduledShiftStartIso,
        scheduledShiftEndIso: widget.attendance.scheduledShiftEndIso,
        overtimeApproved: true, // 사장님 직접 수정본은 무조건 스케줄 제한을 풀어 실시간(수정시간) 그대로 정산
        overtimeReason: widget.attendance.overtimeReason,
        voluntaryWaiverNote: widget.attendance.voluntaryWaiverNote,
        voluntaryWaiverLogAt: widget.attendance.voluntaryWaiverLogAt,
        type: widget.attendance.type,
        isEditedByBoss: true,
        editedByBossAt: AppClock.now(),
      );

      await DatabaseService().recordAttendance(updated);
      if (mounted) Navigator.pop(context, updated);
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('수정 중 오류 발생: $e')));
      }
    }
  }

  Future<void> _confirmDelete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text('기록 삭제'),
          ],
        ),
        content: Text(
          '${_formatDt(widget.attendance.clockIn)} 출근 기록을 삭제하시겠습니까?\n\n'
          '삭제된 기록은 복구할 수 없으며, 급여 정산에서도 제외됩니다.',
          style: const TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _isSaving = true);
    try {
      await FirebaseFirestore.instance
          .collection('attendance')
          .doc(widget.attendance.id)
          .delete();
      if (mounted) Navigator.pop(context, 'deleted');
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('삭제 중 오류 발생: $e')),
        );
      }
    }
  }
}
