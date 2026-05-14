import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_logic/shared_logic.dart';
import '../theme/verify_theme.dart';
import '../data/preset_scenarios.dart';
import '../widgets/save_result_button.dart';

/// 퇴직금 검증 화면 — 퇴직금 + 잔여연차수당 + 일할급여 통합 정산
class SeveranceVerifyScreen extends StatefulWidget {
  const SeveranceVerifyScreen({super.key});

  @override
  State<SeveranceVerifyScreen> createState() => _SeveranceVerifyScreenState();
}

class _SeveranceVerifyScreenState extends State<SeveranceVerifyScreen> {
  // 공통 입력
  final _nameCtrl = TextEditingController(text: '검증대상');
  final _joinDateCtrl = TextEditingController(text: '2024-06-01');
  final _exitDateCtrl = TextEditingController(text: '2026-06-30');
  final _weeklyHoursCtrl = TextEditingController(text: '40');
  final _hourlyRateCtrl = TextEditingController(text: '10320');

  // 연차 관련
  final _usedLeaveCtrl = TextEditingController(text: '3');
  final _manualAdjCtrl = TextEditingController(text: '0');
  List<int> _scheduledDays = [1, 2, 3, 4, 5];
  bool _isFiveOrMore = true;

  // 월급제 옵션
  String _wageType = 'hourly'; // hourly or monthly
  final _monthlySalaryCtrl = TextEditingController(text: '0');
  final _mealPayCtrl = TextEditingController(text: '0');
  final _fixedOtCtrl = TextEditingController(text: '0');
  bool _includeMeal = true;
  bool _includeFixedOt = true;
  bool _includeEtcPay = false;
  final _etcPayCtrl = TextEditingController(text: '0');
  final _etcPayLabelCtrl = TextEditingController(text: '기타수당');

  // 수동 평균임금
  final _manualAvgWageCtrl = TextEditingController(text: '0');

