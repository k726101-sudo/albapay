import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_logic/shared_logic.dart';
import 'package:shared_logic/src/utils/payroll/payroll_models.dart';
import 'package:shared_logic/src/utils/payroll/annual_leave_calculator.dart';
import 'package:shared_logic/src/models/attendance_model.dart';
import '../theme/verify_theme.dart';
import '../widgets/result_card.dart';
import '../widgets/comparison_table.dart';
import '../widgets/save_result_button.dart';
import '../data/preset_scenarios.dart';

/// 시급제 급여 검증 화면 — 요약 입력 모드
class HourlyVerifyScreen extends StatefulWidget {
  const HourlyVerifyScreen({super.key});

  @override
  State<HourlyVerifyScreen> createState() => _HourlyVerifyScreenState();
}

class _HourlyVerifyScreenState extends State<HourlyVerifyScreen> {
  // ─── 기본 정보 ───
  final _hourlyWageCtrl = TextEditingController(text: '10320');
  final _weeklyHoursCtrl = TextEditingController(text: '35');
  final _breakMinutesCtrl = TextEditingController(text: '60');
  final _graceMinutesCtrl = TextEditingController(text: '5');

  DateTime _periodStart = DateTime(2026, 5, 16);
  DateTime _periodEnd = DateTime(2026, 6, 15);
  DateTime _joinDate = DateTime(2025, 3, 1);

  List<int> _scheduledDays = [1, 2, 3, 4, 5]; // 월~금
  bool _isFiveOrMore = true;
  bool _isPaidBreak = false;
  bool _isProbation = false;
  int _probationMonths = 3;
  int _weeklyHolidayDay = 0; // 일요일

  // ─── 근로시간 요약 ───
  final _totalPureHoursCtrl = TextEditingController(text: '150.5');
  final _overtimeHoursCtrl = TextEditingController(text: '0');
  final _nightHoursCtrl = TextEditingController(text: '0');
  final _holidayHoursCtrl = TextEditingController(text: '0');
  final _fullWeeksCtrl = TextEditingController(text: '4');
  final _absentWeeksCtrl = TextEditingController(text: '0');
  bool _laborDayWorked = false;

  // ─── 공제 ───
  bool _apply33 = false;
  bool _deductNP = false;
  bool _deductHI = false;
  bool _deductEI = false;
  final _mealAllowanceCtrl = TextEditingController(text: '0');

  // ─── 결과 ───
  PayrollCalculationResult? _result;
  String? _selectedPreset;

  final _numberFormat = NumberFormat('#,###');
  final _dateFormat = DateFormat('yyyy-MM-dd');

  @override
  void dispose() {
    _hourlyWageCtrl.dispose();
    _weeklyHoursCtrl.dispose();
    _breakMinutesCtrl.dispose();
    _graceMinutesCtrl.dispose();
    _totalPureHoursCtrl.dispose();
    _overtimeHoursCtrl.dispose();
    _nightHoursCtrl.dispose();
    _holidayHoursCtrl.dispose();
    _fullWeeksCtrl.dispose();
    _absentWeeksCtrl.dispose();
    _mealAllowanceCtrl.dispose();
    super.dispose();
  }

  void _loadPreset(String presetKey) {
    final preset = PresetScenarios.hourlyPresets[presetKey];
    if (preset == null) return;

    setState(() {
      _selectedPreset = presetKey;
      _hourlyWageCtrl.text = preset['hourlyWage'].toString();
      _weeklyHoursCtrl.text = preset['weeklyHours'].toString();
      _breakMinutesCtrl.text = preset['breakMinutes'].toString();
      _scheduledDays = List<int>.from(preset['scheduledDays']);
      _isFiveOrMore = preset['isFiveOrMore'] as bool;
      _totalPureHoursCtrl.text = preset['totalPureHours'].toString();
      _overtimeHoursCtrl.text = preset['overtimeHours'].toString();
      _nightHoursCtrl.text = preset['nightHours'].toString();
      _holidayHoursCtrl.text = preset['holidayHours'].toString();
      _fullWeeksCtrl.text = preset['fullWeeks'].toString();
      _absentWeeksCtrl.text = preset['absentWeeks'].toString();
      _result = null;
    });
  }

