/// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
/// [법률 테스트] 결근 시 주휴수당 — 사장님 승인 스위치 Override 검증
/// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
///
/// 【핵심 쟁점】
///   결근이 감지되면 주휴수당이 자동 차단(weeklyHolidayBlockedByAbsence)되지만,
///   사장님이 [지급 승인] 스위치(manualWeeklyHolidayApproval)를 켜면
///   차단이 해제되어 주휴수당이 정상 지급되어야 한다.
///
///   이는 사장님이 쉬라고 한 경우(휴업) 등 무단결근이 아닌 상황에서
///   임금체불을 방지하기 위한 수동 Override 메커니즘이다.
///
/// 【검증 시나리오】
///   주 5일 계약(월~금), 시급 10,320원
///   - 시나리오 A: 만근(5일) → 주휴수당 정상 지급 (기준선)
///   - 시나리오 B: 결근(4일) + 스위치 OFF → 주휴수당 0원 (자동 차단)
///   - 시나리오 C: 결근(4일) + 스위치 ON  → 주휴수당 정상 지급 (Override)
///   - 시나리오 D: 결근(4일) + 스위치 ON  → weeklyHolidayBlockedByAbsence는 여전히 true
///                (UI 경고는 유지하되, 지급만 진행)
/// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_logic/shared_logic.dart';

