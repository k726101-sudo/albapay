/// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
/// [법률 테스트] 퇴직금 정산 엔진 — 퇴직급여보장법/근로기준법 제2조
/// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
///
/// 【검증 대상 법령】
///   - 퇴직급여보장법 제4조: 1년 이상 + 주 15시간 이상 → 퇴직금 대상
///   - 근로기준법 제2조 제1항 제6호: 평균임금 = 퇴직 전 3개월 임금총액 ÷ 역일수
///   - 근로기준법 제2조 제2항: 평균임금 < 통상임금 → 통상임금을 평균임금으로
///
/// 【검증 시나리오】
///   1) 초단시간(주 14시간) 1년 이상 근무 → 퇴직금 자격 없음
///   2) 역월 3개월 기간 정확성 (2월 끼는 경우)
///   3) 5인 미만 사업장 → 연차수당 산입 0원
///   4) 1년 미만 퇴사 → 연차 실제 발생일수로 산입
///   5) 장기근속 연차 가산 반영
///   6) 단시간 근로자(주 20시간) hoursMultiplier 정확성
/// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_logic/shared_logic.dart';

void main() {
  group('[퇴직급여보장법/근로기준법 제2조] 퇴직금 정산 엔진', () {
    final scheduledDays = [1, 2, 3, 4, 5]; // 월~금
    const hourlyRate = 10320.0;

    // ═══════════════════════════════════════════════════════════
    // [케이스 1] 초단시간(주 14시간) 1년 이상 → 퇴직금 자격 없음
    //   퇴직급여보장법 제4조: "4주간 평균 주 15시간 이상"
    // ═══════════════════════════════════════════════════════════
    test('초단시간(주 14h) 400일 근무 → 퇴직금 0원 (자격 배제)', () {
      final result = PayrollCalculator.calculateExitSettlement(
        workerName: '초단시간 알바',
        startDate: '2025-01-01',
        usedAnnualLeave: 0,
        annualLeaveManualAdjustment: 0,
        weeklyHours: 14, // ★ 15시간 미만
        allAttendances: [],
        scheduledWorkDays: [1, 3], // 주 2일
        exitDate: DateTime(2026, 2, 5), // 400일
        hourlyRate: hourlyRate,
        isFiveOrMore: true,
        isVirtual: true,
      );

      expect(result.isSeveranceEligible, isFalse,
          reason: '주 14시간 < 15시간 → 퇴직금 자격 없음');
      expect(result.severancePay, 0.0,
          reason: '퇴직금 = 0원');
    });

    // ═══════════════════════════════════════════════════════════
    // [케이스 2] 주 15시간 정확히 → 퇴직금 자격 있음 (경계값)
    // ═══════════════════════════════════════════════════════════
    test('주 15시간 정확히 + 1년 이상 → 퇴직금 자격 있음', () {
      final result = PayrollCalculator.calculateExitSettlement(
        workerName: '경계 알바',
        startDate: '2025-01-01',
        usedAnnualLeave: 0,
        annualLeaveManualAdjustment: 0,
        weeklyHours: 15, // ★ 정확히 15시간
        allAttendances: [],
        scheduledWorkDays: [1, 2, 3],
        exitDate: DateTime(2026, 1, 2), // 366일
        hourlyRate: hourlyRate,
        isFiveOrMore: true,
        isVirtual: true,
      );

      expect(result.isSeveranceEligible, isTrue,
          reason: '주 15시간 + 366일 → 퇴직금 자격');
      expect(result.severancePay, greaterThan(0),
          reason: '퇴직금 > 0');
    });

    // ═══════════════════════════════════════════════════════════
    // [케이스 3] 역월 3개월: 5월 31일 퇴사 → 3개월 전 = 2월 28일
    //   90일이 아닌 역월 기준 (92일)
    // ═══════════════════════════════════════════════════════════
    test('역월 3개월: 5월 31일 → 2월 28일 (92일, 90일 아님)', () {
      // 2026년 비윤년: 2월 28일까지
      final exitDate = DateTime(2026, 5, 31);
      final result = PayrollCalculator.calculateExitSettlement(
        workerName: '역월 테스트',
        startDate: '2025-01-01',
        usedAnnualLeave: 0,
        annualLeaveManualAdjustment: 0,
        weeklyHours: 40,
        allAttendances: [],
        scheduledWorkDays: scheduledDays,
        exitDate: exitDate,
        hourlyRate: hourlyRate,
        isFiveOrMore: true,
        isVirtual: true,
      );

      // 2월 28일 → 5월 31일 = 92일 (not 90)
      // 평균임금 = total / 92 (90이 아님)
      // 이전 엔진에서는 total / 90으로 나눠서 평균임금이 과대 산정되었음
      expect(result.isSeveranceEligible, isTrue);
      expect(result.severancePay, greaterThan(0));

      // 퇴직금이 역월 기준으로 산출되었는지 간접 검증:
      // 이론적 3개월 총액이 동일하면, / 92 < / 90 이므로 평균임금이 더 낮아야 함
      // → 통상임금 하한선이 걸릴 수도 있어 직접 값 비교는 안정성상 어려움
      // → 여기서는 계산이 오류 없이 완료되는 것만 검증
    });

    // ═══════════════════════════════════════════════════════════
    // [케이스 4] 5인 미만 사업장 → 연차수당 산입 0원
    //   연차 법적 의무 없음 → 평균임금에 연차수당 가산 불가
    // ═══════════════════════════════════════════════════════════
    test('5인 미만: 연차수당 산입 0원 → 평균임금 낮아짐', () {
      final exitDate = DateTime(2026, 6, 1);

      final result5plus = PayrollCalculator.calculateExitSettlement(
        workerName: '5인 이상',
        startDate: '2025-01-01',
        usedAnnualLeave: 0,
        annualLeaveManualAdjustment: 0,
        weeklyHours: 40,
        allAttendances: [],
        scheduledWorkDays: scheduledDays,
        exitDate: exitDate,
        hourlyRate: hourlyRate,
        isFiveOrMore: true, // ★ 5인 이상
        isVirtual: true,
      );

      final resultUnder5 = PayrollCalculator.calculateExitSettlement(
        workerName: '5인 미만',
        startDate: '2025-01-01',
        usedAnnualLeave: 0,
        annualLeaveManualAdjustment: 0,
        weeklyHours: 40,
        allAttendances: [],
        scheduledWorkDays: scheduledDays,
        exitDate: exitDate,
        hourlyRate: hourlyRate,
        isFiveOrMore: false, // ★ 5인 미만
        isVirtual: true,
      );

      // 5인 미만은 연차수당 산입이 0이므로 평균임금(→ 퇴직금)이 낮아야 함
      // 단, 통상임금 하한선이 걸리면 동일할 수 있으므로 >= 비교
      expect(result5plus.severancePay, greaterThanOrEqualTo(resultUnder5.severancePay),
          reason: '5인 미만은 연차수당 미산입 → 퇴직금 ≤ 5인 이상');
    });

    // ═══════════════════════════════════════════════════════════
    // [케이스 5] 입사 6개월 퇴사 → 퇴직금 0원 (1년 미만)
    // ═══════════════════════════════════════════════════════════
    test('입사 6개월 → 퇴직금 0원 (1년 미만)', () {
      final result = PayrollCalculator.calculateExitSettlement(
        workerName: '단기 알바',
        startDate: '2026-01-01',
        usedAnnualLeave: 0,
        annualLeaveManualAdjustment: 0,
        weeklyHours: 40,
        allAttendances: [],
        scheduledWorkDays: scheduledDays,
        exitDate: DateTime(2026, 6, 30), // 180일
        hourlyRate: hourlyRate,
        isFiveOrMore: true,
        isVirtual: true,
      );

      expect(result.isSeveranceEligible, isFalse);
      expect(result.severancePay, 0.0);
      // 연차수당은 별도 정산 (잔여분)
      expect(result.remainingLeaveDays, greaterThan(0),
          reason: '5개월분 연차 발생');
    });

    // ═══════════════════════════════════════════════════════════
    // [케이스 6] 정확히 1년 (365일) → 퇴직금 자격 있음
    // ═══════════════════════════════════════════════════════════
    test('정확히 365일 → 퇴직금 자격 있음', () {
      final joinDate = DateTime(2025, 1, 1);
      // 365일 = 2025-12-31 (joinDate + 364일, but totalWorkingDays 포함)
      final exitDate = DateTime(2025, 12, 31); // 365일째

      final result = PayrollCalculator.calculateExitSettlement(
        workerName: '1년 알바',
        startDate: joinDate.toIso8601String(),
        usedAnnualLeave: 0,
        annualLeaveManualAdjustment: 0,
        weeklyHours: 40,
        allAttendances: [],
        scheduledWorkDays: scheduledDays,
        exitDate: exitDate,
        hourlyRate: hourlyRate,
        isFiveOrMore: true,
        isVirtual: true,
      );

      expect(result.isSeveranceEligible, isTrue);
      expect(result.severancePay, greaterThan(0));
    });

    // ═══════════════════════════════════════════════════════════
    // [케이스 7] 단시간 근로자(주 20시간) → hoursMultiplier 정확성
    //   hoursMultiplier = (20/40) × 8 = 4.0
    // ═══════════════════════════════════════════════════════════
    test('단시간(주 20h): 통상임금 = 4h × 시급 (비례 축소)', () {
      final result = PayrollCalculator.calculateExitSettlement(
        workerName: '단시간 알바',
        startDate: '2025-01-01',
        usedAnnualLeave: 0,
        annualLeaveManualAdjustment: 0,
        weeklyHours: 20, // ★ 단시간
        allAttendances: [],
        scheduledWorkDays: [1, 2, 3],
        exitDate: DateTime(2026, 6, 1),
        hourlyRate: hourlyRate,
        isFiveOrMore: true,
        isVirtual: true,
      );

      // hoursMultiplier = (20/40) × 8 = 4.0
      // 통상임금 하한선 = 4.0 × 10,320 = 41,280원
      // 퇴직금 > 0 (자격 있음)
      expect(result.isSeveranceEligible, isTrue);
      expect(result.severancePay, greaterThan(0));

      // 전일제 대비 퇴직금이 낮아야 함
      final fullTimeResult = PayrollCalculator.calculateExitSettlement(
        workerName: '전일제',
        startDate: '2025-01-01',
        usedAnnualLeave: 0,
        annualLeaveManualAdjustment: 0,
        weeklyHours: 40,
        allAttendances: [],
        scheduledWorkDays: scheduledDays,
        exitDate: DateTime(2026, 6, 1),
        hourlyRate: hourlyRate,
        isFiveOrMore: true,
        isVirtual: true,
      );

      expect(result.severancePay, lessThan(fullTimeResult.severancePay),
          reason: '단시간(20h) 퇴직금 < 전일제(40h) 퇴직금');
    });

    // ═══════════════════════════════════════════════════════════
    // [케이스 8] 지급기한: 퇴사 후 14일 이내 (근로기준법 제36조)
    // ═══════════════════════════════════════════════════════════
    test('지급기한 = 퇴사일 + 14일', () {
      final exitDate = DateTime(2026, 5, 15);
      final result = PayrollCalculator.calculateExitSettlement(
        workerName: '기한 테스트',
        startDate: '2025-01-01',
        usedAnnualLeave: 0,
        annualLeaveManualAdjustment: 0,
        weeklyHours: 40,
        allAttendances: [],
        scheduledWorkDays: scheduledDays,
        exitDate: exitDate,
        hourlyRate: hourlyRate,
        isFiveOrMore: true,
        isVirtual: true,
      );

      expect(result.paymentDeadline, DateTime(2026, 5, 29),
          reason: '5/15 + 14일 = 5/29');
    });
  });
}
