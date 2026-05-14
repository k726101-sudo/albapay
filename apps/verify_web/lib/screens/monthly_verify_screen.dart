import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_logic/shared_logic.dart';
import 'package:shared_logic/src/utils/payroll/payroll_models.dart';
import 'package:shared_logic/src/utils/payroll/annual_leave_calculator.dart';
import '../theme/verify_theme.dart';
import '../widgets/result_card.dart';
import '../widgets/comparison_table.dart';
import '../widgets/save_result_button.dart';
import '../data/preset_scenarios.dart';

/// 월급제 급여 검증 화면 — 요약 입력 모드
class MonthlyVerifyScreen extends StatefulWidget {
  const MonthlyVerifyScreen({super.key});

  @override
  State<MonthlyVerifyScreen> createState() => _MonthlyVerifyScreenState();
}

class _MonthlyVerifyScreenState extends State<MonthlyVerifyScreen> {
  // ─── 월급 구성 ───
  final _baseSalaryCtrl = TextEditingController();
  final _mealPayCtrl = TextEditingController();
  final _fixedOtPayCtrl = TextEditingController();
  final _fixedOtHoursCtrl = TextEditingController();
  final _weeklyHoursCtrl = TextEditingController(text: '40');

  DateTime _periodStart = DateTime(2026, 6, 1);
  DateTime _periodEnd = DateTime(2026, 6, 30);
  DateTime _joinDate = DateTime(2025, 1, 1);
  DateTime? _exitDate;

  List<int> _scheduledDays = [1, 2, 3, 4, 5];
  bool _isFiveOrMore = true;

  // ─── 월급 구성 스위치 ───
  bool _includeMeal = true;
  bool _includeFixedOt = true;
  bool _includeExtraWork = false;

  // ─── 기타 수당 ───
  final _etcPayCtrl = TextEditingController(text: '0');
  final _etcPayLabelCtrl = TextEditingController(text: '기타수당');

  // ─── 공제 ───
  bool _apply33 = false;
  bool _deductNP = true;
  bool _deductHI = true;
  bool _deductEI = true;
  bool _mealTaxExempt = true;

  PayrollCalculationResult? _result;
  String? _selectedPreset;

  final _dateFormat = DateFormat('yyyy-MM-dd');

  @override
  void dispose() {
    _baseSalaryCtrl.dispose();
    _mealPayCtrl.dispose();
    _fixedOtPayCtrl.dispose();
    _fixedOtHoursCtrl.dispose();
    _weeklyHoursCtrl.dispose();
    _etcPayCtrl.dispose();
    _etcPayLabelCtrl.dispose();
    super.dispose();
  }

  void _loadPreset(String key) {
    final preset = PresetScenarios.monthlyPresets[key];
    if (preset == null) return;

    setState(() {
      _selectedPreset = key;
      _baseSalaryCtrl.text = preset['baseSalary'].toString();
      _mealPayCtrl.text = preset['mealPay'].toString();
      _fixedOtPayCtrl.text = preset['fixedOtPay'].toString();
      _weeklyHoursCtrl.text = preset['weeklyHours'].toString();
      _isFiveOrMore = preset['isFiveOrMore'] as bool;
      if (preset['joinDate'] != null) {
        _joinDate = DateTime.parse(preset['joinDate'] as String);
      }
      if (preset['exitDate'] != null) {
        _exitDate = DateTime.parse(preset['exitDate'] as String);
      } else {
        _exitDate = null;
      }
      _result = null;
    });
  }

