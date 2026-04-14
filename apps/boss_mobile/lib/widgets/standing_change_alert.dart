import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_logic/shared_logic.dart';

import '../utils/standing_calculator.dart';
import '../services/worker_service.dart';

class StandingChangeAlert extends StatefulWidget {
  const StandingChangeAlert({super.key, required this.storeId});

  final String storeId;

  @override
  State<StandingChangeAlert> createState() => _StandingChangeAlertState();
}

class _StandingChangeAlertState extends State<StandingChangeAlert> {
  bool _running = false;

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
        'totalBusinessDays': standing.totalDays,
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
    // Invisible widget: it only triggers side-effects.
    return const SizedBox.shrink();
  }
}

