import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_logic/shared_logic.dart';
import 'package:shared_logic/src/utils/payroll/payroll_models.dart';
import '../theme/verify_theme.dart';
import '../widgets/result_card.dart';
import '../widgets/save_result_button.dart';

/// 출퇴근 상세입력 + 엑셀 붙여넣기 검증 화면
/// 실제 출퇴근 기록을 기반으로 PayrollCalculator 를 실행하여 정확한 급여를 검증
class DetailedVerifyScreen extends StatefulWidget {
  const DetailedVerifyScreen({super.key});

  @override
  State<DetailedVerifyScreen> createState() => _DetailedVerifyScreenState();
}

class _DetailedVerifyScreenState extends State<DetailedVerifyScreen> {
  // ─── 근로자 설정 ───
  final _hourlyRateCtrl = TextEditingController(text: '10320');
  final _weeklyHoursCtrl = TextEditingController(text: '35');
  final _breakMinCtrl = TextEditingController(text: '60');
  final _joinDateCtrl = TextEditingController(text: '2025-01-01');
  final _periodStartCtrl = TextEditingController(text: '2026-05-16');
  final _periodEndCtrl = TextEditingController(text: '2026-06-15');
  final _scheduleStartCtrl = TextEditingController(text: '09:00');
  final _scheduleEndCtrl = TextEditingController(text: '18:00');
  final _overtimeHoursCtrl = TextEditingController(text: '0');
  final _nightHoursCtrl = TextEditingController(text: '0');
  final _absentDaysCtrl = TextEditingController(text: '0');
  List<int> _scheduledDays = [1, 2, 3, 4, 5];
  bool _isFiveOrMore = true;
  bool _isPaidBreak = false;

  // ─── 엑셀 붙여넣기 ───
  final _pasteCtrl = TextEditingController();
  List<_ParsedRow> _parsedRows = [];
  String? _parseError;

  // ─── 결과 ───
  PayrollCalculationResult? _result;

  static final _fmt = NumberFormat('#,###');

  @override
  void dispose() {
    _hourlyRateCtrl.dispose();
    _weeklyHoursCtrl.dispose();
    _breakMinCtrl.dispose();
    _joinDateCtrl.dispose();
    _periodStartCtrl.dispose();
    _periodEndCtrl.dispose();
    _scheduleStartCtrl.dispose();
    _scheduleEndCtrl.dispose();
    _overtimeHoursCtrl.dispose();
    _nightHoursCtrl.dispose();
    _absentDaysCtrl.dispose();
    _pasteCtrl.dispose();
    super.dispose();
  }

