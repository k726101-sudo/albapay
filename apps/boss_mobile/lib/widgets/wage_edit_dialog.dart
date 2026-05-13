import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/worker.dart';
import '../services/worker_service.dart';
import 'package:shared_logic/shared_logic.dart' show PayrollConstants;

class WageEditDialog extends StatefulWidget {
  final Worker worker;

  const WageEditDialog({super.key, required this.worker});

  @override
  State<WageEditDialog> createState() => _WageEditDialogState();
}

class _WageEditDialogState extends State<WageEditDialog> {
  late TextEditingController _controller;
  late TextEditingController _oldWageController;
  bool _isSaving = false;
  late DateTime _effectiveDate;
  bool get _historyEmpty {
    if (widget.worker.wageHistoryJson.isEmpty) return true;
    try {
      final history = jsonDecode(widget.worker.wageHistoryJson) as List<dynamic>;
      if (history.isEmpty) return true;
      // 모든 이력이 동일 시급이면 분할 의미가 없으므로 복구 필요
      final wages = history.map((r) => (r['hourlyWage'] as num?)?.toDouble() ?? 0).toSet();
      return wages.length <= 1;
    } catch (_) {
      return true;
    }
  }

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.worker.hourlyWage.toInt().toString(),
    );
    _oldWageController = TextEditingController();
    _effectiveDate = DateTime.now();
  }

  @override
  void dispose() {
    _controller.dispose();
    _oldWageController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _effectiveDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() => _effectiveDate = picked);
    }
  }

  Future<void> _handleSave() async {
    final newWage = double.tryParse(_controller.text.trim());
    if (newWage == null || newWage < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('올바른 시급을 입력해주세요.')),
      );
      return;
    }

    // 법정 최저시급 검증
    final minWage = PayrollConstants.legalMinimumWage;
    if (newWage < minWage) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('법정 최저시급(${minWage.toInt()}원) 미만으로 설정할 수 없습니다.')),
      );
      return;
    }

    final oldWage = widget.worker.hourlyWage;
    final wageChanged = (newWage - oldWage).abs() > 0.5;

    // 이력이 비어있고 시급이 같으면 → 이전 시급을 반드시 입력받아야 함
    double? previousWage;
    if (_historyEmpty && !wageChanged) {
      previousWage = double.tryParse(_oldWageController.text.trim());
      if (previousWage == null || previousWage < 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('변경 전 시급을 입력해주세요.')),
        );
        return;
      }
    }

    setState(() => _isSaving = true);
    try {
      String newHistoryJson = widget.worker.wageHistoryJson;

      // 이력 생성이 필요한 경우: 시급 변경 또는 이력 비어있음
      if (wageChanged || _historyEmpty) {
        List<dynamic> history = [];
        if (newHistoryJson.isNotEmpty) {
          try {
            history = jsonDecode(newHistoryJson) as List<dynamic>;
          } catch (_) {}
        }

        // 히스토리가 비어있다면 이전 시급을 입사일 기준으로 첫 기록 남김
        if (history.isEmpty) {
          final initialDate = widget.worker.joinDate.isNotEmpty
              ? widget.worker.joinDate
              : (widget.worker.startDate.isNotEmpty ? widget.worker.startDate : '2000-01-01');
          final baseWage = previousWage ?? (wageChanged ? oldWage : newWage);
          history.add({
            'effectiveDate': initialDate,
            'hourlyWage': baseWage,
          });
        }

        final effectiveDateStr = '${_effectiveDate.year}-${_effectiveDate.month.toString().padLeft(2, '0')}-${_effectiveDate.day.toString().padLeft(2, '0')}';

        // 같은 적용일에 이미 기록이 있으면 덮어쓰기
        history.removeWhere((r) => r['effectiveDate']?.toString() == effectiveDateStr);
        history.add({
          'effectiveDate': effectiveDateStr,
          'hourlyWage': newWage,
        });

        newHistoryJson = jsonEncode(history);
      }

      final updatedWorker = widget.worker.copyWith(
        hourlyWage: newWage,
        wageHistoryJson: newHistoryJson,
      );
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

  Future<void> _handleResetHistory() async {
    final newWage = double.tryParse(_controller.text.trim());
    if (newWage == null || newWage < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('시급을 먼저 입력해주세요.')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('시급 변경 이력 초기화'),
        content: const Text('그동안의 시급 변동(임금계약변경서 내역)이 모두 삭제되고, 입력한 시급으로 전체 기간이 일괄 계산됩니다. 진행하시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('초기화 진행', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isSaving = true);
    try {
      final updatedWorker = widget.worker.copyWith(hourlyWage: newWage, wageHistoryJson: '');
      await WorkerService.save(updatedWorker);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('초기화 중 오류가 발생했습니다: $e')),
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
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('현재 시급:', style: TextStyle(fontSize: 12, color: Colors.grey)),
            Text(
              '${currencyFormat.format(widget.worker.hourlyWage)}원',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            // 이력이 비어있을 때 이전 시급 입력 필드 표시
            if (_historyEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('⚠️ 시급 변경 이력 복구', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.orange)),
                    const SizedBox(height: 6),
                    const Text('변경 전 시급을 입력해주세요 (이전 계약 시급)', style: TextStyle(fontSize: 11, color: Colors.grey)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _oldWageController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: '변경 전 시급 (원)',
                        border: OutlineInputBorder(),
                        suffixText: '원',
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              keyboardType: TextInputType.number,
              autofocus: !_historyEmpty,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: '새 시급 (원)',
                border: OutlineInputBorder(),
                suffixText: '원',
              ),
              onSubmitted: (_) => _handleSave(),
            ),
            const SizedBox(height: 16),
            const Text('적용 시작일:', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 4),
            InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade400),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${_effectiveDate.year}년 ${_effectiveDate.month}월 ${_effectiveDate.day}일',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    const Icon(Icons.calendar_today, size: 18, color: Colors.grey),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '* 이 날짜부터 새 시급이 적용되며, 이전 출근분은 기존 시급으로 계산됩니다.',
              style: TextStyle(fontSize: 11, color: Colors.orange),
            ),
          ],
        ),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton(
          onPressed: _isSaving ? null : _handleResetHistory,
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: const Text('이력 초기화'),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
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
                  : const Text('저장'),
            ),
          ],
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
