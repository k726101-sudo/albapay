import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_logic/src/utils/payroll/payroll_models.dart';
import 'package:shared_logic/src/constants/payroll_constants.dart';
import '../theme/verify_theme.dart';

/// 계산 결과 카드 — 급여 명세서 형태 + 계산 근거 표시
class ResultCard extends StatelessWidget {
  final PayrollCalculationResult result;
  final bool isHourly;

  const ResultCard({super.key, required this.result, required this.isHourly});

  static final _fmt = NumberFormat('#,###');

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 헤더
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [VerifyTheme.accentPrimary, VerifyTheme.accentSecondary],
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isHourly ? '시급제' : '월급제',
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 12),
                const Text('계산 결과', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),

            // 최저임금 경고
            if (result.minimumWageHardBlock) ...[
              const SizedBox(height: 16),
              _buildAlert(
                '🚨 최저임금 미달 (Hard Block)',
                '기본급 기준 통상시급이 법정 최저임금(${_fmt.format(PayrollConstants.legalMinimumWage)}원)에 미달합니다.',
                VerifyTheme.accentRed,
              ),
            ],
            if (result.minimumWageWarning && !result.minimumWageHardBlock) ...[
              const SizedBox(height: 16),
              _buildAlert(
                '⚠️ 최저임금 주의',
                '식대를 포함해도 최저임금에 미달합니다.',
                VerifyTheme.accentOrange,
              ),
            ],

            const Divider(color: VerifyTheme.borderColor, height: 32),

            // 급여 항목
            if (isHourly) ..._buildHourlyItems() else ..._buildMonthlyItems(),

            const Divider(color: VerifyTheme.borderColor, height: 24),
            _buildTotalRow('총 급여', result.totalPay),

            // 공제
            if (result.insuranceDeduction > 0) ...[
              const Divider(color: VerifyTheme.borderColor, height: 24),
              const Text('공제 항목', style: TextStyle(fontWeight: FontWeight.w600, color: VerifyTheme.accentOrange, fontSize: 13)),
              const SizedBox(height: 8),
              if (result.nationalPension > 0)
                _buildRow('국민연금 (4.5%)', -result.nationalPension),
              if (result.healthInsurance > 0)
                _buildRow('건강보험 (3.545%)', -result.healthInsurance),
              if (result.longTermCareInsurance > 0)
                _buildRow('장기요양 (건보×12.95%)', -result.longTermCareInsurance),
              if (result.employmentInsurance > 0)
                _buildRow('고용보험 (0.9%)', -result.employmentInsurance),
              if (result.businessIncomeTax > 0)
                _buildRow('사업소득세 (3%)', -result.businessIncomeTax),
              if (result.localIncomeTax > 0)
                _buildRow('지방소득세 (0.3%)', -result.localIncomeTax),
              _buildRow('총 공제액', -result.insuranceDeduction, isBold: true),
            ],

            const Divider(color: VerifyTheme.borderColor, height: 24),
            _buildTotalRow('실지급액', result.netPay, isNet: true),

            // 계산 근거
            const SizedBox(height: 24),
            _buildBasisSection(),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildHourlyItems() {
    return [
      _buildRow('기본급', result.basePay, subtitle: '${result.pureLaborHours.toStringAsFixed(1)}h × 시급'),
      if (result.breakPay > 0)
        _buildRow('유급휴게수당', result.breakPay),
      if (result.premiumPay > 0)
        _buildRow('가산수당 (연장+야간+휴일)', result.premiumPay,
            subtitle: '${result.premiumHours.toStringAsFixed(1)}h × 시급 × 0.5'),
      if (result.weeklyHolidayPay > 0)
        _buildRow('주휴수당', result.weeklyHolidayPay),
      if (result.laborDayAllowancePay > 0)
        _buildRow('근로자의날 유급보장', result.laborDayAllowancePay),
      if (result.holidayPremiumPay > 0)
        _buildRow('근로자의날 출근가산', result.holidayPremiumPay),
    ];
  }

  List<Widget> _buildMonthlyItems() {
    return [
      _buildRow('기본급', result.basePay,
          subtitle: result.proRataRatio < 1.0
              ? '${_fmt.format(result.monthlyBasePay)}원 × ${(result.proRataRatio * 100).toStringAsFixed(1)}% (일할)'
              : null),
      if (result.mealAllowancePay > 0)
        _buildRow('식대', result.mealAllowancePay),
      if (result.fixedOvertimeBasePay > 0)
        _buildRow('고정연장수당', result.fixedOvertimeBasePay,
            subtitle: '약정 ${result.fixedOvertimeAgreedHours}h'),
      if (result.premiumPay > 0)
        _buildRow('추가 가산수당', result.premiumPay),
    ];
  }

  Widget _buildRow(String label, double amount, {String? subtitle, bool isBold = false}) {
    final isNegative = amount < 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(
                  color: VerifyTheme.textPrimary,
                  fontWeight: isBold ? FontWeight.w600 : FontWeight.normal,
                )),
                if (subtitle != null)
                  Text(subtitle, style: const TextStyle(color: VerifyTheme.textSecondary, fontSize: 11)),
              ],
            ),
          ),
          Text(
            '${isNegative ? "-" : ""}₩${_fmt.format(amount.abs().round())}',
            style: TextStyle(
              color: isNegative ? VerifyTheme.accentRed : VerifyTheme.textPrimary,
              fontWeight: isBold ? FontWeight.w600 : FontWeight.normal,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalRow(String label, double amount, {bool isNet = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(label, style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: isNet ? VerifyTheme.accentGreen : VerifyTheme.textPrimary,
          )),
          const Spacer(),
          Text(
            '₩${_fmt.format(amount.round())}',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isNet ? VerifyTheme.accentGreen : VerifyTheme.accentPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlert(String title, String message, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 4),
          Text(message, style: TextStyle(color: color.withValues(alpha: 0.8), fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildBasisSection() {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: const Row(
        children: [
          Icon(Icons.info_outline, size: 18, color: VerifyTheme.accentSecondary),
          SizedBox(width: 8),
          Text('계산 근거 상세', style: TextStyle(fontWeight: FontWeight.w600, color: VerifyTheme.accentSecondary)),
        ],
      ),
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: VerifyTheme.bgCardLight,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isHourly) ...[
                _basisItem('기본급', '${result.pureLaborHours.toStringAsFixed(1)}h × 시급 = ₩${_fmt.format(result.basePay.round())}'),
                if (result.weeklyHolidayPay > 0)
                  _basisItem('주휴수당', '만근 주 × (주 소정근로/40 × 8h) × 시급'),
                if (result.premiumPay > 0)
                  _basisItem('가산수당', '(연장+야간+휴일)시간 × 시급 × 0.5'),
              ] else ...[
                _basisItem('S_Legal (법적 소정근로시간)', '${result.scheduledMonthlyHoursLegal.toStringAsFixed(1)}h'),
                _basisItem('S_Ref (참고 소정근로시간)', '${result.scheduledMonthlyHoursRef.toStringAsFixed(1)}h'),
                _basisItem('통상시급 (보수적)', '기본급 / S_Legal = ₩${_fmt.format(result.conservativeHourlyWage.round())}'),
                _basisItem('참고시급', '(기본급+식대) / S_Ref = ₩${_fmt.format(result.referenceHourlyWage.round())}'),
                if (result.proRataRatio < 1.0)
                  _basisItem('일할계산', '${(result.proRataRatio * 100).toStringAsFixed(1)}% 적용'),
              ],
              const SizedBox(height: 12),
              _basisItem('적용 법령', ''),
              _lawRef('기본급', '근로기준법 제2조 제1항 제5호'),
              if (isHourly) _lawRef('주휴수당', '근로기준법 제55조'),
              if (result.isFiveOrMore) _lawRef('가산수당', '근로기준법 제56조'),
              _lawRef('최저임금', '최저임금법 제6조 (${_fmt.format(PayrollConstants.legalMinimumWage.toInt())}원)'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _basisItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(label, style: const TextStyle(color: VerifyTheme.textSecondary, fontSize: 12)),
          ),
          Expanded(child: Text(value, style: const TextStyle(color: VerifyTheme.textPrimary, fontSize: 12))),
        ],
      ),
    );
  }

  Widget _lawRef(String item, String law) {
    return Padding(
      padding: const EdgeInsets.only(left: 12, bottom: 4),
      child: Text(
        '• $item: $law',
        style: const TextStyle(color: VerifyTheme.textSecondary, fontSize: 11),
      ),
    );
  }
}
