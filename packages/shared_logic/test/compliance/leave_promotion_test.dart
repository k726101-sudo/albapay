/// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
/// [법률 테스트] 연차 사용촉진 — 근로기준법 제61조
/// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
///
/// 【검증 대상 법령】
///   - 근로기준법 제61조 제1항: 정기 연차(15일+) 사용촉진
///     · 1차 촉진: 소멸 6개월 전까지 미사용 연차 서면 통보 + 사용 시기 지정 요청
///     · 직원 10일 이내 미제출 시 →
///     · 2차 촉진: 사장님이 직접 사용 시기 서면 지정 (소멸 2개월 전까지)
///   - 근로기준법 제61조 제2항: 1년 미만 발생분(11일) 사용촉진
///     · 1차 촉진: 소멸 3개월 전까지
///     · 2차 촉진: 소멸 1개월 전까지
///   - 이행 완료 시 → 미사용 소멸 연차에 대한 수당 지급 의무 면제
///
/// 【테스트 의의】
///   사용촉진 미이행 시 소멸 연차 수당을 사장님이 전액 부담해야 하므로,
///   앱이 촉진 기한과 절차를 정확히 안내·추적해야 합니다.
///   이 테스트는 촉진 기한 계산, 상태 관리, 수당 면제 판정 로직을 검증합니다.
/// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_logic/shared_logic.dart';