  // 결과
  ExitSettlementResult? _result;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _joinDateCtrl.dispose();
    _exitDateCtrl.dispose();
    _weeklyHoursCtrl.dispose();
    _hourlyRateCtrl.dispose();
    _usedLeaveCtrl.dispose();
    _manualAdjCtrl.dispose();
    _monthlySalaryCtrl.dispose();
    _mealPayCtrl.dispose();
    _fixedOtCtrl.dispose();
    _manualAvgWageCtrl.dispose();
    _etcPayCtrl.dispose();
    _etcPayLabelCtrl.dispose();
    super.dispose();
  }

  void _applyPreset(Map<String, dynamic> preset) {
    _nameCtrl.text = preset['name'] ?? '검증대상';
    _joinDateCtrl.text = preset['joinDate'];
    _exitDateCtrl.text = preset['exitDate'];
    _weeklyHoursCtrl.text = preset['weeklyHours'].toString();
    _hourlyRateCtrl.text = preset['hourlyRate'].toString();
    _usedLeaveCtrl.text = (preset['usedLeave'] ?? 0).toString();
    _manualAdjCtrl.text = (preset['manualAdj'] ?? 0).toString();
    _scheduledDays = List<int>.from(preset['scheduledDays']);
    _isFiveOrMore = preset['isFiveOrMore'];
    _wageType = preset['wageType'] ?? 'hourly';
    _monthlySalaryCtrl.text = (preset['monthlySalary'] ?? 0).toString();
    _mealPayCtrl.text = (preset['mealPay'] ?? 0).toString();
    _fixedOtCtrl.text = (preset['fixedOtPay'] ?? 0).toString();
    _manualAvgWageCtrl.text = (preset['manualAvgWage'] ?? 0).toString();
    _includeMeal = preset['includeMealInOrdinary'] ?? true;
    setState(() => _result = null);
  }

  void _calculate() {
    try {
      final joinDate = DateTime.parse(_joinDateCtrl.text);
      final exitDate = DateTime.parse(_exitDateCtrl.text);
      final weeklyHours = double.tryParse(_weeklyHoursCtrl.text) ?? 40;
      final hourlyRate = double.tryParse(_hourlyRateCtrl.text) ?? 0;
      final usedLeave = double.tryParse(_usedLeaveCtrl.text) ?? 0;
      final manualAdj = double.tryParse(_manualAdjCtrl.text) ?? 0;
      final manualAvg = double.tryParse(_manualAvgWageCtrl.text) ?? 0;

      final result = SeveranceCalculator.calculateExitSettlement(
        workerName: _nameCtrl.text,
        startDate: _joinDateCtrl.text,
        exitDate: exitDate,
        weeklyHours: weeklyHours,
        hourlyRate: hourlyRate,
        usedAnnualLeave: usedLeave,
        annualLeaveManualAdjustment: manualAdj,
        allAttendances: [], // 검증 모드: 출퇴근 데이터 없음
        scheduledWorkDays: _scheduledDays,
        isFiveOrMore: _isFiveOrMore,
        manualAverageDailyWage: manualAvg > 0 ? manualAvg : null,
        wageType: _wageType,
        monthlyWage: double.tryParse(_monthlySalaryCtrl.text) ?? 0,
        mealAllowance: _includeMeal ? (double.tryParse(_mealPayCtrl.text) ?? 0) : 0,
        fixedOvertimePay: _includeFixedOt ? (double.tryParse(_fixedOtCtrl.text) ?? 0) : 0,
        includeMealInOrdinary: _includeMeal,
        otherAllowances: _includeEtcPay ? [double.tryParse(_etcPayCtrl.text) ?? 0] : [],
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
    final fmt = NumberFormat('#,###');
    final isWide = MediaQuery.of(context).size.width > 900;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: isWide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 5, child: _buildInputPanel()),
                const SizedBox(width: 24),
                Expanded(flex: 5, child: _buildResultPanel(fmt)),
              ],
            )
          : Column(
              children: [
                _buildInputPanel(),
                const SizedBox(height: 24),
                _buildResultPanel(fmt),
              ],
            ),
    );
  }

  Widget _buildInputPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 프리셋 시나리오
        _buildPresetChips(),
        const SizedBox(height: 20),

        // 기본 정보
        Text('근로자 정보', style: TextStyle(
          fontSize: 14, fontWeight: FontWeight.bold,
          color: VerifyTheme.accentPrimary,
        )),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _inputField('근로자명', _nameCtrl)),
          const SizedBox(width: 12),
          Expanded(child: _inputField('시급 (원)', _hourlyRateCtrl, isNumber: true)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _inputField('입사일 (yyyy-MM-dd)', _joinDateCtrl)),
          const SizedBox(width: 12),
          Expanded(child: _inputField('퇴사일 (yyyy-MM-dd)', _exitDateCtrl)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _inputField('주 소정근로시간', _weeklyHoursCtrl, isNumber: true)),
          const SizedBox(width: 12),
          Expanded(child: _inputField('사용 연차', _usedLeaveCtrl, isNumber: true)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _inputField('수동 연차 가감', _manualAdjCtrl, isNumber: true)),
          const SizedBox(width: 12),
          Expanded(child: _inputField('수동 평균임금 (0=자동)', _manualAvgWageCtrl, isNumber: true)),
        ]),

        const SizedBox(height: 16),

        // 근무 요일 선택
        Text('근무 요일', style: TextStyle(fontSize: 12, color: VerifyTheme.textSecondary)),
        const SizedBox(height: 8),
        _buildDayChips(),
        const SizedBox(height: 12),

        // 5인이상 토글
        Row(children: [
          _buildSwitch('5인 이상', _isFiveOrMore, (v) => setState(() => _isFiveOrMore = v)),
        ]),

        const Divider(height: 32, color: VerifyTheme.borderColor),

        // 임금 유형 선택
        Text('임금 유형', style: TextStyle(
          fontSize: 14, fontWeight: FontWeight.bold,
          color: VerifyTheme.accentSecondary,
        )),
        const SizedBox(height: 8),
        Row(children: [
          ChoiceChip(
            label: const Text('시급제'),
            selected: _wageType == 'hourly',
            onSelected: (_) => setState(() => _wageType = 'hourly'),
            selectedColor: VerifyTheme.accentPrimary,
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: const Text('월급제'),
            selected: _wageType == 'monthly',
            onSelected: (_) => setState(() => _wageType = 'monthly'),
            selectedColor: VerifyTheme.accentPrimary,
          ),
        ]),

        if (_wageType == 'monthly') ...[
          const SizedBox(height: 12),
          _inputField('통상임금 / 기본급 (월)', _monthlySalaryCtrl, isNumber: true),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _inputField('식대 (월)', _mealPayCtrl, isNumber: true, enabled: _includeMeal)),
            const SizedBox(width: 8),
            _buildSwitch('포함', _includeMeal, (v) => setState(() => _includeMeal = v)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _inputField('고정OT (월)', _fixedOtCtrl, isNumber: true, enabled: _includeFixedOt)),
            const SizedBox(width: 8),
            _buildSwitch('포함', _includeFixedOt, (v) => setState(() => _includeFixedOt = v)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _inputField('기타 수당 (월)', _etcPayCtrl, isNumber: true, enabled: _includeEtcPay)),
            const SizedBox(width: 8),
            _buildSwitch('포함', _includeEtcPay, (v) => setState(() => _includeEtcPay = v)),
          ]),
        ],

        const SizedBox(height: 24),

        // 계산 실행 버튼
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton.icon(
            onPressed: _calculate,
            icon: const Icon(Icons.calculate),
            label: const Text('퇴직금 정산 실행', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: VerifyTheme.accentSecondary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResultPanel(NumberFormat fmt) {
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
            Icon(Icons.account_balance, size: 48, color: VerifyTheme.textSecondary.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text('퇴직금 정산 결과가 여기에 표시됩니다',
                style: TextStyle(color: VerifyTheme.textSecondary)),
          ]),
        ),
      );
    }

    final r = _result!;
    final joinStr = DateFormat('yyyy-MM-dd').format(r.joinDate);
    final exitStr = DateFormat('yyyy-MM-dd').format(r.exitDate);
    final deadlineStr = DateFormat('yyyy-MM-dd').format(r.paymentDeadline);

    return Column(
      children: [
        // 정산 요약 카드
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1A3A5C), Color(0xFF0D2137)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.person, color: Colors.white70, size: 18),
                const SizedBox(width: 8),
                Text(r.workerName, style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white,
                )),
              ]),
              const SizedBox(height: 8),
              Text('$joinStr ~ $exitStr  (${r.totalWorkingDays}일)',
                  style: const TextStyle(fontSize: 13, color: Colors.white60)),
              Text('지급기한: $deadlineStr (퇴직일로부터 14일)',
                  style: TextStyle(fontSize: 12, color: Colors.amber.shade300)),
              const SizedBox(height: 16),

              _resultRow('잔여 연차수당', r.annualLeavePayout, fmt),
              _resultRow('퇴직금', r.severancePay, fmt,
                  sub: r.isSeveranceEligible
                      ? '1일 평균임금: ₩${fmt.format(r.averageDailyWage.round())}'
                      : '대상 아님 (1년 미만 또는 주15h 미만)'),
              _resultRow('퇴사월 일할급여', r.exitMonthWage, fmt,
                  sub: '출퇴근 데이터 없음 → 별도 확인 필요'),

              const Divider(color: Colors.white24, height: 24),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('총 정산금액', style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white,
                  )),
                  Text('₩${fmt.format(r.totalSettlementAmount.round())}',
                      style: TextStyle(
                        fontSize: 22, fontWeight: FontWeight.bold,
                        color: Colors.greenAccent.shade400,
                      )),
                ],
              ),

              if (r.requiresManualInput) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.warning_amber, color: Colors.orange, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(
                      '출퇴근 기록 부족 — 수동 평균임금 입력 권장',
                      style: TextStyle(fontSize: 12, color: Colors.orange.shade200),
                    )),
                  ]),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 16),

        // 계산 근거 상세
        _buildBasisCard(r.calculationBasis),

        const SizedBox(height: 16),

        // JSON 저장
        SaveResultButton(
          verifyType: '퇴직금',
          buildInputData: () => {
            'joinDate': _joinDateCtrl.text,
            'exitDate': _exitDateCtrl.text,
            'weeklyHours': _weeklyHoursCtrl.text,
            'hourlyRate': _hourlyRateCtrl.text,
            'wageType': _wageType,
            'usedLeave': _usedLeaveCtrl.text,
            'isFiveOrMore': _isFiveOrMore,
          },
          buildResultData: () => {
            'severancePay': r.severancePay,
            'annualLeavePayout': r.annualLeavePayout,
            'exitMonthWage': r.exitMonthWage,
            'totalSettlementAmount': r.totalSettlementAmount,
            'averageDailyWage': r.averageDailyWage,
            'isSeveranceEligible': r.isSeveranceEligible,
            'paymentDeadline': DateFormat('yyyy-MM-dd').format(r.paymentDeadline),
            'calculationBasis': r.calculationBasis,
          },
        ),
      ],
    );
  }

  Widget _resultRow(String label, double value, NumberFormat fmt, {String? sub}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(color: Colors.white70, fontSize: 14)),
              Text('₩${fmt.format(value.round())}',
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
            ],
          ),
          if (sub != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(sub, style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.4))),
            ),
        ],
      ),
    );
  }

  // ─── 공통 위젯들 ───

  Widget _buildPresetChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        const Text('예제 시나리오: ', style: TextStyle(color: VerifyTheme.textSecondary, fontSize: 13)),
        ...PresetScenarios.severancePresets.entries.map((e) =>
            ActionChip(
              label: Text(e.key, style: const TextStyle(fontSize: 12)),
              backgroundColor: VerifyTheme.bgCard,
              side: BorderSide(color: VerifyTheme.accentSecondary.withValues(alpha: 0.5)),
              onPressed: () => _applyPreset(e.value),
            ),
        ),
      ],
    );
  }

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
              if (v) {
                _scheduledDays.add(day);
              } else {
                _scheduledDays.remove(day);
              }
              _scheduledDays.sort();
            });
          },
        );
      }),
    );
  }

  Widget _inputField(String label, TextEditingController ctrl, {bool isNumber = false, bool enabled = true}) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.4,
      child: TextField(
        controller: ctrl,
        enabled: enabled,
        keyboardType: isNumber ? TextInputType.number : TextInputType.text,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: VerifyTheme.textSecondary, fontSize: 13),
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
      ),
    );
  }

  Widget _buildBasisCard(List<String> basis) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(children: [
              Icon(Icons.info_outline, size: 18, color: VerifyTheme.accentSecondary),
              SizedBox(width: 8),
              Text('계산 근거 상세', style: TextStyle(
                fontWeight: FontWeight.w600, color: VerifyTheme.accentSecondary,
              )),
            ]),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: VerifyTheme.bgCardLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: basis.map((line) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    line,
                    style: TextStyle(
                      color: line.startsWith('[')
                          ? VerifyTheme.accentPrimary
                          : line.startsWith('※')
                              ? VerifyTheme.textSecondary
                              : VerifyTheme.textPrimary,
                      fontSize: 12,
                      fontWeight: line.startsWith('[') ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                )).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSwitch(String label, bool value, ValueChanged<bool> onChanged) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text(label, style: TextStyle(
        color: value ? VerifyTheme.accentPrimary : VerifyTheme.textSecondary,
        fontSize: 13,
        fontWeight: value ? FontWeight.w600 : FontWeight.normal,
      )),
      const SizedBox(width: 4),
      Switch(value: value, onChanged: onChanged, activeColor: VerifyTheme.accentPrimary),
    ]);
  }
}
