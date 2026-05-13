import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_logic/shared_logic.dart';

import '../../models/worker.dart';
import 'worker_record_screen.dart';
import 'night_consent_screen.dart';
import 'hiring_checklist_screen.dart';
import '../contract_page.dart';

/// 노무서류 순서 안내 위자드.
/// ① 근로자명부 → ② 휴일·야간 동의서 → ③ 채용 체크리스트 → ④ 근로계약서
class DocumentWizardScreen extends StatefulWidget {
  final Worker worker;
  final String storeId;
  final List<LaborDocument> documents;

  const DocumentWizardScreen({
    super.key,
    required this.worker,
    required this.storeId,
    required this.documents,
  });

  @override
  State<DocumentWizardScreen> createState() => _DocumentWizardScreenState();
}

class _DocumentWizardScreenState extends State<DocumentWizardScreen> {
  late final PageController _pageController;
  int _currentStep = 0;
  late List<LaborDocument> _documents;
  bool _isInitializing = true;

  // 서류 순서 정의
  static const _stepOrder = [
    DocumentType.worker_record,
    DocumentType.night_consent,
    DocumentType.checklist,
  ];
  // 4번째 스텝은 contract_full 또는 contract_part (동적)

  static const _stepLabels = [
    '근로자 명부',
    '야간·휴일 동의서',
    '채용 체크리스트',
    '근로계약서',
  ];

  static const _stepIcons = [
    Icons.person_outline,
    Icons.nights_stay_outlined,
    Icons.checklist_outlined,
    Icons.description_outlined,
  ];

  @override
  void initState() {
    super.initState();
    _documents = List.from(widget.documents);
    _pageController = PageController();
    _initializeDocuments();
  }

