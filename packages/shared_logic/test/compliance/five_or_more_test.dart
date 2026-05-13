/// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
/// [법률 테스트] 상시 근로자 수 판정 — 근로기준법 시행령 제7조의2
/// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
///
/// 【검증 대상 법령】
///   근로기준법 시행령 제7조의2(상시 사용하는 근로자 수의 산정 방법)
///   - 제1항: 해당 사업 또는 사업장에서 법 적용 사유 발생일 전 1개월 동안
///            사용한 근로자의 연인원을 같은 기간 중의 가동 일수로 나누어 산정
///   - 제2항 예외: 산정한 수가 5명 미만이더라도, 근로자 5명 이상인 날이
///            가동일수의 1/2 이상이면 5인 이상 사업장으로 본다.
///            반대로 5명 이상이더라도, 5명 미만인 날이 1/2 이상이면 5인 미만.
///
/// 【테스트 의의】
///   이 테스트가 실패하면 5인 이상/미만 판정이 틀어져,
///   야간·연장·휴일 가산수당(1.5배)이 적용되어야 할 사업장에서 누락되거나
///   역으로 불필요한 가산수당이 발생하여 사장님에게 직접적 금전 피해를 줄 수 있습니다.
///   → 앱의 존폐가 걸린 핵심 로직입니다.
/// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_logic/shared_logic.dart';