  void _calculate() {
    final baseSalary = double.tryParse(_baseSalaryCtrl.text) ?? 0;
    final mealPay = double.tryParse(_mealPayCtrl.text) ?? 0;
    final fixedOtPay = double.tryParse(_fixedOtPayCtrl.text) ?? 0;
    final fixedOtHours = double.tryParse(_fixedOtHoursCtrl.text) ?? 0;
    final weeklyHours = double.tryParse(_weeklyHoursCtrl.text) ?? 0;

    // S_Ref = 4.345 × (주 소정근로 + 주휴시간)
    final weeklyHolidayHours = (weeklyHours / 40) * 8;
    final sRef = 4.345 * (weeklyHours + weeklyHolidayHours);

    // S_Legal: 해당 월 기준 (실제 주수 계산)
    final daysInMonth = DateTime(_periodEnd.year, _periodEnd.month + 1, 0).day;
    final weeksInMonth = daysInMonth / 7;
    final sLegal = weeksInMonth * (weeklyHours + weeklyHolidayHours);

    // 통상시급 (보수적: 기본급만)
    final conservativeHourly = sLegal > 0 ? baseSalary / sLegal : 0.0;

    // 참고시급 (기본급+식대)
    final referenceHourly = sRef > 0 ? (baseSalary + mealPay) / sRef : 0.0;

    // 최저임금 판정
    final minWageRef = sRef > 0 ? baseSalary / sRef : 0.0;
    final minimumWageHardBlock = minWageRef < PayrollConstants.legalMinimumWage;
    final minimumWageWarning = sRef > 0 && (baseSalary + mealPay) / sRef < PayrollConstants.legalMinimumWage;

    // 일할 계산
    double proRataRatio = 1.0;
    if (_exitDate != null || _joinDate.isAfter(_periodStart)) {
      final effectiveStart = _joinDate.isAfter(_periodStart) ? _joinDate : _periodStart;
      final effectiveEnd = _exitDate != null && _exitDate!.isBefore(_periodEnd) ? _exitDate! : _periodEnd;
      final workDays = effectiveEnd.difference(effectiveStart).inDays + 1;
      proRataRatio = workDays / daysInMonth;
    }

    final actualBase = baseSalary * proRataRatio;
    final actualMeal = _includeMeal ? mealPay * proRataRatio : 0.0;
    final actualFixedOt = _includeFixedOt ? fixedOtPay * proRataRatio : 0.0;
    final totalMonthly = actualBase + actualMeal + actualFixedOt;

    // 기타 수당
    final etcPay = _includeExtraWork ? (double.tryParse(_etcPayCtrl.text) ?? 0) : 0.0;

    final totalPay = totalMonthly + etcPay;

    // 공제
    final taxFreeMeal = _mealTaxExempt ? (actualMeal > 200000 ? 200000.0 : actualMeal) : 0.0;
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
        basePay: actualBase,
        breakPay: 0,
        premiumPay: etcPay,
        weeklyHolidayPay: 0,
        otherAllowancePay: 0,
        totalPay: totalPay,
        pureLaborHours: 0,
        paidBreakHours: 0,
        stayHours: 0,
        premiumHours: 0,
        needsBreakSeparationGuide: false,
        isWeeklyHolidayEligible: true,
        hasSubstitutionRisk: false,
        newlyGrantedAnnualLeave: 0,
        isPerfectAttendance: true,
        weeklyHolidayBlockedByAbsence: false,
        annualLeaveSummary: const AnnualLeaveSummary(totalGenerated: 0, used: 0, remaining: 0),
        isMonthlyWage: true,
        monthlyBasePay: baseSalary,
        proRataRatio: proRataRatio,
        mealAllowancePay: actualMeal,
        fixedOvertimeBasePay: actualFixedOt,
        fixedOvertimeAgreedHours: fixedOtHours,
        conservativeHourlyWage: conservativeHourly,
        referenceHourlyWage: referenceHourly,
        scheduledMonthlyHours: sLegal,
        scheduledMonthlyHoursLegal: sLegal,
        scheduledMonthlyHoursRef: sRef,
        minimumWageHardBlock: minimumWageHardBlock,
        minimumWageWarning: minimumWageWarning,
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
    final isWide = MediaQuery.of(context).size.width > 1100;

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
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: PresetScenarios.monthlyPresets.entries.map((entry) {
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
                  side: BorderSide(color: isSelected ? VerifyTheme.accentPrimary : VerifyTheme.borderColor),
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
            const Text('📋 월급제 입력 정보', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Divider(color: VerifyTheme.borderColor, height: 32),

            const Text('월급 구성', style: TextStyle(fontWeight: FontWeight.w600, color: VerifyTheme.accentSecondary)),
            const SizedBox(height: 12),
            _buildField('통상임금 / 기본급 (원)', _baseSalaryCtrl, hint: '예) 2,156,880'),
            const SizedBox(height: 12),
            _buildRow([
              _buildField('식대 (원)', _mealPayCtrl, enabled: _includeMeal, hint: '예) 200,000'),
              _buildSwitchCompact('식대 포함', _includeMeal, (v) => setState(() => _includeMeal = v)),
            ]),
            const SizedBox(height: 12),
            _buildRow([
              _buildField('고정연장수당 (원)', _fixedOtPayCtrl, enabled: _includeFixedOt, hint: '예) 140,000'),
              _buildSwitchCompact('고정OT 포함', _includeFixedOt, (v) => setState(() => _includeFixedOt = v)),
            ]),
            const SizedBox(height: 12),
            _buildRow([
              _buildField('고정연장시간 (h)', _fixedOtHoursCtrl, enabled: _includeFixedOt, hint: '예) 0'),
              _buildField('주 소정근로시간', _weeklyHoursCtrl, hint: '예) 40'),
            ]),
            const SizedBox(height: 12),
            _buildDateRow(),
            const SizedBox(height: 12),
            _buildExitDateRow(),
            const SizedBox(height: 12),
            _buildSwitch('5인 이상', _isFiveOrMore, (v) => setState(() => _isFiveOrMore = v)),

            const Divider(color: VerifyTheme.borderColor, height: 32),

            Row(
              children: [
                const Expanded(
                  child: Text('기타(이외) 수당', style: TextStyle(fontWeight: FontWeight.w600, color: VerifyTheme.accentSecondary)),
                ),
                _buildSwitchCompact('포함', _includeExtraWork, (v) => setState(() => _includeExtraWork = v)),
              ],
            ),
            if (_includeExtraWork) ...[
              const SizedBox(height: 12),
              _buildRow([
                _buildField('수당명', _etcPayLabelCtrl, isText: true),
                _buildField('금액 (원)', _etcPayCtrl),
              ]),
            ],

            const Divider(color: VerifyTheme.borderColor, height: 32),

            const Text('공제 항목', style: TextStyle(fontWeight: FontWeight.w600, color: VerifyTheme.accentSecondary)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _buildSwitch('국민연금', _deductNP, (v) => setState(() => _deductNP = v)),
                _buildSwitch('건강보험', _deductHI, (v) => setState(() => _deductHI = v)),
                _buildSwitch('고용보험', _deductEI, (v) => setState(() => _deductEI = v)),
                _buildSwitch('3.3%', _apply33, (v) => setState(() => _apply33 = v)),
                _buildSwitch('식대 비과세', _mealTaxExempt, (v) => setState(() => _mealTaxExempt = v)),
              ],
            ),

            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _calculate,
                icon: const Icon(Icons.calculate),
                label: const Text('계산 실행', style: TextStyle(fontSize: 16)),
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
        ResultCard(result: _result!, isHourly: false),
        const SizedBox(height: 16),
        SaveResultButton(
          verifyType: '월급제',
          buildInputData: () => {
            'baseSalary': _baseSalaryCtrl.text,
            'mealPay': _mealPayCtrl.text,
            'fixedOtPay': _fixedOtPayCtrl.text,
            'fixedOtHours': _fixedOtHoursCtrl.text,
            'weeklyHours': _weeklyHoursCtrl.text,
            'periodStart': _dateFormat.format(_periodStart),
            'periodEnd': _dateFormat.format(_periodEnd),
            'joinDate': _dateFormat.format(_joinDate),
            'exitDate': _exitDate != null ? _dateFormat.format(_exitDate!) : null,
            'isFiveOrMore': _isFiveOrMore,
          },
          buildResultData: () => {
            'basePay': _result!.basePay,
            'mealAllowancePay': _result!.mealAllowancePay,
            'fixedOvertimeBasePay': _result!.fixedOvertimeBasePay,
            'premiumPay': _result!.premiumPay,
            'totalPay': _result!.totalPay,
            'proRataRatio': _result!.proRataRatio,
            'conservativeHourlyWage': _result!.conservativeHourlyWage,
            'insuranceDeduction': _result!.insuranceDeduction,
            'netPay': _result!.netPay,
          },
        ),
        const SizedBox(height: 20),
        ComparisonTable(result: _result!, isHourly: false),
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

  Widget _buildRow(List<Widget> children) {
    return Row(
      children: children.expand((w) sync* {
        yield Expanded(child: w);
        if (w != children.last) yield const SizedBox(width: 12);
      }).toList(),
    );
  }

  Widget _buildField(String label, TextEditingController ctrl, {bool enabled = true, bool isText = false, String? hint}) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.4,
      child: TextField(
        controller: ctrl,
        enabled: enabled,
        keyboardType: isText ? TextInputType.text : const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: isText ? null : [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          hintStyle: TextStyle(color: VerifyTheme.textSecondary.withValues(alpha: 0.4)),
          isDense: true,
        ),
        style: const TextStyle(color: VerifyTheme.textPrimary),
      ),
    );
  }

  Widget _buildDateRow() {
    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: () async {
              final picked = await showDatePicker(context: context, initialDate: _periodStart, firstDate: DateTime(2020), lastDate: DateTime(2030));
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
              final picked = await showDatePicker(context: context, initialDate: _periodEnd, firstDate: DateTime(2020), lastDate: DateTime(2030));
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

  Widget _buildExitDateRow() {
    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: () async {
              final picked = await showDatePicker(context: context, initialDate: _joinDate, firstDate: DateTime(2020), lastDate: DateTime(2030));
              if (picked != null) setState(() => _joinDate = picked);
            },
            child: InputDecorator(
              decoration: const InputDecoration(labelText: '입사일', isDense: true),
              child: Text(_dateFormat.format(_joinDate), style: const TextStyle(color: VerifyTheme.textPrimary)),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: InkWell(
            onTap: () async {
              final picked = await showDatePicker(context: context, initialDate: _exitDate ?? _periodEnd, firstDate: DateTime(2020), lastDate: DateTime(2030));
              if (picked != null) setState(() => _exitDate = picked);
            },
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: '퇴사일 (중도퇴사 시)',
                isDense: true,
                suffixIcon: _exitDate != null
                    ? IconButton(icon: const Icon(Icons.clear, size: 16), onPressed: () => setState(() => _exitDate = null))
                    : null,
              ),
              child: Text(
                _exitDate != null ? _dateFormat.format(_exitDate!) : '해당 없음',
                style: TextStyle(color: _exitDate != null ? VerifyTheme.textPrimary : VerifyTheme.textSecondary),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSwitch(String label, bool value, ValueChanged<bool> onChanged) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(color: VerifyTheme.textSecondary, fontSize: 13)),
        const SizedBox(width: 4),
        Switch(value: value, onChanged: onChanged, activeColor: VerifyTheme.accentPrimary),
      ],
    );
  }
  Widget _buildSwitchCompact(String label, bool value, ValueChanged<bool> onChanged) {
    return SizedBox(
      width: 120,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(
            color: value ? VerifyTheme.accentPrimary : VerifyTheme.textSecondary,
            fontSize: 11,
            fontWeight: value ? FontWeight.w600 : FontWeight.normal,
          )),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: VerifyTheme.accentPrimary,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }
}