void main() {
  group('[결근 + 승인 스위치] 주휴수당 Override 검증', () {
    const double hourlyRate = 10320.0;
    const staffId = 'worker_test';

    // 테스트 데이터가 2026년 6월(미래)이므로 AppClock을 6/22(월)으로 고정
    setUp(() {
      AppClock.setDebugOverride(DateTime(2026, 6, 22), pushToFirestore: false);
    });
    tearDown(() {
      AppClock.setDebugOverride(null, pushToFirestore: false);
    });

    Attendance _shift(DateTime date, int startH, int endH) {
      return Attendance(
        id: '${staffId}_${date.toIso8601String()}',
        staffId: staffId,
        storeId: 'store_1',
        clockIn: DateTime(date.year, date.month, date.day, startH),
        clockOut: DateTime(date.year, date.month, date.day, endH),
        type: AttendanceType.web,
        attendanceStatus: 'Normal',
      );
    }

    PayrollWorkerData _makeWorker({required bool approvalOn}) {
      return PayrollWorkerData(
        joinDate: DateTime(2025, 1, 1),
        scheduledWorkDays: [1, 2, 3, 4, 5], // 월~금
        weeklyHoursPure: 40,
        weeklyTotalStayMinutes: 40 * 60,
        breakMinutesPerShift: 60,
        isPaidBreak: false,
        isProbation: false,
        probationMonths: 0,
        wageType: 'hourly',
        monthlyWage: 0,
        fixedOvertimeHours: 0,
        fixedOvertimePay: 0,
        mealAllowance: 0,
        mealTaxExempt: false,
        allowanceAmounts: [],
        manualWeeklyHolidayApproval: approvalOn, // ★ 핵심 변수
        weeklyHolidayDay: 0,
        previousMonthAdjustment: 0,
        usedAnnualLeave: 0,
        isVirtual: true,
        wageHistoryJson: '',
        breakStartTime: '',
        breakEndTime: '',
      );
    }

    // 테스트 기간: 1주일 (월~일)
    final periodStart = DateTime(2026, 6, 15); // 월요일
    final periodEnd = DateTime(2026, 6, 21);   // 일요일

    // 만근 출석 (월~금 09:00~18:00)
    final fullWeekShifts = [
      _shift(DateTime(2026, 6, 15), 9, 18), // 월
      _shift(DateTime(2026, 6, 16), 9, 18), // 화
      _shift(DateTime(2026, 6, 17), 9, 18), // 수
      _shift(DateTime(2026, 6, 18), 9, 18), // 목
      _shift(DateTime(2026, 6, 19), 9, 18), // 금
    ];

    // 결근 출석 (금요일 빠짐)
    final absentShifts = [
      _shift(DateTime(2026, 6, 15), 9, 18), // 월
      _shift(DateTime(2026, 6, 16), 9, 18), // 화
      _shift(DateTime(2026, 6, 17), 9, 18), // 수
      _shift(DateTime(2026, 6, 18), 9, 18), // 목
      // 금요일 없음 → 결근
    ];

    // ═══════════════════════════════════════════════════
    // [시나리오 A] 기준선: 만근 + 스위치 ON → 주휴수당 정상 지급
    // ═══════════════════════════════════════════════════
    test('시나리오 A: 만근 → 주휴수당 정상 지급 (기준선)', () {
      final result = PayrollCalculator.calculate(
        workerData: _makeWorker(approvalOn: true),
        shifts: fullWeekShifts,
        periodStart: periodStart,
        periodEnd: periodEnd,
        hourlyRate: hourlyRate,
        isFiveOrMore: true,
        allHistoricalAttendances: fullWeekShifts,
      );

      expect(result.weeklyHolidayPay, greaterThan(0),
          reason: '만근 → 주휴수당 발생');
      expect(result.weeklyHolidayBlockedByAbsence, isFalse,
          reason: '만근 → 결근 차단 없음');

      // 주휴수당 = (32/40) × 8 × 10,320 = 66,048원
      // (실 근로 32h, 계약 40h 기준 비례)
      print('✅ 시나리오 A: 주휴수당 = ${result.weeklyHolidayPay}원');
    });

    // ═══════════════════════════════════════════════════
    // [시나리오 B] 결근 + 스위치 OFF → 주휴수당 0원
    // ═══════════════════════════════════════════════════
    test('시나리오 B: 결근 + 스위치 OFF → 주휴수당 0원 (자동 차단)', () {
      final result = PayrollCalculator.calculate(
        workerData: _makeWorker(approvalOn: false),
        shifts: absentShifts,
        periodStart: periodStart,
        periodEnd: periodEnd,
        hourlyRate: hourlyRate,
        isFiveOrMore: true,
        allHistoricalAttendances: absentShifts,
      );

      expect(result.weeklyHolidayPay, 0,
          reason: '결근 + 스위치 OFF → 주휴수당 0원');
      expect(result.weeklyHolidayBlockedByAbsence, isTrue,
          reason: '결근 감지됨');

      print('✅ 시나리오 B: 주휴수당 = ${result.weeklyHolidayPay}원 (차단됨)');
    });

    // ═══════════════════════════════════════════════════
    // [시나리오 C] ★ 핵심: 결근 + 스위치 ON → 주휴수당 정상 지급
    // ═══════════════════════════════════════════════════
    test('시나리오 C: ★ 결근 + 스위치 ON → 주휴수당 정상 지급 (Override)', () {
      final result = PayrollCalculator.calculate(
        workerData: _makeWorker(approvalOn: true),
        shifts: absentShifts,
        periodStart: periodStart,
        periodEnd: periodEnd,
        hourlyRate: hourlyRate,
        isFiveOrMore: true,
        allHistoricalAttendances: absentShifts,
      );

      // ★ 핵심: 스위치 ON이면 결근이어도 주휴수당 지급
      expect(result.weeklyHolidayPay, greaterThan(0),
          reason: '결근이지만 스위치 ON → 주휴수당 지급 (사장님 Override)');

      print('✅ 시나리오 C: 주휴수당 = ${result.weeklyHolidayPay}원 (Override 지급)');
    });

    // ═══════════════════════════════════════════════════
    // [시나리오 D] 스위치 ON이어도 결근 경고는 유지
    //   → UI에서 사장님에게 경고를 보여주되, 지급은 진행
    // ═══════════════════════════════════════════════════
    test('시나리오 D: 스위치 ON이어도 weeklyHolidayBlockedByAbsence = true (경고 유지)', () {
      final result = PayrollCalculator.calculate(
        workerData: _makeWorker(approvalOn: true),
        shifts: absentShifts,
        periodStart: periodStart,
        periodEnd: periodEnd,
        hourlyRate: hourlyRate,
        isFiveOrMore: true,
        allHistoricalAttendances: absentShifts,
      );

      // 경고 플래그는 여전히 true (UI에서 "결근 감지 (수동 승인됨)" 표시)
      expect(result.weeklyHolidayBlockedByAbsence, isTrue,
          reason: '결근 사실 자체는 유지 → UI 경고 카드 표시');

      // 하지만 지급은 진행됨
      expect(result.weeklyHolidayPay, greaterThan(0),
          reason: '경고는 유지하되 지급은 Override');

      print('✅ 시나리오 D: blocked=${result.weeklyHolidayBlockedByAbsence}, 주휴수당=${result.weeklyHolidayPay}원');
    });

    // ═══════════════════════════════════════════════════
    // [시나리오 E] 시나리오 B와 C의 차이 = 순수 스위치 효과
    // ═══════════════════════════════════════════════════
    test('시나리오 E: 스위치 OFF→ON 전환 시 주휴수당 차이 = Override 효과', () {
      final resultOff = PayrollCalculator.calculate(
        workerData: _makeWorker(approvalOn: false),
        shifts: absentShifts,
        periodStart: periodStart,
        periodEnd: periodEnd,
        hourlyRate: hourlyRate,
        isFiveOrMore: true,
        allHistoricalAttendances: absentShifts,
      );

      final resultOn = PayrollCalculator.calculate(
        workerData: _makeWorker(approvalOn: true),
        shifts: absentShifts,
        periodStart: periodStart,
        periodEnd: periodEnd,
        hourlyRate: hourlyRate,
        isFiveOrMore: true,
        allHistoricalAttendances: absentShifts,
      );

      expect(resultOff.weeklyHolidayPay, 0, reason: 'OFF → 0원');
      expect(resultOn.weeklyHolidayPay, greaterThan(0), reason: 'ON → 지급');

      final difference = resultOn.weeklyHolidayPay - resultOff.weeklyHolidayPay;
      expect(difference, greaterThan(0),
          reason: '스위치 전환 효과: +${difference.toInt()}원');

      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('📊 [스위치 Override 효과]');
      print('  스위치 OFF: 주휴수당 = ${resultOff.weeklyHolidayPay.toInt()}원');
      print('  스위치 ON:  주휴수당 = ${resultOn.weeklyHolidayPay.toInt()}원');
      print('  ─────────────────────────');
      print('  Override 효과: +${difference.toInt()}원');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    });
  });
}
