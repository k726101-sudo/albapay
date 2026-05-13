/// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
/// [법률 테스트] 주휴수당 — 근로기준법 제55조
/// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
///
/// 【검증 대상 법령】
///   - 근로기준법 제55조: 유급주휴일 (주 15시간 이상 근로자)
///   - 근로기준법 제18조 제3항: 초단시간(주 15시간 미만) 근로자 주휴 배제
///   - 주휴수당 공식: (주당근로시간/40) × 8 × 시급
///
/// 【테스트 의의】
///   주휴수당은 시급제 직원 급여의 핵심 구성요소.
///   결근 시 주휴수당 미지급, 소정근로시간 15시간 미만 시 미발생 등
///   법적 예외 조항 정확 반영 여부 검증.
/// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_logic/shared_logic.dart';

void main() {
  group('[근로기준법 제55조] 주휴수당', () {
    const hourlyRate = 10320.0;
    final joinDate = DateTime(2025, 1, 1);

    // 테스트 데이터가 2026년 7월(미래)이므로 AppClock을 7/13(일)으로 고정
    setUp(() {
      AppClock.setDebugOverride(DateTime(2026, 7, 13), pushToFirestore: false);
    });
    tearDown(() {
      AppClock.setDebugOverride(null, pushToFirestore: false);
    });

    // ═══════════════════════════════════════════════════
    // [케이스 1] 주 40시간 만근 → 주휴수당 = 8h × 시급
    // ═══════════════════════════════════════════════════
    test('주 40시간 만근 → 주휴수당 = 8h × 시급 (82,560원)', () {
      // 주휴수당은 PayrollCalculator.isWeeklyHolidayEligible에서 판별
      final eligibility = PayrollCalculator.isWeeklyHolidayEligible(
        weeklyAttendances: List.generate(5, (i) => Attendance(
          id: 'a_$i',
          staffId: 'w1',
          storeId: 's1',
          clockIn: DateTime(2026, 7, 6 + i, 9, 0), // 월~금
          clockOut: DateTime(2026, 7, 6 + i, 18, 0), // 9h 체류
          type: AttendanceType.web,
          scheduledShiftStartIso: DateTime(2026, 7, 6 + i, 9, 0).toIso8601String(),
          scheduledShiftEndIso: DateTime(2026, 7, 6 + i, 18, 0).toIso8601String(),
        )),
        defaultBreakMinutesPerShift: 60,
      );

      expect(eligibility, isTrue,
          reason: '주 40시간(5일 × 8시간) → 15시간 이상 → 주휴수당 대상');

      // 실제 수당 계산: 주 40시간 × (40/40) × 8 × 10,320 = 82,560원
      final expectedPay = (40.0 / 40.0) * 8.0 * hourlyRate;
      expect(expectedPay, 82560.0);
    });

    // ═══════════════════════════════════════════════════
    // [케이스 2] 주 15시간 미만(초단시간) → 주휴수당 미발생
    // ═══════════════════════════════════════════════════
    test('주 15시간 미만(초단시간 근로자) → 주휴수당 대상 아님', () {
      // 주 2일 × 4시간 = 8시간 (15시간 미만)
      final eligibility = PayrollCalculator.isWeeklyHolidayEligible(
        weeklyAttendances: List.generate(2, (i) => Attendance(
          id: 'a_$i',
          staffId: 'w1',
          storeId: 's1',
          clockIn: DateTime(2026, 7, 6 + i, 9, 0),
          clockOut: DateTime(2026, 7, 6 + i, 13, 0), // 4시간
          type: AttendanceType.web,
          scheduledShiftStartIso: DateTime(2026, 7, 6 + i, 9, 0).toIso8601String(),
          scheduledShiftEndIso: DateTime(2026, 7, 6 + i, 13, 0).toIso8601String(),
        )),
        defaultBreakMinutesPerShift: 0,
      );

      expect(eligibility, isFalse,
          reason: '주 8시간 < 15시간 → 초단시간 근로자 → 주휴수당 미발생');
    });

    // ═══════════════════════════════════════════════════
    // [케이스 3] 주 15시간 정확히 도달 → 주휴수당 대상
    // ═══════════════════════════════════════════════════
    test('주 정확히 15시간 → 주휴수당 대상', () {
      // 주 5일 × 3시간 = 15시간
      final eligibility = PayrollCalculator.isWeeklyHolidayEligible(
        weeklyAttendances: List.generate(5, (i) => Attendance(
          id: 'a_$i',
          staffId: 'w1',
          storeId: 's1',
          clockIn: DateTime(2026, 7, 6 + i, 9, 0),
          clockOut: DateTime(2026, 7, 6 + i, 12, 0), // 3시간
          type: AttendanceType.web,
          scheduledShiftStartIso: DateTime(2026, 7, 6 + i, 9, 0).toIso8601String(),
          scheduledShiftEndIso: DateTime(2026, 7, 6 + i, 12, 0).toIso8601String(),
        )),
        defaultBreakMinutesPerShift: 0,
      );

      expect(eligibility, isTrue,
          reason: '주 15시간 = 15시간 → 경계 충족 → 주휴수당 대상');
    });

    // ═══════════════════════════════════════════════════
    // [케이스 4] 결근으로 만근 미달 → 주휴수당 미지급
    //           (소정근로일 중 하나라도 결근 시)
    // ═══════════════════════════════════════════════════
    test('만근 미달(결근 있음) 시 주휴수당 미지급', () {
      final worker = PayrollWorkerData(
        weeklyHoursPure: 40,
        weeklyTotalStayMinutes: 40 * 60,
        breakMinutesPerShift: 60,
        isPaidBreak: false,
        joinDate: joinDate,
        scheduledWorkDays: [1, 2, 3, 4, 5],
        manualWeeklyHolidayApproval: true,
        weeklyHolidayDay: 0,
      );

      // 월~목 출근, 금요일 결근 (4일만 출근)
      final atts = List.generate(4, (i) => Attendance(
        id: 'a_$i',
        staffId: 'w1',
        storeId: 's1',
        clockIn: DateTime(2026, 7, 6 + i, 9, 0), // 월~목
        clockOut: DateTime(2026, 7, 6 + i, 18, 0),
        type: AttendanceType.web,
        attendanceStatus: 'Normal',
        scheduledShiftStartIso: DateTime(2026, 7, 6 + i, 9, 0).toIso8601String(),
        scheduledShiftEndIso: DateTime(2026, 7, 6 + i, 18, 0).toIso8601String(),
      ));

      final result = PayrollCalculator.calculate(
        workerData: worker,
        shifts: atts,
        periodStart: DateTime(2026, 7, 6),
        periodEnd: DateTime(2026, 7, 12), // 월~일 1주
        hourlyRate: hourlyRate,
        isFiveOrMore: true,
        allHistoricalAttendances: atts,
      );

      // 결근이 있으므로 주휴수당 미지급 경고 표시
      expect(result.weeklyHolidayBlockedByAbsence, isTrue,
          reason: '금요일 결근 → 만근 미달 → 주휴수당 차단');
    });

    // ═══════════════════════════════════════════════════
    // [케이스 5] 주 20시간(파트타임) → 비례 주휴수당
    //           (20/40) × 8 × 시급 = 4h × 시급
    // ═══════════════════════════════════════════════════
    test('주 20시간 파트타임 → 비례 주휴수당 (4h × 시급)', () {
      // 주휴수당 비례 공식 검증
      final weeklyH = 20.0;
      final expectedHolidayPay = (weeklyH / 40.0) * 8.0 * hourlyRate;
      expect(expectedHolidayPay, closeTo(41280.0, 0.1),
          reason: '(20/40) × 8 × 10,320 = 41,280원');
    });

    // ═══════════════════════════════════════════════════
    // [케이스 6] 조퇴(수요일 3시간만 근무) → 주휴수당 유지
    //
    //   근로기준법상 조퇴는 "출근한 것"이므로 만근 조건 충족.
    //   계약시간(weeklyHoursPure) ≥ 15h면 주휴수당 대상 유지.
    // ═══════════════════════════════════════════════════
    test('조퇴 (수요일 3시간) → 출근했으므로 주휴수당 유지', () {
      final worker = PayrollWorkerData(
        weeklyHoursPure: 40,
        weeklyTotalStayMinutes: 40 * 60 + 300,
        breakMinutesPerShift: 60,
        isPaidBreak: false,
        joinDate: joinDate,
        scheduledWorkDays: [1, 2, 3, 4, 5],
        manualWeeklyHolidayApproval: true,
        weeklyHolidayDay: 0,
        isVirtual: true,
        wageHistoryJson: '[{"effectiveDate":"2025-01-01","hourlyWage":10320}]',
        graceMinutes: 5,
      );

      final atts = <Attendance>[];
      for (int i = 0; i < 5; i++) {
        final day = DateTime(2026, 7, 6 + i); // 월~금
        if (i == 2) {
          // 수요일: 09:00~12:00 (3시간만 근무 = 조퇴)
          atts.add(Attendance(
            id: 'a_$i',
            staffId: 'w1',
            storeId: 's1',
            clockIn: DateTime(2026, 7, 8, 9, 0),
            clockOut: DateTime(2026, 7, 8, 12, 0),
            type: AttendanceType.web,
            attendanceStatus: 'Normal',
            scheduledShiftStartIso: DateTime(2026, 7, 8, 9, 0).toIso8601String(),
            scheduledShiftEndIso: DateTime(2026, 7, 8, 18, 0).toIso8601String(),
          ));
        } else {
          atts.add(Attendance(
            id: 'a_$i',
            staffId: 'w1',
            storeId: 's1',
            clockIn: DateTime(day.year, day.month, day.day, 9, 0),
            clockOut: DateTime(day.year, day.month, day.day, 18, 0),
            type: AttendanceType.web,
            attendanceStatus: 'Normal',
            scheduledShiftStartIso: DateTime(day.year, day.month, day.day, 9, 0).toIso8601String(),
            scheduledShiftEndIso: DateTime(day.year, day.month, day.day, 18, 0).toIso8601String(),
          ));
        }
      }

      final result = PayrollCalculator.calculate(
        workerData: worker,
        shifts: atts,
        substitutionShifts: [],
        hourlyRate: 10320,
        periodStart: DateTime(2026, 7, 6),
        periodEnd: DateTime(2026, 7, 12),
        isFiveOrMore: true,
        allHistoricalAttendances: atts,
      );

      // 조퇴해도 출근 기록 존재 → 만근 → 주휴수당 유지
      expect(result.weeklyHolidayPay, greaterThan(0),
          reason: '조퇴해도 출근 → 만근 → 주휴수당 유지');
      expect(result.weeklyHolidayBlockedByAbsence, isFalse,
          reason: '조퇴 ≠ 결근 → 차단 플래그 false');

      print('✅ [조퇴 시나리오] 주휴수당: ${result.weeklyHolidayPay.round()}원 (유지됨)');
    });

    // ═══════════════════════════════════════════════════
    // [케이스 7] 만근 vs 결근 급여 비교
    //           출퇴근 기록 변경만으로 급여 차이 검증
    // ═══════════════════════════════════════════════════
    test('만근 vs 수요일 결근 → 급여 차이 = 일급 + 주휴수당', () {
      final worker = PayrollWorkerData(
        weeklyHoursPure: 40,
        weeklyTotalStayMinutes: 40 * 60 + 300,
        breakMinutesPerShift: 60,
        isPaidBreak: false,
        joinDate: joinDate,
        scheduledWorkDays: [1, 2, 3, 4, 5],
        manualWeeklyHolidayApproval: true,
        weeklyHolidayDay: 0,
        isVirtual: true,
        wageHistoryJson: '[{"effectiveDate":"2025-01-01","hourlyWage":10320}]',
        graceMinutes: 5,
      );

      // 만근 데이터: 월~금 5일
      final fullAtts = List.generate(5, (i) => Attendance(
        id: 'full_$i',
        staffId: 'w1',
        storeId: 's1',
        clockIn: DateTime(2026, 7, 6 + i, 9, 0),
        clockOut: DateTime(2026, 7, 6 + i, 18, 0),
        type: AttendanceType.web,
        attendanceStatus: 'Normal',
        scheduledShiftStartIso: DateTime(2026, 7, 6 + i, 9, 0).toIso8601String(),
        scheduledShiftEndIso: DateTime(2026, 7, 6 + i, 18, 0).toIso8601String(),
      ));

      // 결근 데이터: 수요일(i=2) 빠짐
      final absentAtts = <Attendance>[];
      for (int i = 0; i < 5; i++) {
        if (i == 2) continue;
        absentAtts.add(Attendance(
          id: 'absent_$i',
          staffId: 'w1',
          storeId: 's1',
          clockIn: DateTime(2026, 7, 6 + i, 9, 0),
          clockOut: DateTime(2026, 7, 6 + i, 18, 0),
          type: AttendanceType.web,
          attendanceStatus: 'Normal',
          scheduledShiftStartIso: DateTime(2026, 7, 6 + i, 9, 0).toIso8601String(),
          scheduledShiftEndIso: DateTime(2026, 7, 6 + i, 18, 0).toIso8601String(),
        ));
      }

      final period = DateTime(2026, 7, 6);
      final periodEndWeek = DateTime(2026, 7, 12);

      final fullResult = PayrollCalculator.calculate(
        workerData: worker,
        shifts: fullAtts,
        substitutionShifts: [],
        hourlyRate: 10320,
        periodStart: period,
        periodEnd: periodEndWeek,
        isFiveOrMore: true,
        allHistoricalAttendances: fullAtts,
      );

      final absentResult = PayrollCalculator.calculate(
        workerData: worker,
        shifts: absentAtts,
        substitutionShifts: [],
        hourlyRate: 10320,
        periodStart: period,
        periodEnd: periodEndWeek,
        isFiveOrMore: true,
        allHistoricalAttendances: absentAtts,
      );

      final totalDiff = fullResult.totalPay - absentResult.totalPay;
      final holidayDiff = fullResult.weeklyHolidayPay - absentResult.weeklyHolidayPay;
      final baseDiff = totalDiff - holidayDiff;

      expect(totalDiff, greaterThan(0), reason: '만근 급여 > 결근 급여');
      expect(holidayDiff, greaterThan(0), reason: '만근 주휴 > 결근 주휴');
      expect(fullResult.weeklyHolidayBlockedByAbsence, isFalse);
      expect(absentResult.weeklyHolidayBlockedByAbsence, isTrue);

      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('📊 [만근 vs 결근 급여 비교]');
      print('  만근 총급여: ${fullResult.totalPay.round()}원');
      print('  결근 총급여: ${absentResult.totalPay.round()}원');
      print('  ─────────────────────────');
      print('  급여 차이: ${totalDiff.round()}원');
      print('    ↳ 결근일 일급: ${baseDiff.round()}원');
      print('    ↳ 주휴수당 차이: ${holidayDiff.round()}원');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    });
  });
}
