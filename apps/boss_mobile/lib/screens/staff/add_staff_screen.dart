import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_logic/shared_logic.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';

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
  final _wageController = TextEditingController();
  WageType _wageType = WageType.hourly;
  final _bonusController = TextEditingController(text: '0');
  final _mealAllowanceController = TextEditingController(text: '0');
  final _transportAllowanceController = TextEditingController(text: '0');
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
  double _minimumHourlyWage = 0;

  // 근무 시간 입력 섹션 모드 (요약/상세)
  bool _isEditingWorkTime = false;

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
  bool _section3Expanded = false;
  bool _section4Expanded = false;
  bool _isMinor = false;

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
    final midpointOffset = ((duration - breakMinutes).clamp(0, duration) / 2).round();
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
    _phoneController.addListener(_phoneFormatListener);
    _breakMinutesController.addListener(_weeklyHoursSyncListener);
    _workStartController.addListener(_weeklyHoursSyncListener);
    _workEndController.addListener(_weeklyHoursSyncListener);
    _loadMinimumHourlyWage();
    _autoAssignBreakStartMidpoint();
    final worker = widget.initialWorker;
    if (worker == null) return;

    _nameController.text = worker.name;
    _employeeIdController.text = worker.employeeId ?? '';
    _phoneController.text = _formatPhoneDisplay(worker.phone);
    _wageController.text = worker.hourlyWage.toStringAsFixed(0);
    _bonusController.text = '0';
    _mealAllowanceController.text = '0';
    _transportAllowanceController.text = '0';
    _hireDate = RobustDateParser.parse(worker.startDate);
    _breakMinutesController.text = worker.breakMinutes.toInt().toString();
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
    if (worker.workerType == 'dispatch') _employeeType = _EmployeeType.dispatched;
    if (worker.workerType == 'foreigner') _employeeType = _EmployeeType.foreigner;
    _isDispatch = _employeeType == _EmployeeType.dispatched;
    _birthDate = worker.birthDate.isEmpty ? null : DateTime.tryParse(worker.birthDate);
    if (_birthDate != null) {
      _isMinor = _calcAge(_birthDate!) < 18;
    }
    _isLongTerm = worker.endDate == null || worker.endDate!.isEmpty;
    _contractEndDate = _isLongTerm ? null : DateTime.tryParse(worker.endDate!);
    _weeklyHolidayDay = worker.weeklyHolidayDay;
    _visaType = worker.visaType;
    _visaExpiryDate = worker.visaExpiry == null ? null : DateTime.tryParse(worker.visaExpiry!);
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
          _dayStartController.text = _workStartByDay[_selectedWorkDay] ?? '17:00';
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
      ..addEntries(worker.workDays.map((d) => MapEntry(d == 0 ? DateTime.sunday : d, worker.checkInTime)));
    _workEndByDay
      ..clear()
      ..addEntries(worker.workDays.map((d) => MapEntry(d == 0 ? DateTime.sunday : d, worker.checkOutTime)));
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
      final wage = (data['currentHourly'] as num?)?.toDouble() ??
          (data['hourly'] as num?)?.toDouble() ??
          (data['minimumHourlyWage'] as num?)?.toDouble();
      if (wage == null || wage <= 0) return;
      if (!mounted) return;
      setState(() {
        _minimumHourlyWage = wage;
        if (widget.initialWorker == null && _wageController.text.trim().isEmpty) {
          _wageController.text = wage.toStringAsFixed(0);
        }
      });
    } catch (_) {
      // 최소시급 정보 조회 실패 시 입력값 기준으로 진행
    }
  }

  Future<String?> _fetchStoreId() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    final snap = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final storeId = snap.data()?['storeId'];
    if (storeId is! String) return null;
    final cleaned = storeId.trim();
    return cleaned.isEmpty ? null : cleaned;
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
    if (initial.compensationIncomeType != current.compensationIncomeType) return true;

    return false;
  }

  Future<Map<DocumentType, String>> _fetchDocumentStatuses(String workerId, String storeId) async {
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

  Worker _toWorker(String storeId) {
    final id = widget.initialWorker?.id ?? const Uuid().v4();
    final hourly = double.tryParse(_wageController.text.trim()) ?? 0;
    final workDays = _workStartByDay.keys.map((d) => d == DateTime.sunday ? 0 : d).toList()..sort();
    final start = (_workStartByDay.values.isNotEmpty ? _workStartByDay.values.first : _bulkStartController.text).trim();
    final end = (_workEndByDay.values.isNotEmpty ? _workEndByDay.values.first : _bulkEndController.text).trim();
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
      if ((int.tryParse(_bonusController.text.trim()) ?? 0) > 0)
        Allowance(label: '상여금', amount: (int.tryParse(_bonusController.text.trim()) ?? 0).toDouble()),
      if ((int.tryParse(_mealAllowanceController.text.trim()) ?? 0) > 0)
        Allowance(label: '식비', amount: (int.tryParse(_mealAllowanceController.text.trim()) ?? 0).toDouble()),
      if ((int.tryParse(_transportAllowanceController.text.trim()) ?? 0) > 0)
        Allowance(label: '교통비', amount: (int.tryParse(_transportAllowanceController.text.trim()) ?? 0).toDouble()),
      ..._customItems.map((e) => Allowance(label: e.label, amount: e.amount.toDouble())),
    ];
    return Worker(
      id: id,
      name: _nameController.text.trim(),
      employeeId: _employeeIdController.text.trim().isNotEmpty ? _employeeIdController.text.trim() : null,
      phone: _phoneController.text.replaceAll(RegExp(r'[^0-9]'), ''),
      birthDate: _birthDate == null ? '' : _birthDate!.toIso8601String().substring(0, 10),
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
      startDate: _hireDate == null ? '' : _hireDate!.toIso8601String().substring(0, 10),
      endDate: _isLongTerm || _contractEndDate == null
          ? null
          : _contractEndDate!.toIso8601String().substring(0, 10),
      isProbation: _applyProbationWage90Percent,
      probationMonths: _applyProbationWage90Percent ? _probationMonths : 0,
      allowances: allowances,
      hasHealthCert: _healthCertificateManagementEnabled && _hasHealthCertificate,
      healthCertExpiry: _healthCertificateExpiryDate?.toIso8601String().substring(0, 10),
      visaType: _employeeType == _EmployeeType.foreigner ? _visaType : null,
      visaExpiry: _employeeType == _EmployeeType.foreigner && _visaExpiryDate != null
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
              ? _dispatchContactController.text
                  .replaceAll(RegExp(r'[^0-9-]'), '')
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
          _compIncomeType == _CompensationIncomeType.labor && _deductNationalPension,
      deductHealthInsurance:
          _compIncomeType == _CompensationIncomeType.labor && _deductHealthInsurance,
      deductEmploymentInsurance:
          _compIncomeType == _CompensationIncomeType.labor && _deductEmploymentInsurance,
      trackIndustrialInsurance:
          _compIncomeType == _CompensationIncomeType.labor && _trackIndustrialInsurance,
      applyWithholding33: _compIncomeType == _CompensationIncomeType.business33 &&
          _applyWithholding33,
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
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
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
                  if (_compIncomeType == _CompensationIncomeType.business33) return;
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
                style: TextStyle(fontSize: 12, height: 1.35, color: Color(0xFF555555)),
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
    final DateTime firstDate =
        isBirthDate ? DateTime(1950) : DateTime(2000);
    final DateTime lastDate = isBirthDate
        ? AppClock.now().subtract(const Duration(days: 1))
        : DateTime(2100);

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate ??
          (isBirthDate ? DateTime(1995, 1, 1) : AppClock.now()),
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
      if (!isBirthDate && picked.isBefore(AppClock.now().subtract(const Duration(days: 1)))) {
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

  Future<bool?> _showBacktrackDialog(BuildContext context, DateTime pickedDate) async {
    final dateStr = DateFormat('yyyy년 MM월 dd일').format(pickedDate);
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.history_edu_rounded, color: Color(0xFF1a6ebd), size: 40),
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
            crossFadeState:
                isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            firstChild: const SizedBox.shrink(),
            secondChild: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Divider(height: 1, thickness: 0.5, color: Color(0xFFF0F0F0)),
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

  Future<Worker?> _saveWorkerToLocalAndCloud() async {
    setState(() => _isLoading = true);
    final storeId = await _fetchStoreId();
    if (!mounted) return null;
    if (storeId == null ||
        _nameController.text.trim().isEmpty ||
        _phoneController.text.replaceAll(RegExp(r'[^0-9]'), '').isEmpty ||
        _hireDate == null ||
        (!_isDispatch && (_workStartByDay.isEmpty || _workEndByDay.isEmpty))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('필수 항목을 확인해 주세요.')),
      );
      setState(() => _isLoading = false);
      return null;
    }

    if (_isMinor) {
      if (_hasNightWork(_bulkStartController.text.trim(), _bulkEndController.text.trim())) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('연소자는 오후 10시~오전 6시 사이의 근로가 원칙적으로 금지되어 있습니다.')),
        );
        setState(() => _isLoading = false);
        return null;
      }
      for (final startHm in _workStartByDay.values) {
        final day = _workStartByDay.keys.firstWhere((k) => _workStartByDay[k] == startHm);
        final endHm = _workEndByDay[day] ?? '';
        if (_hasNightWork(startHm, endHm)) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('연소자는 오후 10시~오전 6시 사이의 근로가 원칙적으로 금지되어 있습니다.')),
          );
          setState(() => _isLoading = false);
          return null;
        }
      }
    }
    if (_employeeType == _EmployeeType.foreigner && (_visaType == null || _visaType!.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('외국인 직원은 비자 종류가 필요합니다.')),
      );
      setState(() => _isLoading = false);
      return null;
    }

    if (_isDispatch) {
      if (_dispatchCompanyController.text.trim().isEmpty || _dispatchStartDate == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('파견 정보의 필수 항목을 확인해 주세요.')),
        );
        setState(() => _isLoading = false);
        return null;
      }
    }
    final baseWage = int.tryParse(_wageController.text.trim()) ?? 0;
    if (_minimumHourlyWage > 0 && baseWage < _minimumHourlyWage) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⚠️ 최저임금(${_formatMoney(_minimumHourlyWage)}원) 미달입니다'),
          backgroundColor: Color(0xFFE24B4A),
        ),
      );
    }
    final worker = _toWorker(storeId);
    try {
      await WorkerService.save(worker);
      return worker;
    } catch (e) {
      debugPrint('Worker save failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('저장 실패: $e')),
        );
      }
      return null;
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveOnly() async {
    final worker = await _saveWorkerToLocalAndCloud();
    if (!mounted || worker == null) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('저장되었습니다.')));
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
      if (!mounted) return;
      Navigator.pop(context);
      return;
    }
    if (!mounted) return;
    Navigator.pop(context);
  }

  Future<void> _saveAndContract() async {
    try {
      final worker = await _saveWorkerToLocalAndCloud();
      if (!mounted || worker == null) return;

      final storeId = await _fetchStoreId();
      if (storeId == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('매장 정보를 찾을 수 없습니다.')),
        );
        return;
      }

      // 순차적 마법사 시작
      await _startDocumentWizard(worker, storeId);
    } catch (e) {
      debugPrint('Save and contract failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('오류가 발생했습니다: $e')),
        );
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

    // 1. 초대 코드 전송 (신규 시에만 또는 코드 미존재 시)
    if (worker.inviteCode == null || worker.inviteCode!.isEmpty) {
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => StaffInviteCodeScreen(storeId: storeId, worker: worker),
        ),
      );
      if (!mounted) return;
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
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ContractPage(
            worker: worker,
            storeId: storeId,
            documentId: documentId,
          ),
        ),
      );
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
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F5F5),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.cake_outlined,
                                color: Color(0xFF888888), size: 18),
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
                          border: Border.all(color: const Color(0xFFE24B4A), width: 0.5),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.warning_rounded,
                                    color: Color(0xFFE24B4A), size: 16),
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
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                    DropdownButtonFormField<WageType>(
                      initialValue: _wageType,
                      items: const [
                        DropdownMenuItem(value: WageType.hourly, child: Text('시급')),
                        DropdownMenuItem(value: WageType.monthly, child: Text('월급여')),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _wageType = v);
                      },
                      decoration: const InputDecoration(labelText: '급여 형태 *'),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F4FF),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF1a6ebd), width: 1),
                      ),
                      child: Row(
                        children: [
                          const Text('시급',
                              style: TextStyle(fontSize: 13, color: Color(0xFF888888))),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _wageController,
                              onChanged: (_) => setState(() {}),
                              keyboardType: TextInputType.number,
                              decoration:
                                  const InputDecoration(border: InputBorder.none, isDense: true),
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
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F4FF),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '예상 월급 (주휴 포함): 약 ${_estimatedMonthlyPayText()}원',
                        style: const TextStyle(fontSize: 13, color: Color(0xFF1a6ebd)),
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
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F5F5),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.event_outlined,
                                color: Color(0xFF888888), size: 18),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    '입사일 *',
                                    style: TextStyle(fontSize: 12, color: Color(0xFF888888)),
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
          _isDispatch ? _buildDispatchSection() : _buildSection(
            '근무 조건',
            Icons.schedule_outlined,
            const Color(0xFF286b3a),
            _section2Expanded,
            () => setState(() => _section2Expanded = !_section2Expanded),
            [
              Padding(
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
                    final selected = _selectedDays.contains(day);
                    return ChoiceChip(
                      label: Text(_weekdayLabel(day)),
                      selected: selected,
                      selectedColor: const Color(0xFF1a6ebd),
                      backgroundColor: const Color(0xFFF2F2F7),
                      labelStyle: TextStyle(
                        color: selected ? Colors.white : Colors.grey,
                      ),
                      labelPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      onSelected: (v) {
                        setState(() {
                          if (v) {
                            _selectedDays.add(day);
                            // 첫 선택일 때만 컨트롤러를 동기화합니다.
                            if (_selectedDays.length == 1) {
                              _bulkStartController.text =
                                  _workStartByDay[day] ?? _bulkStartController.text;
                              _bulkEndController.text =
                                  _workEndByDay[day] ?? _bulkEndController.text;
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
                        onTap: () => _pickTimeForController(_bulkStartController),
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
                        onTap: () => _pickTimeForController(_bulkEndController),
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
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '실시간 계산',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _workMinutesExcludingBreakFromInputs() <= 0
                              ? '시간을 선택하면 표시됩니다.'
                              : '총 ${_workHoursExcludingBreakFromInputs().toStringAsFixed(1)}시간 근무 (휴게 ${_currentBreakMinutes()}분 제외)',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      if (_selectedDays.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('요일을 먼저 선택해 주세요.'),
                          ),
                        );
                        return;
                      }
                      final s = _bulkStartController.text.trim();
                      final e = _bulkEndController.text.trim();
                      if (!_isHm(s) || !_isHm(e)) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('시간은 HH:mm 형식으로 입력해 주세요.'),
                          ),
                        );
                        return;
                      }
                      if (_durationMinutes(s, e) <= 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('종료시간은 시작시간보다 뒤여야 합니다.'),
                          ),
                        );
                        return;
                      }
                      if (_isMinor && _hasNightWork(s, e)) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('연소자는 야간 근로(22:00~06:00)가 금지되어 있습니다. 시간을 다시 설정해 주세요.'),
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
                    },
                    icon: const Icon(Icons.check_circle_outline_rounded),
                    label: const Text('선택 요일에 일괄 적용'),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '휴게시간',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    InputChip(
                      label: const Text('30분'),
                      selected: _breakPreset == _BreakPreset.minutes30,
                      onSelected: (v) {
                        if (!v) return;
                        setState(() => _breakPreset = _BreakPreset.minutes30);
                      },
                    ),
                    InputChip(
                      label: const Text('60분'),
                      selected: _breakPreset == _BreakPreset.minutes60,
                      onSelected: (v) {
                        if (!v) return;
                        setState(() => _breakPreset = _BreakPreset.minutes60);
                      },
                    ),
                    InputChip(
                      label: const Text('직접 입력'),
                      selected: _breakPreset == _BreakPreset.custom,
                      onSelected: (v) {
                        if (!v) return;
                        setState(() => _breakPreset = _BreakPreset.custom);
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
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  tileColor: Colors.black12.withValues(alpha: 0.02),
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFECEFFB),
                    child: Icon(Icons.free_breakfast_rounded,
                        color: Color(0xFF0032A0)),
                  ),
                  title: const Text(
                    '휴게 시작 시간',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: Text(
                    _breakStartTime,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  trailing: const Icon(Icons.keyboard_arrow_right_rounded),
                  onTap: () async {
                    final temp = TextEditingController(text: _breakStartTime);
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
                  onChanged: (val) => setState(() => _isBreakPaid = val),
                ),
                const SizedBox(height: 16),
                Text(
                  '등록된 근무 시간표',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 10),
                if (_workStartByDay.isEmpty || _workEndByDay.isEmpty)
                  const Text('아직 등록된 근무시간이 없습니다.\n위에서 요일과 시간을 먼저 설정해 주세요.')
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
                                  const EdgeInsets.symmetric(horizontal: 10),
                            ),
                          )
                          .toList();
                      return Card(
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
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${g.start}~${g.end}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.w800,
                                              ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '휴게시간: $_breakStartTime~$breakEnd',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline_rounded),
                                    tooltip: '해당 시간표 삭제',
                                    onPressed: () => setState(() {
                                      for (final day in g.days) {
                                        _workStartByDay.remove(day);
                                        _workEndByDay.remove(day);
                                        _selectedDays.remove(day);
                                        _contractedDays.remove(day);
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
                    onPressed: () => setState(() => _isEditingWorkTime = false),
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: _weeklyHours() >= 15
                                        ? const Color(0xFFEAF3DE)
                                        : const Color(0xFFFFF0DC),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    _weeklyHours() >= 15 ? '[유급]' : '[무급]',
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
                                style: TextStyle(color: Color(0xFFA32D2D), fontWeight: FontWeight.w600),
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
                                for (final d in const [1, 2, 3, 4, 5, 6, 0]) // 월..일
                                  ChoiceChip(
                                    label: Text(_weekdayLabelShort(d)),
                                    selected: _weeklyHolidayDay == d,
                                    onSelected: (_) => setState(() => _weeklyHolidayDay = d),
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
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          DropdownButtonFormField<String>(
                            initialValue: _visaType,
                            decoration: const InputDecoration(labelText: '비자 종류'),
                            items: const [
                              DropdownMenuItem(value: 'E-9', child: Text('E-9 비전문취업')),
                              DropdownMenuItem(value: 'H-2', child: Text('H-2 방문취업')),
                              DropdownMenuItem(value: 'F-2', child: Text('F-2 거주')),
                              DropdownMenuItem(value: 'F-4', child: Text('F-4 재외동포')),
                              DropdownMenuItem(value: 'F-5', child: Text('F-5 영주')),
                              DropdownMenuItem(value: '기타', child: Text('기타')),
                            ],
                            onChanged: (v) => setState(() => _visaType = v),
                          ),
                          const SizedBox(height: 8),
                          if (_visaType == 'F-4' || _visaType == '기타')
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFCEBEB),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                '⚠️ 해당 비자는 취업이 제한될 수 있습니다',
                                style: TextStyle(color: Color(0xFFA32D2D)),
                              ),
                            ),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('체류기간 만료일'),
                            subtitle: Text(
                              _visaExpiryDate == null
                                  ? '선택 안됨'
                                  : _visaExpiryDate!.toIso8601String().substring(0, 10),
                            ),
                            trailing: const Icon(Icons.calendar_today_outlined),
                            onTap: () async {
                              final date = await showDatePicker(
                                context: context,
                                initialDate: _visaExpiryDate ?? AppClock.now().add(const Duration(days: 365)),
                                firstDate: AppClock.now(),
                                lastDate: AppClock.now().add(const Duration(days: 3650)),
                              );
                              if (date != null) setState(() => _visaExpiryDate = date);
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
                          subtitle: const Text('수습기간 급여를 90%로 반영합니다.'),
                          value: _applyProbationWage90Percent,
                          activeThumbColor: const Color(0xFF1a6ebd),
                          onChanged: (v) {
                            setState(() {
                              _applyProbationWage90Percent = v;
                              if (!v) _probationMonths = 3;
                            });
                          },
                        ),
                        AnimatedCrossFade(
                          duration: const Duration(milliseconds: 300),
                          crossFadeState: _applyProbationWage90Percent
                              ? CrossFadeState.showSecond
                              : CrossFadeState.showFirst,
                          firstChild: const SizedBox.shrink(),
                          secondChild: _buildProbationGuide(),
                        ),
                      ],
                    ),
                  ),
                ),
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
                        Text(
                          '수당/기타 지급',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _bonusController,
                          decoration: const InputDecoration(
                            labelText: '상여금(월)',
                            suffixText: '원',
                          ),
                          keyboardType: TextInputType.number,
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
                            if ((int.tryParse(_mealAllowanceController.text.trim()) ?? 0) > 0)
                              Chip(
                                label: Text(
                                  '식비: ${int.tryParse(_mealAllowanceController.text.trim()) ?? 0}원',
                                ),
                                deleteIcon: const Icon(Icons.close),
                                onDeleted: () => setState(() {
                                  _mealAllowanceController.text = '0';
                                }),
                              ),
                            if ((int.tryParse(_transportAllowanceController.text.trim()) ?? 0) > 0)
                              Chip(
                                label: Text(
                                  '교통비: ${int.tryParse(_transportAllowanceController.text.trim()) ?? 0}원',
                                ),
                                deleteIcon: const Icon(Icons.close),
                                onDeleted: () => setState(() {
                                  _transportAllowanceController.text = '0';
                                }),
                              ),
                            for (final item in _customItems)
                              Chip(
                                label: Text('${item.label}: ${item.amount}원'),
                                deleteIcon: const Icon(Icons.close),
                                onDeleted: () => setState(() => _customItems.remove(item)),
                              ),
                          ],
                        ),
                      ],
                    ),
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
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF5F5F5),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.calendar_today_outlined,
                                  color: Color(0xFF888888), size: 18),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
          _isDispatch ? const SizedBox.shrink() : _buildSection(
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
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _isLoading ? null : _saveOnly,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF1a1a2e)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text(
                  '기본 정보만 저장',
                  style: TextStyle(
                    color: Color(0xFF1a1a2e),
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            if (!_isDispatch) ...[
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _saveAndContract,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1a1a2e),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text(
                          '저장 및 계약서 작성',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                ),
              ),
            ],
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
                  const Icon(Icons.event_outlined,
                      color: Color(0xFF888888), size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '파견 시작일 *',
                          style: TextStyle(fontSize: 12, color: Color(0xFF888888)),
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
                  const Icon(Icons.event_outlined,
                      color: Color(0xFF888888), size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '파견 종료일',
                          style: TextStyle(fontSize: 12, color: Color(0xFF888888)),
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
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('보건증 보유'),
            subtitle: Text(
              _hasHealthCertificate ? '보유 중' : '미보유',
            ),
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
                final initial = _healthCertificateExpiryDate ??
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
          data: MediaQuery.of(ctx).copyWith(
            textScaler: const TextScaler.linear(1.2),
          ),
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
    final amountController = TextEditingController(text: '0');

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
                bottom: MediaQuery.of(ctx).viewInsets.bottom + MediaQuery.of(ctx).padding.bottom + 16,
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
                      hintText: '예: 50000',
                      suffixText: '원',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('추가'),
                      onPressed: () {
                        final amount = int.tryParse(amountController.text.trim()) ?? 0;
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
                          setState(() => _mealAllowanceController.text = amount.toString());
                        } else if (selected == 'transport') {
                          setState(() => _transportAllowanceController.text = amount.toString());
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
                          setState(() => _customItems.add(CustomPayItem(label: label, amount: amount)));
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

  String _estimatedMonthlyPayText() {
    final hourly = int.tryParse(_wageController.text.trim()) ?? 0;
    if (hourly <= 0) return '0';
    final weekly = _weeklyHours();
    // 주휴수당: 주 소정근로시간 15시간 이상일 때만 자동 발생
    final weeklyHoliday = (weekly >= 15) ? ((weekly / 40.0) * 8.0 * hourly) : 0.0;
    final monthly = ((weekly * hourly) + weeklyHoliday) * 4.345;
    final asInt = monthly.round();
    return asInt.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
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
              Icon(Icons.warning_amber_rounded, color: Color(0xFFd4700a), size: 16),
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
    final hourlyWage = double.tryParse(_wageController.text.trim()) ?? 0;
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
              const Text('계약 시급', style: TextStyle(fontSize: 13, color: Color(0xFF888888))),
              Text(
                '${_formatMoney(hourlyWage)}원',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '수습 기간 시급 (90%)',
                style: TextStyle(fontSize: 13, color: Color(0xFF185FA5), fontWeight: FontWeight.w500),
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
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF1a6ebd) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected ? const Color(0xFF1a6ebd) : const Color(0xFFDDDDDD),
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
    return asInt
        .toString()
        .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
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
}
