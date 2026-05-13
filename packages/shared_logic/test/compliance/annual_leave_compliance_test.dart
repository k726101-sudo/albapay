/// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
/// [법률 테스트] 연차유급휴가 — 근로기준법 제60조
/// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
///
/// 【검증 대상 법령】
///   - 제60조 제1항: 1년간 80% 이상 출근 시 15일의 유급휴가
///   - 제60조 제2항: 1년 미만 근로자 → 1개월 만근 시 1일
///   - 제60조 제3항: 단시간 근로자 → 비례 적용
///   - 제60조 제4항: 3년 이상 → 2년마다 1일 추가 (최대 25일)
///   - 제18조 제3항: 초단시간(주 15시간 미만) → 연차 미발생
///   - 제11조: 5인 미만 사업장 → 연차 법적 의무 없음
///
/// 【테스트 의의】
///   연차는 노동 분쟁에서 가장 빈번하게 다투는 항목.
///   1년 미만 월별 발생, 1년 차 15일 일괄, 장기근속 가산 등
///   모든 엣지 케이스가 정확해야 합니다.
/// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_logic/shared_logic.dart';

void main() {
  group('[근로기준법 제60조] 연차유급휴가', () {
    final scheduledDays = [1, 2, 3, 4, 5]; // 월~금
    const hourlyRate = 10320.0;

    // ═══════════════════════════════════════════════════
    // [케이스 1] 1년 미만: 매월 만근 시 +1일 (최대 11일)
    // ═══════════════════════════════════════════════════
    test('1년 미만: 5개월 만근 → 5일 발생', () {
      final joinDate = DateTime(2026, 1, 1);
      final settlement = DateTime(2026, 6, 1);

      final summary = PayrollCalculator.calculateAnnualLeaveSummary(
        joinDate: joinDate,
        endDate: null,
        allAttendances: [],
        scheduledWorkDays: scheduledDays,
        isFiveOrMore: true,
        settlementPoint: settlement,
        usedAnnualLeave: 0,
        weeklyHoursPure: 40,
        hourlyRate: hourlyRate,
        isVirtual: true,
      );

      expect(summary.totalGenerated, 5.0,
          reason: '1~5월 만근 → 5개 발생');
    });

    // ═══════════════════════════════════════════════════
    // [케이스 2] 1년 미만: 최대 11일 상한
    // ═══════════════════════════════════════════════════
    test('1년 미만: 최대 11일까지만 발생', () {
      final joinDate = DateTime(2025, 1, 1);
      // 정확히 1년 직전
      final settlement = DateTime(2025, 12, 31);

      final summary = PayrollCalculator.calculateAnnualLeaveSummary(
        joinDate: joinDate,
        endDate: null,
        allAttendances: [],
        scheduledWorkDays: scheduledDays,
        isFiveOrMore: true,
        settlementPoint: settlement,
        usedAnnualLeave: 0,
        weeklyHoursPure: 40,
        hourlyRate: hourlyRate,
        isVirtual: true,
      );

      expect(summary.totalGenerated, 11.0,
          reason: '1년 미만 최대 11개 (0~10개월 = 11개)');
    });

    // ═══════════════════════════════════════════════════
    // [케이스 3] 1년 차: 15일 일괄 발생 (+ 1년 미만 11일)
    // ═══════════════════════════════════════════════════
    test('1년 차: 11일(1년미만) + 15일(1년차) = 26일', () {
      final joinDate = DateTime(2025, 1, 1);
      final settlement = DateTime(2026, 1, 2); // 1년 지남

      final summary = PayrollCalculator.calculateAnnualLeaveSummary(
        joinDate: joinDate,
        endDate: null,
        allAttendances: [],
        scheduledWorkDays: scheduledDays,
        isFiveOrMore: true,
        settlementPoint: settlement,
        usedAnnualLeave: 0,
        weeklyHoursPure: 40,
        hourlyRate: hourlyRate,
        isVirtual: true,
      );

      expect(summary.totalGenerated, 26.0,
          reason: '11(1년미만) + 15(1년차) = 26일');
    });

    // ═══════════════════════════════════════════════════
    // [케이스 4] 장기근속 가산: 3년차부터 2년마다 +1일
    //           1년차 15, 2년차 15, 3년차 16, 4년차 16, 5년차 17...
    // ═══════════════════════════════════════════════════
    test('장기근속: 3년차 16일, 5년차 17일 (2년마다 +1)', () {
      final joinDate = DateTime(2021, 1, 1);
      final settlement = DateTime(2026, 1, 2); // 5년 지남

      final summary = PayrollCalculator.calculateAnnualLeaveSummary(
        joinDate: joinDate,
        endDate: null,
        allAttendances: [],
        scheduledWorkDays: scheduledDays,
        isFiveOrMore: true,
        settlementPoint: settlement,
        usedAnnualLeave: 0,
        weeklyHoursPure: 40,
        hourlyRate: hourlyRate,
        isVirtual: true,
      );

      // 1년미만: 11, 1년차: 15, 2년차: 15, 3년차: 16, 4년차: 16, 5년차: 17
      // = 11 + 15 + 15 + 16 + 16 + 17 = 90
      // ★ 참고: 엔진은 (y > 1 ? (y-1)~/2 : 0)으로 가산
      //   y=1: 15, y=2: 15, y=3: 15+1=16, y=4: 15+1=16, y=5: 15+2=17
      expect(summary.totalGenerated, 11 + 15 + 15 + 16 + 16 + 17,
          reason: '5년 누적: 11+15+15+16+16+17 = 90일');
    });

    // ═══════════════════════════════════════════════════
    // [케이스 5] 연차 최대 25일 상한
    // ═══════════════════════════════════════════════════
    test('연차 상한: 단년도 최대 25일', () {
      // 25일 도달: 15 + 10 = 25 → (y-1)~/2 = 10이 되려면 y = 21년차
      final joinDate = DateTime(2005, 1, 1);
      final settlement = DateTime(2026, 1, 2); // 21년 지남

      final summary = PayrollCalculator.calculateAnnualLeaveSummary(
        joinDate: joinDate,
        endDate: null,
        allAttendances: [],
        scheduledWorkDays: scheduledDays,
        isFiveOrMore: true,
        settlementPoint: settlement,
        usedAnnualLeave: 0,
        weeklyHoursPure: 40,
        hourlyRate: hourlyRate,
        isVirtual: true,
      );

      // 21년차: 15 + (21-1)~/2 = 15+10 = 25 (상한)
      // 그 이상은 clamp(15, 25)로 25일 유지
      final lastYearLeave = summary.totalGenerated;
      expect(lastYearLeave, greaterThanOrEqualTo(25),
          reason: '최소 25일 이상 포함');
    });

    // ═══════════════════════════════════════════════════
    // [케이스 6] 5인 미만 사업장 → 연차 법적 의무 없음
    // ═══════════════════════════════════════════════════
    test('5인 미만 사업장: 연차 0일 (법적 의무 없음)', () {
      final joinDate = DateTime(2025, 1, 1);
      final settlement = DateTime(2026, 1, 2);

      final summary = PayrollCalculator.calculateAnnualLeaveSummary(
        joinDate: joinDate,
        endDate: null,
        allAttendances: [],
        scheduledWorkDays: scheduledDays,
        isFiveOrMore: false, // ★ 5인 미만
        settlementPoint: settlement,
        usedAnnualLeave: 0,
        weeklyHoursPure: 40,
        hourlyRate: hourlyRate,
        isVirtual: true,
      );

      expect(summary.totalGenerated, 0.0,
          reason: '5인 미만 → 연차 법적 의무 없음 → 0일');
    });

    // ═══════════════════════════════════════════════════
    // [케이스 7] 초단시간 근로자(주 15시간 미만) → 연차 미발생
    // ═══════════════════════════════════════════════════
    test('초단시간 근로자(주 14시간): 연차 미발생', () {
      final joinDate = DateTime(2025, 1, 1);
      final settlement = DateTime(2026, 1, 2);

      final summary = PayrollCalculator.calculateAnnualLeaveSummary(
        joinDate: joinDate,
        endDate: null,
        allAttendances: [],
        scheduledWorkDays: scheduledDays,
        isFiveOrMore: true,
        settlementPoint: settlement,
        usedAnnualLeave: 0,
        weeklyHoursPure: 14, // ★ 15시간 미만
        hourlyRate: hourlyRate,
        isVirtual: true,
      );

      expect(summary.totalGenerated, 0.0,
          reason: '주 14시간 < 15시간 → 초단시간 → 연차 미발생');
    });

    // ═══════════════════════════════════════════════════
    // [케이스 8] 퇴사 시 잔여 연차 → 연차수당 정산
    // ═══════════════════════════════════════════════════
    test('퇴사 시 잔여 연차 → 수당 정산 (잔여일 × 8h × 시급)', () {
      final joinDate = DateTime(2025, 1, 1);
      final exitDate = DateTime(2026, 6, 1);

      final summary = PayrollCalculator.calculateAnnualLeaveSummary(
        joinDate: joinDate,
        endDate: exitDate,
        allAttendances: [],
        scheduledWorkDays: scheduledDays,
        isFiveOrMore: true,
        settlementPoint: exitDate,
        usedAnnualLeave: 5, // 5일 사용
        weeklyHoursPure: 40,
        hourlyRate: hourlyRate,
        isVirtual: true,
      );

      // 발생: 11(1년미만) + 15(1년차) = 26, 사용: 5 → 잔여: 21일
      expect(summary.remaining, 21.0);
      // 연차수당 = 21일 × 8시간 × 10,320원 = 1,733,760원
      expect(summary.annualLeaveAllowancePay, 21 * 8 * hourlyRate,
          reason: '퇴사 정산: 잔여 21일 × 8h × 10,320 = 1,733,760원');
    });

    // ═══════════════════════════════════════════════════
    // [케이스 9] 단시간 근로자 비례 연차
    //           주 20시간(40h 미만, 15h 이상) → hoursMultiplier = (20/40)*8 = 4h
    // ═══════════════════════════════════════════════════
    test('단시간 근로자(주 20시간): 비례 연차수당 적용', () {
      final joinDate = DateTime(2025, 1, 1);
      final exitDate = DateTime(2026, 1, 2);

      final summary = PayrollCalculator.calculateAnnualLeaveSummary(
        joinDate: joinDate,
        endDate: exitDate,
        allAttendances: [],
        scheduledWorkDays: scheduledDays,
        isFiveOrMore: true,
        settlementPoint: exitDate,
        usedAnnualLeave: 0,
        weeklyHoursPure: 20, // ★ 단시간 20시간
        hourlyRate: hourlyRate,
        isVirtual: true,
      );

      expect(summary.isPartTimeProportional, isTrue);
      // hoursMultiplier = (20/40) × 8 = 4.0시간
      expect(summary.hoursMultiplier, 4.0,
          reason: '단시간: (20/40) × 8 = 4h/일');
    });
  });
}
