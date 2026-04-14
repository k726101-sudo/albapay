import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_logic/shared_logic.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/services.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../models/worker.dart';
import 'signature_pad_screen.dart';

class CreateDocumentScreen extends StatefulWidget {
  final Worker worker;
  final String storeId;

  const CreateDocumentScreen({super.key, required this.worker, required this.storeId});

  @override
  State<CreateDocumentScreen> createState() => _CreateDocumentScreenState();
}

class _CreateDocumentScreenState extends State<CreateDocumentScreen> {
  DocumentType _selectedType = DocumentType.contract_full;
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _dbService = DatabaseService();
  bool _isLoading = false;
  bool _isUltraShort = false;

  @override
  void initState() {
    super.initState();
    _isUltraShort = DocumentCalculator.isUltraShortTime(widget.worker.weeklyHours);
    final suggested = DocumentCalculator.suggestContractType(widget.worker.weeklyHours);
    if (suggested == 'contract_full') {
      _selectedType = DocumentType.contract_full;
    } else {
      _selectedType = DocumentType.contract_part;
    }
    _updateTemplate();
  }

  void _updateTemplate() {
    if (_selectedType == DocumentType.contract_full ||
        _selectedType == DocumentType.contract_part ||
        _selectedType == DocumentType.laborContract) {
      _titleController.text = '표준 근로계약서 - ${widget.worker.name}';
      final workingDaysText = _workingDaysText(widget.worker);
      final workingHoursText = _workingHoursText(widget.worker);
      final breakTimeText = _breakTimeText(widget.worker);
      final breakClauseText = _breakClauseText(widget.worker);
      final weeklyHolidayText = _weeklyHolidayText(widget.worker);
      final dispatchCompany = widget.worker.workerType == 'dispatch'
          ? (widget.worker.dispatchCompany ?? '-')
          : '-';
      final dispatchPeriod = widget.worker.workerType == 'dispatch'
          ? '${_displayDate(widget.worker.dispatchStartDate)} ~ ${_displayOptionalDate(widget.worker.dispatchEndDate)}'
          : '해당 없음';
      final dispatchContact = widget.worker.workerType == 'dispatch'
          ? (widget.worker.dispatchContact ?? '-')
          : '-';
      final dispatchMemo = widget.worker.workerType == 'dispatch'
          ? (widget.worker.dispatchMemo ?? '-')
          : '-';
      final now = AppClock.now();
      final todayStr = '${now.year}년 ${now.month.toString().padLeft(2, '0')}월 ${now.day.toString().padLeft(2, '0')}일';
      _contentController.text = DocumentTemplates.getLaborContract({
        'contractDate': todayStr,
        'startDate': now.toString().substring(0, 10),
        'storeName': '본 매장',
        'jobDescription': '매장 관리 및 고객 응대',
        'workingHours': workingHoursText,
        'breakTime': breakTimeText,
        'breakClause': breakClauseText,
        'breakPaidClause': widget.worker.isPaidBreak
            ? '\n   - 휴게시간 중 업무 수행 시 해당 시간만큼 시급을 가산하여 지급한다.'
            : '',
        'workingDays': workingDaysText,
        'weeklyHoliday': weeklyHolidayText,
        'dispatchCompany': dispatchCompany,
        'dispatchPeriod': dispatchPeriod,
        'dispatchContact': dispatchContact,
        'dispatchMemo': dispatchMemo,
        'baseWage': widget.worker.hourlyWage.toStringAsFixed(0),
        'payday': '10',
        'ownerName': '대표자',
        'staffName': widget.worker.name,
      });
    } else if (_selectedType == DocumentType.night_consent ||
        _selectedType == DocumentType.nightHolidayConsent) {
      _titleController.text = '야간 및 휴일근로 동의서 - ${widget.worker.name}';
      final now = AppClock.now();
      final todayStr = '${now.year}년 ${now.month.toString().padLeft(2, '0')}월 ${now.day.toString().padLeft(2, '0')}일';
      _contentController.text =
          DocumentTemplates.getNightHolidayConsent(widget.worker.name, consentDate: todayStr);
    } else if (_selectedType == DocumentType.worker_record ||
        _selectedType == DocumentType.employeeRegistry) {
      _titleController.text = '근로자 명부 - ${widget.worker.name}';
      _contentController.text = DocumentTemplates.getEmployeeRegistry({
        'name': widget.worker.name,
        'birthDate': '19XX-XX-XX',
        'address': '별도 기재',
        'hireDate': AppClock.now().toString().substring(0, 10),
        'job': '매장 스태프',
        'contractPeriod': '정규직',
      });
    } else if (_selectedType == DocumentType.checklist) {
      _titleController.text = '채용 체크리스트 - ${widget.worker.name}';
      _contentController.text = '채용 체크리스트 내용은 템플릿 단계에서 추가하세요.';
    } else if (_selectedType == DocumentType.minor_consent ||
        _selectedType == DocumentType.parentalConsent) {
      _titleController.text = '친권자 동의서 - ${widget.worker.name}';
      _contentController.text = '친권자 동의서 내용은 템플릿 단계에서 추가하세요.';
    } else if (_selectedType == DocumentType.attendance_record) {
      _titleController.text = '출퇴근기록부 - ${widget.worker.name}';
      _contentController.text = '출퇴근기록부는 직원의 앱 이용 기록(출퇴근 체크)을 바탕으로 자동 처리됩니다.';
    } else if (_selectedType == DocumentType.wageStatement ||
        _selectedType == DocumentType.wage_ledger) {
      _titleController.text = '임금명세서 - ${widget.worker.name}';
      _contentController.text = '임금명세서 및 임금대장은 앱의 급여 정산 엔진을 바탕으로 자동 생성됩니다. (상세 화면에서 PDF로 다운로드 및 발송 가능)';
    } else if (_selectedType == DocumentType.annual_leave_ledger) {
      _titleController.text = '연차휴가 관리대장 - ${widget.worker.name}';
      _contentController.text = '연차 관리 데이터는 직원의 근속 기간과 근무 기록을 바탕으로 자동 계산됩니다.';
    } else if (_selectedType == DocumentType.wage_amendment) {
      _titleController.text = '임금 계약 변경서 - ${widget.worker.name}';
      _contentController.text = '임금 계약 변경서는 인상된 급여 등을 반영하여 새로 작성하는 문서입니다.';
    } else {
      _titleController.text = '기타 서류';
      _contentController.text = '';
    }
  }

