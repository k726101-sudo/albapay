import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_logic/shared_logic.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:share_plus/share_plus.dart';

import '../models/store_info.dart';
import '../models/worker.dart';
import '../services/invitation_service.dart';
import '../utils/pdf/pdf_generator_service.dart';
import 'documents/signature_pad_screen.dart';

class ContractPage extends StatefulWidget {
  const ContractPage({
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
  State<ContractPage> createState() => _ContractPageState();
}

class _ContractPageState extends State<ContractPage> {
  final _jobDetailController = TextEditingController();
  final _insuranceController = TextEditingController();
  final DatabaseService _dbService = DatabaseService();
  bool _isLoading = false;

  @override
  void dispose() {
    _jobDetailController.dispose();
    _insuranceController.dispose();
    super.dispose();
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
        builder: (_) => SignaturePadScreen(title: '${doc.title} 사장님 서명'),
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

      await _updateDocumentStatus(
        doc: doc,
        status: 'boss_signed',
        bossSignatureUrl: downloadUrl,
        bossSignatureMetadata: metadata,
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
        builder: (_) => SignaturePadScreen(title: '${widget.worker.name}님 서명 (대면)'),
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

  Map<String, dynamic> _buildContractData(Worker worker, StoreInfo? store) {
    // 요일별 근무 시간 맵 생성 (일=0, 월=1, ..., 토=6)
    final workSchedule = <String, Map<String, String>>{};
    const dayLabels = ['일요일', '월요일', '화요일', '수요일', '목요일', '금요일', '토요일'];
    
    // 기본적으로는 모든 근무 요일에 동일한 출퇴근/휴게 시간을 적용
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
        'accidental': true, // 산재는 무조건 가입 대상
        'health': worker.deductHealthInsurance,
        'national': worker.deductNationalPension,
      },
      'workSchedule': workSchedule,
    };
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

      // 3. 알바생에게 알림 전송
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
    final baseUrl = 'https://standard-albapay.web.app'; // 실제 운영 URL
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
          return Scaffold(appBar: AppBar(title: const Text('계약서 조회 중')), body: const Center(child: CircularProgressIndicator()));
        }

        final store = Hive.box<StoreInfo>('store').get('current');
        final worker = widget.worker;
        final prescribedHoursPerDay = (worker.weeklyHours / (worker.workDays.isEmpty ? 1 : worker.workDays.length)).toStringAsFixed(1);

        return Scaffold(
          backgroundColor: const Color(0xFFF2F2F7),
          appBar: AppBar(
            backgroundColor: const Color(0xFF1a1a2e),
            title: const Text('근로계약서', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w500)),
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildContractSection('사업장 정보', [
                _buildContractRow('상호명', _readonlyValue(store?.storeName ?? '-')),
                _buildContractRow('사업장 주소', _readonlyValue(store?.address ?? '-')),
                _buildContractRow('대표자', _readonlyValue(store?.ownerName ?? '-')),
                _buildContractRow('연락처', _readonlyValue(store?.phone ?? '-')),
              ]),
              _buildContractSection('근로자 정보', [
                _buildContractRow('성명', _readonlyValue(worker.name)),
                _buildContractRow('연락처', _readonlyValue(worker.phone)),
                _buildContractRow('생년월일', _readonlyValue(worker.birthDate)),
              ]),
              _buildContractSection('계약 기간', [
                _buildContractRow('입사일', _readonlyValue(worker.startDate)),
                _buildContractRow('계약 종료일', _readonlyValue(worker.endDate ?? '기간의 정함이 없음')),
              ]),
              _buildContractSection('근무 조건', [
                _buildContractRow('근무 장소', _readonlyValue(store?.address ?? '-')),
                _buildContractRow('소정근로시간', _readonlyValue('$prescribedHoursPerDay시간')),
                _buildContractRow('근무 요일', _readonlyValue(_formatWorkDays(worker.workDays))),
                _buildContractRow('주휴일', _readonlyValue(_weeklyHolidayText(worker))),
                _buildContractRow('출퇴근 시간', _readonlyValue(_contractCommuteTimeText(worker))),
                _buildContractRow('휴게 시간', _breakTimeContractValue(worker)),
              ]),
              _buildContractSection('임금', [
                _buildContractRow('시급', _readonlyValue('${worker.hourlyWage.toStringAsFixed(0)}원')),
                _buildContractRow('임금 지급일', _readonlyValue('매월 ${store?.payDay ?? 10}일')),
              ]),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                child: Text('현재 상태: ${_getStatusLabel(doc.status)}', style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 16),
              _buildContractActions(doc),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildSignatureBox('사업주', doc.bossSignatureUrl),
                  _buildSignatureBox('근로자', doc.signatureUrl),
                ],
              ),
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
      case 'signed': return '서명 완료';
      case 'sent': return '교부 완료';
      default: return status;
    }
  }

  Widget _buildContractActions(LaborDocument doc) {
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
        if (status == 'sent')
          OutlinedButton.icon(
            icon: const Icon(Icons.share_rounded),
            onPressed: () => _shareDocumentLink(doc),
            label: const Text('서류 다시 공유하기 (전송)'),
          ),
      ],
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

  // 기존 헬퍼 메서드 유지
  Widget _buildContractSection(String title, List<Widget> children) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE5E5EA), width: 0.5)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        ...children,
      ]),
    );
  }

  Widget _buildContractRow(String label, Widget value) {
    return Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 100, child: Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF666666)))),
      Expanded(child: value),
    ]));
  }

  Widget _readonlyValue(String value) {
    return Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500));
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

  String _contractCommuteTimeText(Worker worker) {
    final wd = _formatWorkDays(worker.workDays);
    final start = worker.checkInTime;
    final end = worker.checkOutTime;
    return '$wd $start~$end';
  }

  Widget _breakTimeContractValue(Worker worker) {
    final minutes = worker.breakMinutes.toInt();
    if (minutes <= 0) return const Text('없음', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500));
    return Text('$minutes분', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500));
  }
}
