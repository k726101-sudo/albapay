import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_logic/src/utils/payroll/payroll_models.dart';
import '../theme/verify_theme.dart';

/// 비교 테이블 — AlbaPay 결과 vs 노무법인 기존 결과
class ComparisonTable extends StatefulWidget {
  final PayrollCalculationResult result;
  final bool isHourly;

  const ComparisonTable({super.key, required this.result, required this.isHourly});

  @override
  State<ComparisonTable> createState() => _ComparisonTableState();
}

class _ComparisonTableState extends State<ComparisonTable> {
  final Map<String, TextEditingController> _controllers = {};
  static final _fmt = NumberFormat('#,###');

  List<_CompareItem> get _items {
    if (widget.isHourly) {
      return [
        _CompareItem('기본급', widget.result.basePay),
        _CompareItem('가산수당', widget.result.premiumPay),
        _CompareItem('주휴수당', widget.result.weeklyHolidayPay),
        if (widget.result.laborDayAllowancePay > 0)
          _CompareItem('근로자의날', widget.result.laborDayAllowancePay + widget.result.holidayPremiumPay),
        _CompareItem('총급여', widget.result.totalPay),
        if (widget.result.insuranceDeduction > 0)
          _CompareItem('공제액', widget.result.insuranceDeduction),
        _CompareItem('실지급액', widget.result.netPay),
      ];
    } else {
      return [
        _CompareItem('기본급', widget.result.basePay),
        _CompareItem('식대', widget.result.mealAllowancePay),
        _CompareItem('고정연장수당', widget.result.fixedOvertimeBasePay),
        if (widget.result.premiumPay > 0)
          _CompareItem('추가가산수당', widget.result.premiumPay),
        _CompareItem('총급여', widget.result.totalPay),
        if (widget.result.insuranceDeduction > 0)
          _CompareItem('공제액', widget.result.insuranceDeduction),
        _CompareItem('실지급액', widget.result.netPay),
      ];
    }
  }

  TextEditingController _getCtrl(String key) {
    return _controllers.putIfAbsent(key, () => TextEditingController());
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final hasInput = _controllers.values.any((c) => c.text.isNotEmpty);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.compare_arrows, size: 18, color: VerifyTheme.accentSecondary),
                SizedBox(width: 8),
                Text('비교 검증', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              '기존 엑셀/프로그램 결과를 입력하면 항목별로 비교합니다.',
              style: TextStyle(color: VerifyTheme.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 16),

            // 테이블 헤더
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: VerifyTheme.bgCardLight,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
              ),
              child: const Row(
                children: [
                  Expanded(flex: 2, child: Text('항목', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                  Expanded(flex: 2, child: Text('AlbaPay', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: VerifyTheme.accentPrimary))),
                  Expanded(flex: 2, child: Text('기존 결과', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: VerifyTheme.accentSecondary))),
                  Expanded(flex: 1, child: Text('차이', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                ],
              ),
            ),

            // 테이블 행
            ...items.map((item) {
              final ctrl = _getCtrl(item.label);
              final existingVal = double.tryParse(ctrl.text.replaceAll(',', ''));
              final diff = existingVal != null ? (item.albaPayValue - existingVal).roundToDouble() : null;

              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: VerifyTheme.borderColor, width: 0.5)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(item.label, style: const TextStyle(fontSize: 13)),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        '₩${_fmt.format(item.albaPayValue.round())}',
                        style: const TextStyle(fontSize: 13, fontFeatures: [FontFeature.tabularFigures()]),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: SizedBox(
                        height: 32,
                        child: TextField(
                          controller: ctrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d,]'))],
                          style: const TextStyle(fontSize: 13, color: VerifyTheme.accentSecondary),
                          decoration: const InputDecoration(
                            hintText: '입력',
                            hintStyle: TextStyle(color: VerifyTheme.textSecondary, fontSize: 12),
                            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            isDense: true,
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 1,
                      child: diff != null
                          ? Text(
                              diff == 0
                                  ? '✅'
                                  : '⚠ ${diff > 0 ? "+" : ""}${_fmt.format(diff.toInt())}',
                              style: TextStyle(
                                fontSize: 12,
                                color: diff == 0 ? VerifyTheme.accentGreen : VerifyTheme.accentOrange,
                                fontWeight: FontWeight.w600,
                              ),
                            )
                          : const Text('—', style: TextStyle(color: VerifyTheme.textSecondary, fontSize: 12)),
                    ),
                  ],
                ),
              );
            }),

            // 판정 결과
            if (hasInput) ...[
              const SizedBox(height: 16),
              _buildVerdict(items),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildVerdict(List<_CompareItem> items) {
    int matchCount = 0;
    int mismatchCount = 0;

    for (final item in items) {
      final ctrl = _getCtrl(item.label);
      final val = double.tryParse(ctrl.text.replaceAll(',', ''));
      if (val == null) continue;
      if ((item.albaPayValue - val).abs() < 1) {
        matchCount++;
      } else {
        mismatchCount++;
      }
    }

    final allMatch = mismatchCount == 0 && matchCount > 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: allMatch
            ? VerifyTheme.accentGreen.withValues(alpha: 0.1)
            : VerifyTheme.accentOrange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: allMatch
              ? VerifyTheme.accentGreen.withValues(alpha: 0.3)
              : VerifyTheme.accentOrange.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            allMatch ? Icons.check_circle : Icons.warning_amber,
            color: allMatch ? VerifyTheme.accentGreen : VerifyTheme.accentOrange,
          ),
          const SizedBox(width: 12),
          Text(
            allMatch
                ? '✅ 전 항목 일치 ($matchCount개 항목 검증 완료)'
                : '⚠ $mismatchCount개 항목 불일치 / $matchCount개 항목 일치',
            style: TextStyle(
              color: allMatch ? VerifyTheme.accentGreen : VerifyTheme.accentOrange,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _CompareItem {
  final String label;
  final double albaPayValue;

  const _CompareItem(this.label, this.albaPayValue);
}
