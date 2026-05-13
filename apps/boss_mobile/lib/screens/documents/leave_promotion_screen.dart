import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_logic/shared_logic.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';


import '../../models/worker.dart';
import '../../utils/pdf/pdf_generator_service.dart';
import 'signature_pad_screen.dart';

/// 연차 사용촉진 통보서 작성 화면 (근로기준법 제61조)
///
/// [step] 1 = 1차 촉진 (연차 사용 시기 지정 요청)
///        2 = 2차 촉진 (사장님 직접 사용 날짜 지정)
class LeavePromotionScreen extends StatefulWidget {
  final LaborDocument document;
  final Worker worker;
  final int step; // 1 or 2

  const LeavePromotionScreen({
    super.key,
    required this.document,
    required this.worker,
    required this.step,
  });

  @override
  State<LeavePromotionScreen> createState() => _LeavePromotionScreenState();
}

class _LeavePromotionScreenState extends State<LeavePromotionScreen> {
  bool _isLoading = false;
  late Worker _worker;

  // 촉진 대상 배치 선택
  List<LeavePromotionStatus> _promotionTargets = [];
  LeavePromotionStatus? _selectedTarget;

  // 2차 촉진: 사장님이 지정하는 사용 날짜들
  final List<DateTime> _designatedDates = [];

  // 매장 정보
  String _storeName = '';
  String _ownerName = '';

  @override
  void initState() {
    super.initState();
    _worker = widget.worker;
    _loadStoreInfo();
    _loadPromotionTargets();
  }

