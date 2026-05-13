import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_logic/shared_logic.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../../models/worker.dart';
import '../../utils/pdf/pdf_generator_service.dart';
import 'signature_pad_screen.dart';

class WageAmendmentScreen extends StatefulWidget {
  final LaborDocument document;
  final Map<String, dynamic> storeData;
  final Worker worker;

  const WageAmendmentScreen({
    super.key,
    required this.document,
    required this.storeData,
    required this.worker,
  });

  @override
  State<WageAmendmentScreen> createState() => _WageAmendmentScreenState();
}

class _WageAmendmentScreenState extends State<WageAmendmentScreen> {
  final TextEditingController _newWageCtrl = TextEditingController();
  DateTime _effectiveDate = DateTime.now();
  bool _isLoading = false;
  late Worker _worker;

  @override
  void initState() {
    super.initState();
    _worker = widget.worker;
  }

  @override
  void dispose() {
    _newWageCtrl.dispose();
    super.dispose();
  }

  String _formatWon(double amount) {
    return amount.toInt().toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
  }

  void _loadDraftData(LaborDocument doc) {
    if (doc.dataJson != null) {
      try {
        final data = jsonDecode(doc.dataJson!) as Map<String, dynamic>;
        if (data['newWage'] != null && _newWageCtrl.text.isEmpty) {
          _newWageCtrl.text = data['newWage'].toString();
        }
        if (data['effectiveDate'] != null) {
          _effectiveDate = DateTime.tryParse(data['effectiveDate']) ?? _effectiveDate;
        }
      } catch (_) {}
    }
  }

