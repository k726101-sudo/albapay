import 'package:flutter/material.dart';
import 'package:shared_logic/shared_logic.dart';

import '../../models/worker.dart';
import 'document_content_page.dart';
import 'document_export_page.dart';
import '../contract_page.dart';
import 'hiring_checklist_screen.dart';
import 'worker_record_screen.dart';
import 'night_consent_screen.dart';
import 'attendance_record_screen.dart';

class RetiredWorkerDocumentsScreen extends StatelessWidget {
  final Worker worker;
  final String storeId;

  const RetiredWorkerDocumentsScreen({
    super.key,
    required this.worker,
    required this.storeId,
  });

  @override
  Widget build(BuildContext context) {
    final dbService = DatabaseService();

    return Scaffold(
      appBar: AppBar(
        title: Text('${worker.name} 서류 기록'),
      ),
      body: StreamBuilder<List<LaborDocument>>(
        stream: dbService.streamDocuments(storeId),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final allDocs = snapshot.data ?? [];
          final workerDocs = allDocs.where((d) => d.staffId == worker.id).toList();

          if (workerDocs.isEmpty) {
            return const Center(child: Text('보존된 노무 서류가 없습니다.'));
          }

          return Column(
            children: [
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: workerDocs.length,
                  itemBuilder: (context, index) {
                    final doc = workerDocs[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: _getDocColor(doc.type).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            _getDocIcon(doc.type),
                            color: _getDocColor(doc.type),
                            size: 20,
                          ),
                        ),
                        title: Text(doc.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(_statusSubtitle(doc)),
                        trailing: _buildStatusBadge(doc.status),
                        onTap: () {
                          if (doc.type == DocumentType.checklist) {
                            Navigator.push(context, MaterialPageRoute(builder: (_) => HiringChecklistScreen(worker: worker, storeId: storeId, document: doc)));
                            return;
                          }
                          if (doc.type == DocumentType.worker_record) {
                            Navigator.push(context, MaterialPageRoute(builder: (_) => WorkerRecordScreen(worker: worker, document: doc)));
                            return;
                          }
                          if (doc.type == DocumentType.night_consent) {
                            Navigator.push(context, MaterialPageRoute(builder: (_) => NightConsentScreen(worker: worker, document: doc)));
                            return;
                          }
                          if (doc.type == DocumentType.attendance_record) {
                            Navigator.push(context, MaterialPageRoute(builder: (_) => AttendanceRecordScreen(worker: worker, storeId: storeId)));
                            return;
                          }
                          if (doc.type == DocumentType.wageStatement || doc.type == DocumentType.wage_ledger) {
                            Navigator.push(context, MaterialPageRoute(builder: (_) => DocumentExportPage(storeId: storeId)));
                            return;
                          }
                          if (doc.type == DocumentType.contract_full || doc.type == DocumentType.contract_part) {
                            Navigator.push(context, MaterialPageRoute(builder: (_) => ContractPage(worker: worker, storeId: storeId, documentId: doc.id)));
                            return;
                          }
                          Navigator.push(context, MaterialPageRoute(builder: (_) => DocumentContentPage(worker: worker, documentId: doc.id, storeId: storeId, initialDocument: doc)));
                        },
                      ),
                    );
                  },
                ),
              ),
              // ── 출퇴근 기록부 영구 확인 버튼 (동적 생성) ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0).copyWith(bottom: 32.0), // 하단 여유 공간 추가
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AttendanceRecordScreen(
                        worker: worker,
                        storeId: storeId,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.access_time, color: Colors.blueGrey),
                  label: const Text('출퇴근 기록부 확인 및 PDF 발급 🖨️', style: TextStyle(color: Colors.blueGrey, fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 44),
                    side: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _statusSubtitle(LaborDocument doc) {
    switch (doc.status) {
      case 'draft': return '작성 필요';
      case 'ready': return '서명 대기';
      case 'completed':
      case 'boss_signed':
      case 'signed':
      case 'sent':
      case 'delivered': return '작성 완료';
      default: return '대기 중';
    }
  }

  Widget _buildStatusBadge(String status) {
    final Map<String, Map<String, dynamic>> statusMap = {
      'draft': {'label': '작성 필요', 'bg': const Color(0xFFFFF0DC), 'text': const Color(0xFF854F0B)},
      'ready': {'label': '서명 대기', 'bg': const Color(0xFFE6F1FB), 'text': const Color(0xFF185FA5)},
      'boss_signed': {'label': '작성 완료', 'bg': const Color(0xFFEAF3DE), 'text': const Color(0xFF286b3a)},
      'signed': {'label': '작성 완료', 'bg': const Color(0xFFEAF3DE), 'text': const Color(0xFF286b3a)},
      'completed': {'label': '작성 완료', 'bg': const Color(0xFFEAF3DE), 'text': const Color(0xFF286b3a)},
      'sent': {'label': '작성 완료', 'bg': const Color(0xFFEAF3DE), 'text': const Color(0xFF286b3a)},
      'delivered': {'label': '작성 완료', 'bg': const Color(0xFFEAF3DE), 'text': const Color(0xFF286b3a)},
    };
    final s = statusMap[status] ?? statusMap['draft']!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: s['bg'] as Color, borderRadius: BorderRadius.circular(20)),
      child: Text(s['label'] as String, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: s['text'] as Color)),
    );
  }

  IconData _getDocIcon(DocumentType type) {
    switch (type) {
      case DocumentType.contract_full:
      case DocumentType.contract_part: return Icons.description_outlined;
      case DocumentType.night_consent: return Icons.nights_stay_outlined;
      case DocumentType.checklist: return Icons.checklist_outlined;
      case DocumentType.worker_record: return Icons.person_outline;
      case DocumentType.minor_consent: return Icons.family_restroom;
      case DocumentType.attendance_record: return Icons.access_time;
      case DocumentType.wageStatement:
      case DocumentType.wage_ledger:
      case DocumentType.wage_amendment: return Icons.request_quote_outlined;
      case DocumentType.annual_leave_ledger: return Icons.event_available_outlined;
      case DocumentType.resignation_letter: return Icons.exit_to_app;
      default: return Icons.article_outlined;
    }
  }

  Color _getDocColor(DocumentType type) {
    switch (type) {
      case DocumentType.contract_full:
      case DocumentType.contract_part: return const Color(0xFF1a6ebd);
      case DocumentType.night_consent: return const Color(0xFF286b3a);
      case DocumentType.checklist: return const Color(0xFFd4700a);
      case DocumentType.worker_record: return const Color(0xFF8B5CF6);
      case DocumentType.minor_consent: return const Color(0xFFE24B4A);
      case DocumentType.attendance_record: return const Color(0xFF0288D1);
      case DocumentType.wageStatement:
      case DocumentType.wage_ledger:
      case DocumentType.wage_amendment: return const Color(0xFFE64A19);
      case DocumentType.annual_leave_ledger: return const Color(0xFF00796B);
      case DocumentType.resignation_letter: return const Color(0xFF757575);
      default: return const Color(0xFF888888);
    }
  }
}
