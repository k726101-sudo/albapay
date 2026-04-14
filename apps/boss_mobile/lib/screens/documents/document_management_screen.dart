import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_logic/shared_logic.dart';

import '../../models/worker.dart';
import 'create_document_screen.dart';
import '../../widgets/store_id_gate.dart';
import '../contract_page.dart';
import 'document_content_page.dart';
import 'batch_signing_screen.dart';
import 'document_export_page.dart';
import 'hiring_checklist_screen.dart';
import 'worker_record_screen.dart';
import 'night_consent_screen.dart';
import 'attendance_record_screen.dart';

class DocumentManagementScreen extends StatefulWidget {
  const DocumentManagementScreen({super.key});

  @override
  State<DocumentManagementScreen> createState() => _DocumentManagementScreenState();
}

class _DocumentManagementScreenState extends State<DocumentManagementScreen> {


  @override
  Widget build(BuildContext context) {
    return StoreIdGate(
      builder: (context, storeId) {
        final dbService = DatabaseService();

        return Scaffold(
          appBar: AppBar(
            title: const Text('노무 서류 관리'),
            actions: [
              IconButton(
                icon: const Icon(Icons.picture_as_pdf),
                tooltip: '기간별 PDF 발급',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => DocumentExportPage(storeId: storeId)),
                ),
              ),
            ],
          ),
          body: ValueListenableBuilder<Box<Worker>>(
            valueListenable: Hive.box<Worker>('workers').listenable(),
            builder: (context, box, _) {
              final allWorkers = box.values.toList()
                ..sort((a, b) => a.name.compareTo(b.name));
              final workers = allWorkers.where((w) => w.status == 'active').toList();
              return StreamBuilder<List<LaborDocument>>(
                stream: dbService.streamDocuments(storeId),
                builder: (context, docSnapshot) {
                  final allDocs = docSnapshot.data ?? [];
                  if (allWorkers.isEmpty) {
                    return const Center(child: Text('등록된 직원이 없습니다.'));
                  }

                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      ...workers.map((worker) {
                        final workerDocs = allDocs.where((d) => d.staffId == worker.id).toList();
                        final completedDocs =
                            workerDocs.where((d) => d.status != 'draft').length;

                        return Card(
                          margin: const EdgeInsets.only(bottom: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: ExpansionTile(
                            leading: CircleAvatar(child: Text(worker.name.substring(0, 1))),
                            title: Text(worker.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text('완성도: $completedDocs/${workerDocs.length}'),
                            children: [
                              ...workerDocs.map(
                                (doc) => ListTile(
                                  leading: Container(
                                    width: 30,
                                    height: 30,
                                    decoration: BoxDecoration(
                                      color: _getDocColor(doc.type).withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      _getDocIcon(doc.type),
                                      color: _getDocColor(doc.type),
                                      size: 16,
                                    ),
                                  ),
                                  title: Text(doc.title),
                                  onTap: () {
                                    // 채용 체크리스트 → 전용 인터랙티브 화면
                                    if (doc.type == DocumentType.checklist) {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => HiringChecklistScreen(
                                            worker: worker,
                                            storeId: storeId,
                                            document: doc,
                                          ),
                                        ),
                                      );
                                      return;
                                    }
                                    // 근로자 명부 → 전용 편집 화면
                                    if (doc.type == DocumentType.worker_record) {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => WorkerRecordScreen(
                                            worker: worker,
                                            document: doc,
                                          ),
                                        ),
                                      );
                                      return;
                                    }
                                    // 휴일 및 야간근로 동의서 → 전용 화면
                                    if (doc.type == DocumentType.night_consent) {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => NightConsentScreen(
                                            worker: worker,
                                            document: doc,
                                          ),
                                        ),
                                      );
                                      return;
                                    }
                                    // 출퇴근기록부 → 전용 화면
                                    if (doc.type == DocumentType.attendance_record) {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => AttendanceRecordScreen(
                                            worker: worker,
                                            storeId: storeId,
                                          ),
                                        ),
                                      );
                                      return;
                                    }
                                    // 임금명세서 → PDF 내보내기 페이지
                                    if (doc.type == DocumentType.wageStatement ||
                                        doc.type == DocumentType.wage_ledger) {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => DocumentExportPage(storeId: storeId),
                                        ),
                                      );
                                      return;
                                    }
                                    if (doc.type == DocumentType.contract_full ||
                                        doc.type == DocumentType.contract_part) {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => ContractPage(
                                            worker: worker,
                                            storeId: storeId,
                                            documentId: doc.id,
                                          ),
                                        ),
                                      );
                                      return;
                                    }
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => DocumentContentPage(
                                          worker: worker,
                                          documentId: doc.id,
                                          storeId: storeId,
                                          initialDocument: doc,
                                        ),
                                      ),
                                    );
                                  },
                                  subtitle: Text(_statusSubtitle(doc)),
                                  trailing: _buildStatusBadge(doc.status),
                                ),
                              ),
                            // ── 일괄 서명 버튼 (초안 서류가 1개 이상일 때만 표시) ──
                            Builder(builder: (ctx) {
                              final draftDocs = workerDocs
                                  .where((d) => d.status == 'draft')
                                  .toList();
                              if (draftDocs.isEmpty) return const SizedBox.shrink();
                              return Padding(
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                                child: FilledButton.icon(
                                  onPressed: () async {
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => BatchSigningScreen(
                                          worker: worker,
                                          draftDocuments: draftDocs,
                                          storeId: storeId,
                                        ),
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.draw_rounded, size: 18),
                                  label: Text('일괄 서명 (${draftDocs.length}종)'),
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size(double.infinity, 48),
                                    backgroundColor: const Color(0xFF1A1A2E),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                              );
                            }),
                            // ── 새 서류 작성 버튼 ──
                            Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: ElevatedButton.icon(
                                onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        CreateDocumentScreen(worker: worker, storeId: storeId),
                                  ),
                                ),
                                icon: const Icon(Icons.note_add),
                                label: const Text('새 서류 작성 (템플릿)'),
                                style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 44)),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    ],
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  String _statusSubtitle(LaborDocument doc) {
    switch (doc.status) {
      case 'draft':
        return '작성 필요';
      case 'ready':
        return '서명 대기';
      case 'completed':
      case 'boss_signed':
      case 'signed':
      case 'sent':
      case 'delivered':
        return '작성 완료';
      default:
        return '대기 중';
    }
  }

  Widget _buildStatusBadge(String status) {
    final Map<String, Map<String, dynamic>> statusMap = {
      'draft': {
        'label': '작성 필요',
        'bg': const Color(0xFFFFF0DC),
        'text': const Color(0xFF854F0B),
      },
      'ready': {
        'label': '서명 대기',
        'bg': const Color(0xFFE6F1FB),
        'text': const Color(0xFF185FA5),
      },
      'boss_signed': {
        'label': '작성 완료',
        'bg': const Color(0xFFEAF3DE),
        'text': const Color(0xFF286b3a),
      },
      'signed': {
        'label': '작성 완료',
        'bg': const Color(0xFFEAF3DE),
        'text': const Color(0xFF286b3a),
      },
      'completed': {
        'label': '작성 완료',
        'bg': const Color(0xFFEAF3DE),
        'text': const Color(0xFF286b3a),
      },
      'sent': {
        'label': '작성 완료',
        'bg': const Color(0xFFEAF3DE),
        'text': const Color(0xFF286b3a),
      },
      'delivered': {
        'label': '작성 완료',
        'bg': const Color(0xFFEAF3DE),
        'text': const Color(0xFF286b3a),
      },
    };

    final s = statusMap[status] ?? statusMap['draft']!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: s['bg'] as Color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        s['label'] as String,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: s['text'] as Color,
        ),
      ),
    );
  }

  IconData _getDocIcon(DocumentType type) {
    switch (type) {
      case DocumentType.contract_full:
      case DocumentType.contract_part:
        return Icons.description_outlined;
      case DocumentType.night_consent:
        return Icons.nights_stay_outlined;
      case DocumentType.checklist:
        return Icons.checklist_outlined;
      case DocumentType.worker_record:
        return Icons.person_outline;
      case DocumentType.minor_consent:
        return Icons.family_restroom;
      case DocumentType.attendance_record:
        return Icons.access_time;
      case DocumentType.wageStatement:
      case DocumentType.wage_ledger:
      case DocumentType.wage_amendment:
        return Icons.request_quote_outlined;
      case DocumentType.annual_leave_ledger:
        return Icons.event_available_outlined;
      default:
        return Icons.article_outlined;
    }
  }

  Color _getDocColor(DocumentType type) {
    switch (type) {
      case DocumentType.contract_full:
      case DocumentType.contract_part:
        return const Color(0xFF1a6ebd);
      case DocumentType.night_consent:
        return const Color(0xFF286b3a);
      case DocumentType.checklist:
        return const Color(0xFFd4700a);
      case DocumentType.worker_record:
        return const Color(0xFF8B5CF6);
      case DocumentType.minor_consent:
        return const Color(0xFFE24B4A);
      case DocumentType.attendance_record:
        return const Color(0xFF0288D1);
      case DocumentType.wageStatement:
      case DocumentType.wage_ledger:
      case DocumentType.wage_amendment:
        return const Color(0xFFE64A19);
      case DocumentType.annual_leave_ledger:
        return const Color(0xFF00796B);
      default:
        return const Color(0xFF888888);
    }
  }
}