  void _calculate() {
    final hourlyWage = double.tryParse(_hourlyWageCtrl.text) ?? 0;
    final totalPureHours = double.tryParse(_totalPureHoursCtrl.text) ?? 0;
    final overtimeHours = double.tryParse(_overtimeHoursCtrl.text) ?? 0;
    final nightHours = double.tryParse(_nightHoursCtrl.text) ?? 0;
    final holidayHours = double.tryParse(_holidayHoursCtrl.text) ?? 0;
    final fullWeeks = int.tryParse(_fullWeeksCtrl.text) ?? 0;
    final weeklyHours = double.tryParse(_weeklyHoursCtrl.text) ?? 0;
    final mealAllowance = double.tryParse(_mealAllowanceCtrl.text) ?? 0;

    // ─── 요약 입력 기반 직접 계산 ───
    // (shared_logic 엔진과 동일한 공식을 사용하되, 출퇴근 기록 대신 요약값 사용)

    // 1. 기본급
    final basePay = totalPureHours * hourlyWage;

    // 2. 가산수당 (5인 이상만)
    double premiumPay = 0;
    if (_isFiveOrMore) {
      premiumPay = (overtimeHours * hourlyWage * 0.5) +
          (nightHours * hourlyWage * 0.5) +
          (holidayHours * hourlyWage * 0.5);
    }

    // 3. 주휴수당
    double weeklyHolidayPay = 0;
    if (weeklyHours >= 15) {
      final weeklyHolidayHours = (weeklyHours / 40) * 8;
      final cappedHours = weeklyHolidayHours > 8 ? 8.0 : weeklyHolidayHours;
      weeklyHolidayPay = cappedHours * hourlyWage * fullWeeks;
    }

    // 4. 근로자의 날 수당
    double laborDayPay = 0;
    double laborDayWorkPay = 0;
    // 정산기간에 5/1 포함 확인
    final laborDay = DateTime(_periodStart.year, 5, 1);
    final laborDayInRange = !laborDay.isBefore(_periodStart) && !laborDay.isAfter(_periodEnd);
    if (laborDayInRange) {
      final dailyHours = weeklyHours / _scheduledDays.length;
      laborDayPay = dailyHours * hourlyWage; // 유급 보장분
      if (_laborDayWorked) {
        laborDayWorkPay = _isFiveOrMore
            ? dailyHours * hourlyWage * 1.5
            : dailyHours * hourlyWage;
      }
    }

    // 5. 총 급여
    final totalPay = basePay + premiumPay + weeklyHolidayPay + laborDayPay + laborDayWorkPay;

    // 6. 공제
    final taxFreeMeal = mealAllowance > 200000 ? 200000.0 : mealAllowance;
    final taxableWage = totalPay - taxFreeMeal;

    double nationalPension = 0, healthInsurance = 0, longTermCare = 0, employmentInsurance = 0;
    double businessIncomeTax = 0, localIncomeTax = 0;

    if (_deductNP) nationalPension = taxableWage * 0.045;
    if (_deductHI) {
      healthInsurance = taxableWage * 0.03545;
      longTermCare = healthInsurance * 0.1295;
    }
    if (_deductEI) employmentInsurance = taxableWage * 0.009;
    if (_apply33) {
      businessIncomeTax = taxableWage * 0.03;
      localIncomeTax = businessIncomeTax * 0.1;
    }

    final totalDeduction = nationalPension + healthInsurance + longTermCare +
        employmentInsurance + businessIncomeTax + localIncomeTax;

    final netPay = totalPay + taxFreeMeal - totalDeduction;

    setState(() {
      _result = PayrollCalculationResult(
        basePay: basePay,
        breakPay: 0,
        premiumPay: premiumPay,
        weeklyHolidayPay: weeklyHolidayPay,
        otherAllowancePay: 0,
        totalPay: totalPay,
        pureLaborHours: totalPureHours,
        paidBreakHours: 0,
        stayHours: totalPureHours + (int.tryParse(_breakMinutesCtrl.text) ?? 0) / 60,
        premiumHours: overtimeHours + nightHours + holidayHours,
        laborDayAllowancePay: laborDayPay,
        holidayPremiumPay: _laborDayWorked ? laborDayWorkPay : 0,
        needsBreakSeparationGuide: false,
        isWeeklyHolidayEligible: weeklyHours >= 15,
        hasSubstitutionRisk: false,
        newlyGrantedAnnualLeave: 0,
        isPerfectAttendance: int.tryParse(_absentWeeksCtrl.text) == 0,
        weeklyHolidayBlockedByAbsence: (int.tryParse(_absentWeeksCtrl.text) ?? 0) > 0,
        annualLeaveSummary: const AnnualLeaveSummary(totalGenerated: 0, used: 0, remaining: 0),
        taxableWage: taxableWage,
        insuranceDeduction: totalDeduction,
        nationalPension: nationalPension,
        healthInsurance: healthInsurance,
        longTermCareInsurance: longTermCare,
        employmentInsurance: employmentInsurance,
        businessIncomeTax: businessIncomeTax,
        localIncomeTax: localIncomeTax,
        mealNonTaxable: taxFreeMeal,
        netPay: netPay,
        isFiveOrMore: _isFiveOrMore,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth > 1100;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildPresetSelector(),
              const SizedBox(height: 20),
              if (isWide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _buildInputPanel()),
                    const SizedBox(width: 20),
                    Expanded(child: _result != null ? _buildResultPanel() : _buildPlaceholder()),
                  ],
                )
              else ...[
                _buildInputPanel(),
                const SizedBox(height: 20),
                if (_result != null) _buildResultPanel(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPresetSelector() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.bookmark_outline, size: 18, color: VerifyTheme.accentSecondary),
                SizedBox(width: 8),
                Text('예제 시나리오', style: TextStyle(fontWeight: FontWeight.w600)),
                SizedBox(width: 8),
                Text('— 클릭하면 자동으로 입력됩니다', style: TextStyle(color: VerifyTheme.textSecondary, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: PresetScenarios.hourlyPresets.entries.map((entry) {
                final isSelected = _selectedPreset == entry.key;
                return ChoiceChip(
                  label: Text(entry.value['label'] as String),
                  selected: isSelected,
                  onSelected: (_) => _loadPreset(entry.key),
                  selectedColor: VerifyTheme.accentPrimary.withValues(alpha: 0.3),
                  backgroundColor: VerifyTheme.bgCardLight,
                  labelStyle: TextStyle(
                    color: isSelected ? VerifyTheme.accentPrimary : VerifyTheme.textSecondary,
                    fontSize: 13,
                  ),
                  side: BorderSide(
                    color: isSelected ? VerifyTheme.accentPrimary : VerifyTheme.borderColor,
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputPanel() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('📋 입력 정보', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Divider(color: VerifyTheme.borderColor, height: 32),

            // ─── 기본 정보 ───
            const Text('기본 정보', style: TextStyle(fontWeight: FontWeight.w600, color: VerifyTheme.accentSecondary)),
            const SizedBox(height: 12),
            _buildRow([
              _buildField('시급 (원)', _hourlyWageCtrl),
              _buildField('주 소정근로시간', _weeklyHoursCtrl),
            ]),
            const SizedBox(height: 12),
            _buildRow([
              _buildField('휴게시간 (분/교대)', _breakMinutesCtrl),
              _buildField('지각허용 (분)', _graceMinutesCtrl),
            ]),
            const SizedBox(height: 12),
            _buildDateRow(),
            const SizedBox(height: 12),
            _buildWorkDaySelector(),
            const SizedBox(height: 12),
            _buildSwitchRow(),

            const Divider(color: VerifyTheme.borderColor, height: 32),

            // ─── 근로시간 요약 ───
            const Text('이번 정산기간 근로시간 요약', style: TextStyle(fontWeight: FontWeight.w600, color: VerifyTheme.accentSecondary)),
            const SizedBox(height: 12),
            _buildRow([
              _buildField('총 순수근로시간 (h)', _totalPureHoursCtrl),
              _buildField('만근 주 수', _fullWeeksCtrl),
            ]),
            const SizedBox(height: 12),
            _buildRow([
              _buildField('연장근로 (h, 8h초과)', _overtimeHoursCtrl),
              _buildField('결근 주 수', _absentWeeksCtrl),
            ]),
            const SizedBox(height: 12),
            _buildRow([
              _buildField('야간근로 (h, 22~06)', _nightHoursCtrl),
              _buildField('휴일근로 (h)', _holidayHoursCtrl),
            ]),
            const SizedBox(height: 12),
            _buildLaborDaySwitch(),

            const Divider(color: VerifyTheme.borderColor, height: 32),

            // ─── 공제 ───
            const Text('공제 항목', style: TextStyle(fontWeight: FontWeight.w600, color: VerifyTheme.accentSecondary)),
            const SizedBox(height: 12),
            _buildDeductionSwitches(),
            const SizedBox(height: 12),
            _buildField('식대 비과세 (원)', _mealAllowanceCtrl),

            const SizedBox(height: 24),

            // ─── 계산 버튼 ───
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _calculate,
                icon: const Icon(Icons.calculate),
                label: const Text('계산 실행', style: TextStyle(fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: VerifyTheme.accentPrimary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultPanel() {
    return Column(
      children: [
        ResultCard(result: _result!, isHourly: true),
        const SizedBox(height: 16),
        SaveResultButton(
          verifyType: '시급제',
          buildInputData: () => {
            'hourlyWage': _hourlyWageCtrl.text,
            'weeklyHours': _weeklyHoursCtrl.text,
            'breakMinutes': _breakMinutesCtrl.text,
            'periodStart': _dateFormat.format(_periodStart),
            'periodEnd': _dateFormat.format(_periodEnd),
            'scheduledDays': _scheduledDays,
            'isFiveOrMore': _isFiveOrMore,
            'totalPureHours': _totalPureHoursCtrl.text,
            'overtimeHours': _overtimeHoursCtrl.text,
            'nightHours': _nightHoursCtrl.text,
            'holidayHours': _holidayHoursCtrl.text,
            'fullWeeks': _fullWeeksCtrl.text,
            'absentWeeks': _absentWeeksCtrl.text,
          },
          buildResultData: () => {
            'basePay': _result!.basePay,
            'premiumPay': _result!.premiumPay,
            'weeklyHolidayPay': _result!.weeklyHolidayPay,
            'laborDayAllowancePay': _result!.laborDayAllowancePay,
            'holidayPremiumPay': _result!.holidayPremiumPay,
            'totalPay': _result!.totalPay,
            'insuranceDeduction': _result!.insuranceDeduction,
            'netPay': _result!.netPay,
          },
        ),
        const SizedBox(height: 20),
        ComparisonTable(result: _result!, isHourly: true),
      ],
    );
  }

  Widget _buildPlaceholder() {
    return Card(
      child: Container(
        height: 400,
        alignment: Alignment.center,
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.analytics_outlined, size: 48, color: VerifyTheme.textSecondary),
            SizedBox(height: 16),
            Text('입력 후 [계산 실행]을 누르면\n결과가 여기에 표시됩니다.',
              textAlign: TextAlign.center,
              style: TextStyle(color: VerifyTheme.textSecondary, height: 1.6),
            ),
          ],
        ),
      ),
    );
  }

  // ─── 빌더 헬퍼 ───

  Widget _buildRow(List<Widget> children) {
    return Row(
      children: children.expand((w) sync* {
        yield Expanded(child: w);
        if (w != children.last) yield const SizedBox(width: 12);
      }).toList(),
    );
  }

  Widget _buildField(String label, TextEditingController ctrl) {
    return TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
      decoration: InputDecoration(labelText: label, isDense: true),
      style: const TextStyle(color: VerifyTheme.textPrimary),
    );
  }

  Widget _buildDateRow() {
    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _periodStart,
                firstDate: DateTime(2020),
                lastDate: DateTime(2030),
              );
              if (picked != null) setState(() => _periodStart = picked);
            },
            child: InputDecorator(
              decoration: const InputDecoration(labelText: '정산 시작', isDense: true),
              child: Text(_dateFormat.format(_periodStart), style: const TextStyle(color: VerifyTheme.textPrimary)),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _periodEnd,
                firstDate: DateTime(2020),
                lastDate: DateTime(2030),
              );
              if (picked != null) setState(() => _periodEnd = picked);
            },
            child: InputDecorator(
              decoration: const InputDecoration(labelText: '정산 종료', isDense: true),
              child: Text(_dateFormat.format(_periodEnd), style: const TextStyle(color: VerifyTheme.textPrimary)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWorkDaySelector() {
    const dayLabels = ['월', '화', '수', '목', '금', '토', '일'];
    const dayValues = [1, 2, 3, 4, 5, 6, 7];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('근무 요일', style: TextStyle(color: VerifyTheme.textSecondary, fontSize: 12)),
        const SizedBox(height: 8),
        Row(
          children: List.generate(7, (i) {
            final isSelected = _scheduledDays.contains(dayValues[i]);
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FilterChip(
                label: Text(dayLabels[i], style: TextStyle(
                  color: isSelected ? Colors.white : VerifyTheme.textSecondary,
                  fontSize: 13,
                )),
                selected: isSelected,
                onSelected: (v) {
                  setState(() {
                    if (v) {
                      _scheduledDays.add(dayValues[i]);
                    } else {
                      _scheduledDays.remove(dayValues[i]);
                    }
                  });
                },
                selectedColor: VerifyTheme.accentPrimary,
                backgroundColor: VerifyTheme.bgCardLight,
                checkmarkColor: Colors.white,
                side: BorderSide(color: isSelected ? VerifyTheme.accentPrimary : VerifyTheme.borderColor),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildSwitchRow() {
    return Wrap(
      spacing: 24,
      runSpacing: 8,
      children: [
        _buildSwitch('5인 이상', _isFiveOrMore, (v) => setState(() => _isFiveOrMore = v)),
        _buildSwitch('유급 휴게', _isPaidBreak, (v) => setState(() => _isPaidBreak = v)),
        _buildSwitch('수습기간', _isProbation, (v) => setState(() => _isProbation = v)),
      ],
    );
  }

  Widget _buildSwitch(String label, bool value, ValueChanged<bool> onChanged) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(color: VerifyTheme.textSecondary, fontSize: 13)),
        const SizedBox(width: 4),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: VerifyTheme.accentPrimary,
        ),
      ],
    );
  }

  Widget _buildLaborDaySwitch() {
    final laborDay = DateTime(_periodStart.year, 5, 1);
    final inRange = !laborDay.isBefore(_periodStart) && !laborDay.isAfter(_periodEnd);

    if (!inRange) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: VerifyTheme.accentOrange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: VerifyTheme.accentOrange.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.celebration, color: VerifyTheme.accentOrange, size: 18),
          const SizedBox(width: 8),
          const Text('근로자의 날(5/1) 출근:', style: TextStyle(fontSize: 13)),
          const SizedBox(width: 8),
          Switch(
            value: _laborDayWorked,
            onChanged: (v) => setState(() => _laborDayWorked = v),
            activeColor: VerifyTheme.accentOrange,
          ),
          Text(_laborDayWorked ? '출근함' : '쉼', style: const TextStyle(fontSize: 13, color: VerifyTheme.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildDeductionSwitches() {
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        _buildSwitch('3.3% 원천징수', _apply33, (v) => setState(() => _apply33 = v)),
        _buildSwitch('국민연금', _deductNP, (v) => setState(() => _deductNP = v)),
        _buildSwitch('건강보험', _deductHI, (v) => setState(() => _deductHI = v)),
        _buildSwitch('고용보험', _deductEI, (v) => setState(() => _deductEI = v)),
      ],
    );
  }
}
