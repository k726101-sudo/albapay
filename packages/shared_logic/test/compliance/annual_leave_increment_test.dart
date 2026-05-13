/// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
/// [법률 테스트] 근속 연수별 연차 가산일 검증
/// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
///
/// 【법적 근거】
///   근로기준법 제60조 제4항:
///   "3년 이상 계속 근로한 근로자에게는 제1항에 따른 휴가에
///    최초 1년을 초과하는 계속 근로 연수 매 2년에 대하여
///    1일을 가산한 유급휴가를 주어야 한다. 이 경우 가산휴가를
///    포함한 총 휴가 일수는 25일을 한도로 한다."
/// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_logic/shared_logic.dart';

void main() {
  group('[근로기준법 제60조 §4] 근속 연수별 연차 가산일 검증', () {
    const hourlyRate = 10320.0;
    final workDays = [1, 2, 3, 4, 5];

    /// N년 근속 시 totalGenerated를 구하고,
    /// 직전 연도와의 차이로 해당 연차 발생분만 추출
    double _getYearlyGrant(int year) {
      final joinDate = DateTime(2026 - year, 1, 1);
      final settlement = DateTime(2026, 1, 2);

      final current = PayrollCalculator.calculateAnnualLeaveSummary(
        joinDate: joinDate,
        endDate: null,
        allAttendances: [],
        scheduledWorkDays: workDays,
        isFiveOrMore: true,
        settlementPoint: settlement,
        usedAnnualLeave: 0,
        weeklyHoursPure: 40,
        hourlyRate: hourlyRate,
        isVirtual: true,
      );

      if (year == 1) {
        // 1년차: total - 1년 미만분(11) = 15
        return current.totalGenerated - 11;
      }

      // N년차: N년 누적 - (N-1)년 누적
      final prevJoin = DateTime(2026 - year, 1, 1);
      final prevSettlement = DateTime(2026 - 1, 1, 2); // 직전 연도 끝

      final prev = PayrollCalculator.calculateAnnualLeaveSummary(
        joinDate: prevJoin,
        endDate: null,
        allAttendances: [],
        scheduledWorkDays: workDays,
        isFiveOrMore: true,
        settlementPoint: prevSettlement,
        usedAnnualLeave: 0,
        weeklyHoursPure: 40,
        hourlyRate: hourlyRate,
        isVirtual: true,
      );

      return current.totalGenerated - prev.totalGenerated;
    }

    // 법정 기대값 테이블
    final expectations = <int, int>{
      1: 15, 2: 15, 3: 16, 4: 16, 5: 17, 6: 17,
      7: 18, 8: 18, 9: 19, 10: 19, 11: 20, 12: 20,
      13: 21, 14: 21, 15: 22, 16: 22, 17: 23, 18: 23,
      19: 24, 20: 24, 21: 25, 22: 25, 23: 25, 24: 25, 25: 25,
    };

    // 핵심 연차만 개별 테스트 (1, 2, 3, 5, 10, 15, 21, 25)
    for (final y in [1, 2, 3, 5, 10, 15, 21, 25]) {
      final expected = expectations[y]!;
      test('${y}년차 → ${expected}일 발생${y >= 21 ? " (상한)" : ""}', () {
        final grant = _getYearlyGrant(y);
        expect(grant, expected.toDouble(),
            reason: '${y}년차 발생분 = $expected일');
        print('✅ ${y}년차: ${grant.toInt()}일');
      });
    }

    // 종합 테이블 출력
    test('종합: 1~25년차 전체 연차표 출력', () {
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('📊 [근속 연수별 연차 발생 일수]');
      print('  근속년수  │ 발생일수 │ 가산일 │ 법정기준');
      print('  ─────────┼──────────┼────────┼──────────');

      for (int y = 1; y <= 25; y++) {
        final additional = (y > 1) ? ((y - 1) ~/ 2) : 0;
        final expected = (15 + additional).clamp(15, 25);
        final marker = expected == 25 ? ' (상한)' : '';
        print('  ${y.toString().padLeft(2)}년차   │ '
            '${expected.toString().padLeft(4)}일   │ '
            '+${additional.toString().padLeft(2)}일  │ '
            '$expected일$marker');
      }
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    });
  });
}
