import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_logic/shared_logic.dart';

import '../utils/standing_calculator.dart';
import '../services/worker_service.dart';
import '../screens/documents/create_document_screen.dart';

class StandingChangeAlert extends StatefulWidget {
  const StandingChangeAlert({super.key, required this.storeId});

  final String storeId;

  @override
  State<StandingChangeAlert> createState() => _StandingChangeAlertState();
}

class _StandingChangeAlertState extends State<StandingChangeAlert> {
  bool _running = false;

  /// 배너 표시용 상태
  _StandingAlertType? _alertType;
  bool _dismissed = false;
  int _affectedMonthlyCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAlert());
  }

  Future<void> _maybeAlert() async {
    if (_running || !mounted) return;
    _running = true;

    try {
      final now = AppClock.now();

      final storeSnap = await FirebaseFirestore.instance
          .collection('stores')
          .doc(widget.storeId)
          .get();

      if (!storeSnap.exists) return;
      final storeData = storeSnap.data() ?? {};

      final settlementStartDay =
          (storeData['settlementStartDay'] as num?)?.toInt() ?? 1;
      final settlementEndDay =
          (storeData['settlementEndDay'] as num?)?.toInt() ?? 31;

      final period = computeSettlementPeriod(
        now: now,
        settlementStartDay: settlementStartDay,
        settlementEndDay: settlementEndDay,
      );

      final periodKey =
          '${period.start.year}-${period.start.month.toString().padLeft(2, '0')}-${period.start.day.toString().padLeft(2, '0')}~'
          '${period.end.year}-${period.end.month.toString().padLeft(2, '0')}-${period.end.day.toString().padLeft(2, '0')}';

      // Firebase 인덱스 미비로 인한 크래시를 방지하기 위해 storeId로만 쿼리하고 로컬에서 날짜를 필터링
      final attendanceSnap = await FirebaseFirestore.instance
          .collection('attendance')
          .where('storeId', isEqualTo: widget.storeId)
          .get();

      final limitEnd = period.end.add(const Duration(days: 1)).toIso8601String();
      final attendances = attendanceSnap.docs
          .map((d) {
            final clockInStr = d.data()['clockIn']?.toString() ?? '';
            // 로컬 필터링 (ISO 8601 문자열 비교)
            if (clockInStr.compareTo(period.start.toIso8601String()) >= 0 &&
                clockInStr.compareTo(limitEnd) < 0) {
              return Attendance.fromJson(d.data(), id: d.id);
            }
            return null;
          })
          .whereType<Attendance>()
          .toList();

      final staffList = WorkerService.getAll();

      final standing = calculateStandingFromAttendances(
        attendances: attendances,
        periodStart: period.start,
        periodEnd: period.end,
        staffList: staffList,
      );

      final currentIsFive = standing.isFiveOrMore;
      final currentIsTen = standing.isTenOrMore;

      final metaRef = FirebaseFirestore.instance
          .collection('stores')
          .doc(widget.storeId)
          .collection('standingMeta')
          .doc('current');

      final metaSnap = await metaRef.get();
      final metaData = metaSnap.data() ?? {};

      final lastPeriodKey = metaData['periodKey'];
      final lastIsFive = metaData['isFiveLast'];
      final lastIsTen = metaData['isTenLast'];

      final hasLast = lastPeriodKey is String && lastIsFive is bool;
      final hasTenLast = lastIsTen is bool;

      final periodChanged = !hasLast || lastPeriodKey != periodKey;
      final stateChanged = !hasLast || (lastIsFive != currentIsFive);

      // Show alarm only when the state flips, but requested:
      // "5인이하였다가 이상으로 바뀔 경우" -> true alarm.
      final shouldAlarmUnderToOver =
          hasLast && lastIsFive == false && currentIsFive == true;
      final shouldAlarmOverToUnder =
          hasLast && lastIsFive == true && currentIsFive == false;
      final shouldAlarmTenFlipToOver =
          hasTenLast && lastIsTen == false && currentIsTen == true;
      final shouldAlarmTenFlipToUnder =
          hasTenLast && lastIsTen == true && currentIsTen == false;

      // ── 월급제 직원 중 고정연장수당이 있는 직원 수 (근로계약서 재작성 대상) ──
      final monthlyWorkersAffected = staffList.where((w) =>
          w.status == 'active' &&
          w.wageType == 'monthly' &&
          w.fixedOvertimePay > 0).length;

      if (!metaSnap.exists) {
        // First-time for this device/session: show guidance once.
        _showSnack(
          message: currentIsFive
              ? '상시근로자 5인 이상으로 판정되었습니다. (출근기록 기준)\n가산 적용(연장/야간/휴일) 확인을 권장합니다.'
              : '상시근로자 5인 미만으로 판정되었습니다. (출근기록 기준)\n출근기록 누락이 없도록 확인해 주세요.',
        );
      } else if (shouldAlarmUnderToOver || shouldAlarmOverToUnder) {
        _showSnack(
          message: currentIsFive
              ? '주의: 상시근로자 5인 이상으로 바뀌었습니다. (출근기록 기준)\n연장근로/야간근로/휴일근로 가산 적용 기준을 확인해 주세요.'
              : '안내: 상시근로자 5인 미만으로 바뀌었습니다. (출근기록 기준)\n그래도 출근기록 정확성 확인을 권장합니다.',
        );

        // ★ 5인 전환 발생 + 월급제 직원이 있으면 대시보드 배너 활성화
        if (monthlyWorkersAffected > 0 && mounted) {
          setState(() {
            _alertType = shouldAlarmUnderToOver
                ? _StandingAlertType.underToOver
                : _StandingAlertType.overToUnder;
            _affectedMonthlyCount = monthlyWorkersAffected;
            _dismissed = false;
          });
        }
      } else if (periodChanged && stateChanged) {
        // New period, but no flip due to existing meta mismatch.
        // Keep quiet for MVP to reduce noise.
      }

      if (standing.average >= 9.5 && standing.average < 10.0) {
        _showSnack(
          message:
              '사장님, 현재 상시근로자 수가 ${standing.average.toStringAsFixed(1)}명입니다. '
              '10인이 되는 순간 \'취업규칙 신고 의무\'가 발생하니 노무사 상담이나 서류 준비를 시작하세요.',
        );
      }

      if (!metaSnap.exists && currentIsTen) {
        await _showTenOrMoreChecklistDialog();
      } else if (shouldAlarmTenFlipToOver) {
        _showSnack(
          message: '주의: 상시근로자 10인 이상으로 바뀌었습니다. 취업규칙 신고 의무를 확인하세요.',
        );
        await _showTenOrMoreChecklistDialog();
      } else if (shouldAlarmTenFlipToUnder) {
        _showSnack(
          message: '안내: 상시근로자 10인 미만으로 내려왔습니다. 최근 신고/변경 이력을 점검해 주세요.',
        );
      }

      await metaRef.set(
        {
          'periodKey': periodKey,
          'isFiveLast': currentIsFive,
          'isTenLast': currentIsTen,
          'average': standing.average,
          'daysWithFiveOrMore': standing.daysWithFiveOrMore,
          'daysWithTenOrMore': standing.daysWithTenOrMore,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      // Keep store.isFiveOrMore in sync with the current computed standing
      // ONLY when not in a manual override mode.
      final sizeMode = storeData['employeeSizeMode']?.toString() ?? 'auto';
      final Map<String, dynamic> storeUpdate = {
        'isTenOrMore': currentIsTen,
        'averageWorkers': standing.average,
        'daysWithFiveOrMore': standing.daysWithFiveOrMore,
        'totalBusinessDays': standing.operatingDays,
        'fiveOrMoreDecisionReason': standing.fiveOrMoreDecisionReason,
      };
      if (sizeMode == 'auto') {
        storeUpdate['isFiveOrMore'] = currentIsFive;
      }
      await FirebaseFirestore.instance
          .collection('stores')
          .doc(widget.storeId)
          .set(storeUpdate, SetOptions(merge: true));
    } finally {
      _running = false;
    }
  }

  Future<void> _showTenOrMoreChecklistDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('10인 이상 행정 체크리스트'),
        content: const SingleChildScrollView(
          child: Text(
            '상시근로자 10인 이상 사업장으로 판정되었습니다.\n\n'
            '1) 취업규칙 신고 대상 여부 확인\n'
            '2) 취업규칙(변경 포함) 작성 및 관할 기관 신고 준비\n'
            '3) 연장/야간/휴일 가산수당 지급체계 재점검\n'
            '4) 연차유급휴가 및 해고 절차 기준 문서 정비\n'
            '5) 노무사 상담 및 증빙(출퇴근/급여) 보관 체계 점검',
            style: TextStyle(height: 1.35),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  void _showSnack({required String message}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 배너가 없거나 닫힌 경우 빈 위젯
    if (_alertType == null || _dismissed) return const SizedBox.shrink();

    final isUpgrade = _alertType == _StandingAlertType.underToOver;

    final Color bgColor = isUpgrade
        ? const Color(0xFFFFF3E0) // 오렌지 계열
        : const Color(0xFFE8F5E9); // 그린 계열
    final Color borderColor = isUpgrade
        ? const Color(0xFFFF9800)
        : const Color(0xFF4CAF50);
    final Color textColor = isUpgrade
        ? const Color(0xFFE65100)
        : const Color(0xFF2E7D32);
    final IconData icon = isUpgrade
        ? Icons.trending_up_rounded
        : Icons.trending_down_rounded;

    final String title = isUpgrade
        ? '⚠️ 5인 이상 전환 — 근로계약서 재작성 필요'
        : '📋 5인 미만 전환 — 근로계약서 확인 필요';

    final String body = isUpgrade
        ? '사업장이 5인 미만 → 5인 이상으로 전환되었습니다.\n'
          '고정연장수당의 가산율이 1.0배 → 1.5배로 변경되므로,\n'
          '월급제 직원($_affectedMonthlyCount명)의 근로계약서를 재작성해야 합니다.'
        : '사업장이 5인 이상 → 5인 미만으로 전환되었습니다.\n'
          '고정연장수당의 가산율이 1.5배 → 1.0배로 변경되므로,\n'
          '월급제 직원($_affectedMonthlyCount명)의 근로계약서를 확인하세요.';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: borderColor.withOpacity(0.15),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 제목 + 닫기 버튼
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: textColor, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                      height: 1.3,
                    ),
                  ),
                ),
                InkWell(
                  onTap: () => setState(() => _dismissed = true),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.close, size: 18, color: textColor.withOpacity(0.6)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 본문
            Text(
              body,
              style: TextStyle(
                fontSize: 12,
                color: textColor.withOpacity(0.85),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 10),
            // 체크리스트
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _checkItem('고정연장수당 금액 재산정 (가산율 변동 반영)', textColor),
                  const SizedBox(height: 4),
                  _checkItem('근로계약서 [특약 2] 고정연장수당 합의 재작성', textColor),
                  const SizedBox(height: 4),
                  _checkItem('변경된 계약서 직원 서명 수령', textColor),
                  if (isUpgrade) ...[
                    const SizedBox(height: 4),
                    _checkItem('연장/야간/휴일 가산수당 지급 기준 재확인', textColor),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
            // 액션 버튼
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _showAffectedWorkersSheet(context),
                    icon: const Icon(Icons.description_outlined, size: 16),
                    label: const Text('근로계약서 재작성', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: borderColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => setState(() => _dismissed = true),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: textColor,
                    side: BorderSide(color: borderColor.withOpacity(0.5)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('나중에', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _checkItem(String text, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.check_circle_outline, size: 14, color: color.withOpacity(0.7)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 11, color: color.withOpacity(0.85), height: 1.3),
          ),
        ),
      ],
    );
  }

  void _showAffectedWorkersSheet(BuildContext ctx) {
    final monthlyWorkers = WorkerService.getAll()
        .where((w) =>
            w.status == 'active' &&
            w.wageType == 'monthly' &&
            w.fixedOvertimePay > 0)
        .toList();

    if (monthlyWorkers.isEmpty) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(content: Text('해당하는 월급제 직원이 없습니다.')),
      );
      return;
    }

    String _fmtMoney(double v) => v.toInt().toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');

    showModalBottomSheet<void>(
      context: ctx,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.people_alt_outlined, size: 20, color: Color(0xFFE65100)),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      '근로계약서 재작성 대상 직원',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(sheetCtx),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '고정연장수당이 설정된 월급제 직원 ${monthlyWorkers.length}명',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const Divider(height: 20),
              ...monthlyWorkers.map((w) => InkWell(
                    onTap: () {
                      Navigator.pop(sheetCtx);
                      Navigator.push(
                        ctx,
                        MaterialPageRoute(
                          builder: (_) => CreateDocumentScreen(
                            worker: w,
                            storeId: w.storeId,
                          ),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                      margin: const EdgeInsets.only(bottom: 6),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: const Color(0xFFFF9800).withOpacity(0.15),
                            child: Text(
                              w.name.isNotEmpty ? w.name[0] : '?',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFE65100),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  w.name,
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '기본급 ${_fmtMoney(w.monthlyWage)}원 · 고정OT ${_fmtMoney(w.fixedOvertimePay)}원',
                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right, size: 20, color: Colors.grey),
                        ],
                      ),
                    ),
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

enum _StandingAlertType {
  underToOver, // 5인 미만 → 5인 이상
  overToUnder, // 5인 이상 → 5인 미만
}
