import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_logic/shared_logic.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/store_info.dart';
import '../models/worker.dart';

import '../utils/pdf/pdf_generator_service.dart';
import 'documents/signature_pad_screen.dart';

class ContractPage extends StatefulWidget {
  const ContractPage({
    super.key,
    required this.worker,
    required this.documentId,
    required this.storeId,
    this.initialDocument,
    this.isWizardMode = false,
  });

  final Worker worker;
  final String documentId;
  final String storeId;
  final LaborDocument? initialDocument;
  final bool isWizardMode;

  @override
  State<ContractPage> createState() => _ContractPageState();
}

class _ContractPageState extends State<ContractPage> {
  final _jobDetailController = TextEditingController();
  final _insuranceController = TextEditingController();
  final DatabaseService _dbService = DatabaseService();
  bool _isLoading = false;
  int _wagePaymentDay = 10;

  @override
  void initState() {
    super.initState();
    final store = Hive.box<StoreInfo>('store').get('current');
    if (widget.initialDocument?.dataJson != null) {
      try {
        final data = jsonDecode(widget.initialDocument!.dataJson!);
        _wagePaymentDay = int.tryParse(data['wagePaymentDay']?.toString() ?? '') ?? (store?.payDay ?? 10);
      } catch (_) {
        _wagePaymentDay = store?.payDay ?? 10;
      }
    } else {
      _wagePaymentDay = store?.payDay ?? 10;
    }
  }

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
      'wagePaymentDay': '$_wagePaymentDay',
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

