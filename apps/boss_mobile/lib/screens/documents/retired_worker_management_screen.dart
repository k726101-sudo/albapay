import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../models/worker.dart';
import '../../services/worker_service.dart';
import '../../widgets/store_id_gate.dart';
import 'retired_worker_documents_screen.dart';

class RetiredWorkerManagementScreen extends StatefulWidget {
  const RetiredWorkerManagementScreen({super.key});

  @override
  State<RetiredWorkerManagementScreen> createState() => _RetiredWorkerManagementScreenState();
}

class _RetiredWorkerManagementScreenState extends State<RetiredWorkerManagementScreen> {
  Future<void> _handleReactivate(BuildContext context, Worker worker) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${worker.name} 복직 처리'),
        content: const Text('이 직원을 현 근무자 상태로 복직 처리하시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF286b3a)),
            child: const Text('복직'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await WorkerService.reactivate(worker.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${worker.name} 복직 처리 완료')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StoreIdGate(builder: (context, storeId) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('퇴사자 관리'),
        ),
        body: ValueListenableBuilder<Box<Worker>>(
          valueListenable: Hive.box<Worker>('workers').listenable(),
          builder: (context, box, _) {
            final allWorkers = box.values.toList()..sort((a, b) => a.name.compareTo(b.name));
            final retiredWorkers = allWorkers.where((w) => w.status != 'active').toList();

            if (retiredWorkers.isEmpty) {
              return const Center(child: Text('퇴사자가 없습니다.'));
            }

            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: retiredWorkers.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final w = retiredWorkers[index];
                return Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey.shade300),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: CircleAvatar(
                      backgroundColor: Colors.grey.shade300,
                      foregroundColor: Colors.black87,
                      child: Text(w.name.isEmpty ? '-' : w.name.substring(0, 1)),
                    ),
                    title: Text(w.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    subtitle: Text(
                      '퇴사일: ${w.endDate?.isNotEmpty == true ? w.endDate : '-'}',
                      style: const TextStyle(color: Colors.black54),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => RetiredWorkerDocumentsScreen(
                                  worker: w,
                                  storeId: storeId,
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.history, size: 16),
                          label: const Text('서류 기록'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.blueGrey.shade700,
                            side: BorderSide(color: Colors.blueGrey.shade300),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: () => _handleReactivate(context, w),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF1a1a2e),
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                          ),
                          child: const Text('복직'),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      );
    });
  }
}