  Future<void> _handleCreate() async {
    setState(() => _isLoading = true);

    final docId = const Uuid().v4();

    final doc = LaborDocument(
      id: docId,
      staffId: widget.worker.id,
      storeId: widget.storeId,
      type: _selectedType,
      title: _titleController.text,
      content: _contentController.text,
      createdAt: AppClock.now(),
      status: 'ready',
      expiryDate: DocumentCalculator.calculateExpiryDate(AppClock.now()),
    );

    try {
      await _dbService.saveDocument(doc);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('서류가 성공적으로 생성되었습니다. 상세 화면에서 서명을 진행해 주세요.')),
        );
        Navigator.pop(context);
      }
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

  String _workingDaysText(Worker worker) {
    if (worker.workDays.isEmpty) return '별도 협의';
    final sorted = [...worker.workDays]..sort();
    return sorted.map(_weekdayLabel).join('·');
  }

  String _workingHoursText(Worker worker) {
    if (worker.workDays.isEmpty) return '별도 협의';

    // 요일별 출퇴근이 그룹 단위(workScheduleJson)로 저장될 수 있어서, day -> (start,end) 매핑을 풀어줍니다.
    final dayToTime = <int, ({String start, String end})>{};
    if (worker.workScheduleJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(worker.workScheduleJson) as List<dynamic>;
        for (final raw in decoded) {
          final m = raw as Map<String, dynamic>;
          final start = m['start']?.toString() ?? worker.checkInTime;
          final end = m['end']?.toString() ?? worker.checkOutTime;
          final days = (m['days'] as List<dynamic>? ?? const []);
          for (final d in days) {
            final code = d is int ? d : int.tryParse(d.toString()) ?? 0;
            dayToTime[code] = (start: start, end: end);
          }
        }
      } catch (_) {}
    }

    final breakRange = _resolvedBreakRange(worker);
    final breakInline = breakRange != null
        ? '${breakRange.start}~${breakRange.end}'
        : '${worker.breakMinutes.toInt()}분';

    const order = [1, 2, 3, 4, 5, 6, 0]; // 월..일 (0=일)
    final lines = <String>[];
    for (final day in order) {
      if (!worker.workDays.contains(day)) continue;
      final t = dayToTime[day];
      final start = t?.start ?? worker.checkInTime;
      final end = t?.end ?? worker.checkOutTime;
      lines.add('${_weekdayLabel(day)} $start~$end(휴게시간 $breakInline)');
    }
    return lines.join('\n');
  }

  String _breakTimeText(Worker worker) {
    final minutes = worker.breakMinutes.toInt();
    final paidLabel = worker.isPaidBreak ? '유급' : '무급(원칙)';

    final range = _resolvedBreakRange(worker);
    final hasRange = range != null;
    if (minutes <= 0 && !hasRange) return '없음';
    if (hasRange) {
      return '${range.start} ~ ${range.end} ($minutes분) / $paidLabel';
    }
    return '일 $minutes분 / $paidLabel';
  }

  String _breakClauseText(Worker worker) {
    final minutes = worker.breakMinutes.toInt();
    if (minutes <= 0) return '휴게시간 없음';

    final range = _resolvedBreakRange(worker);
    final hasRange = range != null;
    if (hasRange) {
      return '${range.start}~${range.end} 중 휴게 $minutes분';
    }

    return '휴게 $minutes분';
  }

  ({String start, String end})? _resolvedBreakRange(Worker worker) {
    final minutes = worker.breakMinutes.toInt();
    if (minutes <= 0) return null;
    if (worker.breakStartTime.isNotEmpty && worker.breakEndTime.isNotEmpty) {
      return (start: worker.breakStartTime, end: worker.breakEndTime);
    }
    final start = _autoBreakStart(worker.checkInTime, worker.checkOutTime, minutes);
    if (start == null) return null;
    return (start: start, end: _addMinutesToHm(start, minutes));
  }

  String? _autoBreakStart(String checkIn, String checkOut, int breakMinutes) {
    final total = _durationMinutes(checkIn, checkOut);
    if (total <= 0) return null;
    final inMinutes = _timeToMinutes(checkIn);
    final offset = ((total - breakMinutes).clamp(0, total) / 2).round();
    return _minutesToHm(inMinutes + offset);
  }

  String _minutesToHm(int minutes) {
    final normalized = ((minutes % (24 * 60)) + (24 * 60)) % (24 * 60);
    final hh = (normalized ~/ 60).toString().padLeft(2, '0');
    final mm = (normalized % 60).toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  int _timeToMinutes(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length != 2) return 0;
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    return h * 60 + m;
  }

  int _durationMinutes(String start, String end) {
    return _timeToMinutes(end) - _timeToMinutes(start);
  }

  String _addMinutesToHm(String startHm, int deltaMinutes) {
    return _minutesToHm(_timeToMinutes(startHm) + deltaMinutes);
  }

  String _weeklyHolidayText(Worker worker) {
    if (!worker.weeklyHolidayPay) {
      return '[무급] 15시간 미만 근로자로 주휴수당이 발생하지 않습니다.';
    } else {
      const labels = ['일', '월', '화', '수', '목', '금', '토'];
      final d = worker.weeklyHolidayDay;
      final day = (d >= 0 && d < labels.length) ? labels[d] : '';
      return day.isEmpty ? '[유급] 주 1회' : '[유급] $day요일';
    }
  }

  String _displayDate(String? iso) {
    if (iso == null || iso.trim().isEmpty) return '미정';
    final s = iso.trim();
    return s.length >= 10 ? s.substring(0, 10) : s;
  }

  String _displayOptionalDate(String? iso) {
    if (iso == null || iso.trim().isEmpty) return '미정';
    final s = iso.trim();
    return s.length >= 10 ? s.substring(0, 10) : s;
  }

  String _weekdayLabel(int weekday) {
    // Worker day code 기준 (0=일 ... 6=토)로도 동작하게 처리합니다.
    if (weekday == 0) return '일';
    if (weekday == DateTime.monday) return '월';
    if (weekday == DateTime.tuesday) return '화';
    if (weekday == DateTime.wednesday) return '수';
    if (weekday == DateTime.thursday) return '목';
    if (weekday == DateTime.friday) return '금';
    if (weekday == DateTime.saturday) return '토';
    if (weekday == DateTime.sunday) return '일';
    return '';
  }

  String _documentTypeLabel(DocumentType type) {
    if (type == DocumentType.laborContract) return '표준 근로계약서';
    if (type == DocumentType.nightHolidayConsent) return '야간/휴일근로 동의서';
    if (type == DocumentType.employeeRegistry) return '근로자 명부';
    if (type == DocumentType.attendance_record) return '출퇴근기록부';
    if (type == DocumentType.wageStatement || type == DocumentType.wage_ledger) return '임금명세서/대장';
    if (type == DocumentType.annual_leave_ledger) return '연차휴가관리대장';
    if (type == DocumentType.contract_full) return '표준 근로계약서 (일반)';
    if (type == DocumentType.contract_part) return '표준 근로계약서 (초단기/단시간)';
    if (type == DocumentType.night_consent) return '야간/휴일근로 동의서';
    if (type == DocumentType.checklist) return '채용 체크리스트';
    if (type == DocumentType.worker_record) return '근로자 명부';
    if (type == DocumentType.minor_consent) return '친권자 동의서';
    if (type == DocumentType.wage_amendment) return '임금 계약 변경서';
    return type.name;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('새 노무 서류 작성')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('서류 종류 선택', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            DropdownButtonFormField<DocumentType>(
              initialValue: _selectedType,
              items: DocumentType.values
                  .map(
                    (type) => DropdownMenuItem(
                      value: type,
                      child: Text(_documentTypeLabel(type)),
                    ),
                  )
                  .toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _selectedType = val;
                    _updateTemplate();
                  });
                }
              },
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
            if (_selectedType == DocumentType.contract_part && _isUltraShort)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFDECEC),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Color(0xFFD32F2F), size: 20),
                    SizedBox(width: 8),
                    Expanded(child: Text('주 15시간 미만 초단시간 근로자입니다. (주휴/연차 미대상)', style: TextStyle(color: Color(0xFFD32F2F), fontSize: 13, fontWeight: FontWeight.bold))),
                  ],
                ),
              ),
            const SizedBox(height: 24),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: '서류 제목'),
            ),
            const SizedBox(height: 16),
            const Text('상세 내용 (템플릿 기반 자동 생성)', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _contentController,
              maxLines: 15,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '내용을 입력하거나 템플릿을 수정하세요.',
              ),
            ),
            const SizedBox(height: 40),
            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _handleCreate,
                      child: const Text('작성 완료 및 전송'),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}
