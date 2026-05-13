/// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
/// [법률 테스트] 연차유급휴가 발생 규칙 검증
/// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
///
/// 【법적 근거】
///   근로기준법 제60조
///   - 제1항: 1년간 80% 이상 출근한 근로자에게 15일의 유급휴가
///   - 제2항: 1년 미만 근로자, 1년간 80% 미만 출근한 근로자에게
///            1개월 개근 시 1일의 유급휴가
///
/// 【검증 시나리오】
///   A. 1년 미만 — 매월 만근 시 최대 11개 발생
///   B. 1년 미만 — 3개월 결근 → 8개 발생 (결근 달은 미발생)
///   C. 1년 경과 — 출근율 80% 이상 → 15개 발생 (+ 1년 미만분)
///   D. 1년 경과 — 출근율 80% 미만 → 1년차 15개 차단
///   E. 2년 경과 — 1년차 15 + 2년차 16 = 31 (+ 1년 미만분)
///   F. 5인 미만 사업장 → 연차 법적 의무 없음 (0개)
///   G. 초단시간 근로자 (주 15시간 미만) → 연차 대상 아님 (0개)
/// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_logic/shared_logic.dart';

/// 출근 기록 생성 헬퍼
Attendance _shift(String staffId, DateTime date) {
  return Attendance(
    id: '${staffId}_${date.toIso8601String()}',
    staffId: staffId,
    storeId: 'store_test',
    clockIn: DateTime(date.year, date.month, date.day, 9),
    clockOut: DateTime(date.year, date.month, date.day, 18),
    type: AttendanceType.web,
  );
}

/// 지정 기간의 모든 소정근로일에 출근 기록 생성
List<Attendance> _fullAttendance(
  String staffId,
  DateTime from,
  DateTime to,
  List<int> workDays,
) {
  final shifts = <Attendance>[];
  for (var d = from; !d.isAfter(to); d = d.add(const Duration(days: 1))) {
    if (workDays.contains(d.weekday)) {
      shifts.add(_shift(staffId, d));
    }
  }
  return shifts;
}

