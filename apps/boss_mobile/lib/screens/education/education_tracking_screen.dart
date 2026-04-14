import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_logic/shared_logic.dart';

import '../../models/worker.dart';
import '../../services/worker_service.dart';
import '../../widgets/store_id_gate.dart';

class EducationTrackingScreen extends StatelessWidget {
  final bool showAppBar;
  const EducationTrackingScreen({super.key, this.showAppBar = true});

  @override
  Widget build(BuildContext context) {
    return StoreIdGate(
      builder: (context, storeId) {
        final dbService = DatabaseService();

        return Scaffold(
          appBar: showAppBar ? AppBar(title: const Text('교육 수료 현황')) : null,
          body: ValueListenableBuilder<Box<Worker>>(
            valueListenable: Hive.box<Worker>('workers').listenable(),
            builder: (context, box, _) {
              final workers = WorkerService.getAll();
              return StreamBuilder<List<EducationRecord>>(
                stream: dbService.streamEducationRecords(storeId),
                builder: (context, recordSnapshot) {
                  final records = recordSnapshot.data ?? [];

                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: workers.length,
                    itemBuilder: (context, index) {
                      final worker = workers[index];
                      final staffRecords = records.where((r) => r.staffId == worker.id).toList();

                      return Card(
                        margin: const EdgeInsets.only(bottom: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(child: Text(worker.name.substring(0, 1))),
                                  const SizedBox(width: 12),
                                  Text(
                                    worker.name,
                                    style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold),
                                  ),
                                  const Spacer(),
                                  Text(
                                    '전체 이수율: ${_calculateCompletionRate(staffRecords)}%',
                                    style: const TextStyle(
                                        color: Colors.blue,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              const Divider(height: 32),
                              _buildEducationStatusRow('성희롱 예방 교육',
                                  staffRecords, EducationType.sexualHarassment),
                              _buildEducationStatusRow(
                                  '위생 교육', staffRecords, EducationType.hygiene),
                              _buildEducationStatusRow('직장 내 괴롭힘 방지',
                                  staffRecords, EducationType.workplaceHarassment),
                              _buildEducationStatusRow('개인정보보호 교육',
                                  staffRecords, EducationType.privacy),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  bool _isCompleted(List<EducationRecord> records, EducationType type) {
    String targetId = '';
    switch (type) {
      case EducationType.sexualHarassment:
        targetId = 'edu-1';
        break;
      case EducationType.hygiene:
        targetId = 'edu-2';
        break;
      default:
        targetId = '';
    }
    return records.any((r) => r.educationContentId == targetId);
  }

  int _calculateCompletionRate(List<EducationRecord> records) {
    int count = 0;
    if (_isCompleted(records, EducationType.sexualHarassment)) count++;
    if (_isCompleted(records, EducationType.hygiene)) count++;
    if (_isCompleted(records, EducationType.workplaceHarassment)) count++;
    if (_isCompleted(records, EducationType.privacy)) count++;
    return ((count / 4) * 100).toInt();
  }

  Widget _buildEducationStatusRow(String title, List<EducationRecord> records, EducationType type) {
    final bool isCompleted = _isCompleted(records, type);
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title),
          Icon(
            isCompleted ? Icons.check_circle : Icons.radio_button_unchecked,
            color: isCompleted ? Colors.green : Colors.grey.shade400,
            size: 20,
          ),
        ],
      ),
    );
  }
}