  Future<void> _initializeDocuments() async {
    try {
      await _ensureAllDocumentsExist();
    } catch (e) {
      debugPrint('[DocumentWizard] Auto-creation failed: $e');
    }
    if (!mounted) return;
    setState(() {
      _currentStep = _findFirstIncompleteStep();
      _isInitializing = false;
    });
    // 완료된 서류 다음 스텝으로 이동
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_currentStep > 0) {
        _pageController.jumpToPage(_currentStep);
      }
    });
  }

  /// 누락된 서류 자동 생성 (임연경처럼 이전에 등록된 직원 대응)
  Future<void> _ensureAllDocumentsExist() async {
    final db = FirebaseFirestore.instance;
    final w = widget.worker;
    final storeId = widget.storeId;
    final now = AppClock.now();
    final todayStr = '${now.year}년 ${now.month.toString().padLeft(2, '0')}월 ${now.day.toString().padLeft(2, '0')}일';

    // 필요한 서류 타입 목록
    final contractType = w.weeklyHours >= 40
        ? DocumentType.contract_full
        : DocumentType.contract_part;

    final requiredDocs = <DocumentType, String>{
      DocumentType.worker_record: '근로자 명부',
      DocumentType.night_consent: '휴일·야간근로 동의서',
      DocumentType.checklist: '채용 체크리스트',
      contractType: contractType == DocumentType.contract_full
          ? '표준 근로계약서'
          : '근로계약서 (단시간)',
    };

    for (final entry in requiredDocs.entries) {
      final docType = entry.key;
      final title = entry.value;

      // 이미 있는지 확인
      final exists = _documents.any((d) =>
          d.type == docType ||
          (docType == DocumentType.contract_full && d.type == DocumentType.contract_part) ||
          (docType == DocumentType.contract_part && d.type == DocumentType.contract_full));
      if (exists) continue;

      // 서류 내용 생성
      String content;
      switch (docType) {
        case DocumentType.contract_full:
        case DocumentType.contract_part:
          // 통상시급 & 고정연장수당 적법 산출
          final mealAmt = w.allowances
              .where((a) => a.label == '식대' || a.label == '식비')
              .fold<double>(0, (sum, a) => sum + a.amount);
          // ★ S_Ref: 직원별 소정근로시간 기반
          final weeklyH = w.weeklyHours > 0 ? w.weeklyHours : 40.0;
          final wdpw = w.workDays.isNotEmpty ? w.workDays.length.toDouble() : 5.0;
          final whH = weeklyH >= 15 ? weeklyH / wdpw : 0.0;
          final sRef = ((weeklyH + whH) * 4.345).ceilToDouble();
          final ordHourly = w.monthlyWage > 0 && sRef > 0
              ? (w.monthlyWage + mealAmt) / sRef
              : w.hourlyWage;
          // 5인 이상 사업장 여부 조회
          bool isFiveOrMore = false;
          try {
            final storeSnap = await db.collection('stores').doc(storeId).get();
            isFiveOrMore = storeSnap.data()?['isFiveOrMore'] as bool? ?? false;
          } catch (_) {}
          final otMult = isFiveOrMore ? 1.5 : 1.0;
          final fOTPay = w.fixedOvertimePay > 0
              ? w.fixedOvertimePay
              : (w.fixedOvertimeHours > 0 && ordHourly > 0
                  ? (w.fixedOvertimeHours.floor() * ordHourly * otMult)
                  : 0.0);
          final wTotal = w.monthlyWage + mealAmt + fOTPay;
          content = DocumentTemplates.getLaborContract({
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
          break;
        case DocumentType.night_consent:
          content = DocumentTemplates.getNightHolidayConsent(w.name, consentDate: todayStr);
          break;
        case DocumentType.worker_record:
          content = DocumentTemplates.getEmployeeRegistry({
            'name': w.name,
            'birthDate': w.birthDate.isEmpty ? '19XX-XX-XX' : w.birthDate,
            'address': '별도 기재',
            'hireDate': w.startDate.isEmpty ? now.toString().substring(0, 10) : w.startDate,
            'job': '매장 스태프',
            'contractPeriod': w.weeklyHours >= 40 ? '정규직' : '단시간',
          });
          break;
        case DocumentType.checklist:
          content = '채용 체크리스트는 앱 내 항목을 기준으로 작성하세요.';
          break;
        default:
          content = '';
      }

      final docId = '${w.id}_${docType.name}';
      final createdAt = AppClock.now();
      final documentHash = SecurityMetadataHelper.generateDocumentHash(
        type: docType.name,
        staffId: w.id,
        content: content,
        createdAt: createdAt.toIso8601String(),
      );

      final laborDoc = LaborDocument(
        id: docId,
        staffId: w.id,
        storeId: storeId,
        type: docType,
        status: 'draft',
        title: title,
        content: content,
        createdAt: createdAt,
        documentHash: documentHash,
      );

      await db
          .collection('stores')
          .doc(storeId)
          .collection('documents')
          .doc(docId)
          .set(laborDoc.toMap());

      _documents.add(laborDoc);
      debugPrint('[DocumentWizard] Auto-created missing: $title for ${w.name}');
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  int _findFirstIncompleteStep() {
    for (int i = 0; i < _stepOrder.length; i++) {
      final doc = _findDoc(_stepOrder[i]);
      if (doc == null || doc.status == 'draft') return i;
    }
    // 체크리스트까지 완료 → 계약서 확인
    final contractDoc = _findContractDoc();
    if (contractDoc == null || contractDoc.status == 'draft') return 3;
    return 0; // 모든 서류 완성 시 처음부터
  }

  LaborDocument? _findDoc(DocumentType type) {
    return _documents
        .where((d) => d.type == type)
        .firstOrNull;
  }

  LaborDocument? _findContractDoc() {
    return _documents
        .where((d) =>
            d.type == DocumentType.contract_full ||
            d.type == DocumentType.contract_part)
        .firstOrNull;
  }

  void _goToStep(int step) {
    if (step < 0 || step > 3) return;
    _pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  void _nextStep() {
    if (_currentStep < 3) {
      _goToStep(_currentStep + 1);
    }
  }

  bool _isStepAccessible(int step) {
    // 첫 번째 스텝은 항상 접근 가능
    if (step == 0) return true;
    // 이전 스텝의 서류가 draft가 아니면 접근 가능
    if (step <= 2) {
      final prevDoc = _findDoc(_stepOrder[step - 1]);
      return prevDoc != null && prevDoc.status != 'draft';
    }
    // 4번째 (계약서): 체크리스트까지 완료 시
    if (step == 3) {
      final checklistDoc = _findDoc(DocumentType.checklist);
      return checklistDoc != null && checklistDoc.status != 'draft';
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        foregroundColor: Colors.white,
        title: Text('${widget.worker.name}님 노무서류 작성'),
        centerTitle: true,
      ),
      body: _isInitializing
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('서류 준비 중...', style: TextStyle(color: Colors.grey)),
                ],
              ),
            )
          : Column(
        children: [
          // 스텝 인디케이터
          _buildStepIndicator(),
          // 페이지 컨텐츠
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(), // 스와이프 비활성
              onPageChanged: (page) => setState(() => _currentStep = page),
              children: [
                _buildWorkerRecord(),
                _buildNightConsent(),
                _buildChecklist(),
                _buildContract(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: List.generate(4, (i) {
          final isComplete = _isStepComplete(i);
          final isCurrent = i == _currentStep;
          final isAccessible = _isStepAccessible(i);

          return Expanded(
            child: GestureDetector(
              onTap: isAccessible ? () => _goToStep(i) : null,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 아이콘 + 연결선
                  Row(
                    children: [
                      if (i > 0)
                        Expanded(
                          child: Container(
                            height: 2,
                            color: isComplete || (isCurrent && i > 0)
                                ? const Color(0xFF286b3a)
                                : const Color(0xFFE0E0E0),
                          ),
                        ),
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isComplete
                              ? const Color(0xFF286b3a)
                              : isCurrent
                                  ? const Color(0xFF1A1A2E)
                                  : isAccessible
                                      ? const Color(0xFFBBBBBB)
                                      : const Color(0xFFE0E0E0),
                        ),
                        child: Icon(
                          isComplete ? Icons.check : _stepIcons[i],
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                      if (i < 3)
                        Expanded(
                          child: Container(
                            height: 2,
                            color: isComplete
                                ? const Color(0xFF286b3a)
                                : const Color(0xFFE0E0E0),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _stepLabels[i],
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                      color: isCurrent
                          ? const Color(0xFF1A1A2E)
                          : isComplete
                              ? const Color(0xFF286b3a)
                              : const Color(0xFF999999),
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  bool _isStepComplete(int step) {
    if (step <= 2) {
      final doc = _findDoc(_stepOrder[step]);
      return doc != null && doc.status != 'draft';
    }
    final contractDoc = _findContractDoc();
    return contractDoc != null &&
        contractDoc.status != 'draft' &&
        contractDoc.status != 'ready';
  }

  // ──── 스텝별 화면 ────

  Widget _buildWorkerRecord() {
    final doc = _findDoc(DocumentType.worker_record);
    if (doc == null) {
      return const Center(child: Text('근로자 명부 서류가 없습니다.'));
    }
    return WorkerRecordScreen(
      worker: widget.worker,
      document: doc,
      isWizardMode: true,
      nextButtonLabel: '다음: 야간·휴일 동의서 →',
      onNext: _nextStep,
    );
  }

  Widget _buildNightConsent() {
    final doc = _findDoc(DocumentType.night_consent);
    if (doc == null) {
      return const Center(child: Text('야간·휴일 동의서가 없습니다.'));
    }
    return NightConsentScreen(
      worker: widget.worker,
      document: doc,
      isWizardMode: true,
      nextButtonLabel: '다음: 채용 체크리스트 →',
      onNext: _nextStep,
    );
  }

  Widget _buildChecklist() {
    final doc = _findDoc(DocumentType.checklist);
    if (doc == null) {
      return const Center(child: Text('채용 체크리스트가 없습니다.'));
    }
    return HiringChecklistScreen(
      worker: widget.worker,
      storeId: widget.storeId,
      document: doc,
      isWizardMode: true,
      nextButtonLabel: '다음: 근로계약서 →',
      onNext: _nextStep,
    );
  }

  Widget _buildContract() {
    final doc = _findContractDoc();
    if (doc == null) {
      return const Center(child: Text('근로계약서가 없습니다.'));
    }
    return ContractPage(
      worker: widget.worker,
      documentId: doc.id,
      storeId: widget.storeId,
      initialDocument: doc,
    );
  }
}