void main() {
  group('[근로기준법 제60조] 연차유급휴가 발생 규칙 검증', () {
    const hourlyRate = 10320.0;
    const staffId = 'worker_leave';
    final workDays = [1, 2, 3, 4, 5]; // 월~금

    // ═══════════════════════════════════════════════════
    // [시나리오 A] 1년 미만, 매월 만근 → 최대 11개
    //   제60조 제2항: "1년 미만 근로자… 1개월 개근 시 1일"
    // ═══════════════════════════════════════════════════
    test('시나리오 A: 1년 미만 매월 만근 → 11개 발생', () {
      final joinDate = DateTime(2025, 7, 1);
      // 입사 11개월 후 정산 (1년 미만)
      final settlement = DateTime(2026, 6, 1);

      final attendances = _fullAttendance(
        staffId,
        joinDate,
        settlement,
        workDays,
      );

      final summary = PayrollCalculator.calculateAnnualLeaveSummary(
        joinDate: joinDate,
        endDate: null,
        allAttendances: attendances,
        scheduledWorkDays: workDays,
        isFiveOrMore: true,
        settlementPoint: settlement,
        usedAnnualLeave: 0,
        weeklyHoursPure: 40,
        hourlyRate: hourlyRate,
      );

      expect(summary.totalGenerated, 11.0,
          reason: '1년 미만: 매월 1개 × 11개월 = 11개');

      print('✅ 시나리오 A: ${summary.totalGenerated}개 발생 (1년 미만 매월 만근)');
    });

    // ═══════════════════════════════════════════════════
    // [시나리오 B] 1년 미만, 3개월 결근 → 8개 발생
    // ═══════════════════════════════════════════════════
    test('시나리오 B: 1년 미만, 3개월 결근 → 8개 발생', () {
      final joinDate = DateTime(2025, 7, 1);
      final settlement = DateTime(2026, 6, 1);

      // 11개월 중 3개월(9,10,11월)은 출근 기록 없음
      final attendances = <Attendance>[
        ..._fullAttendance(staffId, DateTime(2025, 7, 1), DateTime(2025, 8, 31), workDays),
        // 9, 10, 11월 결근
        ..._fullAttendance(staffId, DateTime(2025, 12, 1), DateTime(2026, 5, 31), workDays),
      ];

      final summary = PayrollCalculator.calculateAnnualLeaveSummary(
        joinDate: joinDate,
        endDate: null,
        allAttendances: attendances,
        scheduledWorkDays: workDays,
        isFiveOrMore: true,
        settlementPoint: settlement,
        usedAnnualLeave: 0,
        weeklyHoursPure: 40,
        hourlyRate: hourlyRate,
      );

      expect(summary.totalGenerated, 8.0,
          reason: '11개월 - 결근 3개월 = 8개 발생');

      print('✅ 시나리오 B: ${summary.totalGenerated}개 발생 (3개월 결근)');
    });

    // ═══════════════════════════════════════════════════
    // [시나리오 C] 1년 경과, 출근율 80% 이상 → 15개 + 1년 미만분
    //   제60조 제1항: "1년간 80% 이상 출근 → 15일"
    // ═══════════════════════════════════════════════════
    test('시나리오 C: 1년 경과 + 출근율 80% → 15개 발생 (+ 1년 미만분)', () {
      final joinDate = DateTime(2025, 1, 1);
      final settlement = DateTime(2026, 1, 2); // 1년 + 1일

      final attendances = _fullAttendance(
        staffId,
        joinDate,
        settlement,
        workDays,
      );

      final summary = PayrollCalculator.calculateAnnualLeaveSummary(
        joinDate: joinDate,
        endDate: null,
        allAttendances: attendances,
        scheduledWorkDays: workDays,
        isFiveOrMore: true,
        settlementPoint: settlement,
        usedAnnualLeave: 0,
        weeklyHoursPure: 40,
        hourlyRate: hourlyRate,
      );

      // 1년 미만: 11개 + 1년차: 15개 = 26개
      expect(summary.totalGenerated, 26.0,
          reason: '1년 미만 11개 + 1년차 15개 = 26개');

      print('✅ 시나리오 C: ${summary.totalGenerated}개 (11 + 15)');
    });

    // ═══════════════════════════════════════════════════
    // [시나리오 D] 1년 경과, 출근율 80% 미만 → 15개 차단
    //   제60조 제1항 반대해석: 80% 미만이면 15일 미발생
    // ═══════════════════════════════════════════════════
    test('시나리오 D: 1년 경과 + 출근율 80% 미만 → 15개 차단', () {
      final joinDate = DateTime(2025, 1, 1);
      final settlement = DateTime(2026, 1, 2);

      // 1년 중 약 6개월만 출근 (출근율 ~50%)
      final attendances = _fullAttendance(
        staffId,
        DateTime(2025, 1, 1),
        DateTime(2025, 6, 30),
        workDays,
      );

      final summary = PayrollCalculator.calculateAnnualLeaveSummary(
        joinDate: joinDate,
        endDate: null,
        allAttendances: attendances,
        scheduledWorkDays: workDays,
        isFiveOrMore: true,
        settlementPoint: settlement,
        usedAnnualLeave: 0,
        weeklyHoursPure: 40,
        hourlyRate: hourlyRate,
      );

      // 1년 미만: 6개 (1~6월 만근) + 1년차: 0개 (80% 미달) = 6개
      expect(summary.totalGenerated, 6.0,
          reason: '출근율 80% 미만 → 1년차 15개 차단, 1년 미만 6개만 발생');

      // blockedAnnualRateDetail이 존재하고 passed=false여야 함
      expect(summary.blockedAnnualRateDetail, isNotNull,
          reason: '출근율 80% 미달 정보가 기록되어야 함');
      expect(summary.blockedAnnualRateDetail!.passed, isFalse,
          reason: '80% 미만 → passed=false');

      print('✅ 시나리오 D: ${summary.totalGenerated}개 (15개 차단!)');
      print('   출근율: ${(summary.blockedAnnualRateDetail!.rate * 100).toStringAsFixed(1)}%');
    });

    // ═══════════════════════════════════════════════════
    // [시나리오 E] 5인 미만 사업장 → 0개
    // ═══════════════════════════════════════════════════
    test('시나리오 E: 5인 미만 사업장 → 연차 법적 의무 없음 (0개)', () {
      final joinDate = DateTime(2025, 1, 1);
      final settlement = DateTime(2026, 1, 2);

      final summary = PayrollCalculator.calculateAnnualLeaveSummary(
        joinDate: joinDate,
        endDate: null,
        allAttendances: [],
        scheduledWorkDays: workDays,
        isFiveOrMore: false, // ★ 5인 미만
        settlementPoint: settlement,
        usedAnnualLeave: 0,
        weeklyHoursPure: 40,
        hourlyRate: hourlyRate,
        isVirtual: true,
      );

      expect(summary.totalGenerated, 0,
          reason: '5인 미만 사업장: 연차 법적 의무 없음');

      print('✅ 시나리오 E: ${summary.totalGenerated}개 (5인 미만)');
    });

    // ═══════════════════════════════════════════════════
    // [시나리오 F] 초단시간 근로자 (주 15시간 미만) → 0개
    //   근로기준법 제18조 제3항
    // ═══════════════════════════════════════════════════
    test('시나리오 F: 초단시간 근로자 (주 14시간) → 연차 대상 아님 (0개)', () {
      final joinDate = DateTime(2025, 1, 1);
      final settlement = DateTime(2026, 1, 2);

      final summary = PayrollCalculator.calculateAnnualLeaveSummary(
        joinDate: joinDate,
        endDate: null,
        allAttendances: [],
        scheduledWorkDays: workDays,
        isFiveOrMore: true,
        settlementPoint: settlement,
        usedAnnualLeave: 0,
        weeklyHoursPure: 14, // ★ 15시간 미만
        hourlyRate: hourlyRate,
        isVirtual: true,
      );

      expect(summary.totalGenerated, 0,
          reason: '초단시간 근로자(주 14h): 연차 대상 아님 (제18조 제3항)');

      print('✅ 시나리오 F: ${summary.totalGenerated}개 (초단시간 근로자)');
    });
  });
}