void main() {
  group('[근로기준법 시행령 제7조의2] 상시 근로자 수 판정', () {
    // ─────────────────────────────────────────
    // Helper: 특정 날짜에 N명의 출퇴근 기록 생성
    // ─────────────────────────────────────────
    List<Attendance> _makeAttendances(Map<DateTime, int> dailyCounts) {
      final list = <Attendance>[];
      int idx = 0;
      dailyCounts.forEach((date, count) {
        for (int i = 0; i < count; i++) {
          list.add(Attendance(
            id: 'att_${idx++}',
            staffId: 'staff_$i',
            storeId: 'store_1',
            clockIn: DateTime(date.year, date.month, date.day, 9, 0),
            clockOut: DateTime(date.year, date.month, date.day, 18, 0),
            type: AttendanceType.web,
          ));
        }
      });
      return list;
    }

    // ═══════════════════════════════════════════════════
    // [케이스 1] 단순 평균 5인 이상 → true
    // ═══════════════════════════════════════════════════
    test('단순 평균 5인 이상이면 5인 이상 사업장', () {
      // 7일간 매일 6명 근무 → 평균 6.0
      final atts = _makeAttendances({
        for (int d = 1; d <= 7; d++) DateTime(2026, 4, d): 6,
      });
      final result = PayrollCalculator.isFiveOrMore(
        settlementAttendances: atts,
        periodStart: DateTime(2026, 4, 1),
        periodEnd: DateTime(2026, 4, 7),
      );
      expect(result, isTrue, reason: '평균 6.0명 → 5인 이상');
    });

    // ═══════════════════════════════════════════════════
    // [케이스 2] 단순 평균 5인 미만 → false
    // ═══════════════════════════════════════════════════
    test('단순 평균 5인 미만이고 과반수 예외도 해당 없으면 5인 미만', () {
      // 7일간 매일 3명 근무 → 평균 3.0, 5인 이상인 날 0일
      final atts = _makeAttendances({
        for (int d = 1; d <= 7; d++) DateTime(2026, 4, d): 3,
      });
      final result = PayrollCalculator.isFiveOrMore(
        settlementAttendances: atts,
        periodStart: DateTime(2026, 4, 1),
        periodEnd: DateTime(2026, 4, 7),
      );
      expect(result, isFalse, reason: '평균 3.0명, 5인 이상 근무일 0일 → 5인 미만');
    });

    // ═══════════════════════════════════════════════════
    // [케이스 3] ★ 핵심 — 평균 5인 미만이지만 과반수 예외로 5인 이상
    //           (이 케이스가 기존 엔진에서 누락되었던 치명적 버그)
    // ═══════════════════════════════════════════════════
    test('★ 평균 5인 미만이지만 5인 이상 근무일이 가동일수의 1/2 이상이면 5인 이상 (예외 조항)', () {
      // 월~목(4일): 5명 / 금~일(3일): 1명 → 총 23명/7일 = 평균 3.28명
      // BUT 5인 이상 근무일: 4일 ≥ 7/2=3.5 → 과반수 충족 → 5인 이상 판정
      final atts = _makeAttendances({
        DateTime(2026, 4, 6): 5,  // 월
        DateTime(2026, 4, 7): 5,  // 화
        DateTime(2026, 4, 8): 5,  // 수
        DateTime(2026, 4, 9): 5,  // 목
        DateTime(2026, 4, 10): 1, // 금
        DateTime(2026, 4, 11): 1, // 토
        DateTime(2026, 4, 12): 1, // 일
      });
      final result = PayrollCalculator.isFiveOrMore(
        settlementAttendances: atts,
        periodStart: DateTime(2026, 4, 6),
        periodEnd: DateTime(2026, 4, 12),
      );
      expect(result, isTrue,
          reason: '평균 3.28명이지만 5인 이상 근무일이 4일(≥3.5) → 시행령 제7조의2 예외 적용');
    });

    // ═══════════════════════════════════════════════════
    // [케이스 4] ★ 역방향 — 평균 5인 이상이지만 과반수 예외로 5인 미만
    // ═══════════════════════════════════════════════════
    test('★ 평균 5인 이상이지만 5인 미만 근무일이 가동일수의 1/2 이상이면 5인 미만 (역방향 예외)', () {
      // 월(1일): 20명 / 화~일(6일): 2명 → 총 32명/7일 = 평균 4.57명
      // 사실 평균이 5 미만이므로 이건 자연스럽게 false... 더 극단적으로:
      // 월(1일): 30명 / 화~토(5일): 2명 → 총 40명/6일 = 평균 6.67명
      // BUT 5인 미만 근무일: 5일 ≥ 6/2=3 → 과반수 미달 → 5인 미만 판정
      final atts = _makeAttendances({
        DateTime(2026, 4, 6): 30,  // 월 - 대량 투입
        DateTime(2026, 4, 7): 2,   // 화
        DateTime(2026, 4, 8): 2,   // 수
        DateTime(2026, 4, 9): 2,   // 목
        DateTime(2026, 4, 10): 2,  // 금
        DateTime(2026, 4, 11): 2,  // 토
      });
      final result = PayrollCalculator.isFiveOrMore(
        settlementAttendances: atts,
        periodStart: DateTime(2026, 4, 6),
        periodEnd: DateTime(2026, 4, 11),
      );
      expect(result, isFalse,
          reason: '평균 6.67명이지만 5인 미만 근무일이 5일(≥3) → 역방향 예외 적용');
    });

    // ═══════════════════════════════════════════════════
    // [케이스 5] 경계값 — 정확히 과반수(1/2) 도달 시
    // ═══════════════════════════════════════════════════
    test('경계값: 5인 이상 근무일이 정확히 가동일수의 절반일 때 5인 이상 판정', () {
      // 6일 중 3일이 5인 이상 → 3 >= 6/2=3.0 → 5인 이상
      final atts = _makeAttendances({
        DateTime(2026, 4, 6): 5,   // 월
        DateTime(2026, 4, 7): 5,   // 화
        DateTime(2026, 4, 8): 5,   // 수
        DateTime(2026, 4, 9): 2,   // 목
        DateTime(2026, 4, 10): 2,  // 금
        DateTime(2026, 4, 11): 2,  // 토
      });
      final result = PayrollCalculator.isFiveOrMore(
        settlementAttendances: atts,
        periodStart: DateTime(2026, 4, 6),
        periodEnd: DateTime(2026, 4, 11),
      );
      expect(result, isTrue,
          reason: '5인 이상 3일 ≥ 가동 6일/2=3.0 → 경계 충족');
    });

    // ═══════════════════════════════════════════════════
    // [케이스 6] 경계값 — 과반수에 1일 미달 시
    // ═══════════════════════════════════════════════════
    test('경계값: 5인 이상 근무일이 과반수에 1일 미달하면 5인 미만', () {
      // 7일 중 3일이 5인 이상 → 3 < 7/2=3.5 → 5인 미만
      final atts = _makeAttendances({
        DateTime(2026, 4, 6): 5,   // 월
        DateTime(2026, 4, 7): 5,   // 화
        DateTime(2026, 4, 8): 5,   // 수
        DateTime(2026, 4, 9): 2,   // 목
        DateTime(2026, 4, 10): 2,  // 금
        DateTime(2026, 4, 11): 2,  // 토
        DateTime(2026, 4, 12): 2,  // 일
      });
      final result = PayrollCalculator.isFiveOrMore(
        settlementAttendances: atts,
        periodStart: DateTime(2026, 4, 6),
        periodEnd: DateTime(2026, 4, 12),
      );
      expect(result, isFalse,
          reason: '5인 이상 3일 < 가동 7일/2=3.5 → 과반수 미달');
    });

    // ═══════════════════════════════════════════════════
    // [케이스 7] 가동일이 0일 (무영업)
    // ═══════════════════════════════════════════════════
    test('가동일 0일(기록 없음)이면 5인 미만 판정', () {
      final result = PayrollCalculator.isFiveOrMore(
        settlementAttendances: [],
        periodStart: DateTime(2026, 4, 1),
        periodEnd: DateTime(2026, 4, 30),
      );
      expect(result, isFalse, reason: '출퇴근 기록 없음 → 가동일 0 → false');
    });

    // ═══════════════════════════════════════════════════
    // [케이스 8] 정확히 5명이 매일 근무
    // ═══════════════════════════════════════════════════
    test('매일 정확히 5명 근무 → 5인 이상', () {
      final atts = _makeAttendances({
        for (int d = 1; d <= 30; d++) DateTime(2026, 4, d): 5,
      });
      final result = PayrollCalculator.isFiveOrMore(
        settlementAttendances: atts,
        periodStart: DateTime(2026, 4, 1),
        periodEnd: DateTime(2026, 4, 30),
      );
      expect(result, isTrue, reason: '매일 정확히 5명 → 평균 5.0 → 5인 이상');
    });

    // ═══════════════════════════════════════════════════
    // [케이스 9] 가상매장 시뮬레이션 (알바페이 데모 모드 재현)
    //           8명 직원이 교대 근무하는 실제 운영 시나리오
    // ═══════════════════════════════════════════════════
    test('★ 알바페이 데모 모드 재현: 8명 교대근무 → 예외 조항으로 5인 이상', () {
      // 월~목(4일): 김점장+이주간+박오전+최오후+강야간 = 5명
      // 금(1일): 김점장+정금욜 = 2명
      // 토(1일): 조토욜 = 1명
      // 일(1일): 윤일욜 = 1명
      // 총 연인원: 5*4 + 2 + 1 + 1 = 23명 / 가동 7일 = 평균 3.28명
      // BUT 5인 이상 근무일: 4일 ≥ 7/2=3.5 → 5인 이상
      final atts = <Attendance>[];
      final workers = ['김점장', '이주간', '박오전', '최오후', '강야간'];
      // 1주일 시뮬레이션: 2026년 4월 6일(월) ~ 12일(일)
      for (int d = 6; d <= 9; d++) {
        // 월~목: 5명
        for (int w = 0; w < workers.length; w++) {
          atts.add(Attendance(
            id: 'att_${d}_$w',
            staffId: 'worker_${workers[w]}',
            storeId: 'demo_store',
            clockIn: DateTime(2026, 4, d, 9, 0),
            clockOut: DateTime(2026, 4, d, 18, 0),
            type: AttendanceType.web,
          ));
        }
      }
      // 금: 김점장 + 정금욜
      for (final name in ['김점장', '정금욜']) {
        atts.add(Attendance(
          id: 'att_10_$name',
          staffId: 'worker_$name',
          storeId: 'demo_store',
          clockIn: DateTime(2026, 4, 10, 9, 0),
          clockOut: DateTime(2026, 4, 10, 18, 0),
          type: AttendanceType.web,
        ));
      }
      // 토: 조토욜
      atts.add(Attendance(
        id: 'att_11_조토욜',
        staffId: 'worker_조토욜',
        storeId: 'demo_store',
        clockIn: DateTime(2026, 4, 11, 12, 0),
        clockOut: DateTime(2026, 4, 11, 21, 0),
        type: AttendanceType.web,
      ));
      // 일: 윤일욜
      atts.add(Attendance(
        id: 'att_12_윤일욜',
        staffId: 'worker_윤일욜',
        storeId: 'demo_store',
        clockIn: DateTime(2026, 4, 12, 12, 0),
        clockOut: DateTime(2026, 4, 12, 21, 0),
        type: AttendanceType.web,
      ));

      final result = PayrollCalculator.isFiveOrMore(
        settlementAttendances: atts,
        periodStart: DateTime(2026, 4, 6),
        periodEnd: DateTime(2026, 4, 12),
      );
      expect(result, isTrue,
          reason: '데모 매장: 평균 3.28명이지만 4일(월~목)이 5인 이상 → 예외 적용 → 5인 이상');
    });

    // ═══════════════════════════════════════════════════
    // [케이스 10] 1개월(30일) 장기 시뮬레이션
    // ═══════════════════════════════════════════════════
    test('1개월(30일) 장기: 과반수 예외가 장기에서도 정확히 동작', () {
      // 30일 중 16일이 5인 이상, 14일이 3인 → 16 >= 30/2=15 → 5인 이상
      final map = <DateTime, int>{};
      for (int d = 1; d <= 16; d++) {
        map[DateTime(2026, 4, d)] = 6;
      }
      for (int d = 17; d <= 30; d++) {
        map[DateTime(2026, 4, d)] = 3;
      }
      final atts = _makeAttendances(map);
      final result = PayrollCalculator.isFiveOrMore(
        settlementAttendances: atts,
        periodStart: DateTime(2026, 4, 1),
        periodEnd: DateTime(2026, 4, 30),
      );
      expect(result, isTrue,
          reason: '16일 ≥ 15 → 과반수 충족');
    });
  });
}
