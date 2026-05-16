import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_logic/shared_logic.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
        if (bossSignatureUrl != null) 'bossSignatureUrl': bossSignatureUrl,
        if (bossSignatureMetadata != null) 'bossSignatureMetadata': bossSignatureMetadata,
        if (workerSignatureUrl != null) 'signatureUrl': workerSignatureUrl,
        if (workerSignatureMetadata != null) 'signatureMetadata': workerSignatureMetadata,
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
      'isPaidBreak': worker.isPaidBreak,
      'workDaysInfo': _formatWorkDays(worker.workDays),
      'weeklyHoliday': _weeklyHolidayText(worker),
      'wageType': worker.wageType,
      'hourlyWage': worker.hourlyWage.toStringAsFixed(0),
      'monthlyWage': worker.monthlyWage.toStringAsFixed(0),
      // 월급제 상세 데이터
      'fixedOvertimeHours': worker.fixedOvertimeHours.floor(),
      'fixedOvertimePay': worker.fixedOvertimeHours > 0 && worker.hourlyWage > 0
          ? (worker.fixedOvertimeHours.floor() * worker.hourlyWage * 1.5).round()
          : 0,
      'sRefHours': (worker.weeklyHours * 4.345 +
          (worker.weeklyHours >= 15 ? (worker.weeklyHours / 40.0 * 8.0 * 4.345) : 0)).round(),
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
      final newDataJson = jsonEncode(contractData);
      final newHash = SecurityMetadataHelper.generateDocumentHash(
        type: doc.type.name,
        staffId: doc.staffId,
        content: doc.content,
        dataJson: newDataJson,
        createdAt: doc.createdAt.toIso8601String(),
      );

      await FirebaseFirestore.instance
          .collection('stores')
          .doc(widget.storeId)
          .collection('documents')
          .doc(doc.id)
          .update({
        'dataJson': newDataJson,
        'documentHash': newHash,
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
      
      // 4. 교부 완료 안내
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ 서류가 교부되었습니다. 알바생 앱으로 알림이 전송됩니다.'),
          duration: Duration(seconds: 3),
        ),
      );

    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('교부 처리 실패: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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
                child: doc.type == DocumentType.wageStatement && doc.dataJson != null
                    ? _buildWageStatementUI(doc.dataJson!)
                    : Text(
                        doc.content.isEmpty ? '내용이 없습니다.' : doc.content,
                        style: const TextStyle(fontSize: 14, height: 1.45),
                      ),
              ),
              // ★ 서명란 표시
              if (doc.bossSignatureUrl != null || doc.signatureUrl != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE5E5EA), width: 0.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('서명', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildSignatureBox('사업주', doc.bossSignatureUrl),
                          _buildSignatureBox('근로자', doc.signatureUrl),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
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
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle, color: Color(0xFF34C759), size: 20),
                    SizedBox(width: 8),
                    Text('교부 완료 — 알바생 앱으로 알림 전송됨', 
                      style: TextStyle(color: Color(0xFF2E7D32), fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
      ],
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
      return Text('명세서 데이터를 불러올 수 없습니다.\nError: $e\nData: $dataJson', style: const TextStyle(color: Colors.red));
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