  /// 붙여넣기 데이터 파싱
  /// 지원 형식:
  ///   날짜\t출근\t퇴근
  ///   날짜,출근,퇴근
  ///   2026-05-16  09:00  18:00
  void _parseInput() {
    final text = _pasteCtrl.text.trim();
    if (text.isEmpty) {
      setState(() {
        _parsedRows = [];
        _parseError = '데이터를 입력해주세요';
      });
      return;
    }

    final rows = <_ParsedRow>[];
    final lines = text.split('\n');
    String? error;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      // 헤더 행 건너뛰기
      if (line.contains('날짜') || line.contains('date') || line.contains('Date')) continue;

      // 탭, 콤마, 또는 연속 공백으로 분리
      final parts = line.split(RegExp(r'[\t,]|\s{2,}'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      if (parts.length < 3) {
        error = '${i + 1}행: 최소 3개 열(날짜, 출근, 퇴근)이 필요합니다 → "$line"';
        break;
      }

      try {
        final date = _parseDate(parts[0]);
        final clockIn = _parseTime(date, parts[1]);
        final clockOut = _parseTime(date, parts[2]);

        // 퇴근이 출근보다 이전이면 다음날로 간주
        final adjustedOut = clockOut.isBefore(clockIn) 
            ? clockOut.add(const Duration(days: 1)) 
            : clockOut;

        rows.add(_ParsedRow(
          date: date,
          clockIn: clockIn,
          clockOut: adjustedOut,
          raw: line,
        ));
      } catch (e) {
        error = '${i + 1}행 파싱 실패: "$line" → $e';
        break;
      }
    }

    setState(() {
      _parsedRows = rows;
      _parseError = error;
    });
  }

  DateTime _parseDate(String s) {
    // 2026-05-16, 2026/05/16, 20260516
    s = s.replaceAll('/', '-').replaceAll('.', '-');
    if (s.length == 8 && !s.contains('-')) {
      s = '${s.substring(0, 4)}-${s.substring(4, 6)}-${s.substring(6, 8)}';
    }
    return DateTime.parse(s);
  }

  DateTime _parseTime(DateTime date, String s) {
    // 09:00, 9:00, 0900
    s = s.trim();
    int hour, minute;
    if (s.contains(':')) {
      final p = s.split(':');
      hour = int.parse(p[0]);
      minute = int.parse(p[1]);
    } else if (s.length == 4) {
      hour = int.parse(s.substring(0, 2));
      minute = int.parse(s.substring(2, 4));
    } else {
      throw FormatException('시간 형식 오류: $s');
    }
    return DateTime(date.year, date.month, date.day, hour, minute);
  }

  void _loadSampleData() {
    _pasteCtrl.text = '''2026-05-16\t09:00\t18:00
2026-05-19\t09:00\t18:00
2026-05-20\t09:00\t18:00
2026-05-21\t09:00\t18:00
2026-05-22\t09:00\t18:00
2026-05-23\t09:00\t18:00
2026-05-26\t09:00\t18:00
2026-05-27\t09:00\t18:00
2026-05-28\t09:00\t18:00
2026-05-29\t09:00\t18:00
2026-05-30\t09:00\t18:00
2026-06-02\t09:00\t18:00
2026-06-03\t09:00\t18:00
2026-06-04\t09:00\t18:00
2026-06-05\t09:00\t18:00
2026-06-06\t09:00\t18:00
2026-06-09\t09:00\t18:00
2026-06-10\t09:00\t18:00
2026-06-11\t09:00\t18:00
2026-06-12\t09:00\t18:00
2026-06-13\t09:00\t18:00''';
    _parseInput();
  }

  void _loadOvertimeSample() {
    _pasteCtrl.text = '''2026-05-16\t09:00\t20:00
2026-05-19\t09:00\t18:00
2026-05-20\t09:00\t19:00
2026-05-21\t09:00\t18:00
2026-05-22\t09:00\t21:00
2026-05-23\t09:00\t18:00
2026-05-26\t09:00\t18:00
2026-05-27\t09:00\t20:00
2026-05-28\t09:00\t18:00
2026-05-29\t09:00\t18:00
2026-05-30\t09:00\t18:00
2026-06-02\t09:00\t18:00
2026-06-03\t14:00\t23:00
2026-06-04\t09:00\t18:00
2026-06-05\t09:00\t18:00
2026-06-06\t09:00\t18:00
2026-06-09\t09:00\t18:00
2026-06-10\t09:00\t18:00
2026-06-11\t09:00\t18:00
2026-06-12\t09:00\t18:00
2026-06-13\t09:00\t18:00''';
    _parseInput();
  }

  void _calculate() {
    try {
      final breakMin = int.tryParse(_breakMinCtrl.text) ?? 60;
      final weeklyHours = double.tryParse(_weeklyHoursCtrl.text) ?? 35;
      final hourlyRate = double.tryParse(_hourlyRateCtrl.text) ?? 10320;
      final joinDate = DateTime.parse(_joinDateCtrl.text);
      final periodStart = DateTime.parse(_periodStartCtrl.text);
      final periodEnd = DateTime.parse(_periodEndCtrl.text);

      // 스케줄 시간 파싱
      final schedStartParts = _scheduleStartCtrl.text.split(':');
      final schedEndParts = _scheduleEndCtrl.text.split(':');
      final schedStartHour = int.tryParse(schedStartParts[0]) ?? 9;
      final schedStartMin = schedStartParts.length > 1 ? (int.tryParse(schedStartParts[1]) ?? 0) : 0;
      final schedEndHour = int.tryParse(schedEndParts[0]) ?? 18;
      final schedEndMin = schedEndParts.length > 1 ? (int.tryParse(schedEndParts[1]) ?? 0) : 0;

      // 출퇴근 데이터가 있으면 파싱 시도
      if (_pasteCtrl.text.trim().isNotEmpty && _parsedRows.isEmpty) {
        _parseInput();
      }

      // 출퇴근 데이터가 없으면 스케줄 기반으로 자동 생성
      final useSchedule = _parsedRows.isEmpty;
      final List<_ParsedRow> rows;

      if (useSchedule) {
        rows = [];
        for (var d = periodStart; !d.isAfter(periodEnd); d = d.add(const Duration(days: 1))) {
          final weekday = d.weekday;
          if (!_scheduledDays.contains(weekday)) continue;

          final clockIn = DateTime(d.year, d.month, d.day, schedStartHour, schedStartMin);
          final clockOut = DateTime(d.year, d.month, d.day, schedEndHour, schedEndMin);
          rows.add(_ParsedRow(date: d, clockIn: clockIn, clockOut: clockOut, raw: '스케줄'));
        }

        // 결근 주수 → 해당 주에서 1일 제거 (만근 실패 → 주휴수당 차감)
        final absentWeeks = int.tryParse(_absentDaysCtrl.text) ?? 0;
        if (absentWeeks > 0 && rows.isNotEmpty) {
          // 주 단위로 그룹핑 (ISO week number 기준)
          final weekGroups = <int, List<int>>{}; // weekKey → row indices
          for (var i = 0; i < rows.length; i++) {
            final d = rows[i].date;
            final weekKey = d.year * 100 + _isoWeekNumber(d);
            weekGroups.putIfAbsent(weekKey, () => []).add(i);
          }
          // 마지막 주부터 1일씩 제거
          final sortedWeeks = weekGroups.keys.toList()..sort((a, b) => b.compareTo(a));
          final indicesToRemove = <int>[];
          for (var w = 0; w < absentWeeks && w < sortedWeeks.length; w++) {
            final indices = weekGroups[sortedWeeks[w]]!;
            indicesToRemove.add(indices.last); // 해당 주 마지막 근무일 제거
          }
          indicesToRemove.sort((a, b) => b.compareTo(a)); // 역순 제거
          for (final idx in indicesToRemove) {
            rows.removeAt(idx);
          }
        }

        // 연장근로 반영 (근무일에 균등 분배)
        final overtimeHours = double.tryParse(_overtimeHoursCtrl.text) ?? 0;
        if (overtimeHours > 0 && rows.isNotEmpty) {
          final extraMinPerDay = (overtimeHours * 60 / rows.length).round();
          for (var i = 0; i < rows.length; i++) {
            final r = rows[i];
            rows[i] = _ParsedRow(
              date: r.date,
              clockIn: r.clockIn,
              clockOut: r.clockOut.add(Duration(minutes: extraMinPerDay)),
              raw: '스케줄+연장',
            );
          }
        }

        // 야간근로 반영 (앞쪽 근무일부터 22:00 이후로 연장)
        final nightHours = double.tryParse(_nightHoursCtrl.text) ?? 0;
        if (nightHours > 0 && rows.isNotEmpty) {
          var remainingNightMin = (nightHours * 60).round();
          for (var i = 0; i < rows.length && remainingNightMin > 0; i++) {
            final r = rows[i];
            final night22 = DateTime(r.date.year, r.date.month, r.date.day, 22, 0);
            // 현재 퇴근이 22시 이전이면 22시까지 연장 + 야간시간 추가
            final nightToAdd = remainingNightMin.clamp(0, 120); // 하루 최대 2시간
            final newClockOut = night22.add(Duration(minutes: nightToAdd));
            // 퇴근을 22:00 + 야간시간으로 설정 (기존 퇴근보다 늦으면)
            if (newClockOut.isAfter(r.clockOut)) {
              rows[i] = _ParsedRow(
                date: r.date,
                clockIn: r.clockIn,
                clockOut: newClockOut,
                raw: '스케줄+야간',
              );
            }
            remainingNightMin -= nightToAdd;
          }
        }
      } else {
        rows = _parsedRows;
      }

      if (rows.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('정산기간 내 근무일이 없습니다'), backgroundColor: Colors.orange),
        );
        return;
      }

      // Attendance 객체 변환
      final attendances = <Attendance>[];
      for (int i = 0; i < rows.length; i++) {
        final r = rows[i];

        final scheduledStart = DateTime(
          r.date.year, r.date.month, r.date.day,
          schedStartHour, schedStartMin,
        );
        final scheduledEnd = DateTime(
          r.date.year, r.date.month, r.date.day,
          schedEndHour, schedEndMin,
        );

        attendances.add(Attendance(
          id: 'verify_${i}_${r.date.toIso8601String()}',
          staffId: 'verify_worker',
          storeId: 'verify_store',
          clockIn: r.clockIn,
          clockOut: r.clockOut,
          type: AttendanceType.web,
          scheduledShiftStartIso: scheduledStart.toIso8601String(),
          scheduledShiftEndIso: scheduledEnd.toIso8601String(),
          overtimeApproved: true,
        ));
      }

      final daysPerWeek = _scheduledDays.length > 0 ? _scheduledDays.length : 5;
      final dailyHours = weeklyHours / daysPerWeek;
      final weeklyTotalStay = (weeklyHours + (breakMin / 60.0 * daysPerWeek)).round();

      final workerData = PayrollWorkerData(
        weeklyHoursPure: weeklyHours,
        weeklyTotalStayMinutes: weeklyTotalStay * 60 ~/ daysPerWeek * daysPerWeek,
        breakMinutesPerShift: breakMin,
        isPaidBreak: _isPaidBreak,
        joinDate: joinDate,
        scheduledWorkDays: _scheduledDays,
        manualWeeklyHolidayApproval: false,
        graceMinutes: 0,
      );

      final result = PayrollCalculator.calculate(
        workerData: workerData,
        shifts: attendances,
        periodStart: periodStart,
        periodEnd: periodEnd,
        hourlyRate: hourlyRate,
        isFiveOrMore: _isFiveOrMore,
        allHistoricalAttendances: attendances,
      );

      setState(() => _result = result);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('계산 오류: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 900;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: isWide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 5, child: _buildInputPanel()),
                const SizedBox(width: 24),
                Expanded(flex: 5, child: _buildResultPanel()),
              ],
            )
          : Column(
              children: [
                _buildInputPanel(),
                const SizedBox(height: 24),
                _buildResultPanel(),
              ],
            ),
    );
  }

  Widget _buildInputPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 근로자 설정
        const Text('근로 계약 정보', style: TextStyle(
          fontSize: 14, fontWeight: FontWeight.bold,
          color: VerifyTheme.accentPrimary,
        )),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _inputField('시급 (원)', _hourlyRateCtrl, isNumber: true)),
          const SizedBox(width: 12),
          Expanded(child: _inputField('주 소정근로시간', _weeklyHoursCtrl, isNumber: true)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _inputField('휴게시간 (분/일)', _breakMinCtrl, isNumber: true)),
          const SizedBox(width: 12),
          Expanded(child: _inputField('입사일', _joinDateCtrl)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _inputField('정산기간 시작', _periodStartCtrl)),
          const SizedBox(width: 12),
          Expanded(child: _inputField('정산기간 종료', _periodEndCtrl)),
        ]),
        const SizedBox(height: 16),

        // 근무 스케줄
        const Text('근무 스케줄', style: TextStyle(
          fontSize: 14, fontWeight: FontWeight.bold,
          color: VerifyTheme.accentSecondary,
        )),
        const SizedBox(height: 4),
        Text('스케줄 초과 근무시간이 연장근무(가산수당)로 산정됩니다',
            style: TextStyle(fontSize: 11, color: VerifyTheme.textSecondary)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _inputField('출근 시간', _scheduleStartCtrl)),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text('→', style: TextStyle(color: VerifyTheme.textSecondary, fontSize: 16)),
          ),
          Expanded(child: _inputField('퇴근 시간', _scheduleEndCtrl)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _inputField('연장근로 (h)', _overtimeHoursCtrl, isNumber: true)),
          const SizedBox(width: 12),
          Expanded(child: _inputField('야간근로 (h)', _nightHoursCtrl, isNumber: true)),
          const SizedBox(width: 12),
          Expanded(child: _inputField('결근 주수', _absentDaysCtrl, isNumber: true)),
        ]),
        const SizedBox(height: 12),

        // 근무 요일 + 옵션
        const Text('근무 요일', style: TextStyle(fontSize: 12, color: VerifyTheme.textSecondary)),
        const SizedBox(height: 8),
        _buildDayChips(),
        const SizedBox(height: 8),
        Row(children: [
          _toggleChip('5인 이상', _isFiveOrMore, (v) => setState(() => _isFiveOrMore = v)),
          const SizedBox(width: 16),
          _toggleChip('유급휴게', _isPaidBreak, (v) => setState(() => _isPaidBreak = v)),
        ]),

        const Divider(height: 32, color: VerifyTheme.borderColor),

        // 출퇴근 데이터 입력
        Row(
          children: [
            const Icon(Icons.content_paste, size: 18, color: VerifyTheme.accentSecondary),
            const SizedBox(width: 8),
            const Text('출퇴근 데이터 입력', style: TextStyle(
              fontSize: 14, fontWeight: FontWeight.bold,
              color: VerifyTheme.accentSecondary,
            )),
            const Spacer(),
            TextButton.icon(
              onPressed: _loadSampleData,
              icon: const Icon(Icons.science, size: 14),
              label: const Text('만근 예제', style: TextStyle(fontSize: 11)),
              style: TextButton.styleFrom(foregroundColor: VerifyTheme.accentGreen),
            ),
            TextButton.icon(
              onPressed: _loadOvertimeSample,
              icon: const Icon(Icons.timer, size: 14),
              label: const Text('연장+야간 예제', style: TextStyle(fontSize: 11)),
              style: TextButton.styleFrom(foregroundColor: VerifyTheme.accentOrange),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: VerifyTheme.bgCardLight,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: VerifyTheme.borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Text(
                  '형식: 날짜 ↹ 출근 ↹ 퇴근  (탭/콤마/공백 구분)',
                  style: TextStyle(fontSize: 11, color: VerifyTheme.textSecondary),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 2, 12, 0),
                child: Text(
                  '예) 2026-05-16  09:00  18:00',
                  style: TextStyle(fontSize: 11, color: VerifyTheme.textSecondary.withValues(alpha: 0.6)),
                ),
              ),
              TextField(
                controller: _pasteCtrl,
                maxLines: 10,
                style: const TextStyle(fontSize: 12, color: Colors.white, fontFamily: 'monospace', height: 1.5),
                decoration: const InputDecoration(
                  hintText: '엑셀/구글시트에서 복사 후 여기에 붙여넣기 (Ctrl+V)',
                  hintStyle: TextStyle(color: VerifyTheme.textSecondary, fontSize: 12),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.all(12),
                ),
              ),
            ],
          ),
        ),

        if (_parseError != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
            ),
            child: Row(children: [
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text(_parseError!, style: const TextStyle(fontSize: 12, color: Colors.redAccent))),
            ]),
          ),
        ],

        const SizedBox(height: 12),

        // 파싱 결과 미리보기
        if (_parsedRows.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: VerifyTheme.bgCard,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: VerifyTheme.accentGreen.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.check_circle, size: 16, color: VerifyTheme.accentGreen),
                  const SizedBox(width: 6),
                  Text('${_parsedRows.length}건 인식됨', style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.bold, color: VerifyTheme.accentGreen,
                  )),
                ]),
                const SizedBox(height: 8),
                SizedBox(
                  height: 120,
                  child: SingleChildScrollView(
                    child: Column(
                      children: _parsedRows.take(25).map((r) {
                        final dateFmt = DateFormat('MM/dd (E)');
                        final timeFmt = DateFormat('HH:mm');
                        final duration = r.clockOut.difference(r.clockIn);
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 1),
                          child: Row(children: [
                            SizedBox(width: 90, child: Text(dateFmt.format(r.date),
                                style: const TextStyle(fontSize: 11, color: VerifyTheme.textSecondary))),
                            SizedBox(width: 50, child: Text(timeFmt.format(r.clockIn),
                                style: const TextStyle(fontSize: 11, color: Colors.white))),
                            const Text(' → ', style: TextStyle(fontSize: 11, color: VerifyTheme.textSecondary)),
                            SizedBox(width: 50, child: Text(timeFmt.format(r.clockOut),
                                style: const TextStyle(fontSize: 11, color: Colors.white))),
                            const SizedBox(width: 8),
                            Text('${(duration.inMinutes / 60).toStringAsFixed(1)}h',
                                style: TextStyle(fontSize: 11, color: VerifyTheme.accentSecondary)),
                          ]),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),

        const SizedBox(height: 20),

        // 버튼 행
        Row(children: [
          Expanded(
            child: SizedBox(
              height: 48,
              child: OutlinedButton.icon(
                onPressed: _parseInput,
                icon: const Icon(Icons.auto_fix_high, size: 18),
                label: const Text('데이터 파싱'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: VerifyTheme.accentSecondary,
                  side: const BorderSide(color: VerifyTheme.accentSecondary),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _calculate,
                icon: const Icon(Icons.calculate),
                label: const Text('급여 계산', style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: VerifyTheme.accentPrimary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ),
        ]),
      ],
    );
  }

  Widget _buildResultPanel() {
    if (_result == null) {
      return Container(
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: VerifyTheme.bgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: VerifyTheme.borderColor),
        ),
        child: Center(
          child: Column(children: [
            Icon(Icons.insert_chart_outlined, size: 48, color: VerifyTheme.textSecondary.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            const Text('출퇴근 데이터를 입력하고 급여를 계산하세요',
                style: TextStyle(color: VerifyTheme.textSecondary)),
            const SizedBox(height: 8),
            Text('엑셀에서 복사 → 붙여넣기 → 파싱 → 계산',
                style: TextStyle(fontSize: 12, color: VerifyTheme.textSecondary.withValues(alpha: 0.6))),
          ]),
        ),
      );
    }

    // ResultCard 재활용 + 저장 버튼
    return Column(
      children: [
        ResultCard(result: _result!, isHourly: true),
        const SizedBox(height: 16),
        SaveResultButton(
          verifyType: '상세검증',
          buildInputData: () => {
            'hourlyRate': _hourlyRateCtrl.text,
            'weeklyHours': _weeklyHoursCtrl.text,
            'breakMinutes': _breakMinCtrl.text,
            'joinDate': _joinDateCtrl.text,
            'periodStart': _periodStartCtrl.text,
            'periodEnd': _periodEndCtrl.text,
            'scheduledDays': _scheduledDays,
            'isFiveOrMore': _isFiveOrMore,
            'attendanceCount': _parsedRows.length,
            'attendanceData': _parsedRows.map((r) => {
              'date': DateFormat('yyyy-MM-dd').format(r.date),
              'clockIn': DateFormat('HH:mm').format(r.clockIn),
              'clockOut': DateFormat('HH:mm').format(r.clockOut),
            }).toList(),
          },
          buildResultData: () => {
            'basePay': _result!.basePay,
            'premiumPay': _result!.premiumPay,
            'weeklyHolidayPay': _result!.weeklyHolidayPay,
            'pureLaborHours': _result!.pureLaborHours,
            'premiumHours': _result!.premiumHours,
            'totalPay': _result!.totalPay,
            'insuranceDeduction': _result!.insuranceDeduction,
            'netPay': _result!.netPay,
          },
        ),
      ],
    );
  }

  // ─── 공통 위젯 ───

  Widget _buildDayChips() {
    const dayLabels = ['월', '화', '수', '목', '금', '토', '일'];
    return Wrap(
      spacing: 8,
      children: List.generate(7, (i) {
        final day = i + 1;
        final selected = _scheduledDays.contains(day);
        return FilterChip(
          label: Text(dayLabels[i]),
          selected: selected,
          selectedColor: VerifyTheme.accentPrimary,
          checkmarkColor: Colors.white,
          onSelected: (v) {
            setState(() {
              if (v) { _scheduledDays.add(day); } else { _scheduledDays.remove(day); }
              _scheduledDays.sort();
            });
          },
        );
      }),
    );
  }

  Widget _inputField(String label, TextEditingController ctrl, {bool isNumber = false}) {
    return TextField(
      controller: ctrl,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: VerifyTheme.textSecondary, fontSize: 13),
        filled: true,
        fillColor: VerifyTheme.bgCard,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: VerifyTheme.borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: VerifyTheme.borderColor),
        ),
      ),
    );
  }

  Widget _toggleChip(String label, bool value, ValueChanged<bool> onChanged) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text(label, style: const TextStyle(color: VerifyTheme.textSecondary, fontSize: 13)),
      const SizedBox(width: 8),
      Switch(value: value, onChanged: onChanged, activeColor: VerifyTheme.accentPrimary),
    ]);
  }
}

/// 파싱된 출퇴근 행
class _ParsedRow {
  final DateTime date;
  final DateTime clockIn;
  final DateTime clockOut;
  final String raw;

  const _ParsedRow({
    required this.date,
    required this.clockIn,
    required this.clockOut,
    required this.raw,
  });
}

/// ISO 8601 주차 번호 계산
int _isoWeekNumber(DateTime date) {
  final dayOfYear = date.difference(DateTime(date.year, 1, 1)).inDays;
  final wday = date.weekday; // 1=Mon ... 7=Sun
  return ((dayOfYear - wday + 10) / 7).floor();
}
