import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/worker.dart';
import '../services/worker_service.dart';

class WageEditDialog extends StatefulWidget {
  final Worker worker;

  const WageEditDialog({super.key, required this.worker});

  @override
  State<WageEditDialog> createState() => _WageEditDialogState();
}

class _WageEditDialogState extends State<WageEditDialog> {
  late TextEditingController _controller;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.worker.hourlyWage.toInt().toString(),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    final newWage = double.tryParse(_controller.text.trim());
    if (newWage == null || newWage < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('올바른 시급을 입력해주세요.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final updatedWorker = widget.worker.copyWith(hourlyWage: newWage);
      await WorkerService.save(updatedWorker);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('시급 수정 중 오류가 발생했습니다: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat('#,###');

    return AlertDialog(
      title: Text('${widget.worker.name} 시급 수정'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('현재 시급:', style: TextStyle(fontSize: 12, color: Colors.grey)),
          Text(
            '${currencyFormat.format(widget.worker.hourlyWage)}원',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            keyboardType: TextInputType.number,
            autofocus: true,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: '새 시급 (원)',
              border: OutlineInputBorder(),
              suffixText: '원',
            ),
            onSubmitted: (_) => _handleSave(),
          ),
          const SizedBox(height: 8),
          const Text(
            '* 변경 시 실시간 급여 리포트에도 즉시 반영됩니다.',
            style: TextStyle(fontSize: 11, color: Colors.orange),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _handleSave,
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1a1a2e)),
          child: _isSaving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                )
              : const Text('수정 완료'),
        ),
      ],
    );
  }
}

Future<bool?> showWageEditDialog(BuildContext context, Worker worker) {
  return showDialog<bool>(
    context: context,
    builder: (context) => WageEditDialog(worker: worker),
  );
}
