import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_logic/shared_logic.dart';
import 'package:uuid/uuid.dart';
import 'package:printing/printing.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../models/store_info.dart';
import '../../models/worker.dart';
import '../../utils/pdf/pdf_generator_service.dart';
import '../contract_page.dart';
import 'night_consent_screen.dart';
import 'worker_record_screen.dart';
import 'hiring_checklist_screen.dart';
import 'wage_amendment_screen.dart';
import 'leave_promotion_screen.dart';

class CreateDocumentScreen extends StatefulWidget {
  final Worker worker;
  final String storeId;

  const CreateDocumentScreen({super.key, required this.worker, required this.storeId});

  @override
  State<CreateDocumentScreen> createState() => _CreateDocumentScreenState();
}

class _CreateDocumentScreenState extends State<CreateDocumentScreen> {
  final _dbService = DatabaseService();
  bool _isLoading = false;
  bool _isUltraShort = false;

  @override
  void initState() {
    super.initState();
    _isUltraShort = DocumentCalculator.isUltraShortTime(widget.worker.weeklyHours);
  }

  /// 서류 타입에 따라 Firestore 문서 생성 → 구조화 UI 화면으로 이동
  Future<void> _createAndNavigate(DocumentType docType) async {
    setState(() => _isLoading = true);

    try {
      final docId = const Uuid().v4();
      final now = AppClock.now();
      final String title;

      switch (docType) {
        case DocumentType.contract_full:
        case DocumentType.contract_part:
          title = '표준 근로계약서 - ${widget.worker.name}';
          break;
        case DocumentType.night_consent:
          title = '휴일 및 야간근로 동의서 - ${widget.worker.name}';
          break;
        case DocumentType.worker_record:
          title = '근로자 명부 - ${widget.worker.name}';
          break;
        case DocumentType.checklist:
          title = '채용 체크리스트 - ${widget.worker.name}';
          break;
        case DocumentType.wage_amendment:
          title = '임금 계약 변경서 - ${widget.worker.name}';
          break;
        case DocumentType.minor_consent:
          title = '친권자 동의서 - ${widget.worker.name}';
          break;
        case DocumentType.leave_promotion_first:
          title = '연차 사용촉진 1차 통보서 - ${widget.worker.name}';
          break;
        case DocumentType.leave_promotion_second:
          title = '연차 사용촉진 2차 통보서 - ${widget.worker.name}';
          break;
        default:
          title = '기타 서류 - ${widget.worker.name}';
      }

      String initialContent = '';
      final todayStr = '${now.year}년 ${now.month}월 ${now.day}일';
      final w = widget.worker;

      Map<String, dynamic> storeData = {};
      
      if (docType == DocumentType.contract_full || docType == DocumentType.contract_part) {
        final mealAmt = w.allowances
            .where((a) => a.label == '식대' || a.label == '식비')
            .fold<double>(0, (sum, a) => sum + a.amount);
        final weeklyH = w.weeklyHours > 0 ? w.weeklyHours : 40.0;
        final wdpw = w.workDays.isNotEmpty ? w.workDays.length.toDouble() : 5.0;
        final whH = weeklyH >= 15 ? weeklyH / wdpw : 0.0;
        final sRef = ((weeklyH + whH) * 4.345).ceilToDouble();
        final ordHourly = w.monthlyWage > 0 && sRef > 0
            ? (w.monthlyWage + mealAmt) / sRef
            : w.hourlyWage;
            
        bool isFiveOrMore = false;
        try {
          final storeSnap = await FirebaseFirestore.instance.collection('stores').doc(widget.storeId).get();
          storeData = storeSnap.data() ?? {};
          isFiveOrMore = storeData['isFiveOrMore'] as bool? ?? false;
        } catch (_) {}
        final otMult = isFiveOrMore ? 1.5 : 1.0;
        final fOTPay = w.fixedOvertimePay > 0
            ? w.fixedOvertimePay
            : (w.fixedOvertimeHours > 0 && ordHourly > 0
                ? (w.fixedOvertimeHours.floor() * ordHourly * otMult)
                : 0.0);
        final wTotal = w.monthlyWage + mealAmt + fOTPay;

        
        initialContent = DocumentTemplates.getLaborContract({
          'contractDate': todayStr,
          'startDate': now.toString().substring(0, 10),
          'storeName': '본 매장',
          'jobDescription': '매장 관리 및 고객 응대',
          'workingDays': w.workDays.isEmpty ? '별도 협의' : '',
          'workingHours': '',
          'breakClause': '',
          'weeklyHoliday': '',
          'dispatchCompany': '-',
          'dispatchPeriod': '해당 없음',
          'dispatchContact': '-',
          'dispatchMemo': '-',
          'wageType': w.wageType ?? 'hourly',
          'baseWage': ordHourly.round().toStringAsFixed(0),
          'monthlyWage': w.monthlyWage.toStringAsFixed(0),
          'mealAllowance': mealAmt.toStringAsFixed(0),
          'fixedOTHours': w.fixedOvertimeHours.floor().toString(),
          'fixedOTPay': fOTPay.round().toString(),
          'wageTotal': wTotal.round().toStringAsFixed(0),
          'sRef': sRef.toStringAsFixed(0),
          'isFiveOrMore': isFiveOrMore.toString(),
          'payday': '10',
          'ownerName': '대표자',
          'staffName': w.name,
        });
      } else if (docType == DocumentType.night_consent) {
        initialContent = DocumentTemplates.getNightHolidayConsent(w.name, consentDate: todayStr);
      } else if (docType == DocumentType.worker_record) {
        initialContent = DocumentTemplates.getEmployeeRegistry({
          'name': w.name,
          'birthDate': w.birthDate.isEmpty ? '19XX-XX-XX' : w.birthDate,
          'address': '',
          'jobDescription': '매장 관리',
          'hiredDate': w.startDate,
        });
      } else if (docType == DocumentType.wage_amendment) {
        initialContent = DocumentTemplates.getWageAmendment({
          'staffName': w.name,
          'jobDescription': '매장 관리',
          'oldBaseWage': w.hourlyWage.round().toString(),
          'newBaseWage': '(변경될 시급 입력)',
          'effectiveDate': '20XX년 XX월 XX일',
          'contractDate': todayStr,
          'ownerName': '대표자',
        });
      }

      final documentHash = SecurityMetadataHelper.generateDocumentHash(
        type: docType.name,
        staffId: widget.worker.id,
        content: initialContent,
        createdAt: now.toIso8601String(),
      );

      final doc = LaborDocument(
        id: docId,
        staffId: widget.worker.id,
        storeId: widget.storeId,
        type: docType,
        title: title,
        content: initialContent,
        createdAt: now,
        status: 'draft',
        expiryDate: DocumentCalculator.calculateExpiryDate(now),
        documentHash: documentHash,
      );

      await _dbService.saveDocument(doc);

      if (!mounted) return;

      // 서류 타입에 맞는 구조화 UI 화면으로 이동
      Widget targetScreen;
      switch (docType) {
        case DocumentType.contract_full:
        case DocumentType.contract_part:
        case DocumentType.laborContract:
          targetScreen = ContractPage(
            worker: widget.worker,
            documentId: docId,
            storeId: widget.storeId,
            initialDocument: doc,
          );
          break;
        case DocumentType.night_consent:
        case DocumentType.nightHolidayConsent:
          targetScreen = NightConsentScreen(
            worker: widget.worker,
            document: doc,
          );
          break;
        case DocumentType.worker_record:
        case DocumentType.employeeRegistry:
          targetScreen = WorkerRecordScreen(
            worker: widget.worker,
            document: doc,
          );
          break;
        case DocumentType.wage_amendment:
          targetScreen = WageAmendmentScreen(
            worker: widget.worker,
            document: doc,
            storeData: storeData,
          );
          break;
        case DocumentType.leave_promotion_first:
          targetScreen = LeavePromotionScreen(
            worker: widget.worker,
            document: doc,
            step: 1,
          );
          break;
        case DocumentType.leave_promotion_second:
          targetScreen = LeavePromotionScreen(
            worker: widget.worker,
            document: doc,
            step: 2,
          );
          break;
        case DocumentType.minor_consent:
          // 친권자 동의서: Firestore 저장 + 즉시 PDF 생성 → 인쇄 다이얼로그
          try {
            final storeDefaults = <String, dynamic>{};
            try {
              final storeSnap = await FirebaseFirestore.instance
                  .collection('stores')
                  .doc(widget.storeId)
                  .get();
              final sd = storeSnap.data() ?? {};
              storeDefaults['storeName'] = sd['storeName'] ?? '';
              storeDefaults['ownerName'] = sd['ownerName'] ?? '';
              storeDefaults['storeAddress'] = sd['address'] ?? '';
              storeDefaults['storePhone'] = sd['phone'] ?? '';
            } catch (_) {}

            final w = widget.worker;
            final dayLabels = {0: '일', 1: '월', 2: '화', 3: '수', 4: '목', 5: '금', 6: '토'};
            final workDaysStr = w.workDays.map((d) => dayLabels[d] ?? '').join(', ');

            final pdfBytes = await PdfGeneratorService.generateParentalConsent(
              storeDefaults: storeDefaults,
              workerName: w.name,
              workerBirthDate: w.birthDate.isNotEmpty ? w.birthDate : ' ',
              workerAddress: ' ',
              workerPhone: w.phone,
              hourlyWage: _fmtMoney(w.hourlyWage.round()),
              workDays: workDaysStr,
              workingHours: '${w.checkInTime} ~ ${w.checkOutTime}',
              startDate: w.startDate,
            );

            if (mounted) {
              await Printing.layoutPdf(
                onLayout: (_) async => pdfBytes,
                name: '친권자_동의서_${w.name}',
              );
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('PDF 생성 실패: $e')),
              );
            }
          }
          if (mounted) Navigator.pop(context);
          return;
        default:
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('서류가 생성되었습니다.')),
          );
          Navigator.pop(context);
          return;
      }

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => targetScreen),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('서류 생성 실패: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 금액 콤마 포맷
  String _fmtMoney(int amount) {
    return amount.toString().replaceAllMapped(
        RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
  }

  @override
  Widget build(BuildContext context) {
    // 구조화 UI가 있는 서류 타입 목록
    final structuredTypes = <({DocumentType type, String label, IconData icon, Color color})>[
      (
        type: _isUltraShort ? DocumentType.contract_part : DocumentType.contract_full,
        label: '근로계약서',
        icon: Icons.description_outlined,
        color: const Color(0xFF1A73E8),
      ),
      (
        type: DocumentType.night_consent,
        label: '야간/휴일근로\n동의서',
        icon: Icons.nights_stay_outlined,
        color: const Color(0xFF6B4FA2),
      ),
      (
        type: DocumentType.worker_record,
        label: '근로자 명부',
        icon: Icons.person_outline,
        color: const Color(0xFF0D7377),
      ),
      (
        type: DocumentType.checklist,
        label: '채용\n체크리스트',
        icon: Icons.checklist_outlined,
        color: const Color(0xFFE65100),
      ),
      (
        type: DocumentType.wage_amendment,
        label: '임금 계약\n변경서',
        icon: Icons.monetization_on_outlined,
        color: const Color(0xFF2E7D32),
      ),
      (
        type: DocumentType.minor_consent,
        label: '친권자\n동의서',
        icon: Icons.family_restroom,
        color: const Color(0xFFC62828),
      ),
      (
        type: DocumentType.leave_promotion_first,
        label: '연차 사용촉진\n1차 통보서',
        icon: Icons.notification_important_outlined,
        color: const Color(0xFFE65100),
      ),
      (
        type: DocumentType.leave_promotion_second,
        label: '연차 사용촉진\n2차 통보서',
        icon: Icons.event_available_outlined,
        color: const Color(0xFFBF360C),
      ),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: const Text('새 노무 서류 작성'),
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
                  Text('서류 생성 중...', style: TextStyle(color: Colors.grey)),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 직원 정보 헤더
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)],
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: const Color(0xFF1A1A2E),
                          child: Text(
                            widget.worker.name.isNotEmpty ? widget.worker.name[0] : '?',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(widget.worker.name,
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 2),
                              Text(
                                '${widget.worker.wageType == 'monthly' ? '월급제' : '시급제'} · ${widget.worker.workDays.length}일/주',
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        ),
                        if (_isUltraShort)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFDECEC),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text('초단시간',
                                style: TextStyle(
                                    fontSize: 10, color: Color(0xFFD32F2F), fontWeight: FontWeight.bold)),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  const Text('작성할 서류를 선택하세요',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
                  const SizedBox(height: 4),
                  Text('선택하면 해당 양식 화면으로 바로 이동합니다.',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  const SizedBox(height: 16),

                  // 서류 타입 그리드
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 1.4,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: structuredTypes.length,
                    itemBuilder: (context, index) {
                      final item = structuredTypes[index];
                      return InkWell(
                        onTap: () => _createAndNavigate(item.type),
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: item.color.withOpacity(0.2)),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)],
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: item.color.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(item.icon, color: item.color, size: 24),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                item.label,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: item.color,
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 24),

                  // 일괄 작성 안내
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F4FF),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF1A73E8).withOpacity(0.2)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.lightbulb_outline, color: Colors.amber.shade700, size: 20),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            '신규 직원이라면 "노무서류" 탭의 일괄 작성 위자드를\n이용하면 4종 서류를 한 번에 작성할 수 있습니다.',
                            style: TextStyle(fontSize: 11, color: Color(0xFF333333), height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: MediaQuery.of(context).padding.bottom + 40),
                ],
              ),
            ),
    );
  }
}