  Future<void> _updateDocumentStatus({
    required LaborDocument doc,
    required String status,
    DateTime? signedAt,
    DateTime? sentAt,
    String? bossSignatureUrl,
    Map<String, dynamic>? bossSignatureMetadata,
    String? workerSignatureUrl,
    Map<String, dynamic>? workerSignatureMetadata,
    String? dataJson,
    String? documentHash,
    String? content,
  }) async {
    try {
      await FirebaseFirestore.instance
          .collection('stores')
          .doc(widget.document.storeId)
          .collection('documents')
          .doc(doc.id)
          .update({
        'status': status,
        if (signedAt != null) 'signedAt': signedAt.toIso8601String(),
        if (sentAt != null) 'sentAt': sentAt.toIso8601String(),
        if (bossSignatureUrl != null) 'bossSignatureUrl': bossSignatureUrl,
        if (bossSignatureMetadata != null) 'bossSignatureMetadata': bossSignatureMetadata,
        if (workerSignatureUrl != null) 'signatureUrl': workerSignatureUrl,
        if (workerSignatureMetadata != null) 'signatureMetadata': workerSignatureMetadata,
        if (dataJson != null) 'dataJson': dataJson,
        if (documentHash != null) 'documentHash': documentHash,
        if (content != null) 'content': content,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('문서 상태가 "$status"로 업데이트되었습니다.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('상태 업데이트 실패: $e')),
      );
      rethrow;
    }
  }

  Future<void> _handleBossSignature(LaborDocument doc) async {
    final newWageDouble = double.tryParse(_newWageCtrl.text) ?? 0.0;
    if (newWageDouble <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('유효한 임금을 입력하세요.')));
      return;
    }

    // 법정 최저시급 검증 (시급제인 경우)
    if (_worker.wageType != 'monthly') {
      final minWage = PayrollConstants.legalMinimumWage;
      if (newWageDouble < minWage) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('법정 최저시급(${minWage.toInt()}원) 미만으로 설정할 수 없습니다.')),
        );
        return;
      }
    }

    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => SignaturePadScreen(title: '임금 변경 계약 사장님 서명'),
      ),
    );

    if (result == null) return;
    final signatureBytes = result['signatureBytes'] as Uint8List?;
    final metadata = result['metadata'] as Map<String, dynamic>;

    if (signatureBytes == null) return;

    setState(() => _isLoading = true);
    try {
      final authUid = FirebaseAuth.instance.currentUser?.uid;
      if (authUid == null) throw '인증 정보가 없습니다.';
      
      final storageRef = FirebaseStorage.instance.ref().child('signatures/$authUid/${doc.id}_boss.png');
      final uploadTask = await storageRef.putData(signatureBytes, SettableMetadata(contentType: 'image/png'));
      final downloadUrl = await uploadTask.ref.getDownloadURL();

      final effectiveDateStr = '${_effectiveDate.year}-${_effectiveDate.month.toString().padLeft(2, '0')}-${_effectiveDate.day.toString().padLeft(2, '0')}';
      
      final data = {
        'newWage': newWageDouble,
        'effectiveDate': effectiveDateStr,
      };
      
      final newDataJson = jsonEncode(data);

      final isMonthly = _worker.wageType == 'monthly';
      final oldWage = isMonthly ? _worker.monthlyWage : _worker.hourlyWage;
      
      final newContent = DocumentTemplates.getWageAmendment({
        'staffName': _worker.name,
        'jobDescription': '매장 관리',
        'oldBaseWage': _formatWon(oldWage),
        'newBaseWage': _formatWon(newWageDouble),
        'effectiveDate': effectiveDateStr,
        'contractDate': '${DateTime.now().year}년 ${DateTime.now().month}월 ${DateTime.now().day}일',
        'ownerName': widget.storeData['ownerName'] ?? '대표자',
      });

      await _updateDocumentStatus(
        doc: doc,
        status: 'boss_signed',
        bossSignatureUrl: downloadUrl,
        bossSignatureMetadata: metadata,
        dataJson: newDataJson,
        content: newContent,
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('서명 업로드 실패: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleWorkerSignature(LaborDocument doc) async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => SignaturePadScreen(title: '${_worker.name}님 임금 변경 서명 (대면)'),
      ),
    );

    if (result == null) return;
    final signatureBytes = result['signatureBytes'] as Uint8List?;
    final metadata = result['metadata'] as Map<String, dynamic>;

    if (signatureBytes == null) return;

    setState(() => _isLoading = true);
    try {
      final authUid = FirebaseAuth.instance.currentUser?.uid;
      if (authUid == null) throw '인증 정보가 없습니다.';
      final storageRef = FirebaseStorage.instance.ref().child('signatures/$authUid/${doc.id}_worker_f2f.png');
      final uploadTask = await storageRef.putData(signatureBytes, SettableMetadata(contentType: 'image/png'));
      final downloadUrl = await uploadTask.ref.getDownloadURL();

      await _updateDocumentStatus(
        doc: doc,
        status: 'signed',
        signedAt: AppClock.now(),
        workerSignatureUrl: downloadUrl,
        workerSignatureMetadata: metadata,
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('근로자 서명 업로드 실패: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleIssuance(LaborDocument doc) async {
    setState(() => _isLoading = true);
    try {
      final data = jsonDecode(doc.dataJson!) as Map<String, dynamic>;
      final newWageDouble = (data['newWage'] as num).toDouble();
      final effectiveDateStr = data['effectiveDate'] as String;

      // 무결성 해시 생성
      final newHash = SecurityMetadataHelper.generateDocumentHash(
        type: doc.type.name,
        staffId: doc.staffId,
        content: doc.content,
        dataJson: doc.dataJson!,
        createdAt: doc.createdAt.toIso8601String(),
      );

      // PDF 생성 (PdfGeneratorService 이용)
      Uint8List? bossSigBytes;
      Uint8List? workerSigBytes;
      try {
        if (doc.bossSignatureUrl != null) {
          final res = await http.get(Uri.parse(doc.bossSignatureUrl!));
          if (res.statusCode == 200) bossSigBytes = res.bodyBytes;
        }
        if (doc.signatureUrl != null) {
          final res = await http.get(Uri.parse(doc.signatureUrl!));
          if (res.statusCode == 200) workerSigBytes = res.bodyBytes;
        }
      } catch (e) {
        debugPrint('Failed to load signature images for PDF: $e');
      }

      final isMonthly = _worker.wageType == 'monthly';
      final oldWage = isMonthly ? _worker.monthlyWage : _worker.hourlyWage;

      final amendmentData = {
        ...data,
        'oldWage': oldWage,
        'wageType': _worker.wageType,
        'workerName': _worker.name,
        'storeName': widget.storeData['storeName'] ?? widget.storeData['name'] ?? '',
        'ownerName': widget.storeData['ownerName'] ?? '',
      };

      final pdfBytes = await PdfGeneratorService.generateWageAmendment(
        document: doc,
        amendmentData: amendmentData,
        ownerSignatureBytes: bossSigBytes,
        workerSignatureBytes: workerSigBytes,
      );

      // R2 아카이브 (immutable 확정본 보관 — Firebase Storage 미사용)
      try {
        await PdfArchiveService.instance.archiveSignedDocument(
          doc: doc,
          pdfBytes: pdfBytes,
        );
        debugPrint('✅ 임금변경합의서 PDF R2 아카이브 완료: ${doc.id}');
      } catch (e) {
        debugPrint('⚠️ R2 아카이브 실패 (교부는 계속 진행): $e');
      }

      // 문서 상태 업데이트
      await _updateDocumentStatus(
        doc: doc,
        status: 'sent',
        sentAt: AppClock.now(),
        documentHash: newHash,
      );

      List<dynamic> history = [];
      if (_worker.wageHistoryJson.isNotEmpty) {
        try {
          history = jsonDecode(_worker.wageHistoryJson) as List<dynamic>;
        } catch (_) {}
      }
      
      // 히스토리가 비어있다면, 첫 임금 변경이므로 '기존 시급'을 입사일 기준으로 첫 번째 기록으로 남겨야 함.
      if (history.isEmpty) {
        final initialDate = _worker.joinDate.isNotEmpty ? _worker.joinDate : (_worker.startDate.isNotEmpty ? _worker.startDate : '2000-01-01');
        history.add({
          'effectiveDate': initialDate,
          'hourlyWage': oldWage,
        });
      }

      history.add({
        'effectiveDate': effectiveDateStr,
        'hourlyWage': newWageDouble,
      });

      final newHistoryJson = jsonEncode(history);

      // ★ Hive 로컬 Worker도 즉시 업데이트 (Firestore 덮어쓰기 방지)
      _worker.wageHistoryJson = newHistoryJson;
      if (isMonthly) {
        _worker.monthlyWage = newWageDouble;
      } else {
        _worker.hourlyWage = newWageDouble;
      }
      await _worker.save(); // Hive 저장

      // Firestore 업데이트
      final workerRef = FirebaseFirestore.instance
          .collection('stores')
          .doc(widget.document.storeId)
          .collection('workers')
          .doc(_worker.id);

      await workerRef.update({
        'wageHistoryJson': newHistoryJson,
        if (isMonthly) 'monthlyWage': newWageDouble else 'hourlyWage': newWageDouble,
      });

      // 알바생 알림 전송
      final dbService = DatabaseService();
      await dbService.enqueueWorkerDocumentNotification(
        storeId: widget.document.storeId,
        workerId: doc.staffId,
        docId: doc.id,
        docTitle: doc.title,
        kind: 'new_document',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('교부 및 직원 정보 업데이트가 완료되었습니다.'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('교부 처리 실패: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }


  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _effectiveDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF1565C0),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _effectiveDate = picked;
      });
    }
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case 'draft': return '작성 중 (입력)';
      case 'ready': return '서명 대기 중';
      case 'boss_signed': return '근로자 서명 대기';
      case 'signed': return '교부 대기 (서명 완료)';
      case 'sent': return '교부 완료';
      default: return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<LaborDocument?>(
      stream: FirebaseFirestore.instance
          .collection('stores')
          .doc(widget.document.storeId)
          .collection('documents')
          .doc(widget.document.id)
          .snapshots()
          .map((snap) => snap.exists ? LaborDocument.fromMap(snap.id, snap.data()!) : null),
      initialData: widget.document,
      builder: (context, snapshot) {
        final doc = snapshot.data;
        if (doc == null) {
          return Scaffold(appBar: AppBar(title: const Text('조회 중')), body: const Center(child: CircularProgressIndicator()));
        }

        // Load drafted data into controllers if available
        if (doc.status == 'draft' || doc.status == 'ready' || doc.status == 'boss_signed' || doc.status == 'signed' || doc.status == 'sent') {
          _loadDraftData(doc);
        }

        final isMonthly = _worker.wageType == 'monthly';
        final oldWage = isMonthly ? _worker.monthlyWage : _worker.hourlyWage;
        final bool isReadOnly = doc.status != 'draft' && doc.status != 'ready';

        return Scaffold(
          backgroundColor: const Color(0xFFF2F4F8),
          appBar: AppBar(
            title: const Text('임금 계약 변경서', style: TextStyle(fontWeight: FontWeight.w700)),
            backgroundColor: Colors.white,
            foregroundColor: Colors.black87,
            elevation: 0,
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
                  child: Text('현재 문서 상태: ${_getStatusLabel(doc.status)}', 
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1565C0))),
                ),
                
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 2)),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('임금 변경 내용', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF1565C0))),
                      const SizedBox(height: 20),
                      
                      Text('현재 임금 (${isMonthly ? '월급' : '시급'})', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black54)),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F7FA),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${_formatWon(oldWage)}원',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.black45),
                        ),
                      ),
                      const SizedBox(height: 20),

                      Text('변경 후 임금 (${isMonthly ? '월급' : '시급'})', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black54)),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _newWageCtrl,
                        keyboardType: TextInputType.number,
                        readOnly: isReadOnly,
                        decoration: InputDecoration(
                          hintText: '새로운 금액을 입력하세요',
                          suffixText: '원',
                          filled: true,
                          fillColor: isReadOnly ? const Color(0xFFF5F7FA) : Colors.white,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
                        ),
                      ),
                      const SizedBox(height: 20),

                      const Text('효력 발생일 (적용일)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black54)),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: isReadOnly ? null : _pickDate,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                          decoration: BoxDecoration(
                            color: isReadOnly ? const Color(0xFFF5F7FA) : Colors.white,
                            border: Border.all(color: const Color(0xFFE0E0E0)),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${_effectiveDate.year}년 ${_effectiveDate.month}월 ${_effectiveDate.day}일',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: isReadOnly ? Colors.black54 : Colors.black),
                              ),
                              Icon(Icons.calendar_today, color: isReadOnly ? Colors.black26 : Colors.black54, size: 20),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '* 서류가 교부되면 해당 일자부터 자동으로 일할 계산됩니다.',
                        style: TextStyle(fontSize: 11, color: Color(0xFF1565C0)),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),
                
                // Signatures
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildSignatureBox('사업주', doc.bossSignatureUrl),
                    _buildSignatureBox('근로자', doc.signatureUrl),
                  ],
                ),
                
                const SizedBox(height: 24),
                
                // Actions based on status
                if (doc.status == 'draft' || doc.status == 'ready')
                  FilledButton.icon(
                    icon: const Icon(Icons.person_outline),
                    onPressed: _isLoading ? null : () => _handleBossSignature(doc),
                    label: Text(_isLoading ? '처리 중...' : '작성 완료 및 사장님 서명'),
                    style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
                  ),
                if (doc.status == 'boss_signed')
                  FilledButton.icon(
                    icon: const Icon(Icons.draw_rounded),
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF34C759), minimumSize: const Size(double.infinity, 50)),
                    onPressed: _isLoading ? null : () => _handleWorkerSignature(doc),
                    label: Text(_isLoading ? '처리 중...' : '근로자 확인 및 서명 (대면)'),
                  ),
                if (doc.status == 'signed')
                  FilledButton.icon(
                    icon: const Icon(Icons.send_rounded),
                    style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
                    onPressed: _isLoading ? null : () => _handleIssuance(doc),
                    label: Text(_isLoading ? '처리 중...' : '최종 적용 및 교부하기'),
                  ),
                if (doc.status == 'sent')
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(10)),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle, color: Color(0xFF34C759), size: 24),
                        SizedBox(width: 8),
                        Text('서류 교부가 완료되었습니다.', style: TextStyle(color: Color(0xFF2E7D32), fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  
                const SizedBox(height: 40),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSignatureBox(String label, String? imageUrl) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF888888))),
        const SizedBox(height: 8),
        Container(
          width: 140,
          height: 80,
          decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE5E5EA)), borderRadius: BorderRadius.circular(10), color: Colors.white),
          child: imageUrl != null
              ? ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.network(imageUrl, fit: BoxFit.contain))
              : const Center(child: Text('서명 전', style: TextStyle(color: Color(0xFFBBBBBB)))),
        ),
      ],
    );
  }
}
