import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_logic/shared_logic.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/worker.dart';
import '../../services/worker_service.dart';
import 'staff_invite_code_screen.dart';
import '../contract_page.dart';
import '../documents/worker_record_screen.dart';
import '../documents/night_consent_screen.dart';
import '../documents/hiring_checklist_screen.dart';

enum _BreakPreset { minutes30, minutes60, custom }

enum _EmployeeType { normal, dispatched, foreigner }

enum _CompensationIncomeType { labor, business33 }



class AddStaffScreen extends StatefulWidget {
  final Worker? initialWorker;

  const AddStaffScreen({super.key, this.initialWorker});

  @override
  State<AddStaffScreen> createState() => _AddStaffScreenState();
}

class _AddStaffScreenState extends State<AddStaffScreen> {
  static const int _timePickerStepMinutes = 30; // 30분 단위(필요 시 10분으로도 변경 가능)

  final _nameController = TextEditingController();
  final _employeeIdController = TextEditingController();
  final _phoneController = TextEditingController();
  final _nameFocusNode = FocusNode();
  final _phoneFocusNode = FocusNode();
  final _hireDateKey = GlobalKey();
  final _workScheduleKey = GlobalKey();
  final _wageController = TextEditingController();
  final _monthlyWageController = TextEditingController();
  WageType _wageType = WageType.hourly;
  final _bonusController = TextEditingController();
  final _mealAllowanceController = TextEditingController();
  final _transportAllowanceController = TextEditingController();
  bool _mealTaxExempt = false;
  final _fixedOvertimeHoursController = TextEditingController(text: '0');
  final _breakMinutesController = TextEditingController(text: '60');
  final _workStartController = TextEditingController(text: '17:00');
  final _workEndController = TextEditingController(text: '21:30');
  final _breakStartController = TextEditingController(text: '19:00');
  final _breakEndController = TextEditingController(text: '19:30');
  final _dayStartController = TextEditingController(text: '17:00');
  final _dayEndController = TextEditingController(text: '21:30');
  int _selectedWorkDay = DateTime.monday;
  final List<CustomPayItem> _customItems = [];
  final Set<int> _contractedDays = <int>{
    DateTime.monday,
    DateTime.tuesday,
    DateTime.wednesday,
    DateTime.thursday,
    DateTime.friday,
  };
  final Map<int, String> _workStartByDay = {};
  final Map<int, String> _workEndByDay = {};

  // Multi-day selection (패턴 기반 UX)
  final Set<int> _selectedDays = <int>{};
  final _bulkStartController = TextEditingController(text: '17:00');
  final _bulkEndController = TextEditingController(text: '21:30');

  // 수습기간 90% 적용 여부
  bool _applyProbationWage90Percent = false;
  int _probationMonths = 3;

  /// 최저시급 (Firestore app_config/minimum_wage 에서 로드, 실패 시 하드코딩 폴백)
  static const double _fallbackMinimumWage2026 = 10320;
  double _minimumHourlyWage = _fallbackMinimumWage2026;
  String? _wageError;

  // 근무 시간 입력 섹션 모드 (요약/상세)
  bool _isEditingWorkTime = true; // 신규 등록 시 기본 열림

  // 휴게시간 단순화 UX
  _BreakPreset _breakPreset = _BreakPreset.minutes60;
  String _breakStartTime = '19:00';
  bool _isBreakStartManuallyEdited = false;

  DateTime? _hireDate;
  DateTime? _healthCertificateExpiryDate;
  bool _isSubstitutionAllowed = true;
  bool _isBreakPaid = false;
  bool _healthCertificateManagementEnabled = false;
  bool _hasHealthCertificate = false;
  _EmployeeType _employeeType = _EmployeeType.normal;
  bool _isDispatch = false;
  // 파견직 전용 입력값(문서/급여 계산과는 별개로 안내용 메모 포함)
  final _dispatchCompanyController = TextEditingController();
  final _dispatchContactController = TextEditingController();
  final _dispatchMemoController = TextEditingController();
  DateTime? _dispatchStartDate;
  DateTime? _dispatchEndDate;
  DateTime? _birthDate;
  bool _isLongTerm = true;
  DateTime? _contractEndDate;
  // 주 소정근로시간(주간) 15시간 기준으로 자동 판정합니다.
  // (UI 토글/수동 설정 없이 자동으로 유급/무급 결정)
  int _weeklyHolidayDay = 0; // 일=0 ... 토=6
  String? _visaType;
  DateTime? _visaExpiryDate;
  bool _isLoading = false;

  _CompensationIncomeType _compIncomeType = _CompensationIncomeType.labor;
  bool _deductNationalPension = true;
  bool _deductHealthInsurance = true;
  bool _deductEmploymentInsurance = true;
  bool _trackIndustrialInsurance = false;
  bool _applyWithholding33 = false;

  bool _section1Expanded = true;
  bool _section2Expanded = true;
  late bool _section3Expanded;
  late bool _section4Expanded;
  bool _sectionWageExpanded = true; // Block 2: 급여 설계
  bool _sectionAllowanceExpanded = true; // Block 3: 수당 및 절세
  bool _sectionVerifyExpanded = true; // Block 4: 최종 검증

  // ── Auto-Wizard 상태 ──
  final _targetSalaryController = TextEditingController();
  bool _wizardApplied = false;
  // 잔여 금액 다중 분배 필드
  final TextEditingController _wizardPositionController = TextEditingController();
  final TextEditingController _wizardDiligenceController = TextEditingController();
  final TextEditingController _wizardFixedOtController = TextEditingController();
  final TextEditingController _wizardOtherLabelController = TextEditingController();
  final TextEditingController _wizardOtherAmountController = TextEditingController();
  int _wizardBaseSalary = 0; // 마법사 생성 시점의 기본급
  int _wizardMealAllowance = 0; // 마법사 생성 시점의 식대
  bool _isFiveOrMoreStore = false; // 5인 이상 여부 캐싱

  bool _isMinor = false;
  bool _hideBanner = false;

  // 고급 노무 설정 (퇴직금·연차수당·통상임금 산정)
  bool _includeMealInOrdinary = true;
  bool _includeAllowanceInOrdinary = false;
  bool _includeFixedOtInAverage = false;

  void _phoneFormatListener() {
    final text = _phoneController.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (text.length > 11) {
      final truncated = text.substring(0, 11);
      String formatted;
      if (truncated.length <= 3) {
        formatted = truncated;
      } else if (truncated.length <= 7) {
        formatted = '${truncated.substring(0, 3)}-${truncated.substring(3)}';
      } else {
        formatted =
            '${truncated.substring(0, 3)}-${truncated.substring(3, 7)}-${truncated.substring(7)}';
      }
      if (formatted != _phoneController.text) {
        _phoneController.value = TextEditingValue(
          text: formatted,
          selection: TextSelection.collapsed(offset: formatted.length),
        );
      }
      return;
    }
    String formatted;
    if (text.length <= 3) {
      formatted = text;
    } else if (text.length <= 7) {
      formatted = '${text.substring(0, 3)}-${text.substring(3)}';
    } else {
      formatted =
          '${text.substring(0, 3)}-${text.substring(3, 7)}-${text.substring(7)}';
    }
    if (formatted != _phoneController.text) {
      _phoneController.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }
  }

  void _weeklyHoursSyncListener() {
    if (!mounted) return;
    if (!_isBreakStartManuallyEdited) {
      _autoAssignBreakStartMidpoint();
    }
    // weeklyHours 기준 판정(UI 뱃지/안내문구/주휴수당 계산) 즉시 동기화
    setState(() {});
  }

  void _autoAssignBreakStartMidpoint() {
    final start = _workStartController.text.trim();
    final end = _workEndController.text.trim();
    if (!_isHm(start) || !_isHm(end)) return;
    final duration = _durationMinutes(start, end);
    if (duration <= 0) return;
    final breakMinutes = _currentBreakMinutes();
    final startMinutes = _hmToTotalMinutes(start);
    final midpointOffset = ((duration - breakMinutes).clamp(0, duration) / 2)
        .round();
    final autoStart = _totalMinutesToHm(startMinutes + midpointOffset);
    if (autoStart.isNotEmpty) {
      _breakStartTime = autoStart;
    }
  }

  bool _hasNightWork(String startHm, String endHm) {
    if (!_isHm(startHm) || !_isHm(endHm)) return false;
    final s = _hmToTotalMinutes(startHm);
    final dur = _durationMinutes(startHm, endHm);
    if (dur <= 0) return false;
    for (int i = 0; i < dur; i++) {
      final m = (s + i) % (24 * 60);
      if (m >= 22 * 60 || m < 6 * 60) return true;
    }
    return false;
  }

  void _onWorkerTypeChanged(_EmployeeType type) {
    setState(() {
      _employeeType = type;
      _isDispatch = type == _EmployeeType.dispatched;
    });
  }

  static String _formatPhoneDisplay(String raw) {
    final text = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (text.isEmpty) return '';
    if (text.length <= 3) return text;
    if (text.length <= 7) {
      return '${text.substring(0, 3)}-${text.substring(3)}';
    }
    final d = text.length > 11 ? text.substring(0, 11) : text;
    return '${d.substring(0, 3)}-${d.substring(3, 7)}-${d.substring(7)}';
  }

  @override
  void initState() {
    super.initState();
    _fetchStoreIsFiveOrMore();
    _phoneController.addListener(_phoneFormatListener);
    _breakMinutesController.addListener(_weeklyHoursSyncListener);
    _workStartController.addListener(_weeklyHoursSyncListener);
    _workEndController.addListener(_weeklyHoursSyncListener);
    // 새 직원: 소득구분/공제, 보건증 섹션 펼침 / 기존 직원: 접힘
    final isNew = widget.initialWorker == null;
    _section3Expanded = isNew;
    _section4Expanded = isNew;
    _isEditingWorkTime = isNew; // 신규: 편집 모드 열림, 수정: 요약 모드
    _loadMinimumHourlyWage();
    _autoAssignBreakStartMidpoint();
    final worker = widget.initialWorker;
    if (worker == null) return;

    _nameController.text = worker.name;
    _employeeIdController.text = worker.employeeId ?? '';
    _phoneController.text = _formatPhoneDisplay(worker.phone);
    if (worker.wageType == 'monthly') {
      _wageType = WageType.monthly;
      _monthlyWageController.text = worker.monthlyWage.toStringAsFixed(0);
      _wizardBaseSalary = worker.monthlyWage.toInt();
      _wizardMealAllowance = 0;
      _mealAllowanceController.text = '';
      if (worker.fixedOvertimeHours > 0) {
        _wizardApplied = true;
        _wizardFixedOtController.text = _formatMoney(worker.fixedOvertimePay);
        _fixedOvertimeHoursController.text = worker.fixedOvertimeHours.toStringAsFixed(1);
      }
      for (final allowance in worker.allowances) {
        final _lbl = allowance.label.replaceAll(' ', '');
        if (_lbl.contains('식비') || _lbl.contains('식대') || allowance.label == '상여금' || allowance.label == '교통비') continue;
        if (allowance.label == '직책 수당') {
          _wizardApplied = true;
          _wizardPositionController.text = _formatMoney(allowance.amount);
        } else if (allowance.label == '성실 수당') {
          _wizardApplied = true;
          _wizardDiligenceController.text = _formatMoney(allowance.amount);
        } else if (allowance.label == '고정연장수당') {
          _wizardApplied = true;
          _wizardFixedOtController.text = _formatMoney(allowance.amount);
        } else {
          _wizardApplied = true;
          _wizardOtherLabelController.text = allowance.label;
          _wizardOtherAmountController.text = _formatMoney(allowance.amount);
        }
      }
      // 잔여 금액 추정 복원
      // ※ allowances에 고정연장수당이 이미 포함되므로 fixedOvertimePay 별도 합산 금지 (이중 계산 방지)
      final totalAllowance = worker.allowances.fold<double>(0.0, (s, e) => s + e.amount);
      final targetTotal = worker.monthlyWage + totalAllowance + 
          (worker.allowances.any((a) => a.label == '고정연장수당') ? 0.0 : worker.fixedOvertimePay);
      _targetSalaryController.text = targetTotal > 0 ? targetTotal.toInt().toString() : '';
    } else {
      _wageType = WageType.hourly;
      _wageController.text = worker.hourlyWage.toStringAsFixed(0);
      _mealAllowanceController.text = '';
    }
    _bonusController.text = '';
    _transportAllowanceController.text = '';
    
    // 수당 필드 복원
    for (final allowance in worker.allowances) {
      if (allowance.label == '상여금') {
        _bonusController.text = allowance.amount.toInt().toString();
      } else if (allowance.label == '식비' || allowance.label == '식대') {
        _mealAllowanceController.text = allowance.amount.toInt().toString();
        _wizardMealAllowance = allowance.amount.toInt();
        _mealTaxExempt = worker.mealTaxExempt;
      } else if (allowance.label == '교통비') {
        _transportAllowanceController.text = allowance.amount.toInt().toString();
      } else if (!allowance.label.contains('직책') && !allowance.label.contains('성실')) {
        _customItems.add(CustomPayItem(label: allowance.label, amount: allowance.amount.toInt()));
      }
    }
    _hireDate = RobustDateParser.parse(worker.startDate);
    _breakMinutesController.text = worker.breakMinutes.toInt().toString();
    
    // 고급 노무 설정 복원
    _includeMealInOrdinary = worker.includeMealInOrdinary;
    _includeAllowanceInOrdinary = worker.includeAllowanceInOrdinary;
    _includeFixedOtInAverage = worker.includeFixedOtInAverage;
    _breakPreset = worker.breakMinutes == 30
        ? _BreakPreset.minutes30
        : worker.breakMinutes == 60
        ? _BreakPreset.minutes60
        : _BreakPreset.custom;
    _isBreakPaid = worker.isPaidBreak;
    _workStartController.text = worker.checkInTime;
    _workEndController.text = worker.checkOutTime;
    _healthCertificateManagementEnabled = true;
    _hasHealthCertificate = worker.hasHealthCert;
    _healthCertificateExpiryDate = worker.healthCertExpiry == null
        ? null
        : DateTime.tryParse(worker.healthCertExpiry!);
    _applyProbationWage90Percent = worker.isProbation;
    _probationMonths = worker.probationMonths > 0 ? worker.probationMonths : 3;
    if (worker.workerType == 'dispatch')
      _employeeType = _EmployeeType.dispatched;
    if (worker.workerType == 'foreigner')
      _employeeType = _EmployeeType.foreigner;
    _isDispatch = _employeeType == _EmployeeType.dispatched;
    _birthDate = worker.birthDate.isEmpty
        ? null
        : DateTime.tryParse(worker.birthDate);
    if (_birthDate != null) {
      _isMinor = _calcAge(_birthDate!) < 18;
    }
    _isLongTerm = worker.endDate == null || worker.endDate!.isEmpty;
    _contractEndDate = _isLongTerm ? null : DateTime.tryParse(worker.endDate!);
    _weeklyHolidayDay = worker.weeklyHolidayDay;
    _visaType = worker.visaType;
    _visaExpiryDate = worker.visaExpiry == null
        ? null
        : DateTime.tryParse(worker.visaExpiry!);
    _compIncomeType = worker.compensationIncomeType == 'business_income_33'
        ? _CompensationIncomeType.business33
        : _CompensationIncomeType.labor;
    _deductNationalPension = worker.deductNationalPension;
    _deductHealthInsurance = worker.deductHealthInsurance;
    _deductEmploymentInsurance = worker.deductEmploymentInsurance;
    _trackIndustrialInsurance = worker.trackIndustrialInsurance;
    _applyWithholding33 = worker.applyWithholding33;

    if (_isDispatch) {
      _dispatchCompanyController.text = worker.dispatchCompany ?? '';
      _dispatchContactController.text = worker.dispatchContact ?? '';
      _dispatchMemoController.text = worker.dispatchMemo ?? '';
      _dispatchStartDate = worker.dispatchStartDate == null
          ? null
          : DateTime.tryParse(worker.dispatchStartDate!);
      _dispatchEndDate = worker.dispatchEndDate == null
          ? null
          : DateTime.tryParse(worker.dispatchEndDate!);
    }

    if (worker.workScheduleJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(worker.workScheduleJson) as List<dynamic>;
        _workStartByDay.clear();
        _workEndByDay.clear();
        _contractedDays.clear();
        _selectedDays.clear();
        for (final raw in decoded) {
          final m = raw as Map<String, dynamic>;
          final days = (m['days'] as List<dynamic>)
              .map((e) => e is int ? e : int.tryParse(e.toString()) ?? 0)
              .toList();
          final start = m['start']?.toString() ?? '09:00';
          final end = m['end']?.toString() ?? '18:00';
          for (final d in days) {
            final key = d == 0 ? DateTime.sunday : d;
            _workStartByDay[key] = start;
            _workEndByDay[key] = end;
            _contractedDays.add(key);
            _selectedDays.add(key);
          }
        }
        if (_workStartByDay.isNotEmpty) {
          _selectedWorkDay = (_workStartByDay.keys.toList()..sort()).first;
          _dayStartController.text =
              _workStartByDay[_selectedWorkDay] ?? '17:00';
          _dayEndController.text = _workEndByDay[_selectedWorkDay] ?? '21:30';
          final firstDay = (_selectedDays.toList()..sort()).first;
          _bulkStartController.text = _workStartByDay[firstDay] ?? '17:00';
          _bulkEndController.text = _workEndByDay[firstDay] ?? '21:30';
        }
      } catch (_) {
        _applyLegacyWorkDays(worker);
      }
    } else if (worker.workDays.isNotEmpty) {
      _applyLegacyWorkDays(worker);
    }

