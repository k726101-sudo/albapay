import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_logic/shared_logic.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:share_plus/share_plus.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../utils/pdf/pdf_generator_service.dart';
import '../../models/worker.dart';
import '../../models/store_info.dart';
import 'signature_pad_screen.dart';

class DocumentContentPage extends StatefulWidget {
  const DocumentContentPage({
    super.key,
    required this.worker,
    required this.documentId,
    required this.storeId,
    this.initialDocument,
  });

  final Worker worker;
  final String documentId;
  final String storeId;
  final LaborDocument? initialDocument;

  @override
  State<DocumentContentPage> createState() => _DocumentContentPageState();
}

class _DocumentContentPageState extends State<DocumentContentPage> {
  bool _isLoading = false;
  final DatabaseService _dbService = DatabaseService();

  @override
  void initState() {
    super.initState();
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
  }) async {
    try {
      await FirebaseFirestore.instance
          .collection('stores')
          .doc(widget.storeId)
          .collection('documents')
          .doc(doc.id)
          .update({
        'status': status,
        if (signedAt != null) 'signedAt': signedAt.toIso8601String(),
        if (sentAt != null) 'sentAt': sentAt.toIso8601String(),
        'bossSignatureUrl': ?bossSignatureUrl,
        'bossSignatureMetadata': ?bossSignatureMetadata,
        'signatureUrl': ?workerSignatureUrl,
        'signatureMetadata': ?workerSignatureMetadata,
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
    }
  }

  Future<void> _handleBossSignature(LaborDocument doc) async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => SignaturePadScreen(title: '${doc.title} 서명'),
      ),
    );

    if (result == null) return;

    final signatureBytes = result['signatureBytes'] as Uint8List?;
    final metadata = result['metadata'] as Map<String, dynamic>;

    if (signatureBytes == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('서명 데이터가 유효하지 않습니다.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final authUid = FirebaseAuth.instance.currentUser?.uid;
      if (authUid == null) throw '인증 정보가 없습니다.';
      // 격리된 경로 규칙: signatures/{userId}/{filename}
      final storageRef = FirebaseStorage.instance.ref().child('signatures/$authUid/${doc.id}_boss.png');
      
      final uploadTask = await storageRef.putData(
        signatureBytes,
        SettableMetadata(contentType: 'image/png'),
      );
      final downloadUrl = await uploadTask.ref.getDownloadURL();

      await _updateDocumentStatus(
        doc: doc,
        status: 'boss_signed',
        bossSignatureUrl: downloadUrl,
        bossSignatureMetadata: metadata,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('서명 업로드 실패: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleWorkerSignature(LaborDocument doc) async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => SignaturePadScreen(title: '${widget.worker.name}님 서명 (대면)'),
      ),
    );

    if (result == null) return;

    final signatureBytes = result['signatureBytes'] as Uint8List?;
    final metadata = result['metadata'] as Map<String, dynamic>;

    if (signatureBytes == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('서명 데이터가 유효하지 않습니다.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final authUid = FirebaseAuth.instance.currentUser?.uid;
      if (authUid == null) throw '인증 정보가 없습니다.';
      // 사장님 앱에서 받는 알바생 서명도 업로드 주체인 사장님 폴더에 격리 보관 (signatures/{userId}/...)
      final storageRef = FirebaseStorage.instance.ref().child('signatures/$authUid/${doc.id}_worker_f2f.png');
      
      final uploadTask = await storageRef.putData(
        signatureBytes,
        SettableMetadata(contentType: 'image/png'),
      );
      final downloadUrl = await uploadTask.ref.getDownloadURL();

      await _updateDocumentStatus(
        doc: doc,
        status: 'signed',
        signedAt: AppClock.now(),
        workerSignatureUrl: downloadUrl,
        workerSignatureMetadata: metadata,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('근로자 서명 업로드 실패: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Map<String, dynamic> _buildContractData(Worker worker, StoreInfo? store) {
    // 요일별 근무 시간 맵 생성 (일=0, 월=1, ..., 토=6)
    final workSchedule = <String, Map<String, String>>{};
    const dayLabels = ['일요일', '월요일', '화요일', '수요일', '목요일', '금요일', '토요일'];
    
    for (var day in worker.workDays) {
      final label = dayLabels[day % 7];
      workSchedule[label] = {
        'start': worker.checkInTime,
        'end': worker.checkOutTime,
        'break': '${worker.breakStartTime} ~ ${worker.breakEndTime}',
      };
    }

    return {
      'storeName': store?.storeName ?? '',
      'storeAddress': store?.address ?? '',
      'ownerName': store?.ownerName ?? '',
      'storePhone': store?.phone ?? '',
      'workerName': worker.name,
      'workerAddress': '', 
      'workerPhone': worker.phone,
      'startDate': worker.startDate,
      'endDate': worker.endDate ?? '기한의 정함이 없음',
      'startTime': worker.checkInTime,
      'endTime': worker.checkOutTime,
      'breakStart': worker.breakStartTime,
      'breakEnd': worker.breakEndTime,
      'workDaysInfo': _formatWorkDays(worker.workDays),
      'weeklyHoliday': _weeklyHolidayText(worker),
      'hourlyWage': worker.hourlyWage.toStringAsFixed(0),
      'wagePaymentDay': '${store?.payDay ?? 10}',
      'paymentMethod': '통장입금',
      'insurance': {
        'employment': worker.deductEmploymentInsurance,
        'accidental': true, 
        'health': worker.deductHealthInsurance,
        'national': worker.deductNationalPension,
      },
      'workSchedule': workSchedule,
    };
  }

  String _formatWorkDays(List<int> days) {
    const labels = ['일', '월', '화', '수', '목', '금', '토'];
    final list = [...days]..sort();
    return list.map((d) => labels[(d % 7)]).join(', ');
  }

  String _weeklyHolidayText(Worker worker) {
    const labels = ['일', '월', '화', '수', '목', '금', '토'];
    final day = (worker.weeklyHolidayDay >= 0 && worker.weeklyHolidayDay < 7) ? labels[worker.weeklyHolidayDay] : '';
    final dayStr = day.isEmpty ? "주 1회" : "$day요일";
    if (!worker.weeklyHolidayPay) return '[무급] $dayStr';
    return '[유급] $dayStr';
  }

  Future<void> _handleIssuance(LaborDocument doc) async {
    setState(() => _isLoading = true);
    try {
      final store = Hive.box<StoreInfo>('store').get('current');
      final contractData = _buildContractData(widget.worker, store);

      // 1. PDF 생성 및 스토리지 업로드 (DB 상태 업데이트 포함)
      await PdfGeneratorService.generateAndUploadFinalPdf(
        document: doc,
        contractData: contractData,
      );

      // 2. dataJson 업데이트 (히스토리 보존을 위해)
      await FirebaseFirestore.instance
          .collection('stores')
          .doc(widget.storeId)
          .collection('documents')
          .doc(doc.id)
          .update({
        'dataJson': jsonEncode(contractData),
      });

      // 3. 알바생에게 알림 전송 (notificationQueue 적재)
      await _dbService.enqueueWorkerDocumentNotification(
        storeId: widget.storeId,
        workerId: doc.staffId,
        docId: doc.id,
        docTitle: doc.title,
        kind: 'new_document',
      );

      if (!mounted) return;
      
      // 3. 공유 시트 실행
      await _shareDocumentLink(doc);

    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('교부 처리 실패: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _shareDocumentLink(LaborDocument doc) async {
    final baseUrl = 'https://standard-albapay.web.app'; // 실제 운영 URL로 변경 필요
    final shareUrl = '$baseUrl/#/doc-view?id=${doc.id}&storeId=${widget.storeId}';
    
    final message = '[알바급여정석] 근로계약서가 교부되었습니다.\n\n아래 링크를 클릭하여 계약 내용을 확인해 주세요.\n$shareUrl';
    
    final box = context.findRenderObject() as RenderBox?;
    final rect = box != null ? box.localToGlobal(Offset.zero) & box.size : null;

    await SharePlus.instance.share(
      ShareParams(
        text: message,
        title: '${doc.title} 교부',
        sharePositionOrigin: rect,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<LaborDocument?>(
      stream: FirebaseFirestore.instance
          .collection('stores')
          .doc(widget.storeId)
          .collection('documents')
          .doc(widget.documentId)
          .snapshots()
          .map((snap) => snap.exists ? LaborDocument.fromMap(snap.id, snap.data()!) : null),
      initialData: widget.initialDocument,
      builder: (context, snapshot) {
        final doc = snapshot.data;

        if (doc == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('문서 조회 중')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        return Scaffold(
          backgroundColor: const Color(0xFFF2F2F7),
          appBar: AppBar(
            title: Text(doc.title),
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE5E5EA), width: 0.5),
                ),
                child: Text(
                  doc.content,
                  style: const TextStyle(fontSize: 14, height: 1.45),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('현재 상태: ${_getStatusLabel(doc.status)}', 
                  style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 16),
              _buildDocumentActions(doc),
            ],
          ),
        );
      },
    );
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case 'draft': return '작성 초안';
      case 'ready': return '서명 대기 중';
      case 'boss_signed': return '근로자 서명 대기';
      case 'signed': return '서명 완료 (교부 전)';
      case 'sent': return '교부 완료 (전송됨)';
      case 'delivered': return '교부 완료 (알바생 확인)';
      default: return status;
    }
  }

  Widget _buildDocumentActions(LaborDocument doc) {
    final status = doc.status;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (status == 'draft' || status == 'ready')
          FilledButton.icon(
            icon: const Icon(Icons.person_outline),
            onPressed: _isLoading ? null : () => _handleBossSignature(doc),
            label: Text(status == 'draft' ? '작성 완료 및 사장님 서명' : '사장님 서명'),
          ),
        
        if (status == 'boss_signed')
          FilledButton.icon(
            icon: const Icon(Icons.draw_rounded),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF34C759)),
            onPressed: _isLoading ? null : () => _handleWorkerSignature(doc),
            label: const Text('근로자 확인 및 서명 (대면)'),
          ),

        if (status == 'signed')
          FilledButton.icon(
            icon: const Icon(Icons.send_rounded),
            onPressed: _isLoading ? null : () => _handleIssuance(doc),
            label: const Text('서류 교부 완료 (전송)'),
          ),

        if (status == 'sent' || status == 'delivered')
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle, color: status == 'delivered' ? const Color(0xFF34C759) : Colors.orange),
                    const SizedBox(width: 8),
                    Text(status == 'delivered' ? '알바생이 서류를 확인했습니다.' : '서류가 전송되었습니다. (확인 대기)', 
                      style: const TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.share_rounded),
                onPressed: () => _shareDocumentLink(doc),
                label: const Text('서류 다시 공유하기'),
              ),
            ],
          ),
      ],
    );
  }
}
