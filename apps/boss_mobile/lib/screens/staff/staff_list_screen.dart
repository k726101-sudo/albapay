import 'package:flutter/material.dart';
import 'package:shared_logic/shared_logic.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/worker.dart';
import '../../services/worker_service.dart';
import '../../widgets/wage_edit_dialog.dart';
import 'add_staff_screen.dart';
import 'exit_settlement_report_screen.dart';
import 'staff_invite_code_screen.dart';

class StaffListScreen extends StatefulWidget {
  const StaffListScreen({super.key});

  @override
  State<StaffListScreen> createState() => _StaffListScreenState();
}

class _StaffListScreenState extends State<StaffListScreen> {
  String _healthBadge(Worker w) {
    if (!w.hasHealthCert || w.healthCertExpiry == null || w.healthCertExpiry!.isEmpty) return '';
    final expiry = DateTime.tryParse(w.healthCertExpiry!);
    if (expiry == null) return '';
    final today = AppClock.now();
    final d = DateTime(expiry.year, expiry.month, expiry.day)
        .difference(DateTime(today.year, today.month, today.day))
        .inDays;
    if (d < 0) return '만료';
    if (d <= 7) return 'D-7';
    if (d <= 15) return 'D-15';
    if (d <= 30) return 'D-30';
    return '';
  }

