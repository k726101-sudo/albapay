import 'package:flutter/material.dart';
import 'package:shared_logic/shared_logic.dart';
import '../models/worker.dart';

class DashboardExceptionDialogs {
  static Future<String?> showReasonDialog(
    BuildContext context,
    String title,
  ) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: '사유를 입력해주세요 (선택)',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('저장'),
          ),
        ],
      ),
    );
  }

  static Future<({DateTime start, DateTime end, String reason})?>
  showTimeEditDialog(
    BuildContext context,
    String title,
    DateTime initialStart,
    DateTime? initialEnd, {
    bool showReason = false,
  }) async {
    TimeOfDay startTime = TimeOfDay.fromDateTime(initialStart);
    TimeOfDay endTime = TimeOfDay.fromDateTime(
      initialEnd ?? initialStart.add(const Duration(hours: 4)),
    );
    final reasonController = TextEditingController();

    return showDialog<({DateTime start, DateTime end, String reason})>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(title),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      title: const Text('출근 시간'),
                      trailing: Text(startTime.format(context)),
                      onTap: () async {
                        final t = await showTimePicker(
                          context: context,
                          initialTime: startTime,
                        );
                        if (t != null) setState(() => startTime = t);
                      },
                    ),
                    ListTile(
                      title: const Text('퇴근 시간'),
                      trailing: Text(endTime.format(context)),
                      onTap: () async {
                        final t = await showTimePicker(
                          context: context,
                          initialTime: endTime,
                        );
                        if (t != null) setState(() => endTime = t);
                      },
                    ),
                    if (showReason) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: reasonController,
                        decoration: const InputDecoration(
                          hintText: '사유를 입력해주세요 (선택)',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 2,
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(null),
                  child: const Text('취소'),
                ),
                FilledButton(
                  onPressed: () {
                    final start = DateTime(
                      initialStart.year,
                      initialStart.month,
                      initialStart.day,
                      startTime.hour,
                      startTime.minute,
                    );
                    DateTime end = DateTime(
                      initialStart.year,
                      initialStart.month,
                      initialStart.day,
                      endTime.hour,
                      endTime.minute,
                    );
                    if (end.isBefore(start)) {
                      end = end.add(const Duration(days: 1)); // overnight case
                    }
                    Navigator.of(ctx).pop((
                      start: start,
                      end: end,
                      reason: reasonController.text,
                    ));
                  },
                  child: const Text('저장'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  static Future<String?> showSubstituteDialog(
    BuildContext context,
    List<Worker> availableWorkers,
  ) async {
    String? selectedWorkerId;
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('대타 근무자 선택'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: availableWorkers.map((w) {
                    return RadioListTile<String>(
                      title: Text(w.name),
                      value: w.id,
                      groupValue: selectedWorkerId,
                      onChanged: (val) =>
                          setState(() => selectedWorkerId = val),
                    );
                  }).toList(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(null),
                  child: const Text('취소'),
                ),
                FilledButton(
                  onPressed: selectedWorkerId == null
                      ? null
                      : () => Navigator.of(ctx).pop(selectedWorkerId),
                  child: const Text('저장'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