  Future<void> _loadStoreInfo() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('stores')
          .doc(widget.document.storeId)
          .get();
      final data = snap.data() ?? {};
      setState(() {
        _storeName = data['storeName']?.toString() ?? '';
        _ownerName = data['ownerName']?.toString() ?? '';
      });
    } catch (_) {}
  }

  void _loadPromotionTargets() {
    // Worker의 leavePromotionLogsJson에서 촉진 대상 추출
    final logs = _parsePromotionLogs();

    // 촉진 가능한 배치 필터링
    // 1차: pending 상태인 배치
    // 2차: first_sent 또는 awaiting_plan 상태인 배치
    setState(() {
      if (widget.step == 1) {
        _promotionTargets = logs.where((p) => p.status == 'pending').toList();
      } else {
        _promotionTargets = logs
            .where((p) =>
                p.status == 'first_sent' || p.status == 'awaiting_plan')
            .toList();
      }
      if (_promotionTargets.isNotEmpty) {
        _selectedTarget = _promotionTargets.first;
      }
    });
  }

  List<LeavePromotionStatus> _parsePromotionLogs() {
    if (_worker.leavePromotionLogsJson.isEmpty) return [];
    try {
      final list = jsonDecode(_worker.leavePromotionLogsJson) as List;
      return list
          .map((e) =>
              LeavePromotionStatus.fromMap(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _fmtDateKr(DateTime d) => '${d.year}년 ${d.month}월 ${d.day}일';

  Future<void> _addDesignatedDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: _selectedTarget?.batchExpiryDate ??
          DateTime.now().add(const Duration(days: 365)),
      helpText: '연차 사용 날짜를 지정하세요',
    );
    if (picked != null && !_designatedDates.any((d) => d == picked)) {
      setState(() => _designatedDates.add(picked));
    }
  }

  Future<void> _handleSignAndIssue() async {
    if (_selectedTarget == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('촉진 대상 연차 배치를 선택하세요.')),
      );
      return;
    }

    if (widget.step == 2 && _designatedDates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('연차 사용 날짜를 1개 이상 지정하세요.')),
      );
      return;
    }

    // 서명 화면으로 이동
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => SignaturePadScreen(
          title: widget.step == 1
              ? '연차 사용촉진 1차 통보 서명'
              : '연차 사용촉진 2차 통보 서명',
        ),
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

      // 서명 업로드
      final sigRef = FirebaseStorage.instance
          .ref()
          .child('signatures/$authUid/${widget.document.id}_boss.png');
      final uploadTask = await sigRef.putData(
          signatureBytes, SettableMetadata(contentType: 'image/png'));
      final sigUrl = await uploadTask.ref.getDownloadURL();

      final target = _selectedTarget!;
      final now = AppClock.now();
      final designatedDateStrs =
          _designatedDates.map((d) => _fmtDate(d)).toList();

      // 구조화된 데이터
      final dataMap = {
        'step': widget.step,
        'batchGrantDate': target.batchGrantDate.toIso8601String(),
        'batchExpiryDate': target.batchExpiryDate.toIso8601String(),
        'unusedDays': target.unusedDays,
        'isPreAnniversary': target.isPreAnniversary,
        'firstNoticeDeadline': target.firstNoticeDeadline.toIso8601String(),
        'secondNoticeDeadline': target.secondNoticeDeadline.toIso8601String(),
        if (widget.step == 2) 'designatedDates': designatedDateStrs,
      };

      // 텍스트 콘텐츠 생성
      final templateData = {
        'staffName': _worker.name,
        'storeName': _storeName,
        'ownerName': _ownerName,
        'date': _fmtDateKr(now),
        'leaveType': target.leaveTypeLabel,
        'legalBasis': target.isPreAnniversary
            ? '근로기준법 제61조 제2항'
            : '근로기준법 제61조 제1항',
        'grantDate': _fmtDateKr(target.batchGrantDate),
        'expiryDate': _fmtDateKr(target.batchExpiryDate),
        'unusedDays': target.unusedDays.toStringAsFixed(1),
        'deadlineType': target.deadlineLabel,
        if (widget.step == 2)
          'designatedDates':
              designatedDateStrs.map((d) => '  • $d').join('\n'),
      };
      final content =
          DocumentTemplates.getLeavePromotionNotice(widget.step, templateData);

      // 무결성 해시
      final docHash = SecurityMetadataHelper.generateDocumentHash(
        type: widget.document.type.name,
        staffId: widget.document.staffId,
        content: content,
        dataJson: jsonEncode(dataMap),
        createdAt: widget.document.createdAt.toIso8601String(),
      );

      // PDF 생성
      final pdfBytes = await PdfGeneratorService.generateLeavePromotionNotice(
        step: widget.step,
        workerName: _worker.name,
        unusedDays: target.unusedDays,
        batchGrantDate: target.batchGrantDate,
        batchExpiryDate: target.batchExpiryDate,
        isPreAnniversary: target.isPreAnniversary,
        designatedDates: designatedDateStrs,
        auditHash: docHash,
      );

      // PDF 업로드
      final pdfRef = FirebaseStorage.instance
          .ref()
          .child('stores')
          .child(widget.document.storeId)
          .child('documents')
          .child('${widget.document.id}.pdf');
      final pdfUpload = await pdfRef.putData(
          pdfBytes, SettableMetadata(contentType: 'application/pdf'));
      final pdfUrl = await pdfUpload.ref.getDownloadURL();

      // Firestore 문서 업데이트 (서명 완료 + 교부 = sent)
      await FirebaseFirestore.instance
          .collection('stores')
          .doc(widget.document.storeId)
          .collection('documents')
          .doc(widget.document.id)
          .update({
        'status': 'sent',
        'content': content,
        'dataJson': jsonEncode(dataMap),
        'bossSignatureUrl': sigUrl,
        'bossSignatureMetadata': metadata,
        'signedAt': now.toIso8601String(),
        'sentAt': now.toIso8601String(),
        'pdfUrl': pdfUrl,
        'documentHash': docHash,
      });

      // Worker의 leavePromotionLogsJson 업데이트
      await _updateWorkerPromotionLog(target, now);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.step == 1
                ? '✅ 1차 촉진 통보서가 작성·교부되었습니다.'
                : '✅ 2차 촉진 통보서가 작성·교부되었습니다.',
          ),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('통보서 발급 실패: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _updateWorkerPromotionLog(
      LeavePromotionStatus target, DateTime now) async {
    // 기존 로그 파싱
    final logs = _parsePromotionLogs();
    final updatedLogs = logs.map((log) {
      if (log.batchGrantDate.year == target.batchGrantDate.year &&
          log.batchGrantDate.month == target.batchGrantDate.month &&
          log.batchGrantDate.day == target.batchGrantDate.day) {
        if (widget.step == 1) {
          return log.copyWith(
            firstNoticeDate: now.toIso8601String(),
            firstNoticeDocId: widget.document.id,
            status: 'first_sent',
          );
        } else {
          return log.copyWith(
            secondNoticeDate: now.toIso8601String(),
            secondNoticeDocId: widget.document.id,
            designatedDates:
                _designatedDates.map((d) => _fmtDate(d)).toList(),
            status: 'completed',
          );
        }
      }
      return log;
    }).toList();

    final updatedJson =
        jsonEncode(updatedLogs.map((l) => l.toMap()).toList());

    // Hive 로컬 업데이트
    _worker.leavePromotionLogsJson = updatedJson;
    await _worker.save();

    // Firestore 업데이트
    try {
      await FirebaseFirestore.instance
          .collection('stores')
          .doc(widget.document.storeId)
          .collection('workers')
          .doc(_worker.firebaseId ?? _worker.id)
          .update({'leavePromotionLogsJson': updatedJson});
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final stepLabel = widget.step == 1 ? '1차 촉진 통보서' : '2차 촉진 통보서';

    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: Text('연차 사용촉진 $stepLabel'),
        backgroundColor: const Color(0xFF1A1A2E),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('통보서 생성 및 교부 중...',
                      style: TextStyle(color: Colors.grey)),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 법적 근거 안내
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.gavel,
                                color: Colors.deepOrange, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              widget.step == 1
                                  ? '연차 사용 시기 지정 요청 (1차 촉진)'
                                  : '연차 사용 시기 지정 통보 (2차 촉진)',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.deepOrange,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.step == 1
                              ? '근로기준법 제61조에 따라 미사용 연차에 대해 직원에게 사용 시기를 '
                                  '정하도록 서면 요청합니다. 직원은 10일 이내 사용 계획을 회신해야 합니다.'
                              : '1차 촉진 후 직원이 10일 이내 사용 시기를 제출하지 않은 경우, '
                                  '사장님이 직접 연차 사용 날짜를 지정하여 서면 통보합니다.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 대상 직원
                  _infoRow('대상 직원', _worker.name),
                  const Divider(),

                  // 촉진 대상 선택
                  const Text(
                    '촉진 대상 연차 배치',
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  if (_promotionTargets.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          widget.step == 1
                              ? '현재 촉진 대상 연차 배치가 없습니다.\n'
                                  '급여 명세서의 연차 사용촉진 현황에서\n'
                                  '"⏳ 촉진 미이행" 상태인 배치가 있어야 합니다.'
                              : '1차 촉진이 완료된 배치가 없습니다.\n'
                                  '먼저 1차 촉진 통보서를 발행하세요.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.grey.shade600, fontSize: 13),
                        ),
                      ),
                    )
                  else
                    ..._promotionTargets.map((target) {
                      final isSelected = _selectedTarget == target;
                      return GestureDetector(
                        onTap: () =>
                            setState(() => _selectedTarget = target),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.deepOrange.shade50
                                : Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected
                                  ? Colors.deepOrange
                                  : Colors.grey.shade300,
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    target.leaveTypeLabel,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13),
                                  ),
                                  if (isSelected)
                                    const Icon(Icons.check_circle,
                                        color: Colors.deepOrange,
                                        size: 20),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '미사용: ${target.unusedDays.toStringAsFixed(1)}일',
                                style: const TextStyle(fontSize: 12),
                              ),
                              Text(
                                '발생일: ${_fmtDate(target.batchGrantDate)} | 소멸일: ${_fmtDate(target.batchExpiryDate)}',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade600),
                              ),
                              Text(
                                '1차 기한: ${_fmtDate(target.firstNoticeDeadline)} | 2차 기한: ${_fmtDate(target.secondNoticeDeadline)}',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade600),
                              ),
                              if (target.firstNoticeDate != null)
                                Text(
                                  '✅ 1차 통보 완료: ${target.firstNoticeDate}',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.green.shade700),
                                ),
                            ],
                          ),
                        ),
                      );
                    }),

                  // 2차 촉진: 사용 날짜 지정
                  if (widget.step == 2 && _selectedTarget != null) ...[
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '연차 사용 날짜 지정',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                        TextButton.icon(
                          onPressed: _addDesignatedDate,
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('날짜 추가'),
                        ),
                      ],
                    ),
                    if (_designatedDates.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          '직원이 사용할 연차 날짜를 지정해주세요.',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade600),
                        ),
                      )
                    else
                      ..._designatedDates.asMap().entries.map((entry) {
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.calendar_today,
                              size: 18, color: Colors.deepOrange),
                          title: Text(_fmtDateKr(entry.value),
                              style: const TextStyle(fontSize: 13)),
                          trailing: IconButton(
                            icon: const Icon(Icons.close,
                                size: 18, color: Colors.red),
                            onPressed: () => setState(
                                () => _designatedDates.removeAt(entry.key)),
                          ),
                        );
                      }),
                  ],

                  const SizedBox(height: 30),

                  // 서명 및 교부 버튼
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton.icon(
                      onPressed: _promotionTargets.isEmpty
                          ? null
                          : _handleSignAndIssue,
                      icon: const Icon(Icons.send_rounded),
                      label: Text(
                        '서명 후 알바앱으로 교부',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepOrange,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        disabledBackgroundColor: Colors.grey.shade300,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 안내 문구
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline,
                            size: 16, color: Colors.blue.shade600),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '서명 후 PDF가 자동 생성되어 알바생 앱으로 즉시 전송됩니다.\n'
                            '교부 완료 시 촉진 이력이 자동으로 기록되며, '
                            '급여 명세서의 사용촉진 현황에 반영됩니다.',
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.blue.shade700,
                                height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
          Text(value,
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