    if (worker.breakStartTime.isNotEmpty) {
      _breakStartTime = worker.breakStartTime;
      _isBreakStartManuallyEdited = true;
    }
  }

  void _applyLegacyWorkDays(Worker worker) {
    if (worker.workDays.isEmpty) return;
    _workStartByDay
      ..clear()
      ..addEntries(
        worker.workDays.map(
          (d) => MapEntry(d == 0 ? DateTime.sunday : d, worker.checkInTime),
        ),
      );
    _workEndByDay
      ..clear()
      ..addEntries(
        worker.workDays.map(
          (d) => MapEntry(d == 0 ? DateTime.sunday : d, worker.checkOutTime),
        ),
      );
    _contractedDays
      ..clear()
      ..addAll(_workStartByDay.keys);
    _selectedWorkDay = (_workStartByDay.keys.toList()..sort()).first;
    _dayStartController.text = _workStartByDay[_selectedWorkDay] ?? '17:00';
    _dayEndController.text = _workEndByDay[_selectedWorkDay] ?? '21:30';

    _selectedDays
      ..clear()
      ..addAll(_workStartByDay.keys);
    final firstDay = (_selectedDays.toList()..sort()).first;
    _bulkStartController.text = _workStartByDay[firstDay] ?? '17:00';
    _bulkEndController.text = _workEndByDay[firstDay] ?? '21:30';
  }

  Future<void> _loadMinimumHourlyWage() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('app_config')
          .doc('minimum_wage')
          .get();
      final data = snap.data() ?? {};
      final wage =
          (data['currentHourly'] as num?)?.toDouble() ??
          (data['hourly'] as num?)?.toDouble() ??
          (data['minimumHourlyWage'] as num?)?.toDouble();
      if (wage != null && wage > 0 && mounted) {
        setState(() {
          _minimumHourlyWage = wage;
          if (widget.initialWorker == null &&
              _wageController.text.trim().isEmpty) {
            _wageController.text = wage.toStringAsFixed(0);
          }
        });
      }
    } catch (_) {
      // Firestore 실패 시 하드코딩 폴백(_fallbackMinimumWage2026) 사용
    }
  }

  void _validateWage(String value) {
    final wage = int.tryParse(value.trim()) ?? 0;
    setState(() {
      if (value.trim().isEmpty) {
        _wageError = null;
      } else if (!_isDispatch && wage > 0 && wage < _minimumHourlyWage) {
        _wageError =
            '⚠️ ${_formatMoney(_minimumHourlyWage)}원 이상 입력해 주세요\n(${DateTime.now().year}년 최저시급)';
      } else {
        _wageError = null;
      }
    });
  }

  void _validateMonthlyWage(String value) {
    // 기본급 입력 시 → 통상시급(보수적) = 기본급 / S
    final baseSalary =
        int.tryParse(value.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    if (baseSalary > 0) {
      final weeklyH = _weeklyHours();
      final weeklyHolidayH = weeklyH >= 15 ? weeklyH / _workDaysPerWeek() : 0.0;
      final scheduledH = ((weeklyH + weeklyHolidayH) * 4.345).ceilToDouble();
      final conservativeHourly = scheduledH > 0
          ? (baseSalary / scheduledH).round()
          : 0;
      _wageController.text = NumberFormat('#,###').format(conservativeHourly);
    }
    setState(() {});
  }

  Future<String?> _fetchStoreId() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    final storeId = snap.data()?['storeId'];
    if (storeId is! String) return null;
    final cleaned = storeId.trim();
    return cleaned.isEmpty ? null : cleaned;
  }

  Future<void> _fetchStoreIsFiveOrMore() async {
    try {
      final storeId = await _fetchStoreId();
      if (storeId == null) return;
      final doc = await FirebaseFirestore.instance
          .collection('stores')
          .doc(storeId)
          .get();
      if (mounted && doc.exists) {
        setState(() {
          _isFiveOrMoreStore = doc.data()?['isFiveOrMore'] as bool? ?? false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching store isFiveOrMore: $e');
    }
  }

  bool get _canApplyProbation {
    if (_hireDate == null) return false;
    if (_isLongTerm) return true;
    if (_contractEndDate == null) return false;
    
    // 1년 후의 날짜 계산 (윤년 고려)
    final oneYearLater = DateTime(_hireDate!.year + 1, _hireDate!.month, _hireDate!.day);
    return !_contractEndDate!.isBefore(oneYearLater);
  }

  bool _hasProfileChanges() {
    final initial = widget.initialWorker;
    if (initial == null) return false;

    final current = _toWorker(initial.storeId);

    // 주요 계약 조건 비교
    if (initial.name != current.name) return true;
    if (initial.phone != current.phone) return true;
    if (initial.birthDate != current.birthDate) return true;
    if (initial.hourlyWage != current.hourlyWage) return true;
    if (initial.workerType != current.workerType) return true;
    if (initial.startDate != current.startDate) return true;
    if (initial.endDate != current.endDate) return true;
    if (initial.checkInTime != current.checkInTime) return true;
    if (initial.checkOutTime != current.checkOutTime) return true;
    if (initial.workDays.length != current.workDays.length) return true;
    if (initial.compensationIncomeType != current.compensationIncomeType)
      return true;

    return false;
  }

  Future<Map<DocumentType, String>> _fetchDocumentStatuses(
    String workerId,
    String storeId,
  ) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('stores')
          .doc(storeId)
          .collection('documents')
          .where('staffId', isEqualTo: workerId)
          .get();

      final Map<DocumentType, String> statuses = {};
      for (final doc in snapshot.docs) {
        final typeStr = doc.data()['type'] as String?;
        final status = doc.data()['status'] as String? ?? 'draft';
        if (typeStr != null) {
          try {
            final type = DocumentType.values.byName(typeStr);
            statuses[type] = status;
          } catch (_) {}
        }
      }
      return statuses;
    } catch (e) {
      debugPrint('Error fetching document statuses: $e');
      return {};
    }
  }

  Worker _toWorker(String storeId, {bool? isPaperContract}) {
    final id = widget.initialWorker?.id ?? const Uuid().v4();
    final hourly = double.tryParse(_numText(_wageController)) ?? 0;
    final workDays =
        _workStartByDay.keys.map((d) => d == DateTime.sunday ? 0 : d).toList()
          ..sort();
    final start =
        (_workStartByDay.values.isNotEmpty
                ? _workStartByDay.values.first
                : _bulkStartController.text)
            .trim();
    final end =
        (_workEndByDay.values.isNotEmpty
                ? _workEndByDay.values.first
                : _bulkEndController.text)
            .trim();
    final weeklyTotalStayMinutes = _weeklyTotalStayMinutes();
    final weeklyPureLaborMinutes = _weeklyPureLaborMinutes();
    final weeklyHours = weeklyPureLaborMinutes / 60.0;
    final scheduleJson = jsonEncode(
      _workScheduleGroups().map((g) {
        final days = [...g.days]..sort();
        return {
          'days': days.map((d) => d == DateTime.sunday ? 0 : d).toList(),
          'start': g.start,
          'end': g.end,
        };
      }).toList(),
    );
    final allowances = <Allowance>[
      if ((int.tryParse(_numText(_bonusController)) ?? 0) > 0)
        Allowance(
          label: '상여금',
          amount: (int.tryParse(_numText(_bonusController)) ?? 0).toDouble(),
        ),
      if ((int.tryParse(_numText(_mealAllowanceController)) ?? 0) > 0)
        Allowance(
          label: '식비',
          amount: (int.tryParse(_numText(_mealAllowanceController)) ?? 0)
              .toDouble(),
        ),
      if ((int.tryParse(_numText(_transportAllowanceController)) ?? 0) > 0)
        Allowance(
          label: '교통비',
          amount: (int.tryParse(_numText(_transportAllowanceController)) ?? 0)
              .toDouble(),
        ),
      if (_wizardApplied) ...[
        if ((int.tryParse(_numText(_wizardPositionController)) ?? 0) > 0)
          Allowance(
            label: '직책 수당',
            amount: (int.tryParse(_numText(_wizardPositionController)) ?? 0).toDouble(),
          ),
        if ((int.tryParse(_numText(_wizardDiligenceController)) ?? 0) > 0)
          Allowance(
            label: '성실 수당',
            amount: (int.tryParse(_numText(_wizardDiligenceController)) ?? 0).toDouble(),
          ),
        if ((int.tryParse(_numText(_wizardFixedOtController)) ?? 0) > 0)
          Allowance(
            label: '고정연장수당',
            amount: (int.tryParse(_numText(_wizardFixedOtController)) ?? 0).toDouble(),
          ),
        if ((int.tryParse(_numText(_wizardOtherAmountController)) ?? 0) > 0)
          Allowance(
            label: _wizardOtherLabelController.text.trim().isNotEmpty
                ? _wizardOtherLabelController.text.trim()
                : '기타 수당',
            amount: (int.tryParse(_numText(_wizardOtherAmountController)) ?? 0).toDouble(),
          ),
      ],
      ..._customItems.map(
        (e) => Allowance(label: e.label, amount: e.amount.toDouble()),
      ),
    ];
    return Worker(
      id: id,
      name: _nameController.text.trim(),
      employeeId: _employeeIdController.text.trim().isNotEmpty
          ? _employeeIdController.text.trim()
          : null,
      phone: _phoneController.text.replaceAll(RegExp(r'[^0-9]'), ''),
      birthDate: _birthDate == null
          ? ''
          : _birthDate!.toIso8601String().substring(0, 10),
      workerType: _employeeType == _EmployeeType.normal
          ? 'regular'
          : _employeeType == _EmployeeType.dispatched
          ? 'dispatch'
          : 'foreigner',
      hourlyWage: hourly,
      isPaidBreak: _isBreakPaid,
      breakMinutes: _currentBreakMinutes().toDouble(),
      workDays: workDays,
      checkInTime: start,
      checkOutTime: end,
      weeklyHours: weeklyHours,
      totalStayMinutes: weeklyTotalStayMinutes,
      pureLaborMinutes: weeklyPureLaborMinutes,
      startDate: _hireDate == null
          ? ''
          : _hireDate!.toIso8601String().substring(0, 10),
      endDate: _isLongTerm || _contractEndDate == null
          ? null
          : _contractEndDate!.toIso8601String().substring(0, 10),
      isProbation: _applyProbationWage90Percent && _canApplyProbation,
      probationMonths: (_applyProbationWage90Percent && _canApplyProbation) ? _probationMonths : 0,
      allowances: allowances,
      hasHealthCert:
          _healthCertificateManagementEnabled && _hasHealthCertificate,
      healthCertExpiry: _healthCertificateExpiryDate
          ?.toIso8601String()
          .substring(0, 10),
      visaType: _employeeType == _EmployeeType.foreigner ? _visaType : null,
      visaExpiry:
          _employeeType == _EmployeeType.foreigner && _visaExpiryDate != null
          ? _visaExpiryDate!.toIso8601String().substring(0, 10)
          : null,
      // 주휴/보험 판정은 순수근로시간(휴게 제외) 기준으로만 판정
      weeklyHolidayPay: _weeklyHours() >= 15,
      weeklyHolidayDay: _weeklyHolidayDay,
      status: 'active',
      createdAt: AppClock.now().toIso8601String(),
      storeId: storeId,
      workScheduleJson: scheduleJson,
      breakStartTime: _breakStartTime.trim(),
      breakEndTime: _computedBreakEndTime(),
      dispatchCompany:
          _isDispatch && _dispatchCompanyController.text.trim().isNotEmpty
          ? _dispatchCompanyController.text.trim()
          : null,
      dispatchContact:
          _isDispatch && _dispatchContactController.text.trim().isNotEmpty
          ? _dispatchContactController.text.replaceAll(RegExp(r'[^0-9-]'), '')
          : null,
      dispatchStartDate: _isDispatch && _dispatchStartDate != null
          ? _dispatchStartDate!.toIso8601String().substring(0, 10)
          : null,
      dispatchEndDate: _isDispatch && _dispatchEndDate != null
          ? _dispatchEndDate!.toIso8601String().substring(0, 10)
          : null,
      dispatchMemo:
          _isDispatch && _dispatchMemoController.text.trim().isNotEmpty
          ? _dispatchMemoController.text.trim()
          : null,
      compensationIncomeType: _compIncomeType == _CompensationIncomeType.labor
          ? 'labor'
          : 'business_income_33',
      deductNationalPension:
          _compIncomeType == _CompensationIncomeType.labor &&
          _deductNationalPension,
      deductHealthInsurance:
          _compIncomeType == _CompensationIncomeType.labor &&
          _deductHealthInsurance,
      deductEmploymentInsurance:
          _compIncomeType == _CompensationIncomeType.labor &&
          _deductEmploymentInsurance,
      trackIndustrialInsurance:
          _compIncomeType == _CompensationIncomeType.labor &&
          _trackIndustrialInsurance,
      applyWithholding33:
          _compIncomeType == _CompensationIncomeType.business33 &&
          _applyWithholding33,
      wageType: _wageType == WageType.monthly ? 'monthly' : 'hourly',
      monthlyWage: _wageType == WageType.monthly
          ? (double.tryParse(_numText(_monthlyWageController)) ?? 0.0)
          : 0.0,
      fixedOvertimeHours: _wageType == WageType.monthly
          ? (double.tryParse(_fixedOvertimeHoursController.text) ?? 0.0)
          : 0.0,
      fixedOvertimePay: _wageType == WageType.monthly && _wizardApplied
          ? (double.tryParse(_numText(_wizardFixedOtController)) ?? 0.0)
          : 0.0,
      mealTaxExempt: _mealTaxExempt,
      isPaperContract: isPaperContract ?? widget.initialWorker?.isPaperContract ?? false,
      includeMealInOrdinary: _includeMealInOrdinary,
      includeAllowanceInOrdinary: _includeAllowanceInOrdinary,
      includeFixedOtInAverage: _includeFixedOtInAverage,
    );
  }

  Future<bool> _showBusinessIncomeWarningDialog(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(
          Icons.warning_amber_rounded,
          color: Color(0xFFE65100),
          size: 44,
        ),
        title: const Text('주의'),
        content: const SingleChildScrollView(
          child: Text(
            '주의: 실질 근로자일 경우 추후 4대 보험 소급 청구 및 퇴직금 분쟁의 소지가 있습니다.',
            style: TextStyle(fontSize: 15, height: 1.4),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('확인'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Widget _compensationDeductionSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '소득 유형',
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: const Text('근로소득'),
              selected: _compIncomeType == _CompensationIncomeType.labor,
              selectedColor: const Color(0xFF1a6ebd),
              backgroundColor: const Color(0xFFF2F2F7),
              labelStyle: TextStyle(
                color: _compIncomeType == _CompensationIncomeType.labor
                    ? Colors.white
                    : Colors.black54,
              ),
              onSelected: (v) {
                if (!v) return;
                setState(() => _compIncomeType = _CompensationIncomeType.labor);
              },
            ),
            ChoiceChip(
              label: const Text('사업소득(3.3%)'),
              selected: _compIncomeType == _CompensationIncomeType.business33,
              selectedColor: const Color(0xFFE65100),
              backgroundColor: const Color(0xFFF2F2F7),
              labelStyle: TextStyle(
                color: _compIncomeType == _CompensationIncomeType.business33
                    ? Colors.white
                    : Colors.black54,
              ),
              onSelected: (v) async {
                if (!v) return;
                if (_compIncomeType == _CompensationIncomeType.business33)
                  return;
                final ok = await _showBusinessIncomeWarningDialog(context);
                if (!context.mounted) return;
                if (ok) {
                  setState(() {
                    _compIncomeType = _CompensationIncomeType.business33;
                    _applyWithholding33 = true;
                  });
                }
              },
            ),
          ],
        ),
        if (_compIncomeType == _CompensationIncomeType.labor) ...[
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE0E0E0)),
            ),
            child: const Text(
              '4대보험 본인부담 요율은 연도·고시에 따라 달라질 수 있습니다. 아래는 관리용 참고치입니다.\n'
              '· 국민연금: 약 4.5%(본인)\n'
              '· 건강·장기요양: 약 3.545% + 장기요양(본인)\n'
              '· 고용보험: 약 0.9%(본인)\n'
              '· 산재보험: 근로자 부담 없음(사업주 전액) — 명세·인건비 관리용',
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: Color(0xFF555555),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('국민연금 공제'),
            subtitle: const Text('참고 요율 약 4.5% · 본인부담'),
            value: _deductNationalPension,
            onChanged: (v) => setState(() => _deductNationalPension = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('건강·장기요양 공제'),
            subtitle: const Text('참고 요율 약 3.545% + 장기요양'),
            value: _deductHealthInsurance,
            onChanged: (v) => setState(() => _deductHealthInsurance = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('고용보험 공제'),
            subtitle: const Text('참고 요율 약 0.9% · 본인부담'),
            value: _deductEmploymentInsurance,
            onChanged: (v) => setState(() => _deductEmploymentInsurance = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('산재보험(관리)'),
            subtitle: const Text('근로자 공제 없음 · 인건비/명세에 반영할지 선택'),
            value: _trackIndustrialInsurance,
            onChanged: (v) => setState(() => _trackIndustrialInsurance = v),
          ),
        ] else ...[
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('3.3% 원천징수 공제'),
            subtitle: const Text('사업소득 세액(3.3%) 공제 반영 여부'),
            value: _applyWithholding33,
            onChanged: (v) => setState(() => _applyWithholding33 = v),
          ),
        ],
      ],
    );
  }

  Future<void> _selectDate(
    BuildContext context,
    DateTime? initialDate,
    void Function(DateTime) onSelected, {
    bool isBirthDate = false,
  }) async {
    final DateTime firstDate = isBirthDate ? DateTime(1950) : DateTime(2000);
    final DateTime lastDate = isBirthDate
        ? AppClock.now().subtract(const Duration(days: 1))
        : DateTime(2100);

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate:
          initialDate ?? (isBirthDate ? DateTime(1995, 1, 1) : AppClock.now()),
      firstDate: firstDate,
      lastDate: lastDate,
      locale: const Locale('ko', 'KR'),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF1a1a2e),
              onPrimary: Colors.white,
              surface: Colors.white,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF1a1a2e),
              ),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      if (!isBirthDate &&
          picked.isBefore(AppClock.now().subtract(const Duration(days: 1)))) {
        if (!context.mounted) return;
        final shouldBacktrack = await _showBacktrackDialog(context, picked);
        if (shouldBacktrack == true) {
          // 여기서 필요한 초기화 로직(자동 보정 등)을 수행할 수 있습니다.
          // 현재는 입사일 설정만으로도 엔진이 "기록 없음 = 만근 가정" 로직을 수행하도록 설계됨
        }
      }
      onSelected(picked);
    }
  }

  Future<bool?> _showBacktrackDialog(
    BuildContext context,
    DateTime pickedDate,
  ) async {
    final dateStr = DateFormat('yyyy년 MM월 dd일').format(pickedDate);
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(
          Icons.history_edu_rounded,
          color: Color(0xFF1a6ebd),
          size: 40,
        ),
        title: const Text('과거 데이터 보정'),
        content: Text(
          '$dateStr 입사로 선택하셨습니다.\n\n이 날짜부터 현재까지의 데이터를 시스템이 자동으로 보정(정상 근로 간주)하시겠습니까?\n\n이 작업은 초기 연차 발생량 계산에 활용됩니다.',
          style: const TextStyle(fontSize: 15, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('아니오'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('네, 보정합니다'),
          ),
        ],
      ),
    );
  }

  String _formatDateKo(DateTime? date) {
    if (date == null) return '선택 안 됨';
    return DateFormat('yyyy년 MM월 dd일', 'ko_KR').format(date);
  }

  int _calcAge(DateTime birthDate) {
    final today = AppClock.now();
    var age = today.year - birthDate.year;
    if (today.month < birthDate.month ||
        (today.month == birthDate.month && today.day < birthDate.day)) {
      age--;
    }
    return age;
  }

  void _checkMinor(DateTime birthDate) {
    final age = _calcAge(birthDate);
    setState(() {
      _isMinor = age < 18;
    });
  }

  Widget _buildMinorGuideItem(String title, String content) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 4,
          height: 4,
          margin: const EdgeInsets.only(top: 6, right: 6),
          decoration: const BoxDecoration(
            color: Color(0xFFE24B4A),
            shape: BoxShape.circle,
          ),
        ),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFFA32D2D),
                height: 1.5,
              ),
              children: [
                TextSpan(
                  text: '$title: ',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                TextSpan(text: content),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDispatchGuideItem(String title, String content) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 4,
          height: 4,
          margin: const EdgeInsets.only(top: 6, right: 6),
          decoration: const BoxDecoration(
            color: Color(0xFF7C3AED),
            shape: BoxShape.circle,
          ),
        ),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF7C3AED),
                height: 1.5,
              ),
              children: [
                TextSpan(
                  text: '$title: ',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                TextSpan(text: content),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(
    String title,
    IconData icon,
    Color iconBg,
    bool isExpanded,
    VoidCallback onTap, {
    String? subtitle,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (subtitle != null && !isExpanded)
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF888888),
                      ),
                    ),
                ],
              ),
            ),
            AnimatedRotation(
              turns: isExpanded ? 0.5 : 0,
              duration: const Duration(milliseconds: 200),
              child: const Icon(
                Icons.keyboard_arrow_down,
                color: Color(0xFFBBBBBB),
                size: 22,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(
    String title,
    IconData icon,
    Color iconBg,
    bool isExpanded,
    VoidCallback onToggle,
    List<Widget> children, {
    String? subtitle,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E5EA), width: 0.5),
      ),
      child: Column(
        children: [
          _buildSectionHeader(
            title,
            icon,
            iconBg,
            isExpanded,
            onToggle,
            subtitle: subtitle,
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 250),
            crossFadeState: isExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox.shrink(),
            secondChild: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Divider(
                  height: 1,
                  thickness: 0.5,
                  color: Color(0xFFF0F0F0),
                ),
                ...children,
              ],
            ),
          ),
        ],
      ),
    );
  }

  String get _formattedPhoneSubtitle =>
      _formatPhoneDisplay(_phoneController.text);

  String _subtitleSection1() {
    if (_nameController.text.trim().isNotEmpty &&
        _phoneController.text.trim().isNotEmpty) {
      return '${_nameController.text.trim()} · $_formattedPhoneSubtitle';
    }
    return '이름, 연락처, 생년월일, 시급';
  }

  String _subtitleSection2() {
    final summary = _workTimeSummaryText();
    if (summary == '근무시간 미입력') {
      return '근무요일, 시간 설정';
    }
    final groups = _workScheduleGroups();
    if (groups.isEmpty) return '근무요일, 시간 설정';
    final g = groups.first;
    final daysText = g.days.map(_weekdayLabel).join('/');
    return '$daysText · ${g.start}~${g.end}';
  }

  String _subtitleSection3() {
    if (_compIncomeType == _CompensationIncomeType.labor) {
      return '근로소득 · 4대보험 적용';
    }
    return '급여 공제 설정';
  }

  String _weekdayLabelShort(int code) {
    const labels = ['일', '월', '화', '수', '목', '금', '토'];
    if (code >= 0 && code < labels.length) return labels[code];
    return '';
  }

  Future<int?> _showWeeklyHolidayDialog(
    BuildContext context,
    bool isFiveOrMore,
  ) async {
    int tempDay = _weeklyHolidayDay;
    return showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Text(
                '휴일(주휴일) 선택',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isFiveOrMore
                        ? '근로기준법상 주 1회 이상의 휴일이 필요합니다.\n휴일근로(1.5배)로 정산할 요일을 선택해 주세요.'
                        : '근로기준법상 주 1회 이상의 휴일 지정이 필요합니다.\n서류상 휴일(주휴일)로 지정할 요일을 선택해 주세요.',
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.4,
                      color: Color(0xFF424242),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (int day = 0; day < 7; day++)
                        ChoiceChip(
                          label: Text(['일', '월', '화', '수', '목', '금', '토'][day]),
                          selected: tempDay == day,
                          selectedColor: const Color(0xFF1a6ebd),
                          backgroundColor: const Color(0xFFF2F2F7),
                          labelStyle: TextStyle(
                            color: tempDay == day
                                ? Colors.white
                                : Colors.black54,
                          ),
                          onSelected: (selected) {
                            if (selected) setState(() => tempDay = day);
                          },
                        ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  child: const Text('취소', style: TextStyle(color: Colors.grey)),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, tempDay),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF1a6ebd),
                  ),
                  child: const Text('확인'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<Worker?> _saveWorkerToLocalAndCloud({bool? isPaperContract}) async {
    setState(() => _isLoading = true);
    final storeId = await _fetchStoreId();
    if (!mounted) return null;
    if (storeId == null) {
      setState(() => _isLoading = false);
      return null;
    }
    if (_nameController.text.trim().isEmpty) {
      _showErrorAndFocus('이름을 입력해 주세요.', _nameFocusNode);
      return null;
    }
    if (_phoneController.text.replaceAll(RegExp(r'[^0-9]'), '').isEmpty) {
      _showErrorAndFocus('연락처를 입력해 주세요.', _phoneFocusNode);
      return null;
    }
    if (_hireDate == null) {
      _showErrorAndScroll('입사일을 선택해 주세요.', _hireDateKey);
      return null;
    }
    if (!_isDispatch && (_workStartByDay.isEmpty || _workEndByDay.isEmpty)) {
      _showErrorAndScroll('근무 요일 및 시간을 선택해 주세요.', _workScheduleKey);
      return null;
    }

    if (!_isDispatch && _workStartByDay.length == 7) {
      try {
        final storeDoc = await FirebaseFirestore.instance
            .collection('stores')
            .doc(storeId)
            .get();
        final isFiveOrMore =
            (storeDoc.data()?['isFiveOrMore'] as bool?) ?? false;
        if (!mounted) return null;
        final result = await _showWeeklyHolidayDialog(context, isFiveOrMore);
        if (result == null) {
          setState(() => _isLoading = false);
          return null;
        }
        _weeklyHolidayDay = result;
      } catch (e) {
        debugPrint('Error showing weekly holiday dialog: $e');
      }
    }

    if (_isMinor) {
      if (_hasNightWork(
        _bulkStartController.text.trim(),
        _bulkEndController.text.trim(),
      )) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('연소자는 오후 10시~오전 6시 사이의 근로가 원칙적으로 금지되어 있습니다.'),
          ),
        );
        setState(() => _isLoading = false);
        return null;
      }
      for (final startHm in _workStartByDay.values) {
        final day = _workStartByDay.keys.firstWhere(
          (k) => _workStartByDay[k] == startHm,
        );
        final endHm = _workEndByDay[day] ?? '';
        if (_hasNightWork(startHm, endHm)) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('연소자는 오후 10시~오전 6시 사이의 근로가 원칙적으로 금지되어 있습니다.'),
            ),
          );
          setState(() => _isLoading = false);
          return null;
        }
      }
    }
    if (_employeeType == _EmployeeType.foreigner &&
        (_visaType == null || _visaType!.isEmpty)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('외국인 직원은 비자 종류가 필요합니다.')));
      setState(() => _isLoading = false);
      return null;
    }

    if (_isDispatch) {
      if (_dispatchCompanyController.text.trim().isEmpty ||
          _dispatchStartDate == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('파견 정보의 필수 항목을 확인해 주세요.')));
        setState(() => _isLoading = false);
        return null;
      }
    }
    final baseWage = int.tryParse(_numText(_wageController)) ?? 0;
    if (_wageType == WageType.monthly) {
      // ── 초보수적 방어형: 구성→합산 검증 ──
      final baseSalaryVal = int.tryParse(_numText(_monthlyWageController)) ?? 0;
      if (baseSalaryVal <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('기본급을 입력해 주세요.'),
            backgroundColor: Color(0xFFE24B4A),
          ),
        );
        setState(() => _isLoading = false);
        return null;
      }

      // 1단계 Hard Block: 기본급 / S < 최저임금 → 저장 차단
      final weeklyH = _weeklyHours();
      final weeklyHolidayH = weeklyH >= 15 ? weeklyH / _workDaysPerWeek() : 0.0;
      final scheduledH = ((weeklyH + weeklyHolidayH) * 4.345).ceilToDouble();
      if (scheduledH > 0) {
        final conservativeRate = baseSalaryVal / scheduledH;
        if (conservativeRate < _minimumHourlyWage) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '🚫 기본급만으로 최저임금 미달! (${_formatMoney(conservativeRate.round())}원/h < ${_formatMoney(_minimumHourlyWage.round())}원/h)\n분쟁 방지를 위해 기본급을 ${_formatMoney((scheduledH * _minimumHourlyWage).ceil())}원 이상으로 설정해 주세요.',
              ),
              backgroundColor: const Color(0xFFE53935),
              duration: const Duration(seconds: 5),
            ),
          );
          setState(() => _isLoading = false);
          return null;
        }
      } // scheduledH > 0 guard
    } else if (_minimumHourlyWage > 0 && baseWage < _minimumHourlyWage) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '⚠️ 최저임금(${_formatMoney(_minimumHourlyWage)}원) 미달입니다. 최저임금 이상으로 입력해 주세요.',
          ),
          backgroundColor: const Color(0xFFE24B4A),
        ),
      );
      setState(() => _isLoading = false);
      return null;
    }
    final worker = _toWorker(storeId, isPaperContract: isPaperContract);
    try {
      await WorkerService.save(worker);
      return worker;
    } catch (e) {
      debugPrint('Worker save failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('저장 실패: $e')));
      }
      return null;
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showErrorAndFocus(String message, FocusNode node) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
    FocusScope.of(context).requestFocus(node);
    setState(() => _isLoading = false);
  }

  /// 월급제 저장 전 근로계약서 미리보기 팝업
  Future<bool?> _showContractPreviewDialog() async {
    final isMonthly = _wageType == WageType.monthly;
    final baseSalary = int.tryParse(_numText(_monthlyWageController)) ?? 0;
    final mealVal = int.tryParse(_numText(_mealAllowanceController)) ?? 0;
    final fixedOTH = (double.tryParse(_fixedOvertimeHoursController.text) ?? 0)
        .floor();
    final weeklyH = _weeklyHours();
    final weeklyHolidayH = weeklyH >= 15 ? weeklyH / _workDaysPerWeek() : 0.0;
    final sRefH = ((weeklyH + weeklyHolidayH) * 4.345).ceil();
    // 통상시급: 월급제는 (기본급+식대)/209 역산, 시급제는 입력값 사용
    final hourlyRate = isMonthly
        ? (sRefH > 0 ? ((baseSalary + mealVal) / sRefH).round() : 0)
        : (int.tryParse(_numText(_wageController)) ?? 0);
    // 고정연장수당: 위자드 확정값 우선, 없으면 통상시급×가산율×시간
    final otMultiplier = _isFiveOrMoreStore ? 1.5 : 1.0;
    final fixedOTPay = _wizardApplied
        ? (int.tryParse(_numText(_wizardFixedOtController)) ?? 0)
        : (fixedOTH > 0 && hourlyRate > 0
            ? (fixedOTH * hourlyRate * otMultiplier).round()
            : 0);

    // 최저임금 미달 시 차단 (월급제)
    if (isMonthly && sRefH > 0 && baseSalary > 0) {
      final rate = baseSalary / sRefH;
      if (rate < _minimumHourlyWage) {
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: const Icon(
              Icons.block_rounded,
              color: Color(0xFFE53935),
              size: 48,
            ),
            title: const Text(
              '⛔ 최저임금 미달',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            content: Text(
              '임금 설계 단계에서 법적 하한선을 준수하십시오.\n\n'
              '현재 역산 시급: ${_formatMoney(rate.round())}원/h\n'
              '최저임금: ${_formatMoney(_minimumHourlyWage.round())}원/h\n\n'
              '기본급을 ${_formatMoney((sRefH * _minimumHourlyWage).ceil())}원 이상으로 설정해 주세요.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('돌아가기'),
              ),
            ],
          ),
        );
        return false;
      }
    }

    // 최저임금 미달 시 차단 (시급제)
    if (!isMonthly && hourlyRate > 0 && hourlyRate < _minimumHourlyWage) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(
            Icons.block_rounded,
            color: Color(0xFFE53935),
            size: 48,
          ),
          title: const Text(
            '⛔ 최저임금 미달',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          content: Text(
            '시급이 최저임금 기준에 미달합니다.\n\n'
            '현재 시급: ${_formatMoney(hourlyRate)}원/h\n'
            '최저임금: ${_formatMoney(_minimumHourlyWage.round())}원/h\n\n'
            '시급을 ${_formatMoney(_minimumHourlyWage.round())}원 이상으로 설정해 주세요.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('돌아가기'),
            ),
          ],
        ),
      );
      return false;
    }

    // 미리보기 팝업
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            backgroundColor: const Color(0xFF1a1a2e),
            title: const Text(
              '📋 근로계약서 미리보기',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            leading: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.pop(ctx, false),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // 임금 구성
              if (isMonthly)
                _previewSection('💰 임금 구성', [
                  _previewRow('급여 형태', '월급제 (고정급)'),
                  _previewRow('기본급', '${_formatMoney(baseSalary)}원'),
                  _previewRow('시급 (역산)', '${_formatMoney(hourlyRate)}원'),
                  _previewRow('S_Ref 기준시간', '$sRefH시간'),
                  if (mealVal > 0)
                    _previewRow('식대 (비과세)', '${_formatMoney(mealVal)}원'),
                  if (fixedOTH > 0)
                    _previewRow(
                      '고정연장수당',
                      '${_formatMoney(fixedOTPay)}원 (월 $fixedOTH시간)',
                    ),
                ])
              else
                _previewSection('💰 임금 구성', [
                  _previewRow('급여 형태', '시급제'),
                  _previewRow('시급', '${_formatMoney(hourlyRate)}원'),
                  if (weeklyH >= 15)
                    _previewRow(
                      '주휴수당',
                      '발생 (주 ${weeklyH.toStringAsFixed(1)}시간 ≥ 15시간)',
                    ),
                  if (weeklyH < 15)
                    _previewRow(
                      '주휴수당',
                      '미발생 (주 ${weeklyH.toStringAsFixed(1)}시간 < 15시간)',
                    ),
                ]),
              const SizedBox(height: 16),

              // 근무 조건
              _previewSection('📅 근무 조건', [
                _previewRow(
                  '근무 요일',
                  (() {
                    const labels = ['일', '월', '화', '수', '목', '금', '토'];
                    final sorted = [..._selectedDays]..sort();
                    return sorted.map((d) => labels[d % 7]).join(', ');
                  })(),
                ),
                _previewRow(
                  '출퇴근 시간',
                  '${_workStartController.text} ~ ${_workEndController.text}',
                ),
                _previewRow('휴게시간', '${_breakMinutesController.text}분'),
                _previewRow('주 소정근로', '${weeklyH.toStringAsFixed(1)}시간'),
              ]),
              const SizedBox(height: 16),

              // 노무 방패 특약 (월급제만 표시)
              if (isMonthly) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3E5F5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF7B1FA2),
                      width: 0.5,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.shield_outlined,
                            size: 18,
                            color: Color(0xFF7B1FA2),
                          ),
                          SizedBox(width: 6),
                          Text(
                            '🛡️ 노무 방패 특약 (계약서에 삽입)',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF4A148C),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _shieldClauseItem(
                        '[특약 1] 주휴수당',
                        '기본급은 유급주휴수당을 포함하여 산정된 금액입니다. '
                            '단, 소정근로일을 개근하지 않은 경우 해당 주휴수당은 지급되지 않으며, '
                            '이에 해당하는 금액은 공제될 수 있습니다.',
                      ),
                      if (fixedOTH > 0 && fixedOTPay > 0) ...[
                        const SizedBox(height: 8),
                        Builder(builder: (_) {
                          // 통상시급 = (기본급 + 식대) / 209
                          final conservativeHourly = sRefH > 0
                              ? (baseSalary + mealVal) / sRefH
                              : 0.0;
                          // 고정OT 시간 역산 — ★ 보수적 내림 적용
                          final fixedOTHoursCalc = _isFiveOrMoreStore
                              ? fixedOTPay / (conservativeHourly * 1.5)
                              : fixedOTPay / conservativeHourly;
                          final fixedOTHoursDisplay =
                              (fixedOTHoursCalc * 10).floor() / 10.0;
                          // 법정 가산 시급 (원 단위 절사)
                          final premiumHourly =
                              (conservativeHourly * 1.5).floor();
                          final overtimeHourly =
                              (conservativeHourly * 2.0).floor();

                          final String clauseBody;
                          if (_isFiveOrMoreStore) {
                            clauseBody =
                                '고정연장수당 ${_formatMoney(fixedOTPay)}원은 '
                                '월 ${fixedOTHoursDisplay.toStringAsFixed(1)}시간의 연장근로에 대한 사전 정액 지급분입니다.\n'
                                '본 사업장은 상시 근로자 5인 이상으로 근로기준법 제56조에 따른 가산수당이 적용됩니다.\n\n'
                                '① 실제 연장근로가 월 ${fixedOTHoursDisplay.toStringAsFixed(1)}시간 이하인 경우:\n'
                                '   고정연장수당 전액 지급 (차액 공제 없음)\n\n'
                                '② 실제 연장근로가 월 ${fixedOTHoursDisplay.toStringAsFixed(1)}시간을 초과하는 경우:\n'
                                '   초과시간 × ${_formatMoney(premiumHourly)}원(1.5배 가산)을 익월 급여에 별도 지급\n\n'
                                '③ 휴일 및 휴무일 근무 시:\n'
                                '   - 8시간 이내: 시간당 ${_formatMoney(premiumHourly)}원(1.5배)\n'
                                '   - 8시간 초과: 시간당 ${_formatMoney(overtimeHourly)}원(2.0배)\n'
                                '   익월 급여에 별도 지급 (고정연장시간에서 차감 불가)';
                          } else {
                            clauseBody =
                                '고정연장수당 ${_formatMoney(fixedOTPay)}원은 '
                                '월 ${fixedOTHoursDisplay.toStringAsFixed(1)}시간의 연장근로에 대한 사전 정액 지급분입니다.\n'
                                '본 사업장은 상시 근로자 5인 미만으로 근로기준법 제56조(가산수당)가 적용되지 않습니다.\n\n'
                                '① 실제 연장근로가 월 ${fixedOTHoursDisplay.toStringAsFixed(1)}시간 이하인 경우:\n'
                                '   고정연장수당 전액 지급 (차액 공제 없음)\n\n'
                                '② 실제 연장근로가 월 ${fixedOTHoursDisplay.toStringAsFixed(1)}시간을 초과하는 경우:\n'
                                '   초과시간 × ${_formatMoney(conservativeHourly.floor())}원을 익월 급여에 별도 지급\n\n'
                                '③ 휴일 및 휴무일 근무 시:\n'
                                '   근무시간 × ${_formatMoney(conservativeHourly.floor())}원을 별도 지급\n'
                                '   (고정연장시간에서 차감 불가, 원 단위 절사 적용)';
                          }

                          return _shieldClauseItem(
                            '[특약 2] 고정연장수당 합의',
                            clauseBody,
                          );
                        }),
                      ],
                      const SizedBox(height: 8),
                      _shieldClauseItem(
                        '[특약 ${fixedOTH > 0 && fixedOTPay > 0 ? "3" : "2"}] 평균 주수 합의',
                        '본 급여는 1개월 평균 주수(4.345주)를 기준으로 산정된 금액이며, '
                            '실제 근로 제공 여부에 따라 결근·지각·조퇴 시간에 대해서는 '
                            '관련 법령 및 내부 기준에 따라 공제될 수 있습니다.',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // SHA-256 해시 안내
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '📌 저장 시 근로계약서에 SHA-256 무결성 해시가 자동 삽입됩니다.\n'
                  'Engine: Alba Payroll Standard Engine v1.0',
                  style: TextStyle(fontSize: 11, color: Color(0xFF666666)),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('수정하기'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: () => Navigator.pop(ctx, true),
                      icon: const Icon(Icons.check_circle_outline),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF1a1a2e),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      label: const Text(
                        '확인 후 저장',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _previewSection(String title, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E5EA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }

  Widget _previewRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: Color(0xFF666666)),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _shieldClauseItem(String title, String body) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Color(0xFF4A148C),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          body,
          style: const TextStyle(
            fontSize: 11,
            color: Color(0xFF555555),
            height: 1.4,
          ),
        ),
      ],
    );
  }

  void _showErrorAndScroll(String message, GlobalKey key) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
    if (key.currentContext != null) {
      Scrollable.ensureVisible(
        key.currentContext!,
        duration: const Duration(milliseconds: 300),
        alignment: 0.5,
      );
    }
    setState(() => _isLoading = false);
  }

  Future<void> _saveOnly() async {
    final worker = await _saveWorkerToLocalAndCloud();
    if (!mounted || worker == null) return;
    // 온보딩: 첫 직원 등록 완료
    OnboardingGuideService.instance.completeStep(OnboardingStep.firstStaff);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('저장되었습니다.')));
    if (widget.initialWorker == null) {
      final storeId = await _fetchStoreId();
      if (!mounted) return;
      if (storeId == null) {
        Navigator.pop(context);
        return;
      }
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              StaffInviteCodeScreen(storeId: storeId, worker: worker),
        ),
      );
      // 온보딩: 초대 코드 발송 완료
      OnboardingGuideService.instance.completeStep(OnboardingStep.sendInvite);
      if (!mounted) return;
      Navigator.pop(context);
      return;
    }
    if (!mounted) return;
    Navigator.pop(context);
  }

  Future<void> _saveWithPaperContract() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('서면 계약서 작성 확인', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text(
          '직원과 실제 종이로 된 서면 계약서를 작성하셨습니까?\n\n'
          '이 경우 전자 근로계약서 생성 절차가 생략되며, '
          '입력하신 정보는 실제 서면 계약서의 내용과 일치해야 합니다.\n\n'
          '허위 입력으로 인한 법적 책임은 사업주에게 있습니다.',
          style: TextStyle(height: 1.5, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소', style: TextStyle(color: Colors.grey)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1a1a2e)),
            child: const Text('동의 후 저장'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final worker = await _saveWorkerToLocalAndCloud(isPaperContract: true);
    if (!mounted || worker == null) return;
    
    // 온보딩: 첫 직원 등록 완료
    OnboardingGuideService.instance.completeStep(OnboardingStep.firstStaff);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('서면 계약 상태로 저장되었습니다.')),
    );
    
    if (widget.initialWorker == null) {
      final storeId = await _fetchStoreId();
      if (!mounted) return;
      if (storeId == null) {
        Navigator.pop(context);
        return;
      }
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => StaffInviteCodeScreen(storeId: storeId, worker: worker),
        ),
      );
      // 온보딩: 초대 코드 발송 완료
      OnboardingGuideService.instance.completeStep(OnboardingStep.sendInvite);
      if (!mounted) return;
      Navigator.pop(context);
      return;
    }
    if (!mounted) return;
    Navigator.pop(context);
  }

  Future<void> _saveAndContract() async {
    try {
      // ── 저장 전 근로계약서 미리보기 (시급제/월급제 공통) ──
      final confirmed = await _showContractPreviewDialog();
      if (confirmed != true) return;

      final worker = await _saveWorkerToLocalAndCloud();
      if (!mounted || worker == null) return;

      final storeId = await _fetchStoreId();
      if (storeId == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('매장 정보를 찾을 수 없습니다.')));
        return;
      }

      // 순차적 마법사 시작
      await _startDocumentWizard(worker, storeId);
    } catch (e) {
      debugPrint('Save and contract failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('오류가 발생했습니다: $e')));
      }
    }
  }

  Future<void> _startDocumentWizard(Worker worker, String storeId) async {
    Map<DocumentType, String> statuses = {};
    bool hasChanges = false;

    try {
      hasChanges = _hasProfileChanges();
      statuses = await _fetchDocumentStatuses(worker.id, storeId);
    } catch (e) {
      debugPrint('Wizard init failed: $e');
      // 에러가 나더라도 기본적으로는 처음부터 작성하게 함
      hasChanges = true;
    }

    bool isCompleted(DocumentType type) {
      if (hasChanges) return false;
      final s = statuses[type];
      return s != null && s != 'draft';
    }

    // 2. 근로자 명부 작성
    if (!isCompleted(DocumentType.worker_record)) {
      if (!mounted) return;
      final showNextFromRecord = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => WorkerRecordScreen(
            worker: worker,
            document: LaborDocument(
              id: '${worker.id}_worker_record',
              title: '근로자 명부',
              type: DocumentType.worker_record,
              staffId: worker.id,
              storeId: storeId,
              status: 'draft',
              createdAt: AppClock.now(),
            ),
            isWizardMode: true,
            nextButtonLabel: '다음: 휴일·야간동의서 작성',
            onNext: () => Navigator.pop(context, true),
          ),
        ),
      );
      if (!mounted) return;
      if (showNextFromRecord != true) {
        if (showNextFromRecord == false) Navigator.pop(context);
        return;
      }
    }

    // 3. 야간 및 휴일근로 동의서 작성
    if (!isCompleted(DocumentType.night_consent)) {
      if (!mounted) return;
      final showNextFromConsent = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => NightConsentScreen(
            worker: worker,
            document: LaborDocument(
              id: '${worker.id}_night_consent',
              title: '휴일·야간근로 동의서',
              type: DocumentType.night_consent,
              staffId: worker.id,
              storeId: storeId,
              status: 'draft',
              createdAt: AppClock.now(),
            ),
            isWizardMode: true,
            nextButtonLabel: '다음: 채용 체크리스트 작성',
            onNext: () => Navigator.pop(context, true),
          ),
        ),
      );
      if (!mounted) return;
      if (showNextFromConsent != true) {
        if (showNextFromConsent == false) Navigator.pop(context);
        return;
      }
    }

    // 4. 채용 체크리스트 작성
    if (!isCompleted(DocumentType.checklist)) {
      if (!mounted) return;
      final showNextFromChecklist = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => HiringChecklistScreen(
            worker: worker,
            storeId: storeId,
            document: LaborDocument(
              id: '${worker.id}_checklist',
              title: '채용 체크리스트',
              type: DocumentType.checklist,
              staffId: worker.id,
              storeId: storeId,
              status: 'draft',
              createdAt: AppClock.now(),
            ),
            isWizardMode: true,
            nextButtonLabel: '다음: 근로계약서 작성',
            onNext: () => Navigator.pop(context, true),
          ),
        ),
      );
      if (!mounted) return;
      if (showNextFromChecklist != true) {
        if (showNextFromChecklist == false) Navigator.pop(context);
        return;
      }
    }

    // 5. 근로계약서 작성
    final contractType = worker.weeklyHours >= 40
        ? DocumentType.contract_full
        : DocumentType.contract_part;

    if (!isCompleted(contractType)) {
      final documentId = '${worker.id}_${contractType.name}';
      if (!mounted) return;
      final showNextFromContract = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => ContractPage(
            worker: worker,
            storeId: storeId,
            documentId: documentId,
            isWizardMode: widget.initialWorker == null,
          ),
        ),
      );
      if (!mounted) return;
      if (showNextFromContract != true) {
        if (showNextFromContract == false) Navigator.pop(context);
        return;
      }
    }

    // 마법사 마지막 단계: 신규 직원인 경우 노무서류 작성을 모두 마친 후 직원 초대 팝업 띄우기
    if (widget.initialWorker == null) {
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              StaffInviteCodeScreen(storeId: storeId, worker: worker),
        ),
      );
      // 온보딩: 초대 코드 발송 완료
      OnboardingGuideService.instance.completeStep(OnboardingStep.sendInvite);
      if (!mounted) return;
      Navigator.pop(context); // 마법사 종료 후 직원등록 화면 닫기
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: Text(widget.initialWorker == null ? '신규 직원 등록' : '직원 정보 수정'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 160),
        children: [
          // ── 신규 직원 필수 입력 안내 배너 ──
          if (widget.initialWorker == null && !_hideBanner)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1565C0), Color(0xFF1E88E5)],
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF1565C0).withValues(alpha: 0.25),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('\ud83d\udcdd', style: TextStyle(fontSize: 22)),
                          SizedBox(width: 8),
                          Text(
                            '\uc9c1\uc6d0 \uc815\ubcf4\ub97c \uc785\ub825\ud574 \uc8fc\uc138\uc694!',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Text(
                        '① 직원 정보를 꼼꼼히 입력할수록 모든 노무서류(계약서, 명부 등)에 자동 반영되어 사장님이 편해져요!\n'
                        '② 당장 알 수 없는 필수 외 정보는 나중에 수정할 수 있어요.\n'
                        '③ 입력 후 하단의 [저장 및 노무서류 작성] 버튼을 눌러주세요 👇',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white70,
                          height: 1.6,
                        ),
                      ),
                    ],
                  ),
                  Positioned(
                    top: -12,
                    right: -12,
                    child: IconButton(
                      icon: const Icon(
                        Icons.close,
                        color: Colors.white70,
                        size: 20,
                      ),
                      onPressed: () async {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setBool('hide_add_staff_banner', true);
                        if (mounted) setState(() => _hideBanner = true);
                      },
                      tooltip: '다시 보지 않기',
                    ),
                  ),
                ],
              ),
            ),
          _buildSection(
            '필수 정보',
            Icons.person_outline,
            const Color(0xFF1a6ebd),
            _section1Expanded,
            () => setState(() => _section1Expanded = !_section1Expanded),
            [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('일반직'),
                            selected: _employeeType == _EmployeeType.normal,
                            selectedColor: const Color(0xFF1a6ebd),
                            backgroundColor: const Color(0xFFF2F2F7),
                            labelStyle: TextStyle(
                              color: _employeeType == _EmployeeType.normal
                                  ? Colors.white
                                  : Colors.black54,
                            ),
                            onSelected: (_) =>
                                _onWorkerTypeChanged(_EmployeeType.normal),
                          ),
                          ChoiceChip(
                            label: const Text('파견직'),
                            selected: _employeeType == _EmployeeType.dispatched,
                            selectedColor: const Color(0xFF1a6ebd),
                            backgroundColor: const Color(0xFFF2F2F7),
                            labelStyle: TextStyle(
                              color: _employeeType == _EmployeeType.dispatched
                                  ? Colors.white
                                  : Colors.black54,
                            ),
                            onSelected: (_) =>
                                _onWorkerTypeChanged(_EmployeeType.dispatched),
                          ),
                          ChoiceChip(
                            label: const Text('외국인'),
                            selected: _employeeType == _EmployeeType.foreigner,
                            selectedColor: const Color(0xFF1a6ebd),
                            backgroundColor: const Color(0xFFF2F2F7),
                            labelStyle: TextStyle(
                              color: _employeeType == _EmployeeType.foreigner
                                  ? Colors.white
                                  : Colors.black54,
                            ),
                            onSelected: (_) =>
                                _onWorkerTypeChanged(_EmployeeType.foreigner),
                          ),
                        ],
                      ),
                    ),
                    AnimatedCrossFade(
                      duration: const Duration(milliseconds: 300),
                      crossFadeState: _isDispatch
                          ? CrossFadeState.showSecond
                          : CrossFadeState.showFirst,
                      firstChild: const SizedBox.shrink(),
                      secondChild: Container(
                        margin: const EdgeInsets.fromLTRB(14, 8, 14, 4),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F0FF),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: const Color(0xFF8B5CF6),
                            width: 0.5,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.info_outline,
                                  color: Color(0xFF7C3AED),
                                  size: 15,
                                ),
                                const SizedBox(width: 6),
                                const Text(
                                  '파견근로자 안내',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF7C3AED),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            _buildDispatchGuideItem(
                              '급여/4대보험',
                              '파견업체에서 관리 및 납부\n별도 입력 불필요',
                            ),
                            const SizedBox(height: 4),
                            _buildDispatchGuideItem(
                              '근로계약서',
                              '파견업체와 근로자 간 체결\n이 앱에서 작성 불필요',
                            ),
                            const SizedBox(height: 4),
                            _buildDispatchGuideItem(
                              '5인 판단',
                              '상시 근로자 산정에서 제외\n(근로기준법 시행령 제7조의2)',
                            ),
                            const SizedBox(height: 4),
                            _buildDispatchGuideItem(
                              '보건증',
                              '파견근로자도 보건증 필요\n만료일 관리는 동일하게 적용',
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: _nameController,
                            focusNode: _nameFocusNode,
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                              labelText: '이름 *',
                              hintText: '실명 입력',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: _employeeIdController,
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                              labelText: 'ID (선택)',
                              hintText: '동명이인 구분용',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _phoneController,
                      focusNode: _phoneFocusNode,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: '연락처 *',
                        hintText: '010-0000-0000',
                      ),
                      keyboardType: TextInputType.phone,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9-]')),
                        LengthLimitingTextInputFormatter(13),
                      ],
                    ),
                    const SizedBox(height: 14),
                    GestureDetector(
                      onTap: () => _selectDate(
                        context,
                        _birthDate,
                        (date) => setState(() {
                          _birthDate = date;
                          _checkMinor(date);
                        }),
                        isBirthDate: true,
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F5F5),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.cake_outlined,
                              color: Color(0xFF888888),
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _formatDateKo(_birthDate),
                                style: TextStyle(
                                  fontSize: 15,
                                  color: _birthDate != null
                                      ? const Color(0xFF1a1a2e)
                                      : const Color(0xFFBBBBBB),
                                ),
                              ),
                            ),
                            if (_birthDate != null)
                              Text(
                                '만 ${_calcAge(_birthDate!)}세',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: _isMinor
                                      ? const Color(0xFFE24B4A)
                                      : const Color(0xFF888888),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    AnimatedCrossFade(
                      duration: const Duration(milliseconds: 300),
                      crossFadeState: _isMinor
                          ? CrossFadeState.showSecond
                          : CrossFadeState.showFirst,
                      firstChild: const SizedBox.shrink(),
                      secondChild: Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFCEBEB),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFFE24B4A),
                            width: 0.5,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(
                                  Icons.warning_rounded,
                                  color: Color(0xFFE24B4A),
                                  size: 16,
                                ),
                                SizedBox(width: 6),
                                Text(
                                  '연소자 근로자 안내',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFFA32D2D),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            _buildMinorGuideItem(
                              '친권자(부모님) 종이 동의서 필수 지참',
                              '만 18세 미만 알바생은 부모님의 서면 동의서와 가족관계증명서가 법적으로 필수입니다. 앱 내 전자서명 대신, 반드시 부모님께 직접 종이로 사인을 받아 매장에 보관해 주세요.',
                            ),
                            const SizedBox(height: 6),
                            _buildMinorGuideItem(
                              '야간근로 제한',
                              '오후 10시 ~ 오전 6시 야간근로 원칙 금지\n(고용노동부 인가 시 예외)',
                            ),
                            const SizedBox(height: 6),
                            _buildMinorGuideItem(
                              '휴일근로 제한',
                              '휴일근로 원칙 금지\n(본인 동의 + 고용노동부 인가)',
                            ),
                            const SizedBox(height: 6),
                            _buildMinorGuideItem(
                              '근로시간',
                              '1일 7시간, 주 35시간 초과 금지',
                            ),
                            const SizedBox(height: 10),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                '⚠️ 채용 체크리스트에서 친권자 동의서 필수 확인',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFFA32D2D),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    GestureDetector(
                      onTap: () => _selectDate(
                        context,
                        _hireDate,
                        (d) => setState(() => _hireDate = d),
                      ),
                      child: Container(
                        key: _hireDateKey,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F5F5),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.event_outlined,
                              color: Color(0xFF888888),
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    '입사일 *',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF888888),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _formatDateKo(_hireDate),
                                    style: TextStyle(
                                      fontSize: 15,
                                      color: _hireDate != null
                                          ? const Color(0xFF1a1a2e)
                                          : const Color(0xFFBBBBBB),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            subtitle: _subtitleSection1(),
          ),
          _isDispatch
              ? _buildDispatchSection()
              : _buildSection(
                  '근무 조건',
                  Icons.schedule_outlined,
                  const Color(0xFF286b3a),
                  _section2Expanded,
                  () => setState(() => _section2Expanded = !_section2Expanded),
                  [
                    Padding(
                      key: _workScheduleKey,
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AnimatedCrossFade(
                            crossFadeState: _isEditingWorkTime
                                ? CrossFadeState.showSecond
                                : CrossFadeState.showFirst,
                            duration: const Duration(milliseconds: 250),
                            firstChild: _workTimeSummaryCard(),
                            secondChild: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: _weekdayOrder().map((day) {
                                    final selected = _selectedDays.contains(
                                      day,
                                    );
                                    return ChoiceChip(
                                      label: Text(_weekdayLabel(day)),
                                      selected: selected,
                                      selectedColor: const Color(0xFF1a6ebd),
                                      backgroundColor: const Color(0xFFF2F2F7),
                                      labelStyle: TextStyle(
                                        color: selected
                                            ? Colors.white
                                            : Colors.grey,
                                      ),
                                      labelPadding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                        vertical: 2,
                                      ),
                                      onSelected: (v) {
                                        setState(() {
                                          if (v) {
                                            _selectedDays.add(day);
                                            // 첫 선택일 때만 컨트롤러를 동기화합니다.
                                            if (_selectedDays.length == 1) {
                                              _bulkStartController.text =
                                                  _workStartByDay[day] ??
                                                  _bulkStartController.text;
                                              _bulkEndController.text =
                                                  _workEndByDay[day] ??
                                                  _bulkEndController.text;
                                            }
                                          } else {
                                            _selectedDays.remove(day);
                                          }
                                        });
                                      },
                                    );
                                  }).toList(),
                                ),
                                const SizedBox(height: 14),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: _bulkStartController,
                                        readOnly: true,
                                        onTap: () => _pickTimeForController(
                                          _bulkStartController,
                                        ),
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w900,
                                        ),
                                        decoration: const InputDecoration(
                                          labelText: '근무 시작(HH:mm)',
                                          hintText: '17:00',
                                          contentPadding: EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 18,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: TextField(
                                        controller: _bulkEndController,
                                        readOnly: true,
                                        onTap: () => _pickTimeForController(
                                          _bulkEndController,
                                        ),
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w900,
                                        ),
                                        decoration: const InputDecoration(
                                          labelText: '근무 종료(HH:mm)',
                                          hintText: '21:30',
                                          contentPadding: EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 18,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  child: FilledButton.icon(
                                    onPressed: () {
                                      if (_selectedDays.isEmpty) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text('요일을 먼저 선택해 주세요.'),
                                          ),
                                        );
                                        return;
                                      }
                                      final s = _bulkStartController.text
                                          .trim();
                                      final e = _bulkEndController.text.trim();
                                      if (!_isHm(s) || !_isHm(e)) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              '시간은 HH:mm 형식으로 입력해 주세요.',
                                            ),
                                          ),
                                        );
                                        return;
                                      }
                                      if (_durationMinutes(s, e) <= 0) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              '종료시간은 시작시간보다 뒤여야 합니다.',
                                            ),
                                          ),
                                        );
                                        return;
                                      }
                                      if (_isMinor && _hasNightWork(s, e)) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              '연소자는 야간 근로(22:00~06:00)가 금지되어 있습니다. 시간을 다시 설정해 주세요.',
                                            ),
                                          ),
                                        );
                                        return;
                                      }
                                      setState(() {
                                        for (final day in _selectedDays) {
                                          _workStartByDay[day] = s;
                                          _workEndByDay[day] = e;
                                          _contractedDays.add(day);
                                        }
                                        _workStartController.text = s;
                                        _workEndController.text = e;
                                      });
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            '✅ ${_selectedDays.length}개 요일에 $s~$e 적용 완료',
                                          ),
                                          backgroundColor: const Color(
                                            0xFF286b3a,
                                          ),
                                          duration: const Duration(seconds: 2),
                                        ),
                                      );
                                    },
                                    icon: const Icon(
                                      Icons.check_circle_outline_rounded,
                                    ),
                                    label: const Text('선택 요일에 일괄 적용'),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  '휴게시간',
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    InputChip(
                                      label: const Text('30분'),
                                      selected:
                                          _breakPreset ==
                                          _BreakPreset.minutes30,
                                      onSelected: (v) {
                                        if (!v) return;
                                        setState(
                                          () => _breakPreset =
                                              _BreakPreset.minutes30,
                                        );
                                      },
                                    ),
                                    InputChip(
                                      label: const Text('60분'),
                                      selected:
                                          _breakPreset ==
                                          _BreakPreset.minutes60,
                                      onSelected: (v) {
                                        if (!v) return;
                                        setState(
                                          () => _breakPreset =
                                              _BreakPreset.minutes60,
                                        );
                                      },
                                    ),
                                    InputChip(
                                      label: const Text('직접 입력'),
                                      selected:
                                          _breakPreset == _BreakPreset.custom,
                                      onSelected: (v) {
                                        if (!v) return;
                                        setState(
                                          () => _breakPreset =
                                              _BreakPreset.custom,
                                        );
                                      },
                                    ),
                                  ],
                                ),
                                if (_breakPreset == _BreakPreset.custom) ...[
                                  const SizedBox(height: 10),
                                  TextField(
                                    controller: _breakMinutesController,
                                    decoration: const InputDecoration(
                                      labelText: '직접 입력(분)',
                                      hintText: '예: 45',
                                      helperText: '0~1440 사이 숫자',
                                    ),
                                    keyboardType: TextInputType.number,
                                  ),
                                ],
                                const SizedBox(height: 14),
                                ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 6,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  tileColor: Colors.black12.withValues(
                                    alpha: 0.02,
                                  ),
                                  leading: const CircleAvatar(
                                    backgroundColor: Color(0xFFECEFFB),
                                    child: Icon(
                                      Icons.free_breakfast_rounded,
                                      color: Color(0xFF0032A0),
                                    ),
                                  ),
                                  title: const Text(
                                    '휴게 시작 시간',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  subtitle: Text(
                                    _breakStartTime,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  trailing: const Icon(
                                    Icons.keyboard_arrow_right_rounded,
                                  ),
                                  onTap: () async {
                                    final temp = TextEditingController(
                                      text: _breakStartTime,
                                    );
                                    await _pickTimeForController(temp);
                                    setState(() {
                                      _breakStartTime = temp.text;
                                      _isBreakStartManuallyEdited = true;
                                    });
                                  },
                                ),
                                SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text('휴게시간 유급 처리'),
                                  subtitle: const Text('쉬지 못할 경우 급여 지급'),
                                  value: _isBreakPaid,
                                  onChanged: (val) =>
                                      setState(() => _isBreakPaid = val),
                                ),
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Icon(Icons.info_outline, size: 18, color: Colors.blue.shade800),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          '근로기준법 제54조에 따라 근로시간이 4시간인 경우에는 30분 이상, 8시간인 경우에는 1시간 이상의 휴게시간을 근로시간 도중에 주어야 합니다.',
                                          style: TextStyle(
                                            fontSize: 12,
                                            height: 1.4,
                                            color: Colors.blue.shade900,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (_currentBreakMinutes() == 0 && !_isBreakPaid) ...[
                                  const SizedBox(height: 12),
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.red.shade50,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.red.shade200),
                                    ),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Icon(Icons.warning_amber_rounded, size: 18, color: Colors.red.shade800),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            '경고: 휴게시간을 0분으로 무급 처리할 경우, 법적 휴게시간 미준수(근로기준법 제54조 위반)로 인한 노무 리스크가 발생할 수 있습니다.',
                                            style: TextStyle(
                                              fontSize: 12,
                                              height: 1.4,
                                              color: Colors.red.shade900,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 16),
                                Card(
                                  elevation: 0,
                                  color: const Color(0xFFF3F4F6),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(14),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          '실시간 계산',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          _workMinutesExcludingBreakFromInputs() <=
                                                  0
                                              ? '시간을 선택하면 표시됩니다.'
                                              : '총 ${_workHoursExcludingBreakFromInputs().toStringAsFixed(1)}시간 근무 (휴게 ${_currentBreakMinutes()}분 제외)',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleLarge
                                              ?.copyWith(
                                                fontWeight: FontWeight.w900,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  '등록된 근무 시간표',
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 10),
                                if (_workStartByDay.isEmpty ||
                                    _workEndByDay.isEmpty)
                                  const Text(
                                    '아직 등록된 근무시간이 없습니다.\n위에서 요일과 시간을 먼저 설정해 주세요.',
                                  )
                                else
                                  Column(
                                    children: _workScheduleGroups().map((g) {
                                      final breakEnd = _computedBreakEndTime();
                                      final sortedDays = [...g.days]..sort();
                                      final dayChipList = sortedDays
                                          .map(
                                            (d) => Chip(
                                              label: Text(_weekdayLabel(d)),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                  ),
                                            ),
                                          )
                                          .toList();
                                      return Card(
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.all(14),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          '${g.start}~${g.end}',
                                                          style: Theme.of(context)
                                                              .textTheme
                                                              .titleMedium
                                                              ?.copyWith(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w800,
                                                              ),
                                                        ),
                                                        const SizedBox(
                                                          height: 4,
                                                        ),
                                                        Text(
                                                          '휴게시간: $_breakStartTime~$breakEnd',
                                                          style: Theme.of(
                                                            context,
                                                          ).textTheme.bodySmall,
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  IconButton(
                                                    icon: const Icon(
                                                      Icons
                                                          .delete_outline_rounded,
                                                    ),
                                                    tooltip: '해당 시간표 삭제',
                                                    onPressed: () =>
                                                        setState(() {
                                                          for (final day
                                                              in g.days) {
                                                            _workStartByDay
                                                                .remove(day);
                                                            _workEndByDay
                                                                .remove(day);
                                                            _selectedDays
                                                                .remove(day);
                                                            _contractedDays
                                                                .remove(day);
                                                          }
                                                        }),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 10),
                                              Wrap(
                                                spacing: 8,
                                                runSpacing: 8,
                                                children: dayChipList,
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                const SizedBox(height: 14),
                                SizedBox(
                                  width: double.infinity,
                                  child: FilledButton.icon(
                                    onPressed: () => setState(
                                      () => _isEditingWorkTime = false,
                                    ),
                                    icon: const Icon(Icons.check_rounded),
                                    label: const Text('확인'),
                                  ),
                                ),
                                // [UI 개선] 확인 버튼이 하단 내비게이션 바에 가려지지 않도록 충분한 여백 확보
                                const SizedBox(height: 80),
                              ],
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 14),
                            child: Divider(
                              height: 24,
                              thickness: 0.5,
                              color: Color(0xFFF0F0F0),
                            ),
                          ),
                          Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Expanded(
                                        child: Text(
                                          '주휴일',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: _weeklyHours() >= 15
                                              ? const Color(0xFFEAF3DE)
                                              : const Color(0xFFFFF0DC),
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                        ),
                                        child: Text(
                                          _weeklyHours() >= 15
                                              ? '[유급]'
                                              : '[무급]',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: _weeklyHours() >= 15
                                                ? const Color(0xFF286b3a)
                                                : const Color(0xFF854F0B),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  if (_weeklyHours() < 15)
                                    const Text(
                                      '초단시간 근로자로 주휴수당이 발생하지 않습니다(무급 주휴일)',
                                      style: TextStyle(
                                        color: Color(0xFFA32D2D),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  const SizedBox(height: 10),
                                  const Text(
                                    '주휴일(요일) 선택',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Color(0xFF666666),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      for (final d in const [
                                        1,
                                        2,
                                        3,
                                        4,
                                        5,
                                        6,
                                        0,
                                      ]) // 월..일
                                        ChoiceChip(
                                          label: Text(_weekdayLabelShort(d)),
                                          selected: _weeklyHolidayDay == d,
                                          onSelected: (_) => setState(
                                            () => _weeklyHolidayDay = d,
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (_employeeType == _EmployeeType.foreigner) ...[
                            const SizedBox(height: 12),
                            Card(
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    DropdownButtonFormField<String>(
                                      initialValue: _visaType,
                                      decoration: const InputDecoration(
                                        labelText: '비자 종류',
                                      ),
                                      items: const [
                                        DropdownMenuItem(
                                          value: 'E-9',
                                          child: Text('E-9 비전문취업'),
                                        ),
                                        DropdownMenuItem(
                                          value: 'H-2',
                                          child: Text('H-2 방문취업'),
                                        ),
                                        DropdownMenuItem(
                                          value: 'F-2',
                                          child: Text('F-2 거주'),
                                        ),
                                        DropdownMenuItem(
                                          value: 'F-4',
                                          child: Text('F-4 재외동포'),
                                        ),
                                        DropdownMenuItem(
                                          value: 'F-5',
                                          child: Text('F-5 영주'),
                                        ),
                                        DropdownMenuItem(
                                          value: '기타',
                                          child: Text('기타'),
                                        ),
                                      ],
                                      onChanged: (v) =>
                                          setState(() => _visaType = v),
                                    ),
                                    const SizedBox(height: 8),
                                    if (_visaType == 'F-4' || _visaType == '기타')
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFCEBEB),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: const Text(
                                          '⚠️ 해당 비자는 취업이 제한될 수 있습니다',
                                          style: TextStyle(
                                            color: Color(0xFFA32D2D),
                                          ),
                                        ),
                                      ),
                                    ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: const Text('체류기간 만료일'),
                                      subtitle: Text(
                                        _visaExpiryDate == null
                                            ? '선택 안됨'
                                            : _visaExpiryDate!
                                                  .toIso8601String()
                                                  .substring(0, 10),
                                      ),
                                      trailing: const Icon(
                                        Icons.calendar_today_outlined,
                                      ),
                                      onTap: () async {
                                        final date = await showDatePicker(
                                          context: context,
                                          initialDate:
                                              _visaExpiryDate ??
                                              AppClock.now().add(
                                                const Duration(days: 365),
                                              ),
                                          firstDate: AppClock.now(),
                                          lastDate: AppClock.now().add(
                                            const Duration(days: 3650),
                                          ),
                                        );
                                        if (date != null)
                                          setState(
                                            () => _visaExpiryDate = date,
                                          );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                          Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SwitchListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text('수습기간 적용(90%) 여부'),
                                    subtitle: const Text(
                                      '수습기간 급여를 90%로 반영합니다.',
                                    ),
                                    value: _applyProbationWage90Percent && _canApplyProbation,
                                    activeThumbColor: const Color(0xFF1a6ebd),
                                    onChanged: (v) {
                                      if (v && !_canApplyProbation) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('1년 이상 계약 시에만 수습 기간을 적용할 수 있습니다.')),
                                        );
                                        return;
                                      }
                                      setState(() {
                                        _applyProbationWage90Percent = v;
                                        if (!v) _probationMonths = 3;
                                      });
                                    },
                                  ),
                                  AnimatedCrossFade(
                                    duration: const Duration(milliseconds: 300),
                                    crossFadeState: (_applyProbationWage90Percent && _canApplyProbation)
                                        ? CrossFadeState.showSecond
                                        : CrossFadeState.showFirst,
                                    firstChild: const SizedBox.shrink(),
                                    secondChild: _buildProbationGuide(),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // ── 자동 판정 안내 ──
                          Container(
                            margin: const EdgeInsets.only(top: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0F4FF),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: const Color(0xFF90CAF9),
                              ),
                            ),
                            child: const Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('ℹ️', style: TextStyle(fontSize: 16)),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '주휴 발생 여부는 출퇴근 데이터(월~일 달력 기준)를 기반으로 시스템이 자동 판정합니다.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF1565C0),
                                      height: 1.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 14),
                            child: Divider(
                              height: 24,
                              thickness: 0.5,
                              color: Color(0xFFF0F0F0),
                            ),
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('장기 근무'),
                            value: _isLongTerm,
                            onChanged: (v) => setState(() => _isLongTerm = v),
                          ),
                          if (!_isLongTerm)
                            GestureDetector(
                              onTap: () => _selectDate(
                                context,
                                _contractEndDate,
                                (d) => setState(() => _contractEndDate = d),
                              ),
                              child: Container(
                                margin: const EdgeInsets.only(top: 8),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 14,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF5F5F5),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.calendar_today_outlined,
                                      color: Color(0xFF888888),
                                      size: 18,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            '계약 종료일 (선택)',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Color(0xFF888888),
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            _formatDateKo(_contractEndDate),
                                            style: TextStyle(
                                              fontSize: 15,
                                              color: _contractEndDate != null
                                                  ? const Color(0xFF1a1a2e)
                                                  : const Color(0xFFBBBBBB),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                  subtitle: _subtitleSection2(),
                ),
          // ── Block 2: 급여 설계 ──
          _buildSection(
            '급여 설계',
            Icons.payments_outlined,
            const Color(0xFF0D47A1),
            _sectionWageExpanded,
            () => setState(() => _sectionWageExpanded = !_sectionWageExpanded),
            [_buildBlock2WageContent()],
            subtitle: _wageType == WageType.monthly ? '월급제' : '시급제',
          ),
          // ── Block 3: 수당 및 절세 ──
          _buildSection(
            '수당 및 절세',
            Icons.savings_outlined,
            const Color(0xFF2E7D32),
            _sectionAllowanceExpanded,
            () => setState(
              () => _sectionAllowanceExpanded = !_sectionAllowanceExpanded,
            ),
            [_buildBlock3AllowanceContent()],
            subtitle: '식대/비과세/고정OT',
          ),
          // ── Block 4: 최종 검증 대시보드 ──
          _buildSection(
            '최종 검증',
            Icons.verified_user_outlined,
            const Color(0xFF6A1B9A),
            _sectionVerifyExpanded,
            () => setState(
              () => _sectionVerifyExpanded = !_sectionVerifyExpanded,
            ),
            [_buildBlock4VerifyContent()],
            subtitle: 'S_Legal 기반 노무 방패',
          ),
          _isDispatch
              ? const SizedBox.shrink()
              : _buildSection(
                  '소득 구분 · 공제',
                  Icons.receipt_long_outlined,
                  const Color(0xFF6B4F2C),
                  _section3Expanded,
                  () => setState(() => _section3Expanded = !_section3Expanded),
                  [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                      child: _compensationDeductionSection(context),
                    ),
                  ],
                  subtitle: _subtitleSection3(),
                ),
          _buildSection(
            '보건증/근무 정책',
            Icons.health_and_safety_outlined,
            const Color(0xFFc45c26),
            _section4Expanded,
            () => setState(() => _section4Expanded = !_section4Expanded),
            [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: _buildHealthPolicySection(),
              ),
            ],
            subtitle: '보건증 관리 설정',
          ),
          
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: _buildAdvancedLaborSettingsSection(),
          ),


          // ── 온보딩: 맨 아래까지 내리면 보이는 계약서 안내 ──
          if (widget.initialWorker == null &&
              OnboardingGuideService.instance.isActive &&
              OnboardingGuideService.instance.currentStep.index <=
                  OnboardingStep.firstStaff.index &&
              !_isDispatch)
            Container(
              margin: const EdgeInsets.only(top: 20, bottom: 8),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF2E7D32), Color(0xFF43A047)],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF2E7D32).withValues(alpha: 0.25),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('📄', style: TextStyle(fontSize: 24)),
                      SizedBox(width: 10),
                      Text(
                        '여기까지 오셨으면 거의 다 됐어요!',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 10),
                  Text(
                    '아래 「저장 및 계약서 작성」 버튼을 누르면\n'
                    '직원 정보 저장 → 초대코드 발급 → 근로계약서 작성까지\n'
                    '한 번에 진행됩니다!',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white70,
                      height: 1.6,
                    ),
                  ),
                  SizedBox(height: 12),
                  Center(
                    child: Text(
                      '👇 아래 버튼을 눌러주세요',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 온보딩 안내: 어떤 버튼을 눌러야 하는지 표시
            if (widget.initialWorker == null &&
                OnboardingGuideService.instance.isActive &&
                OnboardingGuideService.instance.currentStep.index <=
                    OnboardingStep.firstStaff.index &&
                !_isDispatch)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFE3F2FD),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF1565C0).withValues(alpha: 0.3),
                  ),
                ),
                child: const Row(
                  children: [
                    Text('\ud83d\udc47', style: TextStyle(fontSize: 18)),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '오른쪽 버튼을 누르면 모든 노무서류 작성을 마친 후 알바생을 초대할 수 있어요!',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF1565C0),
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!_isDispatch) ...[
                  ElevatedButton(
                    onPressed: _isLoading ? null : _saveAndContract,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1a1a2e),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 0,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            '전자 근로계약서 신규 생성',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: _isLoading ? null : _saveWithPaperContract,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF1a1a2e)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text(
                      '이미 서면 계약서로 작성함 (전자서명 생략)',
                      style: TextStyle(
                        color: Color(0xFF1a1a2e),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                TextButton(
                  onPressed: _isLoading ? null : _saveOnly,
                  child: const Text(
                    '기본 정보만 저장',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatOptionalDateKo(DateTime? date) {
    if (date == null) return '미정';
    return _formatDateKo(date);
  }

  Widget _buildDispatchSection() {
    return _buildSection(
      '파견 정보',
      Icons.business_outlined,
      const Color(0xFF8B5CF6),
      _section2Expanded,
      () => setState(() => _section2Expanded = !_section2Expanded),
      [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          child: TextField(
            controller: _dispatchCompanyController,
            decoration: const InputDecoration(
              labelText: '파견업체명 *',
              hintText: 'OO파견 주식회사',
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          child: TextField(
            controller: _dispatchContactController,
            decoration: const InputDecoration(
              labelText: '담당자 연락처',
              hintText: '010-0000-0000',
            ),
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9-]')),
              LengthLimitingTextInputFormatter(13),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          child: GestureDetector(
            onTap: () => _selectDate(
              context,
              _dispatchStartDate,
              (d) => setState(() => _dispatchStartDate = d),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.event_outlined,
                    color: Color(0xFF888888),
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '파견 시작일 *',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF888888),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatDateKo(_dispatchStartDate),
                          style: TextStyle(
                            fontSize: 15,
                            color: _dispatchStartDate != null
                                ? const Color(0xFF1a1a2e)
                                : const Color(0xFFBBBBBB),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          child: GestureDetector(
            onTap: () => _selectDate(
              context,
              _dispatchEndDate,
              (d) => setState(() => _dispatchEndDate = d),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.event_outlined,
                    color: Color(0xFF888888),
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '파견 종료일',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF888888),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatOptionalDateKo(_dispatchEndDate),
                          style: TextStyle(
                            fontSize: 15,
                            color: _dispatchEndDate != null
                                ? const Color(0xFF1a1a2e)
                                : const Color(0xFFBBBBBB),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '근무 메모',
                style: TextStyle(fontSize: 14, color: Color(0xFF555555)),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _dispatchMemoController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: '담당 업무, 특이사항 등',
                  hintStyle: const TextStyle(
                    color: Color(0xFFBBBBBB),
                    fontSize: 14,
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF5F5F5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
            ],
          ),
        ),
      ],
      subtitle: (_dispatchCompanyController.text.trim().isNotEmpty)
          ? '${_dispatchCompanyController.text.trim()} · 파견기간'
          : '파견업체명, 담당자 연락처, 파견기간',
    );
  }

  Widget _buildHealthPolicySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('보건증 관리 사용'),
          subtitle: const Text('업종 특성상 필요 없는 경우 끌 수 있습니다.'),
          value: _healthCertificateManagementEnabled,
          onChanged: (val) => setState(() {
            _healthCertificateManagementEnabled = val;
            if (!val) {
              _hasHealthCertificate = false;
              _healthCertificateExpiryDate = null;
            }
          }),
        ),
        if (_healthCertificateManagementEnabled) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4, right: 4, bottom: 8),
            child: Text(
              '만료 전 사장님께 푸시 알림을 보내드려요',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('보건증 보유'),
            subtitle: Text(_hasHealthCertificate ? '보유 중' : '미보유'),
            value: _hasHealthCertificate,
            onChanged: (val) => setState(() {
              _hasHealthCertificate = val;
              if (!val) _healthCertificateExpiryDate = null;
            }),
          ),
          if (_hasHealthCertificate)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('보건증 만료일'),
              subtitle: Text(
                _healthCertificateExpiryDate == null
                    ? '선택 안 됨'
                    : _formatDateKo(_healthCertificateExpiryDate),
              ),
              trailing: const Icon(Icons.calendar_today_outlined),
              onTap: () async {
                final initial =
                    _healthCertificateExpiryDate ??
                    AppClock.now().add(const Duration(days: 365));
                final date = await showDatePicker(
                  context: context,
                  initialDate: initial,
                  firstDate: DateTime(2000),
                  lastDate: AppClock.now().add(const Duration(days: 3650)),
                  locale: const Locale('ko', 'KR'),
                  builder: (context, child) {
                    return Theme(
                      data: Theme.of(context).copyWith(
                        colorScheme: const ColorScheme.light(
                          primary: Color(0xFF1a1a2e),
                          onPrimary: Colors.white,
                          surface: Colors.white,
                        ),
                        textButtonTheme: TextButtonThemeData(
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFF1a1a2e),
                          ),
                        ),
                      ),
                      child: child!,
                    );
                  },
                );
                if (date == null) return;
                setState(() => _healthCertificateExpiryDate = date);
              },
            ),
        ],
        SwitchListTile(
          title: const Text('근무 대근/교환 허용'),
          contentPadding: EdgeInsets.zero,
          value: _isSubstitutionAllowed,
          onChanged: (val) => setState(() => _isSubstitutionAllowed = val),
        ),
      ],
    );
  }

  int _currentBreakMinutes() {
    if (_breakPreset == _BreakPreset.minutes30) return 30;
    if (_breakPreset == _BreakPreset.minutes60) return 60;
    final parsed = int.tryParse(_breakMinutesController.text.trim());
    if (parsed == null) return 0;
    return parsed.clamp(0, 1440);
  }

  String _computedBreakEndTime() {
    return _addMinutesToHm(_breakStartTime, _currentBreakMinutes());
  }

  int _hmToTotalMinutes(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length != 2) return 0;
    final hh = int.tryParse(parts[0]) ?? 0;
    final mm = int.tryParse(parts[1]) ?? 0;
    return (hh * 60) + mm;
  }

  String _totalMinutesToHm(int totalMinutes) {
    final normalized = ((totalMinutes % (24 * 60)) + (24 * 60)) % (24 * 60);
    final hh = normalized ~/ 60;
    final mm = normalized % 60;
    return '${hh.toString().padLeft(2, '0')}:${mm.toString().padLeft(2, '0')}';
  }

  int _roundMinutesToStep(int totalMinutes, int stepMinutes) {
    final step = stepMinutes <= 0 ? _timePickerStepMinutes : stepMinutes;
    var rounded = ((totalMinutes + step / 2) ~/ step) * step;
    final maxMinutes = (24 * 60) - 1;
    if (rounded > maxMinutes) rounded = maxMinutes;
    if (rounded < 0) rounded = 0;
    return rounded;
  }

  Future<void> _pickTimeForController(TextEditingController controller) async {
    final current = controller.text.trim();
    final initialMinutes = _hmToTotalMinutes(current);
    final initial = TimeOfDay(
      hour: (initialMinutes ~/ 60).clamp(0, 23),
      minute: (initialMinutes % 60).clamp(0, 59),
    );

    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (ctx, child) {
        // 사장님들이 큰 글씨로 보실 수 있도록 약간 확대
        return MediaQuery(
          data: MediaQuery.of(
            ctx,
          ).copyWith(textScaler: const TextScaler.linear(1.2)),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );

    if (picked == null) return;

    final pickedTotal = (picked.hour * 60) + picked.minute;
    final rounded = _roundMinutesToStep(pickedTotal, _timePickerStepMinutes);
    controller.text = _totalMinutesToHm(rounded);
    setState(() {});
  }

  int _workMinutesExcludingBreakFromInputs() {
    final s = _bulkStartController.text.trim();
    final e = _bulkEndController.text.trim();
    if (!_isHm(s) || !_isHm(e)) return 0;
    final minutes = _durationMinutes(s, e);
    if (minutes <= 0) return 0;
    final breakMinutes = _currentBreakMinutes();
    return (minutes - breakMinutes).clamp(0, 24 * 60);
  }

  double _workHoursExcludingBreakFromInputs() {
    return _workMinutesExcludingBreakFromInputs() / 60.0;
  }

  String _addMinutesToHm(String hhmm, int minutesToAdd) {
    final parts = hhmm.split(':');
    if (parts.length != 2) return hhmm;
    final hh = int.tryParse(parts[0]);
    final mm = int.tryParse(parts[1]);
    if (hh == null || mm == null) return hhmm;
    if (minutesToAdd == 0) return hhmm;

    final base = (hh * 60) + mm;
    final total = base + minutesToAdd;
    final normalized = ((total % (24 * 60)) + (24 * 60)) % (24 * 60);
    final outH = normalized ~/ 60;
    final outM = normalized % 60;
    return '${outH.toString().padLeft(2, '0')}:${outM.toString().padLeft(2, '0')}';
  }

  List<({String start, String end, List<int> days})> _workScheduleGroups() {
    final groupDays = <String, List<int>>{};

    for (final day in _workStartByDay.keys) {
      final start = _workStartByDay[day] ?? '';
      final end = _workEndByDay[day] ?? '';
      if (start.isEmpty || end.isEmpty) continue;
      final key = '$start|$end';
      groupDays.putIfAbsent(key, () => <int>[]).add(day);
    }

    final groups = groupDays.entries.map((e) {
      final parts = e.key.split('|');
      final start = parts.isNotEmpty ? parts.first : '';
      final end = parts.length > 1 ? parts[1] : '';
      final days = [...e.value]..sort();
      return (start: start, end: end, days: days);
    }).toList();

    groups.sort((a, b) => (a.start).compareTo(b.start));
    return groups;
  }

  String _workTimeSummaryText() {
    final groups = _workScheduleGroups();
    if (groups.isEmpty) return '근무시간 미입력';

    final g = groups.first;
    final daysText = g.days.map(_weekdayLabel).join('/');
    final base = '$daysText ${g.start}~${g.end}';
    if (groups.length > 1) {
      return '$base 외 ${groups.length - 1}개';
    }
    return base;
  }

  Widget _workTimeSummaryCard() {
    return InkWell(
      onTap: () => setState(() => _isEditingWorkTime = true),
      borderRadius: BorderRadius.circular(18),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  _workTimeSummaryText(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () => setState(() => _isEditingWorkTime = true),
                icon: const Icon(Icons.edit_rounded),
                tooltip: '수정',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showAllowanceAddSheet() async {
    String selected = 'meal'; // meal | transport | custom
    final labelController = TextEditingController();
    final amountController = TextEditingController();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final title = selected == 'meal'
                ? '식비 추가'
                : selected == 'transport'
                ? '교통비 추가'
                : '기타 지급 추가';

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                // [UI 개선] 키보드뿐만 아니라 기기 하단 세이프 에어리어(홈 바 등)까지 고려하여 여백 확보
                bottom:
                    MediaQuery.of(ctx).viewInsets.bottom +
                    MediaQuery.of(ctx).padding.bottom +
                    16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('식비'),
                        selected: selected == 'meal',
                        onSelected: (v) {
                          if (!v) return;
                          setModalState(() => selected = 'meal');
                        },
                      ),
                      ChoiceChip(
                        label: const Text('교통비'),
                        selected: selected == 'transport',
                        onSelected: (v) {
                          if (!v) return;
                          setModalState(() => selected = 'transport');
                        },
                      ),
                      ChoiceChip(
                        label: const Text('기타'),
                        selected: selected == 'custom',
                        onSelected: (v) {
                          if (!v) return;
                          setModalState(() => selected = 'custom');
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (selected == 'custom') ...[
                    TextField(
                      controller: labelController,
                      decoration: const InputDecoration(
                        labelText: '항목명',
                        hintText: '예: 성과수당',
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  TextField(
                    controller: amountController,
                    decoration: const InputDecoration(
                      labelText: '금액(월)',
                      hintText: '예: 200,000',
                      suffixText: '원',
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      _MoneyInputFormatter(),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('추가'),
                      onPressed: () {
                        final amount =
                            int.tryParse(
                              amountController.text.replaceAll(',', '').trim(),
                            ) ??
                            0;
                        if (amount <= 0) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(
                              content: Text('수당 금액을 입력해 주세요 (0보다 커야 함)'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                          return;
                        }

                        if (selected == 'meal') {
                          setState(
                            () => _mealAllowanceController.text = amount
                                .toString(),
                          );
                        } else if (selected == 'transport') {
                          setState(
                            () => _transportAllowanceController.text = amount
                                .toString(),
                          );
                        } else {
                          final label = labelController.text.trim();
                          if (label.isEmpty) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(
                                content: Text('기타 수당의 항목명을 입력해 주세요 (예: 성과수당)'),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                            return;
                          }
                          setState(
                            () => _customItems.add(
                              CustomPayItem(label: label, amount: amount),
                            ),
                          );
                        }

                        Navigator.pop(ctx);
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  int _weeklyTotalStayMinutes() {
    if (_workStartByDay.isEmpty || _workEndByDay.isEmpty) return 0;
    var total = 0;
    for (final day in _workStartByDay.keys) {
      final s = _workStartByDay[day] ?? '';
      final e = _workEndByDay[day] ?? '';
      if (!_isHm(s) || !_isHm(e)) continue;
      final minutes = _durationMinutes(s, e);
      if (minutes <= 0) continue;
      total += minutes;
    }
    return total;
  }

  int _weeklyPureLaborMinutes() {
    final totalStay = _weeklyTotalStayMinutes();
    if (totalStay <= 0) return 0;
    // 판정 기준에서는 유급/무급과 무관하게 휴게시간을 항상 제외
    final breakTotal = _currentBreakMinutes() * _workStartByDay.length;
    final pure = totalStay - breakTotal;
    return pure > 0 ? pure : 0;
  }

  double _weeklyHours() => _weeklyPureLaborMinutes() / 60.0;

  /// 컨트롤러에서 콤마를 제거한 순수 숫자 문자열 반환
  String _numText(TextEditingController c) =>
      c.text.replaceAll(RegExp(r'[^0-9]'), '');

  /// 소정근로일수 (주 n일) - workStartByDay에서 선택된 요일 수
  double _workDaysPerWeek() =>
      _workStartByDay.isNotEmpty ? _workStartByDay.length.toDouble() : 5.0;

  /// S_Legal: 달력 기반 법정 소정근로시간 (해당 월)
  double _sLegal({DateTime? month}) {
    final weeklyH = _weeklyHours();
    final weeklyHolidayH = weeklyH >= 15 ? weeklyH / _workDaysPerWeek() : 0.0;
    final now = month ?? DateTime.now();
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    return (weeklyH + weeklyHolidayH) * (daysInMonth / 7.0);
  }

  /// S_Ref: 고정 4.345 기준 소정근로시간 (209시간 기준, 정수 올림)
  double _sRef() {
    final weeklyH = _weeklyHours();
    final weeklyHolidayH = weeklyH >= 15 ? weeklyH / _workDaysPerWeek() : 0.0;
    return ((weeklyH + weeklyHolidayH) * 4.345).ceilToDouble();
  }

  String _estimatedMonthlyPayText() {
    if (_wageType == WageType.monthly) {
      final mw = int.tryParse(_numText(_monthlyWageController)) ?? 0;
      if (mw <= 0) return '0';
      return mw.toString().replaceAllMapped(
        RegExp(r'\B(?=(\d{3})+(?!\d))'),
        (m) => ',',
      );
    }
    final hourly = int.tryParse(_numText(_wageController)) ?? 0;
    if (hourly <= 0) return '0';
    final weekly = _weeklyHours();
    // 시급제: S_Legal(달력 기반)으로 예상 월급 산출 → 월별 차이 정확 반영
    final now = DateTime.now();
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final weeksInMonth = daysInMonth / 7.0;
    // 주휴수당: 주 소정근로시간 15시간 이상일 때만 자동 발생
    final weeklyHolidayHours = (weekly >= 15) ? ((weekly / 40.0) * 8.0) : 0.0;
    final monthly = (weekly + weeklyHolidayHours) * hourly * weeksInMonth;
    final asInt = monthly.round();
    return asInt.toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (m) => ',',
    );
  }

  /// 월급제 비과세 수당(식대) 전략 분석 가이드 말풍선
  /// 식대 비과세 활성화 전 필수 체크리스트 확인 팝업
  Future<bool?> _showMealTaxExemptChecklist(BuildContext context) {
    bool check1 = false; // 실물 식사 미제공 확인
    bool check2 = false; // 매월 고정 지급 확인

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final allChecked = check1 && check2;
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            contentPadding: EdgeInsets.zero,
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── 헤더 ──
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      vertical: 20,
                      horizontal: 20,
                    ),
                    decoration: const BoxDecoration(
                      color: Color(0xFFFFF8E1),
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(16),
                      ),
                    ),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFD54F),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: const Color(
                                  0xFFFFD54F,
                                ).withValues(alpha: 0.4),
                                blurRadius: 12,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: const Text(
                            '✋',
                            style: TextStyle(fontSize: 28),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          '잠깐만요, 사장님!',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFF57F17),
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          '법적 체크가 필요합니다',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF795548),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── 체크리스트 ──
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Column(
                      children: [
                        // 조건 1: 실물 식사 미제공
                        _buildCheckItem(
                          index: 1,
                          checked: check1,
                          title: '실물 식사를 별도로 제공하지 않습니다',
                          description:
                              '매장에서 밥을 따로 차려주거나 식권을 주면서 '
                              '현금 식대까지 비과세로 처리하면 \'이중 수혜\'로 간주되어 '
                              '세금이 추징될 수 있습니다.',
                          onChanged: (v) =>
                              setDialogState(() => check1 = v ?? false),
                        ),
                        const SizedBox(height: 12),

                        // 조건 2: 매월 고정 지급
                        _buildCheckItem(
                          index: 2,
                          checked: check2,
                          title: '매달 고정적으로 지급합니다',
                          description:
                              '어떤 달은 주고 어떤 달은 안 주면 \'비과세 수당\'으로 '
                              '인정받지 못합니다. 근로계약서에 명시된 대로 '
                              '매달 정기적으로 지급해야 합니다.',
                          onChanged: (v) =>
                              setDialogState(() => check2 = v ?? false),
                        ),
                      ],
                    ),
                  ),

                  // ── 하단 버튼 ──
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton(
                            onPressed: allChecked
                                ? () => Navigator.of(ctx).pop(true)
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: allChecked
                                  ? const Color(0xFF2E7D32)
                                  : Colors.grey.shade300,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: allChecked ? 2 : 0,
                            ),
                            child: Text(
                              allChecked
                                  ? '위 조건을 모두 충족합니다 ✅'
                                  : '위 조건을 모두 확인해 주세요',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: allChecked
                                    ? Colors.white
                                    : Colors.grey.shade500,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(false),
                          child: Text(
                            '취소',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// 체크리스트 개별 항목 위젯
  Widget _buildCheckItem({
    required int index,
    required bool checked,
    required String title,
    required String description,
    required ValueChanged<bool?> onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: checked ? const Color(0xFFE8F5E9) : const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: checked ? const Color(0xFF66BB6A) : Colors.grey.shade300,
          width: checked ? 1.5 : 1.0,
        ),
      ),
      child: InkWell(
        onTap: () => onChanged(!checked),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: checked ? const Color(0xFF2E7D32) : Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: checked
                        ? const Color(0xFF2E7D32)
                        : Colors.grey.shade400,
                    width: 2,
                  ),
                ),
                child: checked
                    ? const Icon(Icons.check, size: 16, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF8F00),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '$index',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: checked
                                  ? const Color(0xFF2E7D32)
                                  : Colors.black87,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNonTaxableStrategyGuide() {
    final mealVal = int.tryParse(_numText(_mealAllowanceController)) ?? 0;
    final monthlyWage = int.tryParse(_numText(_monthlyWageController)) ?? 0;

    // 식대가 없거나 월급이 없으면 기본 안내만 표시
    if (monthlyWage <= 0) return const SizedBox.shrink();

    final weeklyH = _weeklyHours();
    // 월 소정근로시간 (주휴 포함)
    final monthlyScheduledH =
        ((weeklyH + (weeklyH >= 15 ? (weeklyH / 40.0) * 8.0 : 0)) * 4.345).ceilToDouble();
    final baseMonthlyH = (weeklyH * 4.345).ceilToDouble(); // 소정근로시간 (주휴 제외)

    // 식대가 아직 없을 때: 안내 말풍선
    if (mealVal <= 0) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F0FF),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFD1C4E9)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('💡', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '식비를 별도 수당으로 등록하시면, 비과세 혜택(최대 20만원)으로 4대보험료가 절감되어 실수령액이 높아집니다. '
                  '위 [+ 수당 추가] 버튼으로 식비를 추가해 보세요.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.deepPurple.shade700,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // ─── 식대가 있을 때: 전략 분석 ───
    final nonTaxableMeal = mealVal > 200000 ? 200000.0 : mealVal.toDouble();

    // [A] 통상임금 기준 (2024.12 대법원 판례 반영)
    // 통상임금 = 기본급 + 식대 (정기·일률·고정 지급분)
    // 고정OT는 연장근로의 대가이므로 통상임금에서 제외
    final fixedOTPay = _wizardApplied
        ? (int.tryParse(_numText(_wizardFixedOtController)) ?? 0)
        : 0;
    final totalOrdinaryWage = monthlyWage + mealVal; // 기본급 + 식대 (고정OT 제외)
    final hourlyA = totalOrdinaryWage / monthlyScheduledH;

    // [보험료/실수령 비교] 총지급액 = 기본급 + 식대 + 고정OT (실제 수령 총액)
    final totalGrossPay = monthlyWage + mealVal + fixedOTPay;

    // [A] 전액 과세 (식대 미분리 시)
    final taxableA = totalGrossPay.toDouble();
    final insuranceA = taxableA * 0.094; // 4대보험 약 9.4%
    final netPayA = totalGrossPay - insuranceA;

    // [B] 식대를 비과세 수당으로 분리한 경우
    // 총지급액은 동일, 식대(비과세)만 4대보험 대상에서 제외
    final taxableB = totalGrossPay - nonTaxableMeal;
    final insuranceB = taxableB * 0.094;
    final netPayB = totalGrossPay - insuranceB;

    // 비교 수치
    final insuranceSaving = insuranceA - insuranceB;
    final netPayGain = netPayB - netPayA;

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFFF3E5F5).withValues(alpha: 0.7),
              const Color(0xFFE8EAF6).withValues(alpha: 0.7),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: const Color(0xFFCE93D8).withValues(alpha: 0.5),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 제목
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.shade50,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    '📊 비과세 전략 분석',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF4527A0),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '식비 ${_formatMoney(mealVal)}원 기준',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // ✅ 장점: 절세 효과
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Text('✅', style: TextStyle(fontSize: 14)),
                      SizedBox(width: 6),
                      Text(
                        '장점: 절세 효과',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF2E7D32),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _strategyRow(
                    '4대보험 절감',
                    '+${_formatMoney(insuranceSaving.round())}원/월',
                    const Color(0xFF2E7D32),
                  ),
                  _strategyRow(
                    '실수령액 증가',
                    '+${_formatMoney(netPayGain.round())}원/월',
                    const Color(0xFF2E7D32),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '비과세 식비(${_formatMoney(nonTaxableMeal.toInt())}원)가 4대보험 산정 기준에서 제외되어\n'
                    '사장님과 직원 모두 보험료가 줄어듭니다.',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.green.shade800,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // ⚠️ 법적 주의사항: 2024.12.19 대법원 전원합의체 판결
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFEBEE),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFEF9A9A)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Text('⚖️', style: TextStyle(fontSize: 14)),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '주의: 통상임금 판례 변경 (\'24.12 대법원)',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFC62828),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '2024.12.19 대법원 전원합의체 판결로 \'고정성\' 요건이 폐기되었습니다. '
                    '2025.2.6 고용노동부 개정 지침에 따르면:',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.red.shade900,
                      height: 1.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '• 매월 정기적·일률적으로 지급되는 식비는 명칭과 관계없이 통상임금에 포함\n'
                      '• 식비를 분리해도 통상시급 계산 시 합산해야 할 가능성이 높음\n'
                      '• 비과세 혜택은 유지되나, 연장수당 절감 효과는 기대하기 어려움',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.red.shade800,
                        height: 1.6,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _strategyRow(
                    '통상시급 (식비 포함)',
                    '${_formatMoney(hourlyA.round())}원',
                    const Color(0xFFC62828),
                  ),
                  if (_isFiveOrMoreStore) _strategyRow(
                    '연장근로 1시간 수당',
                    '${_formatMoney((hourlyA * 1.5).round())}원',
                    const Color(0xFFC62828),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _isFiveOrMoreStore
                        ? '→ 식비를 분리 지급하더라도, 연장·야간·휴일 수당 계산 시 '
                          '식비가 포함된 통상시급(${_formatMoney(hourlyA.round())}원)을 적용하는 것이 안전합니다.'
                        : '→ 5인 미만 사업장은 연장·야간·휴일 가산수당 의무가 없으나, '
                          '통상시급 산정 시 식비 포함 기준(${_formatMoney(hourlyA.round())}원)을 참고하세요.',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.red.shade700,
                      height: 1.4,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // 🚨 5/9 포괄임금 오남용 방지 지침
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF3E5F5),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFAB47BC)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFAB47BC),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'NEW',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Expanded(
                        child: Text(
                          '🚨 포괄임금 오남용 방지 지침 (\'26.4.9~)',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF6A1B9A),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      '• 정액급제·포괄임금 원칙적 금지 (기본급·수당 분리 기재 의무)\n'
                      '• 실근로시간 기반 연장·야간·휴일수당 지급 의무\n'
                      '• 고정OT 약정 시에도 실근로 초과분 차액 지급 필수\n'
                      '• 위반 시 임금체불로 처벌 가능',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF4A148C),
                        height: 1.6,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E9),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('✅', style: TextStyle(fontSize: 12)),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '알바급여정석은 이 지침 준수를 돕는 기능을 제공합니다:\n'
                            '• 기본급/연장수당/야간수당/주휴수당 분리 계산 지원\n'
                            '• 실근로시간 기반 연장수당 산출 보조\n'
                            '• 고정OT 초과 시 차액 산출 보조\n'
                            '• 임금명세서에 항목별 구분 기재',
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF2E7D32),
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '→ 월급제로 등록하시면, 시스템이 기본급과 각종 수당을 분리 산출하여 지침 준수를 돕습니다. '
                    '단, 정확한 출퇴근 기록이 필요하며, 최종 판단은 노무사 자문을 권장합니다.',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.purple.shade700,
                      height: 1.4,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // 💰 최종 비교 요약
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '💰 월간 비교 요약',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              '식비 미분리',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '공제 ${_formatMoney(insuranceA.round())}원',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.red,
                              ),
                            ),
                            Text(
                              '실수령 ${_formatMoney(netPayA.round())}원',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.arrow_forward_rounded,
                        color: Color(0xFF4527A0),
                        size: 20,
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              '식비 비과세',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '공제 ${_formatMoney(insuranceB.round())}원',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.red,
                              ),
                            ),
                            Text(
                              '실수령 ${_formatMoney(netPayB.round())}원',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF4527A0),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // 안내 문구
            Text(
              '※ 위 분석은 2025.2.6 통상임금 지침 및 2026.4.9 포괄임금 오남용 방지 지침 기준이며, 참고용입니다. '
              '보다 정확한 통상임금 판단을 위해 노무사 또는 전문가의 자문을 권장합니다.',
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey.shade500,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _strategyRow(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Colors.black87),
          ),
          Flexible(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: valueColor,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProbationGuide() {
    return Column(
      children: [
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFE6F1FB),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF1a6ebd), width: 0.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.info_outline, color: Color(0xFF185FA5), size: 16),
                  SizedBox(width: 6),
                  Text(
                    '수습기간 적용 안내',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF185FA5),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _buildGuideItem(
                '적용 조건',
                '1년 이상 계약 근로자에 한해 수습 기간 3개월까지 최저임금의 90% 적용 가능',
                const Color(0xFF185FA5),
              ),
              const SizedBox(height: 8),
              _buildWagePreview(),
              const SizedBox(height: 8),
              _buildProbationMonthSelector(),
              const SizedBox(height: 8),
              _buildWarningItem(),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF0DC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFd4700a), width: 0.5),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: Color(0xFFd4700a),
                size: 16,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '단순노무직 주의',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF854F0B),
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '청소, 경비, 주방보조 등 단순노무직은 수습기간 중에도 최저임금 100% 지급 의무가 있습니다.\n'
                      '판매직의 경우 업무 성격에 따라 적용 여부가 다를 수 있으니 노무사 확인을 권장합니다.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF854F0B),
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWagePreview() {
    final hourlyWage = double.tryParse(_numText(_wageController)) ?? 0;
    final probationWage = (hourlyWage * 0.9).floorToDouble();
    final minimumWage = _minimumHourlyWage;
    final isUnderMinimum = minimumWage > 0 && probationWage < minimumWage;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '계약 시급',
                style: TextStyle(fontSize: 13, color: Color(0xFF888888)),
              ),
              Text(
                '${_formatMoney(hourlyWage)}원',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '수습 기간 시급 (90%)',
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF185FA5),
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                '${_formatMoney(probationWage)}원',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF185FA5),
                ),
              ),
            ],
          ),
          if (isUnderMinimum) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFCEBEB),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '⚠️ 수습 적용 시급 ${_formatMoney(probationWage)}원이 최저임금(${_formatMoney(minimumWage)}원) 미달입니다. 최저임금법 위반입니다.',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFFA32D2D),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProbationMonthSelector() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          '수습 기간',
          style: TextStyle(fontSize: 13, color: Color(0xFF555555)),
        ),
        Row(
          children: [1, 2, 3].map((month) {
            final isSelected = _probationMonths == month;
            return GestureDetector(
              onTap: () => setState(() => _probationMonths = month),
              child: Container(
                margin: const EdgeInsets.only(left: 6),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF1a6ebd) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFF1a6ebd)
                        : const Color(0xFFDDDDDD),
                  ),
                ),
                child: Text(
                  '$month개월',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: isSelected ? Colors.white : const Color(0xFF555555),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildGuideItem(String title, String content, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 4,
          height: 4,
          margin: const EdgeInsets.only(top: 6, right: 6),
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF185FA5),
                height: 1.5,
              ),
              children: [
                TextSpan(
                  text: '$title: ',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                TextSpan(text: content),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWarningItem() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 4,
          height: 4,
          margin: const EdgeInsets.only(top: 6, right: 6),
          decoration: const BoxDecoration(
            color: Color(0xFF185FA5),
            shape: BoxShape.circle,
          ),
        ),
        const Expanded(
          child: Text(
            '본 계산은 참고용이며 정확한 적용 여부는 고용노동부(1350) 또는 노무사 확인을 권장합니다.',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFF185FA5),
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }

  String _formatMoney(num value) {
    final asInt = value.floor();
    return asInt.toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (m) => ',',
    );
  }

  @override
  void dispose() {
    _phoneController.removeListener(_phoneFormatListener);
    _breakMinutesController.removeListener(_weeklyHoursSyncListener);
    _workStartController.removeListener(_weeklyHoursSyncListener);
    _workEndController.removeListener(_weeklyHoursSyncListener);
    _nameController.dispose();
    _phoneController.dispose();
    _dispatchCompanyController.dispose();
    _dispatchContactController.dispose();
    _dispatchMemoController.dispose();
    _wageController.dispose();
    _bonusController.dispose();
    _mealAllowanceController.dispose();
    _transportAllowanceController.dispose();
    _breakMinutesController.dispose();
    _workStartController.dispose();
    _workEndController.dispose();
    _breakStartController.dispose();
    _breakEndController.dispose();
    _dayStartController.dispose();
    _dayEndController.dispose();
    _bulkStartController.dispose();
    _bulkEndController.dispose();
    _nameFocusNode.dispose();
    _phoneFocusNode.dispose();
    _wizardPositionController.dispose();
    _wizardDiligenceController.dispose();
    _wizardFixedOtController.dispose();
    _wizardOtherLabelController.dispose();
    _wizardOtherAmountController.dispose();
    super.dispose();
  }

  List<int> _weekdayOrder() => const [
    DateTime.monday,
    DateTime.tuesday,
    DateTime.wednesday,
    DateTime.thursday,
    DateTime.friday,
    DateTime.saturday,
    DateTime.sunday,
  ];

  String _weekdayLabel(int weekday) {
    if (weekday == DateTime.monday) return '월';
    if (weekday == DateTime.tuesday) return '화';
    if (weekday == DateTime.wednesday) return '수';
    if (weekday == DateTime.thursday) return '목';
    if (weekday == DateTime.friday) return '금';
    if (weekday == DateTime.saturday) return '토';
    if (weekday == DateTime.sunday) return '일';
    return '';
  }

  bool _isHm(String value) {
    final reg = RegExp(r'^\d{2}:\d{2}$');
    if (!reg.hasMatch(value)) return false;
    final parts = value.split(':');
    final hh = int.tryParse(parts[0]);
    final mm = int.tryParse(parts[1]);
    if (hh == null || mm == null) return false;
    return hh >= 0 && hh <= 23 && mm >= 0 && mm <= 59;
  }

  int _durationMinutes(String start, String end) {
    final s = start.split(':');
    final e = end.split(':');
    final sm = (int.parse(s[0]) * 60) + int.parse(s[1]);
    final em = (int.parse(e[0]) * 60) + int.parse(e[1]);
    return em - sm;
  }

  // ════════════════════════════════════════════════════════════════
  // Block 2: 급여 설계 섹션
  // ════════════════════════════════════════════════════════════════
  // ════════════════════════════════════════════════════════════════
  // Auto-Wizard: 목표 월급 자동 설계
  // ════════════════════════════════════════════════════════════════
  void _runAutoWizard() {
    final target = int.tryParse(_numText(_targetSalaryController)) ?? 0;
    if (target <= 0) return;

    final sR = _sRef();
    if (sR <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ 근무 요일과 출퇴근 시간을 먼저 설정해 주세요.\n(Block 1: 근무 조건)'),
          backgroundColor: Color(0xFFE65100),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    // Step 1: 기본급 = S_Ref(209h) × 최저시급 (정부 고시 기준: 209시간)
    final sRefInt = sR.toInt(); // 이미 ceil된 209
    final minBase = sRefInt * _minimumHourlyWage.round();
    int baseSalary = minBase;

    // Step 2: 식대 (비과세) 최대 200,000원
    int mealAllowance = 0;
    int remaining = target - baseSalary;
    if (remaining >= 200000) {
      mealAllowance = 200000;
      remaining -= 200000;
    } else if (remaining > 0) {
      mealAllowance = remaining;
      remaining = 0;
    }

    // 기본급에 남은 금액 재조정: 기본급 + 잔여가 목표에 맞도록
    // 잔여 금액이 남으면 Step 3에서 사용자가 분류
    setState(() {
      _wizardBaseSalary = baseSalary;
      _wizardMealAllowance = mealAllowance;
      _wageType = WageType.monthly;
      _monthlyWageController.text = _formatMoney(baseSalary);
      _mealAllowanceController.text = _formatMoney(mealAllowance);
      _mealTaxExempt = mealAllowance > 0;
      _wizardPositionController.text = '';
      _wizardDiligenceController.text = '';
      _wizardFixedOtController.text = '';
      _wizardOtherLabelController.text = '';
      _wizardOtherAmountController.text = '';
      _fixedOvertimeHoursController.text = '0';
      _wizardApplied = true;
      // 기본급 검증도 트리거
      _validateMonthlyWage(_monthlyWageController.text);
    });
  }

  int get _wizardRemainder {
    final target = int.tryParse(_numText(_targetSalaryController)) ?? 0;
    final base = int.tryParse(_numText(_monthlyWageController)) ?? 0;
    final meal = int.tryParse(_numText(_mealAllowanceController)) ?? 0;
    return (target - base - meal).clamp(0, target);
  }

  int get _wizardDistributedAmount {
    final p = int.tryParse(_numText(_wizardPositionController)) ?? 0;
    final d = int.tryParse(_numText(_wizardDiligenceController)) ?? 0;
    final f = int.tryParse(_numText(_wizardFixedOtController)) ?? 0;
    final o = int.tryParse(_numText(_wizardOtherAmountController)) ?? 0;
    return p + d + f + o;
  }

  Widget _buildAutoWizard() {
    final sR = _sRef();
    final sRefInt = sR.toInt(); // 이미 ceil된 209
    final remainder = _wizardRemainder;
    final mealVal = int.tryParse(_numText(_mealAllowanceController)) ?? 0;
    final baseSal = int.tryParse(_numText(_monthlyWageController)) ?? 0;
    // 통상시급 = (기본급 + 식대) / 209 (법적 판례에 따라 식대 포함)
    final ordinaryWage = sRefInt > 0
        ? (baseSal + mealVal) / sRefInt
        : 0.0;
    final otMultiplier = _isFiveOrMoreStore ? 1.5 : 1.0;
    final fixedOTHoursRaw = ordinaryWage > 0 && remainder > 0
        ? remainder / (ordinaryWage * otMultiplier)
        : 0.0;
    // ★ 보수적 내림(floor) 처리: 소수점 1자리까지 살린 뒤 내림
    // ex) 9.76h → 9.7h, 12.69h → 12.6h (점주 초과 지급 방지)
    double fixedOTHoursFloor = (fixedOTHoursRaw * 10).floorToDouble() / 10.0;
    if (fixedOTHoursFloor > 20) fixedOTHoursFloor = 20;
    final int fixedOTHours = fixedOTHoursFloor.floor();
    final String fixedOTHoursLabel = fixedOTHoursFloor.toStringAsFixed(1);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1a237e), Color(0xFF283593)],
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.auto_fix_high, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Text(
                '🧙 목표 월급 자동 설계',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            '목표 금액을 입력하면 법적 최적 구성안을 자동으로 생성합니다.',
            style: TextStyle(
              fontSize: 11,
              color: Color(0xFFBBDEFB),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          // Step 1: 목표 금액 입력
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Text(
                  '목표 월급',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1a237e),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _targetSalaryController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      _MoneyInputFormatter(),
                    ],
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      hintText: '예: 2,500,000',
                    ),
                    onChanged: (_) => setState(() => _wizardApplied = false),
                  ),
                ),
                const Text(
                  '원',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1a237e),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed:
                  (int.tryParse(_numText(_targetSalaryController)) ?? 0) > 0
                  ? _runAutoWizard
                  : null,
              icon: const Icon(Icons.bolt, size: 18),
              label: const Text(
                '추천 구성안 생성',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFD54F),
                foregroundColor: const Color(0xFF1a237e),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          // Step 2: 자동 분배 결과
          if (_wizardApplied) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFE8EAF6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '📋 자동 분배 결과',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1a237e),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _wizRow(
                    '① 기본급',
                    '${_formatMoney(int.tryParse(_numText(_monthlyWageController)) ?? 0)}원',
                    '= S_Ref(${sR.toInt()}h) × ${_formatMoney(_minimumHourlyWage.round())}원',
                  ),
                  _wizRow(
                    '② 식대(비과세)',
                    '${_formatMoney(int.tryParse(_numText(_mealAllowanceController)) ?? 0)}원',
                    '최대 200,000원 자동 배정',
                  ),
                  if (remainder > 0) ...[
                    const Divider(height: 16),
                    _wizRow(
                      '③ 잔여 금액',
                      '${_formatMoney(remainder)}원',
                      '아래에서 성격을 지정하세요',
                    ),
                  ],
                ],
              ),
            ),
            // Step 3: 잔여 금액 처리
            if (remainder > 0) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFFB74D)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              '💡 잔여 ${_formatMoney(remainder)}원을 각 수당에 분배하세요',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFFE65100),
                              ),
                              softWrap: true,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (remainder - _wizardDistributedAmount != 0)
                            Text(
                              '미분배: ${_formatMoney(remainder - _wizardDistributedAmount)}원',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFD32F2F),
                              ),
                            )
                          else
                            const Text(
                              '분배 완료 ✅',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF388E3C),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _wizDistributionField('직책 수당', _wizardPositionController),
                      _wizDistributionField('성실 수당', _wizardDiligenceController),
                      _wizDistributionField('고정연장수당', _wizardFixedOtController, isOt: true),
                      if (int.tryParse(_numText(_wizardFixedOtController)) != null &&
                          (int.tryParse(_numText(_wizardFixedOtController)) ?? 0) > 0)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            '→ 월 $fixedOTHoursLabel시간의 고정연장에 대한 수당 (소수점 내림 적용)',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFFE65100),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      _wizDistributionOtherField('항목명 직접입력 (기타)', _wizardOtherLabelController, _wizardOtherAmountController),
                      if (int.tryParse(_numText(_wizardFixedOtController)) != null &&
                          (int.tryParse(_numText(_wizardFixedOtController)) ?? 0) > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFEBEE),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              '⚠️ 본 고정연장수당은 \'당일 업무 지연으로 인한 추가 근무\' 대비용입니다.\n이를 악용하여 본래 휴무일에 강제 대타를 지시할 경우 부당노동행위 분쟁의 원인이 됩니다. 대타 근로는 이 시간에서 차감되지 않고 별도 지급됩니다.',
                              style: TextStyle(
                                fontSize: 11,
                                color: Color(0xFFB71C1C),
                                fontWeight: FontWeight.w600,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ),
                  ],
                ),
              ),
            ],
            // Step 4: 최종 체크리스트
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '검증 체크리스트',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _wizCheck(
                    '기본급 최저임금 충족(209시간 기준)',
                    ordinaryWage >= _minimumHourlyWage,
                  ),
                  _wizCheck(
                    '잔여 금액 100% 분배 완료',
                    remainder <= 0 || (remainder - _wizardDistributedAmount) == 0,
                  ),
                  if ((int.tryParse(_numText(_wizardFixedOtController)) ?? 0) > 0)
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Text(
                        '  ⚠ 고정연장수당 배정 시 실제 연장근로가 발생해야 합니다.',
                        style: TextStyle(
                          fontSize: 10,
                          color: Color(0xFFFF8A80),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _wizRow(String label, String value, String sub) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: Color(0xFF37474F)),
            ),
            Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1a237e),
              ),
            ),
          ],
        ),
        Text(
          sub,
          style: const TextStyle(fontSize: 10, color: Color(0xFF78909C)),
        ),
      ],
    ),
  );

  Widget _wizDistributionField(String label, TextEditingController controller, {bool isOt = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8.0),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Text(
                label,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
            Expanded(
              flex: 4,
              child: Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFFFCC80)),
                ),
                child: TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    _MoneyInputFormatter(),
                  ],
                  textAlign: TextAlign.right,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 9),
                    hintText: '0',
                    hintStyle: TextStyle(color: Color(0xFFB0BEC5), fontSize: 13),
                    suffixText: ' 원',
                    suffixStyle: TextStyle(color: Color(0xFF455A64), fontSize: 13),
                  ),
                  onChanged: (v) {
                    setState(() {
                      if (isOt) {
                        final otAmount = int.tryParse(_numText(controller)) ?? 0;
                        if (otAmount > 0) {
                          final sR = _sRef().toInt();
                          final hourlyRate = sR > 0 ? _wizardBaseSalary / sR : 0.0;
                          final otMultiplier = _isFiveOrMoreStore ? 1.5 : 1.0;
                          double otHoursFloor = hourlyRate > 0
                              ? ((otAmount / (hourlyRate * otMultiplier)) * 10).floorToDouble() / 10.0
                              : 0.0;
                          if (otHoursFloor > 20) otHoursFloor = 20;
                          _fixedOvertimeHoursController.text = otHoursFloor.toStringAsFixed(1);
                        } else {
                          _fixedOvertimeHoursController.text = '0';
                        }
                      }
                    });
                  },
                ),
              ),
            ),
          ],
        ),
      );

  Widget _wizDistributionOtherField(String labelHint, TextEditingController labelController, TextEditingController amountController) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8.0),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Container(
                height: 36,
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFFFCC80)),
                ),
                child: TextField(
                  controller: labelController,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 9),
                    hintText: labelHint,
                    hintStyle: const TextStyle(color: Color(0xFFB0BEC5), fontSize: 11),
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 4,
              child: Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFFFCC80)),
                ),
                child: TextField(
                  controller: amountController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    _MoneyInputFormatter(),
                  ],
                  textAlign: TextAlign.right,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 9),
                    hintText: '0',
                    hintStyle: TextStyle(color: Color(0xFFB0BEC5), fontSize: 13),
                    suffixText: ' 원',
                    suffixStyle: TextStyle(color: Color(0xFF455A64), fontSize: 13),
                  ),
                  onChanged: (v) {
                    setState(() {});
                  },
                ),
              ),
            ),
          ],
        ),
      );

  Widget _wizCheck(String label, bool ok) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 1),
    child: Row(
      children: [
        Icon(
          ok ? Icons.check_circle : Icons.cancel,
          size: 16,
          color: ok ? const Color(0xFF66BB6A) : const Color(0xFFFF5252),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: ok ? const Color(0xFFA5D6A7) : const Color(0xFFFF8A80),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    ),
  );

  Widget _buildBlock2WageContent() {
    final sR = _sRef();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _isDispatch ? '용역비 형태 (앱 계산용 아님) *' : '급여 형태 *',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF333333),
            ),
          ),
          const SizedBox(height: 6),
          DropdownButtonFormField<WageType>(
            value: _wageType,
            items: const [
              DropdownMenuItem(value: WageType.hourly, child: Text('시급')),
              DropdownMenuItem(value: WageType.monthly, child: Text('월급여')),
            ],
            onChanged: (v) {
              if (v == null) return;
              setState(() => _wageType = v);
            },
            decoration: const InputDecoration(
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 14,
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (_wageType == WageType.monthly) _buildAutoWizard(),
          if (_wageType == WageType.monthly) ...[
            // 기본급 입력
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F4FF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF1a6ebd), width: 1),
              ),
              child: Row(
                children: [
                  Text(
                    _isDispatch ? '월 용역비' : '기본급',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF888888),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _monthlyWageController,
                      onChanged: (v) {
                        _validateMonthlyWage(v);
                        setState(() {});
                      },
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        _MoneyInputFormatter(),
                      ],
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        hintText: '예: 2,156,880',
                      ),
                    ),
                  ),
                  const Text(
                    '원',
                    style: TextStyle(
                      fontSize: 14,
                      color: Color(0xFF1a6ebd),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),

            // S_Ref(209시간) 기반 최저임금 실시간 검증
            Builder(
              builder: (_) {
                final enteredBase =
                    int.tryParse(_numText(_monthlyWageController)) ?? 0;
                if (enteredBase <= 0 || sR <= 0) return const SizedBox.shrink();
                final rate = enteredBase / sR;
                final minBase = (sR * _minimumHourlyWage).ceil();
                if (!_isDispatch && rate < _minimumHourlyWage) {
                  return Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFEBEE),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE53935)),
                    ),
                    child: Text(
                      '🚫 기본급/${sR.toInt()}h = ${_formatMoney(rate.round())}원/h < 최저임금 ${_formatMoney(_minimumHourlyWage.round())}원/h\n→ 기본급을 최소 ${_formatMoney(minBase)}원 이상으로 설정해 주세요. (209시간 기준)',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFFB71C1C),
                        height: 1.5,
                      ),
                    ),
                  );
                }
                // 월급제: S_Ref 단일 기준만 사용 (S_Legal 방패 비활성화)
                return const SizedBox.shrink();
              },
            ),
          ] else ...[
            // 시급 입력
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F4FF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF1a6ebd), width: 1),
              ),
              child: Row(
                children: [
                  Text(
                    _isDispatch ? '시간당 용역비' : '시급',
                    style: const TextStyle(fontSize: 13, color: Color(0xFF888888)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _wageController,
                      onChanged: (v) {
                        _validateWage(v);
                        setState(() {});
                      },
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        _MoneyInputFormatter(),
                      ],
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                      ),
                    ),
                  ),
                  const Text(
                    '원',
                    style: TextStyle(
                      fontSize: 14,
                      color: Color(0xFF1a6ebd),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            if (_wageError != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFF9800)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        color: Color(0xFFE65100),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _wageError!,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFFE65100),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
          if (_wageType == WageType.hourly) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F4FF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '예상 월급 (${DateTime.now().month}월 달력 기준, 주휴 포함): 약 ${_estimatedMonthlyPayText()}원',
                style: const TextStyle(fontSize: 13, color: Color(0xFF1a6ebd)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  // Block 3: 수당 및 절세
  // ════════════════════════════════════════════════════════════════
  Widget _buildBlock3AllowanceContent() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '상여금(월)',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF333333),
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _bonusController,
            decoration: const InputDecoration(
              suffixText: '원',
              hintText: '금액 입력',
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 14,
              ),
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              _MoneyInputFormatter(),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _showAllowanceAddSheet(),
              icon: const Icon(Icons.add_rounded),
              label: const Text('+ 수당 추가'),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if ((int.tryParse(_numText(_mealAllowanceController)) ?? 0) > 0)
                Chip(
                  label: Text(
                    '식비: ${int.tryParse(_numText(_mealAllowanceController)) ?? 0}원${_mealTaxExempt ? ' (비과세)' : ''}',
                  ),
                  backgroundColor: _mealTaxExempt
                      ? const Color(0xFFE8F5E9)
                      : null,
                  deleteIcon: const Icon(Icons.close),
                  onDeleted: () => setState(() {
                    _mealAllowanceController.text = '';
                    _mealTaxExempt = false;
                  }),
                ),
              if ((int.tryParse(_numText(_transportAllowanceController)) ?? 0) >
                  0)
                Chip(
                  label: Text(
                    '교통비: ${int.tryParse(_numText(_transportAllowanceController)) ?? 0}원',
                  ),
                  deleteIcon: const Icon(Icons.close),
                  onDeleted: () =>
                      setState(() => _transportAllowanceController.text = ''),
                ),
              for (final item in _customItems)
                Chip(
                  label: Text('${item.label}: ${item.amount}원'),
                  deleteIcon: const Icon(Icons.close),
                  onDeleted: () => setState(() => _customItems.remove(item)),
                ),
            ],
          ),
          if ((int.tryParse(_numText(_mealAllowanceController)) ?? 0) > 0) ...[
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Container(
                decoration: BoxDecoration(
                  color: _mealTaxExempt
                      ? const Color(0xFFE8F5E9)
                      : const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _mealTaxExempt
                        ? const Color(0xFF66BB6A)
                        : Colors.grey.shade300,
                  ),
                ),
                child: SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  dense: true,
                  title: Text(
                    '식대 비과세 적용',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _mealTaxExempt
                          ? const Color(0xFF2E7D32)
                          : Colors.black87,
                    ),
                  ),
                  subtitle: Text(
                    _mealTaxExempt
                        ? '✅ 식비 최대 20만원까지 4대보험 산정에서 제외됩니다'
                        : '식비를 과세 대상에 포함합니다',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                  value: _mealTaxExempt,
                  onChanged: (v) async {
                    if (v) {
                      final c = await _showMealTaxExemptChecklist(context);
                      if (c == true) setState(() => _mealTaxExempt = true);
                    } else {
                      setState(() => _mealTaxExempt = false);
                    }
                  },
                  activeColor: const Color(0xFF2E7D32),
                ),
              ),
            ),
            if (_wageType == WageType.monthly)
              AnimatedSize(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                child: _mealTaxExempt
                    ? _buildNonTaxableStrategyGuide()
                    : const SizedBox.shrink(),
              ),
          ],
          if (_wageType == WageType.monthly) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFFB300), width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.timer_outlined,
                        size: 16,
                        color: Color(0xFFFF8F00),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        '고정연장 약정시간',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF888888),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 80,
                        child: TextField(
                          controller: _fixedOvertimeHoursController,
                          onChanged: (v) => setState(() {}),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          textAlign: TextAlign.center,
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                            hintText: '0',
                          ),
                        ),
                      ),
                      const Text(
                        '시간/월',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFFFF8F00),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '0 = 고정연장 없음 | 초과 시 차액 자동 지급',
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  // Block 4: 최종 검증 대시보드 (읽기 전용)
  // ════════════════════════════════════════════════════════════════
  Widget _buildBlock4VerifyContent() {
    final sR = _sRef();
    final enteredBase = int.tryParse(_numText(_monthlyWageController)) ?? 0;
    final mealVal = int.tryParse(_numText(_mealAllowanceController)) ?? 0;
    final fixedOTH = double.tryParse(_fixedOvertimeHoursController.text) ?? 0;
    final cRate = sR > 0 && enteredBase > 0 ? enteredBase / sR : 0.0;
    final combRate = sR > 0 && enteredBase > 0
        ? (enteredBase + mealVal + (_wizardApplied ? _wizardDistributedAmount : 0)) / sR
        : 0.0;
    // 고정연장수당: 위자드 확정값 우선, 없으면 시간×시급 역산
    final fixedOTPay = _wizardApplied 
        ? (int.tryParse(_numText(_wizardFixedOtController)) ?? 0)
        : (fixedOTH > 0 && combRate > 0
            ? (fixedOTH * combRate * (_isFiveOrMoreStore ? 1.5 : 1.0)).round()
            : 0);
    final total = enteredBase + fixedOTPay + mealVal + (_wizardApplied ? (_wizardDistributedAmount - fixedOTPay) : 0);
    final hardBlock = sR > 0 && enteredBase > 0 && cRate < _minimumHourlyWage;

    if (_wageType != WageType.monthly || enteredBase <= 0) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F5F5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text(
            '급여 정보를 입력하면 검증 결과가 표시됩니다.',
            style: TextStyle(color: Color(0xFF888888), fontSize: 13),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: Column(
        children: [
          // 통상시급 이원화 (초록/빨강)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: hardBlock
                  ? const Color(0xFFFFEBEE)
                  : const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: hardBlock
                    ? const Color(0xFFE53935)
                    : const Color(0xFF4CAF50),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hardBlock ? '🚫 최저임금 미달' : '✅ 통상시급 검증',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: hardBlock
                        ? const Color(0xFFB71C1C)
                        : const Color(0xFF1B5E20),
                  ),
                ),
                const SizedBox(height: 8),
                _vRow(
                  '통상시급',
                  '${_formatMoney(combRate.round())}원/h',
                  hardBlock,
                ),
                _vRow(
                  '최저임금 기준',
                  '${_formatMoney(_minimumHourlyWage.round())}원/h',
                  false,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // 월간 요약
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F4FF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF1a6ebd)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '💰 월간 급여 요약',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0D47A1),
                  ),
                ),
                const SizedBox(height: 8),
                _vRow('기본급', '${_formatMoney(enteredBase)}원', false),
                if (fixedOTPay > 0)
                  _vRow('고정연장수당', '${_formatMoney(fixedOTPay)}원', false),
                if (mealVal > 0)
                  _vRow(
                    '식대${_mealTaxExempt ? '(비과세)' : ''}',
                    '${_formatMoney(mealVal)}원',
                    false,
                  ),
                const Divider(height: 16),
                _vRow('예상 총급여', '${_formatMoney(total)}원', false),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _vRow(String l, String v, bool e) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          l,
          style: TextStyle(
            fontSize: 12,
            color: e ? const Color(0xFFB71C1C) : const Color(0xFF555555),
          ),
        ),
        Text(
          v,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: e ? const Color(0xFFB71C1C) : const Color(0xFF1a1a2e),
          ),
        ),
      ],
    ),
  );

  Widget _buildAdvancedLaborSettingsSection() {
    return ExpansionTile(
      title: const Text('고급 노무 설정', style: TextStyle(fontWeight: FontWeight.bold)),
      subtitle: const Text('퇴직금·연차수당·통상임금 산정 기준', style: TextStyle(fontSize: 12, color: Colors.grey)),
      collapsedBackgroundColor: Colors.grey.shade50,
      backgroundColor: Colors.grey.shade50,
      childrenPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        SwitchListTile(
          title: const Text('식대 통상임금 포함', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          subtitle: const Text('정기·일률적으로 지급되는 식대를\n통상임금 계산에 포함합니다.', style: TextStyle(fontSize: 13, color: Colors.black54)),
          value: _includeMealInOrdinary,
          activeColor: Theme.of(context).primaryColor,
          onChanged: (val) => setState(() => _includeMealInOrdinary = val),
        ),
        const Divider(height: 1),
        SwitchListTile(
          title: const Text('고정수당 통상임금 포함', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          subtitle: const Text('직책수당·근속수당 등\n고정 지급 수당을 통상임금에 포함합니다.', style: TextStyle(fontSize: 13, color: Colors.black54)),
          value: _includeAllowanceInOrdinary,
          activeColor: Theme.of(context).primaryColor,
          onChanged: (val) => setState(() => _includeAllowanceInOrdinary = val),
        ),
        const Divider(height: 1),
        SwitchListTile(
          title: const Text('고정OT 평균임금 포함', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          subtitle: const Text('고정적으로 지급되는 연장근로수당을\n평균임금 계산에 반영합니다.', style: TextStyle(fontSize: 13, color: Colors.black54)),
          value: _includeFixedOtInAverage,
          activeColor: Theme.of(context).primaryColor,
          onChanged: (val) => setState(() => _includeFixedOtInAverage = val),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.amber.shade200),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '실제 지급 형태에 따라 노동청·법원에서 통상임금 포함 대상으로 판단될 수 있습니다.',
                  style: TextStyle(fontSize: 13, color: Colors.black87, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// 금액 입력 시 자동 콤마 포맷 (예: 2200000 → 2,200,000)
class _MoneyInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (text.isEmpty) {
      return newValue.copyWith(text: '');
    }
    final number = int.tryParse(text);
    if (number == null) return newValue;
    final formatted = NumberFormat('#,###').format(number);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