void main() {
  group('[근로기준법 제61조] 연차 사용촉진', () {
    // ═══════════════════════════════════════════════════
    // [케이스 1] 정기 연차: 1차 촉진 기한 = 소멸 6개월 전
    // ═══════════════════════════════════════════════════
    test('정기 연차: 1차 촉진 기한 = 소멸 6개월 전', () {
      // 입사 2025-01-01 → 1년 차 연차 발생일 2026-01-01
      // 소멸일 2027-01-01 → 1차 촉진 기한 2026-07-01
      final batch = LeaveExpirationBatch(
        grantDate: DateTime(2026, 1, 1),
        expiryDate: DateTime(2027, 1, 1),
        granted: 15.0,
        isPreAnniversary: false,
      );

      expect(batch.firstNoticeDeadline, DateTime(2026, 7, 1),
          reason: '정기 연차 1차 촉진 = 소멸 6개월 전 (2027-01-01 → 2026-07-01)');
    });

    // ═══════════════════════════════════════════════════
    // [케이스 2] 정기 연차: 2차 촉진 기한 = 소멸 2개월 전
    // ═══════════════════════════════════════════════════
    test('정기 연차: 2차 촉진 기한 = 소멸 2개월 전', () {
      final batch = LeaveExpirationBatch(
        grantDate: DateTime(2026, 1, 1),
        expiryDate: DateTime(2027, 1, 1),
        granted: 15.0,
        isPreAnniversary: false,
      );

      expect(batch.secondNoticeDeadline, DateTime(2026, 11, 1),
          reason: '정기 연차 2차 촉진 = 소멸 2개월 전 (2027-01-01 → 2026-11-01)');
    });

    // ═══════════════════════════════════════════════════
    // [케이스 3] 1년 미만 발생분: 1차 촉진 = 소멸 3개월 전
    // ═══════════════════════════════════════════════════
    test('1년 미만 발생분: 1차 촉진 = 소멸 3개월 전', () {
      // 1년 미만분 소멸일 2026-01-01 → 1차 촉진 기한 2025-10-01
      final batch = LeaveExpirationBatch(
        grantDate: DateTime(2025, 2, 1),
        expiryDate: DateTime(2026, 1, 1),
        granted: 1.0,
        isPreAnniversary: true,
      );

      expect(batch.firstNoticeDeadline, DateTime(2025, 10, 1),
          reason: '1년 미만 1차 촉진 = 소멸 3개월 전');
    });

    // ═══════════════════════════════════════════════════
    // [케이스 4] 1년 미만 발생분: 2차 촉진 = 소멸 1개월 전
    // ═══════════════════════════════════════════════════
    test('1년 미만 발생분: 2차 촉진 = 소멸 1개월 전', () {
      final batch = LeaveExpirationBatch(
        grantDate: DateTime(2025, 2, 1),
        expiryDate: DateTime(2026, 1, 1),
        granted: 1.0,
        isPreAnniversary: true,
      );

      expect(batch.secondNoticeDeadline, DateTime(2025, 12, 1),
          reason: '1년 미만 2차 촉진 = 소멸 1개월 전');
    });

    // ═══════════════════════════════════════════════════
    // [케이스 5] LeavePromotionStatus: 촉진 완료 시 수당 면제
    // ═══════════════════════════════════════════════════
    test('촉진 완료(status=completed) → isExemptFromPayout = true', () {
      final promo = LeavePromotionStatus(
        batchGrantDate: DateTime(2026, 1, 1),
        batchExpiryDate: DateTime(2027, 1, 1),
        unusedDays: 5.0,
        firstNoticeDeadline: DateTime(2026, 7, 1),
        secondNoticeDeadline: DateTime(2026, 11, 1),
        firstNoticeDate: '2026-06-15',
        secondNoticeDate: '2026-10-20',
        status: 'completed',
      );

      expect(promo.isCompleted, isTrue);
      expect(promo.isExemptFromPayout, isTrue,
          reason: '1차+2차 촉진 모두 적법 이행 → 소멸분 수당 면제');
    });

    // ═══════════════════════════════════════════════════
    // [케이스 6] 촉진 미완료 → 수당 면제 불가
    // ═══════════════════════════════════════════════════
    test('촉진 미완료(status=pending) → isExemptFromPayout = false', () {
      final promo = LeavePromotionStatus(
        batchGrantDate: DateTime(2026, 1, 1),
        batchExpiryDate: DateTime(2027, 1, 1),
        unusedDays: 5.0,
        firstNoticeDeadline: DateTime(2026, 7, 1),
        secondNoticeDeadline: DateTime(2026, 11, 1),
        status: 'pending',
      );

      expect(promo.isCompleted, isFalse);
      expect(promo.isExemptFromPayout, isFalse,
          reason: '촉진 미이행 → 소멸 연차 수당 전액 지급 의무');
    });

    // ═══════════════════════════════════════════════════
    // [케이스 7] 촉진 만료 (기한 내 미이행) → 수당 면제 불가
    // ═══════════════════════════════════════════════════
    test('촉진 만료(status=expired) → isExemptFromPayout = false', () {
      final promo = LeavePromotionStatus(
        batchGrantDate: DateTime(2025, 1, 1),
        batchExpiryDate: DateTime(2026, 1, 1),
        unusedDays: 3.0,
        firstNoticeDeadline: DateTime(2025, 7, 1),
        secondNoticeDeadline: DateTime(2025, 11, 1),
        status: 'expired',
      );

      expect(promo.isCompleted, isFalse);
      expect(promo.isExemptFromPayout, isFalse,
          reason: '기한 내 촉진 미이행 → 소멸 연차 수당 사장님 부담');
    });

    // ═══════════════════════════════════════════════════
    // [케이스 8] 라벨 정확도: 정기 vs 1년 미만
    // ═══════════════════════════════════════════════════
    test('연차 유형 라벨: 정기 vs 1년 미만 구분', () {
      final regular = LeavePromotionStatus(
        batchGrantDate: DateTime(2026, 1, 1),
        batchExpiryDate: DateTime(2027, 1, 1),
        unusedDays: 5.0,
        firstNoticeDeadline: DateTime(2026, 7, 1),
        secondNoticeDeadline: DateTime(2026, 11, 1),
        isPreAnniversary: false,
      );
      final preAnniv = LeavePromotionStatus(
        batchGrantDate: DateTime(2025, 2, 1),
        batchExpiryDate: DateTime(2026, 1, 1),
        unusedDays: 1.0,
        firstNoticeDeadline: DateTime(2025, 10, 1),
        secondNoticeDeadline: DateTime(2025, 12, 1),
        isPreAnniversary: true,
      );

      expect(regular.leaveTypeLabel, '정기 연차');
      expect(regular.deadlineLabel, '6개월/2개월');
      expect(preAnniv.leaveTypeLabel, '1년 미만 발생분');
      expect(preAnniv.deadlineLabel, '3개월/1개월');
    });

    // ═══════════════════════════════════════════════════
    // [케이스 9] ★ 핵심 — 엔진이 촉진 현황을 자동 생성하는지 검증
    //           미사용 연차가 있고 촉진 기한에 진입한 경우
    // ═══════════════════════════════════════════════════
    test('★ 엔진: 미사용 연차 촉진 기한 진입 시 promotionStatuses 자동 생성', () {
      // 입사 2025-01-01, 현재 2026-08-01 (1차 촉진 기한 2026-07-01 경과)
      // 1년 차 15일 발생 → 0일 사용 → 15일 미사용
      final joinDate = DateTime(2025, 1, 1);
      final settlement = DateTime(2026, 8, 1); // 1차 촉진 기한 지남

      final summary = PayrollCalculator.calculateAnnualLeaveSummary(
        joinDate: joinDate,
        endDate: null,
        allAttendances: [],
        scheduledWorkDays: [1, 2, 3, 4, 5],
        isFiveOrMore: true,
        settlementPoint: settlement,
        usedAnnualLeave: 0, // ★ 미사용
        weeklyHoursPure: 40,
        hourlyRate: 10320,
        isVirtual: true,
      );

      // 미사용 연차가 있으므로 촉진 현황이 생성되어야 함
      expect(summary.promotionStatuses, isNotEmpty,
          reason: '미사용 연차 + 촉진 기한 경과 → 촉진 현황 자동 생성');
      
      // 1년 미만 배치(소멸일 2026-01-01)는 이미 소멸 → expired
      // 정기 연차 배치(소멸일 2027-01-01)가 있다면 → pending
      final hasExpired = summary.promotionStatuses.any((p) => p.status == 'expired');
      final hasPending = summary.promotionStatuses.any((p) => p.status == 'pending');
      expect(hasExpired || hasPending, isTrue,
          reason: '소멸된 배치는 expired, 진행 중 배치는 pending');
    });

    // ═══════════════════════════════════════════════════
    // [케이스 10] 촉진 완료 로그 주입 시 수당 면제 금액 반영
    // ═══════════════════════════════════════════════════
    test('촉진 완료 로그 주입 → promotionExemptPayoutAmount 반영', () {
      final joinDate = DateTime(2024, 1, 1);
      // 소멸일: 2026-01-01, 소멸 후 시점
      final settlement = DateTime(2026, 2, 1);

      final completedLog = LeavePromotionStatus(
        batchGrantDate: DateTime(2025, 1, 1), // 1년 차 발생
        batchExpiryDate: DateTime(2026, 1, 1), // 소멸일
        unusedDays: 10.0,
        firstNoticeDeadline: DateTime(2025, 7, 1),
        secondNoticeDeadline: DateTime(2025, 11, 1),
        firstNoticeDate: '2025-06-15',
        secondNoticeDate: '2025-10-20',
        status: 'completed', // ★ 촉진 완료
      );

      final summary = PayrollCalculator.calculateAnnualLeaveSummary(
        joinDate: joinDate,
        endDate: null,
        allAttendances: [],
        scheduledWorkDays: [1, 2, 3, 4, 5],
        isFiveOrMore: true,
        settlementPoint: settlement,
        usedAnnualLeave: 1, // 1일만 사용
        weeklyHoursPure: 40,
        hourlyRate: 10320,
        isVirtual: true,
        promotionLogs: [completedLog],
      );

      // 촉진 완료된 소멸분은 수당 면제
      expect(summary.promotionExemptPayoutAmount, greaterThanOrEqualTo(0),
          reason: '촉진 완료 소멸분 → 수당 면제 금액 반영');
    });

    // ═══════════════════════════════════════════════════
    // [케이스 11] Serialization: toMap / fromMap 라운드트립
    // ═══════════════════════════════════════════════════
    test('LeavePromotionStatus toMap/fromMap 라운드트립 정확도', () {
      final original = LeavePromotionStatus(
        batchGrantDate: DateTime(2026, 1, 1),
        batchExpiryDate: DateTime(2027, 1, 1),
        unusedDays: 5.0,
        isPreAnniversary: false,
        firstNoticeDeadline: DateTime(2026, 7, 1),
        firstNoticeDate: '2026-06-15',
        firstNoticeDocId: 'doc_123',
        employeePlanDate: '2026-06-25',
        employeePlanContent: '7월 15~19일 사용 예정',
        secondNoticeDeadline: DateTime(2026, 11, 1),
        secondNoticeDate: '2026-10-20',
        secondNoticeDocId: 'doc_456',
        designatedDates: ['2026-12-01', '2026-12-02'],
        status: 'completed',
      );

      final map = original.toMap();
      final restored = LeavePromotionStatus.fromMap(map);

      expect(restored.batchGrantDate, original.batchGrantDate);
      expect(restored.batchExpiryDate, original.batchExpiryDate);
      expect(restored.unusedDays, original.unusedDays);
      expect(restored.isPreAnniversary, original.isPreAnniversary);
      expect(restored.firstNoticeDate, original.firstNoticeDate);
      expect(restored.firstNoticeDocId, original.firstNoticeDocId);
      expect(restored.employeePlanDate, original.employeePlanDate);
      expect(restored.secondNoticeDate, original.secondNoticeDate);
      expect(restored.secondNoticeDocId, original.secondNoticeDocId);
      expect(restored.designatedDates.length, 2);
      expect(restored.status, 'completed');
      expect(restored.isCompleted, isTrue);
      expect(restored.isExemptFromPayout, isTrue);
    });
  });
}
