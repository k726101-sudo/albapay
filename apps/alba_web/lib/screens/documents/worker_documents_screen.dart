import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_logic/shared_logic.dart';

import 'document_signing_screen.dart';

class WorkerDocumentsScreen extends StatelessWidget {
  const WorkerDocumentsScreen({super.key, required this.storeId});

  final String storeId;

  String _statusLabel(String status) {
    switch (status) {
      case 'draft': return '작성 필요';
      case 'ready': return '서명 대기';
      case 'boss_signed': return '확인 및 서명 필요';
      case 'signed': return '서명 완료 (수령 대기)';
      case 'sent': return '교부 완료 (최종)';
      default: return status;
    }
  }

  IconData _docIcon(DocumentType type) {
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
      default:
        return Icons.article_outlined;
    }
  }

  Color _docColor(DocumentType type) {
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
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('로그인이 필요합니다.')));
    }

    final db = DatabaseService();

    return Scaffold(
      appBar: AppBar(title: const Text('계약/서류')),
      body: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        // 1. 유저 정보에서 workerId 조회
        future: FirebaseFirestore.instance.collection('users').doc(user.uid).get(),
        builder: (context, userSnap) {
          if (userSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final userData = userSnap.data?.data();
          final workerId = userData?['workerId']?.toString();
          
          if (workerId == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.orange),
                  const SizedBox(height: 16),
                  const Text('직원 정보가 연결되지 않았습니다.', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text('UID: ${user.uid}', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                  const SizedBox(height: 16),
                  ElevatedButton(onPressed: () => FirebaseAuth.instance.signOut(), child: const Text('다시 로그인하기')),
                ],
              ),
            );
          }

          return Column(
            children: [
              // 디버그 정보 (배포 전 확인용, 투명도 낮게)
              Opacity(
                opacity: 0.3,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
                  color: Colors.blue.shade50,
                  child: Text('DEBUG-INFO: uid=${user.uid.substring(0,6)}... / workerId=${workerId.substring(0,6)}...', style: const TextStyle(fontSize: 10)),
                ),
              ),
              Expanded(
                child: StreamBuilder<List<LaborDocument>>(
                  // 2. 내 서류만 필터링하여 실시간 스트림으로 가져옵니다.
                  stream: db.streamWorkerDocuments(storeId, workerId),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.security, size: 48, color: Colors.red),
                              const SizedBox(height: 16),
                              const Text('보안 권한 오류가 발생했습니다.', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              const Text('본인의 서류만 조회할 수 있는 규칙에 의해 차단되었습니다.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
                              const SizedBox(height: 16),
                              Text('오류 상세: ${snapshot.error}', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                              const SizedBox(height: 24),
                              ElevatedButton(onPressed: () => FirebaseAuth.instance.signOut(), child: const Text('로그아웃 후 다시 시도')),
                            ],
                          ),
                        ),
                      );
                    }
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final allDocs = snapshot.data ?? [];
                    final myDocs = allDocs.where((doc) {
                      final t = doc.type;
                      return t == DocumentType.contract_full ||
                             t == DocumentType.contract_part ||
                             t == DocumentType.laborContract ||
                             t == DocumentType.wageStatement;
                    }).toList();
                    myDocs.sort((a, b) => b.createdAt.compareTo(a.createdAt));

                    if (myDocs.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.description_outlined, size: 64, color: Colors.grey.shade300),
                            const SizedBox(height: 16),
                            const Text('교부된 서류가 없습니다.', style: TextStyle(color: Colors.grey)),
                          ],
                        ),
                      );
                    }

                    return ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: myDocs.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final doc = myDocs[index];
                        final c = _docColor(doc.type);
                        final s = _statusLabel(doc.status);
                        final needsAction = doc.status == 'boss_signed' || doc.status == 'sent';
                        
                        return Card(
                          elevation: needsAction ? 2 : 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: needsAction ? BorderSide(color: c, width: 1.5) : BorderSide.none,
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: c.withValues(alpha: 0.1),
                              child: Icon(_docIcon(doc.type), color: c),
                            ),
                            title: Text(doc.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text(s, style: TextStyle(color: needsAction ? c : Colors.grey, fontWeight: needsAction ? FontWeight.bold : FontWeight.normal)),
                            trailing: needsAction ? Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(20)),
                              child: Text(doc.status == 'sent' ? '수령 확인' : '서명하기', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                            ) : const Icon(Icons.chevron_right),
                            onTap: () {
                              if (doc.status == 'boss_signed') {
                                Navigator.push(context, MaterialPageRoute(builder: (_) => DocumentSigningScreen(document: doc, allStaffDocs: myDocs)));
                              } else if (doc.status == 'sent') {
                                Navigator.push(context, MaterialPageRoute(builder: (_) => DocumentReadOnlyScreen(document: doc, canAcknowledge: true)));
                              } else {
                                Navigator.push(context, MaterialPageRoute(builder: (_) => DocumentReadOnlyScreen(document: doc, canAcknowledge: false)));
                              }
                            },
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class DocumentReadOnlyScreen extends StatelessWidget {
  const DocumentReadOnlyScreen({super.key, required this.document, this.canAcknowledge = false});

  final LaborDocument document;
  final bool canAcknowledge;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(document.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE5E5EA), width: 0.5)),
            child: document.type == DocumentType.wageStatement && document.dataJson != null
                ? _buildWageStatementUI(document.dataJson!)
                : Text(document.content.isEmpty ? '내용이 없습니다.' : document.content, style: const TextStyle(height: 1.5)),
          ),
          const SizedBox(height: 32),
          if (canAcknowledge && document.deliveryConfirmedAt == null)
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: () async {
                  await DatabaseService().acknowledgeDocument(storeId: document.storeId, docId: document.id, ip: 'unknown', userAgent: 'web');
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('서류 수령이 확인되었습니다.')));
                  }
                },
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
                child: const Text('위 내용을 확인하고 서류를 수령했습니다', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            )
          else if (document.deliveryConfirmedAt != null)
            const Center(child: Text('✅ 서류 수령 확인 완료', style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }

  Widget _buildWageStatementUI(String dataJson) {
    try {
      final data = jsonDecode(dataJson) as Map<String, dynamic>;
      final base = data['basePay'] as int? ?? 0;
      final premium = data['premiumPay'] as int? ?? 0;
      final weekly = data['weeklyHolidayPay'] as int? ?? 0;
      final breakP = data['breakPay'] as int? ?? 0;
      final other = data['otherAllowancePay'] as int? ?? 0;
      final total = data['totalPay'] as int? ?? 0;

      String fmt(int v) => '${v.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}원';

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('급여 산출 내역', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const Divider(height: 32),
          _row('기본급', fmt(base)),
          _row('초과수당', fmt(premium)),
          _row('주휴수당', fmt(weekly)),
          _row('근로장려수당', fmt(breakP)),
          _row('기타수당', fmt(other)),
          const Divider(height: 32),
          _row('지급 총액', fmt(total), isTotal: true),
        ],
      );
    } catch (_) {
      return const Text('명세서 데이터를 불러올 수 없습니다.', style: TextStyle(color: Colors.red));
    }
  }

  Widget _row(String label, String value, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: isTotal ? Colors.black : Colors.black87, fontWeight: isTotal ? FontWeight.bold : FontWeight.normal, fontSize: isTotal ? 16 : 14)),
          Text(value, style: TextStyle(color: isTotal ? const Color(0xFF10B981) : Colors.black, fontWeight: isTotal ? FontWeight.bold : FontWeight.w600, fontSize: isTotal ? 18 : 14)),
        ],
      ),
    );
  }
}