  String _healthLabel(Worker w) {
    if (!w.hasHealthCert) return '보건증 미보유';
    if (w.healthCertExpiry == null || w.healthCertExpiry!.isEmpty) return '보건증 보유';
    return '보건증 보유(만료: ${w.healthCertExpiry})';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Box<Worker>>(
      valueListenable: Hive.box<Worker>('workers').listenable(),
      builder: (context, box, _) {
        final allWorkers = box.values.toList()
          ..sort((a, b) => a.name.compareTo(b.name));
        final activeWorkers =
            allWorkers.where((w) => w.status == 'active').toList();
        final listedWorkers = activeWorkers;
        final activeCount = activeWorkers.length;
        final healthAlertCount =
            activeWorkers.where((w) => _healthBadge(w).isNotEmpty).length;

        return Scaffold(
          backgroundColor: const Color(0xFFF2F2F7),
          appBar: AppBar(
            backgroundColor: const Color(0xFF1a1a2e),
            foregroundColor: Colors.white,
            title: const Text(
              '직원 관리',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w500),
            ),
          ),
          body: listedWorkers.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1a1a2e),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _kpi('전체', '${allWorkers.length}명'),
                                _kpi('재직', '$activeCount명'),
                                _kpi('보건증 주의', '$healthAlertCount건'),
                              ],
                            ),
                          ),
                          const Spacer(),
                          const Text('등록된 재직자가 없습니다.'),
                          const Spacer(),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                      itemCount: listedWorkers.length + 2,
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1a1a2e),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _kpi('전체', '${allWorkers.length}명'),
                                _kpi('재직', '$activeCount명'),
                                _kpi('보건증 주의', '$healthAlertCount건'),
                              ],
                            ),
                          );
                        }
                        if (index == 1) return const SizedBox(height: 0);
                        final worker = listedWorkers[index - 2];
                        final badge = _healthBadge(worker);
                        final isActive = worker.status == 'active';
                        final typeLabel = _workerTypeLabel(worker.workerType);

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFE5E5EA), width: 0.5),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            leading: CircleAvatar(
                              backgroundColor: isActive ? const Color(0xFF1a6ebd) : Colors.grey,
                              child: Text(
                                worker.name.isEmpty ? '-' : worker.name.substring(0, 1),
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                              ),
                            ),
                            title: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  worker.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                                if (typeLabel.isNotEmpty || badge.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      children: [
                                        if (typeLabel.isNotEmpty)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFE6F1FB),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              typeLabel,
                                              style: const TextStyle(
                                                fontSize: 10,
                                                color: Color(0xFF1a6ebd),
                                              ),
                                            ),
                                          ),
                                        if (badge.isNotEmpty)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: badge == '만료'
                                                  ? const Color(0xFFFCEBEB)
                                                  : const Color(0xFFFFF0DC),
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            child: Text(
                                              badge,
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: badge == '만료'
                                                    ? const Color(0xFFA32D2D)
                                                    : const Color(0xFF854F0B),
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Wrap(
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    spacing: 4,
                                    runSpacing: 4,
                                    children: [
                                      if (worker.wageType == 'monthly') ...[
                                        const Text('월급: ', style: TextStyle(fontSize: 12, color: Color(0xFF888888))),
                                        Text(
                                          '${_fmtWage(worker.monthlyWage)}원',
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF1a6ebd),
                                          ),
                                        ),
                                      ] else ...[
                                        const Text('시급: ', style: TextStyle(fontSize: 12, color: Color(0xFF888888))),
                                        Text(
                                          '${_fmtWage(worker.hourlyWage)}원',
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF1a6ebd),
                                          ),
                                        ),
                                        InkWell(
                                          onTap: () => showWageEditDialog(context, worker),
                                          child: Container(
                                            padding: const EdgeInsets.all(2),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF1a6ebd).withAlpha(25),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: const Icon(
                                              Icons.edit_outlined,
                                              size: 14,
                                              color: Color(0xFF1a6ebd),
                                            ),
                                          ),
                                        ),
                                      ],
                                      Text(
                                        ' · ${worker.phone}',
                                        style: const TextStyle(fontSize: 12, color: Color(0xFF888888)),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(_healthLabel(worker), style: const TextStyle(fontSize: 12, color: Color(0xFF888888))),
                                ],
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  tooltip: '수정',
                                  icon: const Icon(
                                    Icons.edit_outlined,
                                    color: Color(0xFF1a6ebd),
                                    size: 20,
                                  ),
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => AddStaffScreen(
                                          initialWorker: worker,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                const SizedBox(width: 12),
                                if (isActive)
                                  IconButton(
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    tooltip: '퇴사 처리',
                                    icon: const Icon(Icons.logout, color: Color(0xFFE24B4A), size: 20),
                                    onPressed: () => _handleTerminate(context, worker),
                                  ),
                                PopupMenuButton<String>(
                                  padding: EdgeInsets.zero,
                                  icon: const Icon(Icons.more_vert, color: Colors.grey, size: 20),
                                  onSelected: (val) {
                                    if (val == 'delete') {
                                      _handleHardDelete(context, worker);
                                    } else if (val == 'special_auth') {
                                      _showSpecialExtensionDialog(context, worker);
                                    } else if (val == 'send_invite') {
                                      _handleResendInvite(context, worker);
                                    } else if (val == 'reset_device') {
                                      _handleResetDevice(context, worker);
                                    }
                                  },
                                  itemBuilder: (ctx) => [
                                    const PopupMenuItem(
                                      value: 'send_invite',
                                      child: Row(
                                        children: [
                                          Icon(Icons.send_rounded, size: 16, color: Color(0xFF1a6ebd)),
                                          SizedBox(width: 8),
                                          Text('초대 코드 보내기', style: TextStyle(fontSize: 13)),
                                        ],
                                      ),
                                    ),
                                    const PopupMenuItem(
                                      value: 'reset_device',
                                      child: Row(
                                        children: [
                                          Icon(Icons.phonelink_erase, size: 16, color: Colors.orange),
                                          SizedBox(width: 8),
                                          Text('기기 연동 해제', style: TextStyle(fontSize: 13)),
                                        ],
                                      ),
                                    ),
                                    const PopupMenuItem(
                                      value: 'special_auth',
                                      child: Row(
                                        children: [
                                          Icon(Icons.security, size: 16, color: Colors.blue),
                                          SizedBox(width: 8),
                                          Text('특별연장 승인 (52h)', style: TextStyle(fontSize: 13)),
                                        ],
                                      ),
                                    ),
                                    const PopupMenuItem(
                                      value: 'delete',
                                      child: Row(
                                        children: [
                                          Icon(Icons.delete_outline, size: 16, color: Colors.red),
                                          SizedBox(width: 8),
                                          Text('완전 삭제', style: TextStyle(color: Colors.red, fontSize: 13)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => AddStaffScreen(
                                    initialWorker: worker,
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
          floatingActionButton: FloatingActionButton(
            backgroundColor: const Color(0xFF1a1a2e),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AddStaffScreen()),
            ),
            child: const Icon(Icons.add, color: Colors.white),
          ),
        );
      },
    );
  }

  Future<void> _showSpecialExtensionDialog(BuildContext context, Worker worker) async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('특별연장근로 승인'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${worker.name}님의 주 52시간 한도 예외를 승인하시겠습니까?'),
            const SizedBox(height: 12),
            const Text(
              '승인 사유를 입력해 주세요. (예: 천재지변, 기계고장, 노동부 인가 등)\n이 기록은 3년간 보존됩니다.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: '사유를 입력하세요',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isEmpty) return;
              Navigator.pop(ctx, true);
            },
            child: const Text('승인'),
          ),
        ],
      ),
    );

    if (ok == true && mounted) {
      final reason = controller.text.trim();
      final today = AppClock.now().toIso8601String().substring(0, 10);
      
      // Update Firestore
      final sid = await WorkerService.resolveStoreId();
      if (sid.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('stores')
            .doc(sid)
            .collection('workers')
            .doc(worker.id)
            .update({
          'specialExtensionAuthorizedAt': today,
          'specialExtensionReason': reason,
        });
      }

      // Update Local Hive
      worker.specialExtensionAuthorizedAt = today;
      worker.specialExtensionReason = reason;
      await worker.save();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${worker.name}님의 특별연장근로(당일 한정)가 승인되었습니다.')),
        );
      }
    }
  }

  Future<void> _handleResendInvite(BuildContext context, Worker worker) async {
    final storeId = await WorkerService.resolveStoreId();
    if (!context.mounted || storeId.isEmpty) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StaffInviteCodeScreen(
          storeId: storeId,
          worker: worker,
        ),
      ),
    );
  }

  Future<void> _handleResetDevice(BuildContext context, Worker worker) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('기기 연동 해제'),
        content: Text('${worker.name} 직원이 새로운 기기에서 로그인할 수 있도록 기존 기기 연동을 해제합니다.\n연동 해제 후, 초대 코드를 다시 전송해 주세요.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('해제하기'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final storeId = await WorkerService.resolveStoreId();
      if (storeId.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('stores')
            .doc(storeId)
            .collection('workers')
            .doc(worker.id)
            .update({
          'uid': FieldValue.delete(),
          'linkedAt': FieldValue.delete(),
        });
      }
      
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${worker.name}님의 기기 연동이 해제되었습니다.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('기기 연동 해제에 실패했습니다.')),
      );
    }
  }

  Future<void> _handleTerminate(BuildContext context, Worker worker) async {
    if (worker.startDate.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('입사일이 없어 퇴사 처리를 진행할 수 없습니다.')),
      );
      return;
    }

    final DateTime? exitDate = await showDatePicker(
      context: context,
      initialDate: AppClock.now(),
      firstDate: DateTime.parse(worker.startDate),
      lastDate: AppClock.now().add(const Duration(days: 365)),
      helpText: '${worker.name} 퇴사 일자 선택',
      confirmText: '정산하기',
      cancelText: '취소',
    );

    if (exitDate == null || !context.mounted) return;

    // 퇴사 정산 리포트 화면으로 이동 (추후 생성 예정)
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExitSettlementReportScreen(
          worker: worker,
          exitDate: exitDate,
        ),
      ),
    );
  }

  Future<void> _handleHardDelete(BuildContext context, Worker worker) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${worker.name} 완전 삭제'),
        content: const Text('해당 직원을 시스템에서 완전히 삭제하시겠습니까?\n이 작업은 되돌릴 수 없으며 모든 데이터가 삭제됩니다.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.black),
            child: const Text('삭제 진행'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await WorkerService.hardDelete(worker.id);

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${worker.name} 삭제 완료')),
    );
  }

  String _workerTypeLabel(String type) {
    if (type == 'dispatch') return '파견';
    if (type == 'foreigner') return '외국인';
    return '';
  }

  String _fmtWage(double wage) =>
      wage.toStringAsFixed(0).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');

  Widget _kpi(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ],
    );
  }
}
