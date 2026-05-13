import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_logic/shared_logic.dart';
import 'package:url_launcher/url_launcher.dart';
import 'document_signing_screen.dart';

class WorkerDocumentsScreen extends StatelessWidget {
  const WorkerDocumentsScreen({super.key, required this.storeId});

  final String storeId;

  String _statusLabel(LaborDocument doc) {
    switch (doc.status) {
      case 'draft': return '작성 필요';
      case 'ready': return '서명 대기';
      case 'boss_signed': return '확인 및 서명 필요';
      case 'signed': return '서명 완료 (수령 대기)';
      case 'sent': return doc.deliveryConfirmedAt != null ? '교부/수령 완료 (최종)' : '교부 완료 (수령 확인 필요)';
      case 'delivered': return '제출 완료 / 수령 완료';
      default: return doc.status;
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
      case DocumentType.wage_amendment:
        return Icons.edit_note_outlined;
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
      case DocumentType.wage_amendment:
        return const Color(0xFFD97706);
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
                             t == DocumentType.wageStatement ||
                             t == DocumentType.wage_amendment;
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
                        final s = _statusLabel(doc);
                        final needsAction = doc.status == 'boss_signed' || (doc.status == 'sent' && doc.deliveryConfirmedAt == null);
                        
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
                            ) : (doc.deliveryConfirmedAt != null ? const Icon(Icons.check_circle, color: Color(0xFF10B981)) : const Icon(Icons.chevron_right)),
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

class DocumentReadOnlyScreen extends StatefulWidget {
  const DocumentReadOnlyScreen({super.key, required this.document, this.canAcknowledge = false});

  final LaborDocument document;
  final bool canAcknowledge;

  @override
  State<DocumentReadOnlyScreen> createState() => _DocumentReadOnlyScreenState();
}

class _DocumentReadOnlyScreenState extends State<DocumentReadOnlyScreen> {
  bool _isProcessing = false;

  Future<void> _openPdf() async {
    // 1. R2 아카이브 우선 (immutable 확정본)
    final doc = widget.document;
    if (doc.pdfR2DocId != null && doc.pdfR2DocId!.isNotEmpty) {
      try {
        final archiveUrl = await PdfArchiveService.instance.getArchivedPdfUrl(doc);
        if (archiveUrl != null) {
          final success = await launchUrl(Uri.parse(archiveUrl), mode: LaunchMode.externalApplication);
          if (success) return;
        }
      } catch (e) {
        debugPrint('R2 아카이브 PDF 열기 실패, 폴백: $e');
      }
    }

    // 2. 폴백: Firebase Storage pdfUrl
    final pdfUrl = doc.pdfUrl;
    if (pdfUrl == null || pdfUrl.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PDF 서류가 아직 생성되지 않았거나 주소가 없습니다. 사장님께 문의해 주세요.')),
        );
      }
      return;
    }
    final url = Uri.parse(pdfUrl);
    try {
      final success = await launchUrl(url, mode: LaunchMode.externalApplication);
      if (!success) {
        debugPrint('url_launcher could not launch: $pdfUrl');
      }
    } catch (e) {
      debugPrint('Error launching PDF URL: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.document.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE5E5EA), width: 0.5)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                widget.document.type == DocumentType.wageStatement && widget.document.dataJson != null
                    ? _buildWageStatementUI(widget.document.dataJson!)
                    : Text(widget.document.content.isEmpty ? '내용이 없습니다.' : widget.document.content, style: const TextStyle(height: 1.5)),
                // ★ 서명란 표시
                if (widget.document.bossSignatureUrl != null || widget.document.signatureUrl != null) ...[
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildSignatureBox('사업주', widget.document.bossSignatureUrl),
                      _buildSignatureBox('근로자', widget.document.signatureUrl),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                if (widget.document.pdfUrl != null && widget.document.pdfUrl!.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _openPdf,
                    icon: const Icon(Icons.picture_as_pdf),
                    label: const Text('정식 PDF 계약서 보기'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.blueGrey,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 32),
          if (widget.canAcknowledge && widget.document.deliveryConfirmedAt == null)
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: _isProcessing ? null : () async {
                  setState(() => _isProcessing = true);
                  try {
                    final meta = await SecurityMetadataHelper.captureMetadata('employee');
                    await DatabaseService().acknowledgeDocument(
                      storeId: widget.document.storeId, 
                      docId: widget.document.id, 
                      metadata: meta,
                    );
                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('서류 수령이 확인되었습니다.')));
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('오류 발생: $e')));
                    }
                  } finally {
                    if (mounted) setState(() => _isProcessing = false);
                  }
                },
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
                child: _isProcessing 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('위 내용을 확인하고 서류를 수령했습니다', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            )
          else if (widget.document.deliveryConfirmedAt != null)
            const Center(child: Text('✅ 서류 수령 확인 완료', style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }

  Widget _buildWageStatementUI(String dataJson) {
    try {
      final data = jsonDecode(dataJson) as Map<String, dynamic>;
      final base = (data['basePay'] as num?)?.toInt() ?? 0;
      final premium = (data['premiumPay'] as num?)?.toInt() ?? 0;
      final weekly = (data['weeklyHolidayPay'] as num?)?.toInt() ?? 0;
      final breakP = (data['breakPay'] as num?)?.toInt() ?? 0;
      final other = (data['otherAllowancePay'] as num?)?.toInt() ?? 0;
      final total = (data['totalPay'] as num?)?.toInt() ?? 0;
      final mealNonTaxable = (data['mealNonTaxable'] as num?)?.toInt() ?? 0;
      final insuranceDeduction = (data['insuranceDeduction'] as num?)?.toInt() ?? 0;
      
      final nationalPension = (data['nationalPension'] as num?)?.toInt() ?? 0;
      final healthInsurance = (data['healthInsurance'] as num?)?.toInt() ?? 0;
      final longTermCareInsurance = (data['longTermCareInsurance'] as num?)?.toInt() ?? 0;
      final employmentInsurance = (data['employmentInsurance'] as num?)?.toInt() ?? 0;
      final businessIncomeTax = (data['businessIncomeTax'] as num?)?.toInt() ?? 0;
      final localIncomeTax = (data['localIncomeTax'] as num?)?.toInt() ?? 0;

      final prevAdjustment = (data['previousMonthAdjustment'] as num?)?.toInt() ?? 0;
      final netPay = (data['netPay'] as num?)?.toInt() ?? 0;

      final hourlyRate = (data['hourlyRate'] as num?)?.toDouble() ?? 0.0;
      final workerName = data['workerName'] as String? ?? '이름 미상';
      final workerBirthDate = data['workerBirthDate'] as String? ?? '미입력';
      
      String paydayDateStr = '';
      if (data['paydayDate'] != null) {
        try {
          final dt = DateTime.parse(data['paydayDate'] as String);
          paydayDateStr = '${dt.year}.${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')}';
        } catch (_) {}
      } else {
        paydayDateStr = '당월/익월 지정일'; // fallback
      }

      String _fH(double h) => h == h.toInt() ? h.toInt().toString() : h.toStringAsFixed(1);
      String fmt(num v) => '${v.toInt().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}원';

      final pureLaborHours = (data['pureLaborHours'] as num?)?.toDouble() ?? (hourlyRate > 0 ? base / hourlyRate : 0.0);
      final breakH = (data['paidBreakHours'] as num?)?.toDouble() ?? (hourlyRate > 0 ? breakP / hourlyRate : 0.0);
      final weekH = hourlyRate > 0 ? weekly / hourlyRate : 0.0;
      final premH = hourlyRate > 0 ? premium / (hourlyRate * 0.5) : 0.0;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 24),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.shade100),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('성명: $workerName', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 4),
                Text('생년월일: ${workerBirthDate.isEmpty ? '미입력' : workerBirthDate}', style: const TextStyle(color: Colors.black87, fontSize: 13)),
                const SizedBox(height: 4),
                Text('임금지급일: $paydayDateStr', style: const TextStyle(color: Colors.black87, fontSize: 13)),
              ],
            ),
          ),
          const Text('급여 산출 내역', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const Divider(height: 32),
          _row('기본급', fmt(base), subtitle: '${_fH(pureLaborHours)}시간 × ${fmt(hourlyRate)}'),
          if (premium > 0) _row('초과수당', fmt(premium), subtitle: '${_fH(premH)}시간 × ${fmt(hourlyRate * 0.5)}'),
          if (weekly > 0) _row('주휴수당', fmt(weekly), subtitle: '${_fH(weekH)}시간 × ${fmt(hourlyRate)} (4주 평균 산정)'),
          if (breakP > 0) _row('유급휴게수당', fmt(breakP), subtitle: '${_fH(breakH)}시간 × ${fmt(hourlyRate)}'),
          if (other > 0) _row('기타수당', fmt(other)),
          const Divider(height: 24),
          _row('지급액 합계 (세전)', fmt(total), isTotal: true),
          
          if (mealNonTaxable > 0 || insuranceDeduction > 0 || prevAdjustment != 0) ...[
            const SizedBox(height: 24),
            const Text('공제 및 조정 내역', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const Divider(height: 32),
            if (mealNonTaxable > 0)
              _row('└ (포함) 비과세 식대', fmt(mealNonTaxable), subtitle: '과세 대상액 산정 시 제외금액'),
            
            if (nationalPension > 0) _row('국민연금', '-${fmt(nationalPension)}', valueColor: Colors.red),
            if (healthInsurance > 0) _row('건강보험', '-${fmt(healthInsurance)}', valueColor: Colors.red),
            if (longTermCareInsurance > 0) _row('장기요양보험', '-${fmt(longTermCareInsurance)}', valueColor: Colors.red),
            if (employmentInsurance > 0) _row('고용보험', '-${fmt(employmentInsurance)}', valueColor: Colors.red),
            
            if (businessIncomeTax > 0) _row('사업소득세(3%)', '-${fmt(businessIncomeTax)}', valueColor: Colors.red),
            if (localIncomeTax > 0) _row('지방소득세(0.3%)', '-${fmt(localIncomeTax)}', valueColor: Colors.red),
            
            if (insuranceDeduction > 0)
              _row('공제액 합계', '-${fmt(insuranceDeduction)}', isTotal: true, valueColor: Colors.red),

            if (prevAdjustment != 0)
              _row('전월 이월/정산금', prevAdjustment > 0 ? '+${fmt(prevAdjustment)}' : fmt(prevAdjustment), subtitle: '이전 정산 이월분', valueColor: prevAdjustment > 0 ? Colors.blue : Colors.red),
            const Divider(height: 24),
            _row('최종 실지급액', fmt(netPay), isTotal: true),
          ],
        ],
      );
    } catch (e) {
      return Text('명세서 데이터를 불러올 수 없습니다.\nError: $e', style: const TextStyle(color: Colors.red));
    }
  }

  Widget _row(String label, String value, {bool isTotal = false, String? subtitle, Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: TextStyle(color: isTotal ? Colors.black : Colors.black87, fontWeight: isTotal ? FontWeight.bold : FontWeight.normal, fontSize: isTotal ? 16 : 14)),
              Text(value, style: TextStyle(color: valueColor ?? (isTotal ? const Color(0xFF10B981) : Colors.black), fontWeight: isTotal ? FontWeight.bold : FontWeight.w600, fontSize: isTotal ? 18 : 14)),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.black38)),
          ]
        ],
      ),
    );
  }

  Widget _buildSignatureBox(String label, String? imageUrl) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF888888))),
        const SizedBox(height: 6),
        Container(
          width: 130,
          height: 70,
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE5E5EA)),
            borderRadius: BorderRadius.circular(10),
            color: Colors.white,
          ),
          child: imageUrl != null && imageUrl.isNotEmpty
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Center(
                      child: Icon(Icons.broken_image_outlined, color: Colors.grey, size: 24),
                    ),
                  ),
                )
              : const Center(
                  child: Text('서명 전', style: TextStyle(color: Color(0xFFBBBBBB), fontSize: 12)),
                ),
        ),
      ],
    );
  }
}