      // 3. 알바생에게 알림 전송
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
              _buildContractSection('임금', (() {
                if (worker.wageType == 'monthly') {
                  // ── 월급제 임금 구성 상세 ──
                  final mealAmt = worker.allowances
                      .where((a) => a.label == '식대' || a.label == '식비')
                      .fold<double>(0, (sum, a) => sum + a.amount);

                  // S_Ref 계산 (직원별 소정근로시간 반영)
                  final weeklyH = worker.weeklyHours > 0 ? worker.weeklyHours : 40.0;
                  final workDaysPerWeek = worker.workDays.isNotEmpty
                      ? worker.workDays.length.toDouble()
                      : 5.0;
                  final dailyH = weeklyH / workDaysPerWeek;
                  final weeklyHolidayH = weeklyH >= 15 ? dailyH : 0.0;
                  final sRef = ((weeklyH + weeklyHolidayH) * 4.345).ceilToDouble();

                  // 통상시급 = (기본급 + 식대) / S_Ref
                  final ordinaryHourly = sRef > 0
                      ? (worker.monthlyWage + mealAmt) / sRef
                      : 0.0;

                  // 주휴수당 역산 (기본급에 포함된 주휴수당 금액)
                  // 주휴시간 = 1일소정근로시간 × 4.345주
                  final weeklyHolidayHoursPerMonth = weeklyHolidayH * 4.345;
                  final weeklyHolidayPayAmount = ordinaryHourly * weeklyHolidayHoursPerMonth;

                  // 고정연장수당
                  final fixedOTPay = worker.fixedOvertimePay > 0
                      ? worker.fixedOvertimePay
                      : (worker.fixedOvertimeHours > 0 && ordinaryHourly > 0
                          ? worker.fixedOvertimeHours * ordinaryHourly * 1.5
                          : 0.0);

                  final wageTotal = worker.monthlyWage + mealAmt + fixedOTPay;

                  // 사업장 규모
                  final isFiveOrMore = store?.isFiveOrMore ?? false;

                  return <Widget>[
                    _buildContractRow('급여 형태', _readonlyValue('월급제')),
                    _buildContractRow('기본급', _readonlyValue(
                        '${_formatContractMoney(worker.monthlyWage.round())}원')),
                    // ★ 주휴수당 포함 안내
                    if (weeklyH >= 15)
                      Padding(
                        padding: const EdgeInsets.only(left: 12, bottom: 8),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0F7FF),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF1A73E8).withOpacity(0.2)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('📌 주휴수당 포함 내역',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1A73E8))),
                              const SizedBox(height: 4),
                              Text(
                                '주휴시간: ${weeklyHolidayH.toStringAsFixed(1)}h/주 × 4.345주 = ${weeklyHolidayHoursPerMonth.toStringAsFixed(1)}h/월\n'
                                '주휴수당(포함): ${_formatContractMoney(weeklyHolidayPayAmount.round())}원 (기본급에 포함)',
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade700, height: 1.5),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (mealAmt > 0)
                      _buildContractRow('식대(비과세)', _readonlyValue(
                          '${_formatContractMoney(mealAmt.round())}원')),
                    if (worker.fixedOvertimeHours > 0) ...[
                      _buildContractRow('고정연장수당', _readonlyValue(
                          '${_formatContractMoney(fixedOTPay.round())}원 (월 ${worker.fixedOvertimeHours.toStringAsFixed(1)}시간분)')),
                      Padding(
                        padding: const EdgeInsets.only(left: 12, bottom: 8),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF8E1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFFF9800).withOpacity(0.3)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('📋 고정연장수당 특약',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFE65100))),
                              const SizedBox(height: 4),
                              Text(
                                isFiveOrMore
                                    ? '• 5인 이상 사업장 (근로기준법 제56조 적용)\n'
                                      '• 통상시급 ${_formatContractMoney(ordinaryHourly.round())}원 × 1.5배 = ${_formatContractMoney((ordinaryHourly * 1.5).round())}원/h\n'
                                      '• 월 ${worker.fixedOvertimeHours.toStringAsFixed(1)}h 이하: 전액 지급 (차액 미공제)\n'
                                      '• 초과 시: 초과분 × 1.5배 가산 별도 지급\n'
                                      '• 휴일/휴무일 근무: 별도 지급 (고정연장시간에서 차감 불가)'
                                    : '• 5인 미만 사업장 (가산수당 미적용)\n'
                                      '• 통상시급 ${_formatContractMoney(ordinaryHourly.round())}원 기준\n'
                                      '• 월 ${worker.fixedOvertimeHours.toStringAsFixed(1)}h 이하: 전액 지급 (차액 미공제)\n'
                                      '• 초과 시: 초과분 × 통상시급 별도 지급\n'
                                      '• 휴일/휴무일 근무: 별도 지급 (고정연장시간에서 차감 불가)',
                                style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700, height: 1.5),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const Divider(height: 16),
                    _buildContractRow('합계', Text(
                      '${_formatContractMoney(wageTotal.round())}원',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black),
                    )),
                    _buildContractRow('통상시급', Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${_formatContractMoney(ordinaryHourly.round())}원',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(
                          '└ (기본급+식대) ÷ 월 ${sRef.toInt()}시간 = ${_formatContractMoney(ordinaryHourly.round())}원',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                        ),
                      ],
                    )),
                    // ★ 평균 주수 합의 안내
                    Padding(
                      padding: const EdgeInsets.only(left: 12, top: 4, bottom: 8),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F5F5),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: const Text(
                          '※ 본 급여는 1개월 평균 주수(4.345주) 기준으로 산정됩니다.\n'
                          '결근·지각·조퇴 시 관련 법령에 따라 공제될 수 있습니다.',
                          style: TextStyle(fontSize: 10.5, color: Colors.grey, height: 1.5),
                        ),
                      ),
                    ),
                    _buildContractRow('임금 지급일', _buildEditablePayDay(doc)),
                  ];
                } else {
                  return <Widget>[
                    _buildContractRow('급여 형태', _readonlyValue('시급제')),
                    _buildContractRow('시급', _readonlyValue(
                        '${_formatContractMoney(worker.hourlyWage.round())}원')),
                    _buildContractRow('임금 지급일', _buildEditablePayDay(doc)),
                  ];
                }
              })()),
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
              if (widget.isWizardMode) ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  icon: const Icon(Icons.person_add_alt_1),
                  onPressed: () => Navigator.pop(context),
                  label: const Text('다음: 알바생 초대하기'),
                ),
              ],
            ],
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
    return Text(
      value,
      style: const TextStyle(fontSize: 14, color: Colors.black87, fontWeight: FontWeight.normal),
    );
  }

  Widget _buildEditablePayDay(LaborDocument doc) {
    if (doc.status == 'draft' || doc.status == 'ready') {
      return Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(4),
          color: Colors.white,
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<int>(
            value: _wagePaymentDay,
            isDense: true,
            style: const TextStyle(fontSize: 14, color: Colors.blue),
            icon: const Icon(Icons.arrow_drop_down, color: Colors.blue, size: 20),
            items: List.generate(28, (i) => i + 1)
                .map((d) => DropdownMenuItem<int>(
                      value: d,
                      child: Text('매월 $d일'),
                    ))
                .toList(),
            onChanged: (v) {
              if (v != null) {
                setState(() => _wagePaymentDay = v);
              }
            },
          ),
        ),
      );
    } else {
      return _readonlyValue('매월 $_wagePaymentDay일');
    }
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
    if (worker.workScheduleJson.isNotEmpty) {
      try {
        final List<dynamic> schedules = jsonDecode(worker.workScheduleJson);
        if (schedules.isNotEmpty) {
          final List<String> parts = [];
          for (final group in schedules) {
            final days = (group['days'] as List).cast<int>();
            final wd = _formatWorkDays(days);
            final s = group['start'];
            final e = group['end'];
            parts.add('$wd $s~$e');
          }
          return parts.join('\n');
        }
      } catch (_) {}
    }

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

  String _formatContractMoney(int amount) {
    return amount.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
  }
}
