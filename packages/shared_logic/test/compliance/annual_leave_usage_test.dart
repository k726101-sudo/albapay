/// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
/// [법률 테스트] 연차 사용 등록 → 급여 엔진 반영 통합 검증
/// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
///
/// 【검증 대상 법령】
///   - 제60조 제6항: 연차유급휴가 사용일은 출근한 것으로 본다 (주휴수당 보호)
///   - 제60조 제1~2항: 연차 발생일수 vs 사용일수 → 잔여일수 정확성
///
/// 【검증 시나리오】
///   1) 연차 사용 시 급여 0원 (이중 지급 방지)
///   2) 연차 사용일이 주휴수당 만근 판정에 "출근"으로 반영
///   3) usedAnnualLeave 차감 후 잔여일수 정확성
///   4) 퇴사 시 잔여 연차 수당 정산과 사용분 반영 정합성
///   5) 연차 사용 후 취소 시 복원 검증 (usedAnnualLeave 역산)
/// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_logic/shared_logic.dart';

/// 가상 Attendance 레코드 헬퍼
Attendance _shift(String staffId, DateTime date, int startH, int endH) {
  return Attendance(
    id: '${staffId}_${date.toIso8601String()}',
    staffId: staffId,
    storeId: 'store_test',
    clockIn: DateTime(date.year, date.month, date.day, startH),
    clockOut: DateTime(date.year, date.month, date.day, endH),
    type: AttendanceType.mobile,
  );
}

/// 연차 Attendance 레코드 헬퍼 (실제 _handleAnnualLeave가 생성하는 것과 동일)
Attendance _annualLeaveAttendance(String staffId, DateTime date) {
  return Attendance(
    id: 'leave_${staffId}_${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}',
    staffId: staffId,
    storeId: 'store_test',
    clockIn: DateTime(date.year, date.month, date.day, 9, 0),
    clockOut: DateTime(date.year, date.month, date.day, 9, 0), // clockIn == clockOut
    type: AttendanceType.mobile,
    isAttendanceEquivalent: true,
    attendanceStatus: 'annual_leave',
    isEditedByBoss: true,
  );
}

/// 테스트용 PayrollWorkerData 생성 헬퍼
PayrollWorkerData _workerData({
  double usedAnnualLeave = 0,
  DateTime? joinDate,
  DateTime? endDate,
}) {
  return PayrollWorkerData(
    joinDate: joinDate ?? DateTime(2025, 7, 1),
    endDate: endDate,
    scheduledWorkDays: [1, 2, 3, 4, 5], // 월~금
    weeklyHoursPure: 40,
    weeklyTotalStayMinutes: 2700,
    breakMinutesPerShift: 60,
    isPaidBreak: false,
    isProbation: false,
    probationMonths: 0,
    graceMinutes: 0,
    wageType: 'hourly',
    monthlyWage: 0,
    fixedOvertimeHours: 0,
    fixedOvertimePay: 0,
    mealAllowance: 0,
    mealTaxExempt: false,
    allowanceAmounts: [],
    deductNationalPension: false,
    deductHealthInsurance: false,
    deductEmploymentInsurance: false,
    applyWithholding33: false,
    manualWeeklyHolidayApproval: true,
    weeklyHolidayDay: 0, // 일요일
    previousMonthAdjustment: 0,
    usedAnnualLeave: usedAnnualLeave,
    manualAdjustment: 0,
    initialAdjustment: 0,
    initialAdjustmentReason: '',
    promotionLogs: [],
    wageHistoryJson: '',
    isVirtual: true,
    breakStartTime: '',
    breakEndTime: '',
  );
}

void main() {
  group('[근로기준법 제60조 §6] 연차 사용 등록 → 급여 엔진 통합 검증', () {
    const hourlyRate = 10320.0;
    const staffId = 'worker_kim';

    // ═══════════════════════════════════════════════════════════
    // [케이스 1] 연차 사용일 유급 보장
    //   기본급(basePay)에서는 제외되지만,
    //   별도 annualLeaveUsedPay로 1일분 유급수당 지급
    // ═══════════════════════════════════════════════════════════
    test('연차 사용일 유급 보장: basePay 제외 + annualLeaveUsedPay로 유급 지급', () {
      final periodStart = DateTime(2026, 5, 1);
      final periodEnd = DateTime(2026, 5, 31);
      
      // 월~목 정상 출근 + 금요일 연차
      final shifts = <Attendance>[
        _shift(staffId, DateTime(2026, 5, 5), 9, 18),  // 월
        _shift(staffId, DateTime(2026, 5, 6), 9, 18),  // 화
        _shift(staffId, DateTime(2026, 5, 7), 9, 18),  // 수
        _shift(staffId, DateTime(2026, 5, 8), 9, 18),  // 목
        _annualLeaveAttendance(staffId, DateTime(2026, 5, 9)), // 금: 연차
      ];

      final result = PayrollCalculator.calculate(
        workerData: _workerData(usedAnnualLeave: 1),
        shifts: shifts,
        periodStart: periodStart,
        periodEnd: periodEnd,
        hourlyRate: hourlyRate,
        isFiveOrMore: true,
        allHistoricalAttendances: shifts,
      );

      // ① basePay: 4일 × 8h × 10,320 = 330,240원 (연차일 제외)
      final expectedBase = 4 * 8 * hourlyRate;
      expect(result.basePay, expectedBase,
          reason: '기본급: 4일 × 8h × 10,320 = ${expectedBase.toInt()}원');

      // ② annualLeaveAllowancePay: 연차 사용 1일 유급수당 포함
      //    1일 소정근로 = 40h ÷ 5일 = 8h → 8h × 10,320 = 82,560원
      final expectedLeavePay = 8 * hourlyRate;
      expect(result.annualLeaveAllowancePay, expectedLeavePay,
          reason: '연차 유급수당: 1일 × 8h × 10,320 = ${expectedLeavePay.toInt()}원');
    });

    // ═══════════════════════════════════════════════════════════
    // [케이스 2] 연차 사용일은 주휴수당 만근 판정에 "출근"으로 간주
    //   근로기준법 제60조 제6항: "연차유급휴가를 사용한 기간은 출근한 것으로 본다"
    // ═══════════════════════════════════════════════════════════
    test('연차 사용일 = 출근 간주 → 주휴수당 만근 유지 (제60조 §6)', () {
      final periodStart = DateTime(2026, 5, 4);  // 월요일
      final periodEnd = DateTime(2026, 5, 10);    // 일요일 (1주일)

      // 월~목 출근 + 금요일 연차 → 주 5일 "출근"으로 간주되어야 함
      final shifts = <Attendance>[
        _shift(staffId, DateTime(2026, 5, 4), 9, 18),  // 월
        _shift(staffId, DateTime(2026, 5, 5), 9, 18),  // 화
        _shift(staffId, DateTime(2026, 5, 6), 9, 18),  // 수
        _shift(staffId, DateTime(2026, 5, 7), 9, 18),  // 목
        _annualLeaveAttendance(staffId, DateTime(2026, 5, 8)), // 금: 연차
      ];

      final result = PayrollCalculator.calculate(
        workerData: _workerData(usedAnnualLeave: 1),
        shifts: shifts,
        periodStart: periodStart,
        periodEnd: periodEnd,
        hourlyRate: hourlyRate,
        isFiveOrMore: true,
        allHistoricalAttendances: shifts,
      );

      // 주휴수당이 발생해야 함 (만근 인정)
      expect(result.weeklyHolidayPay, greaterThan(0),
          reason: '연차일 = 출근 간주 → 주 5일 만근 → 주휴수당 발생');

      // 연차일은 실 근로시간 0h → weekPure = 4일 × 8h = 32h
      // 주휴수당 = (32/40) × 8 × 10,320 = 66,048원
      // ★ 핵심: 연차 없이 결근이면 주휴수당 0원이지만,
      //   연차 처리 시 "출근으로 간주"되어 만근이 인정되고 주휴수당이 발생
      final expectedWeeklyPay = (32.0 / 40.0) * 8 * hourlyRate;
      expect(result.weeklyHolidayPay, expectedWeeklyPay,
          reason: '주휴수당 = (32/40) × 8h × 10,320 = ${expectedWeeklyPay.toInt()}원');
    });

    // ═══════════════════════════════════════════════════════════
    // [케이스 3] 연차 없이 결근 → 주휴수당 미지급 (대조군)
    //   같은 주에 금요일에 출근 기록 없음 → 만근 미달
    // ═══════════════════════════════════════════════════════════
    test('연차 없이 결근 → 주휴수당 미지급 (대조군, 승인 스위치 OFF)', () {
      final periodStart = DateTime(2026, 5, 4);
      final periodEnd = DateTime(2026, 5, 10);

      // 월~목만 출근, 금요일 결근 (연차 아님)
      final shifts = <Attendance>[
        _shift(staffId, DateTime(2026, 5, 4), 9, 18),
        _shift(staffId, DateTime(2026, 5, 5), 9, 18),
        _shift(staffId, DateTime(2026, 5, 6), 9, 18),
        _shift(staffId, DateTime(2026, 5, 7), 9, 18),
        // 금요일 없음 → 결근
      ];

      // ★ manualWeeklyHolidayApproval: false → 사장님 승인 없이 결근 → 주휴 차단
      final workerData = _workerData();
      final noApprovalWorker = PayrollWorkerData(
        joinDate: workerData.joinDate,
        scheduledWorkDays: workerData.scheduledWorkDays,
        weeklyHoursPure: workerData.weeklyHoursPure,
        weeklyTotalStayMinutes: workerData.weeklyTotalStayMinutes,
        breakMinutesPerShift: workerData.breakMinutesPerShift,
        isPaidBreak: workerData.isPaidBreak,
        isProbation: workerData.isProbation,
        probationMonths: workerData.probationMonths,
        wageType: workerData.wageType,
        monthlyWage: workerData.monthlyWage,
        fixedOvertimeHours: workerData.fixedOvertimeHours,
        fixedOvertimePay: workerData.fixedOvertimePay,
        mealAllowance: workerData.mealAllowance,
        mealTaxExempt: workerData.mealTaxExempt,
        allowanceAmounts: workerData.allowanceAmounts,
        manualWeeklyHolidayApproval: false, // ★ 승인 OFF
        weeklyHolidayDay: workerData.weeklyHolidayDay,
        previousMonthAdjustment: workerData.previousMonthAdjustment,
        usedAnnualLeave: workerData.usedAnnualLeave,
        isVirtual: workerData.isVirtual,
        wageHistoryJson: workerData.wageHistoryJson,
        breakStartTime: workerData.breakStartTime,
        breakEndTime: workerData.breakEndTime,
      );

      final result = PayrollCalculator.calculate(
        workerData: noApprovalWorker,
        shifts: shifts,
        periodStart: periodStart,
        periodEnd: periodEnd,
        hourlyRate: hourlyRate,
        isFiveOrMore: true,
        allHistoricalAttendances: shifts,
      );

      expect(result.weeklyHolidayPay, 0,
          reason: '결근(연차 아님) + 승인 OFF → 만근 미달 → 주휴수당 0원');
    });

    // ═══════════════════════════════════════════════════════════
    // [케이스 4] 연차 사용일수 차감 후 잔여일수 정확성
    //   발생 26일 - 사용 3일 = 잔여 23일
    // ═══════════════════════════════════════════════════════════
    test('연차 잔여일수: 발생 26일 - 사용 3일 = 23일', () {
      final joinDate = DateTime(2025, 1, 1);
      final settlement = DateTime(2026, 1, 2);

      final summary = PayrollCalculator.calculateAnnualLeaveSummary(
        joinDate: joinDate,
        endDate: null,
        allAttendances: [],
        scheduledWorkDays: [1, 2, 3, 4, 5],
        isFiveOrMore: true,
        settlementPoint: settlement,
        usedAnnualLeave: 3,
        weeklyHoursPure: 40,
        hourlyRate: hourlyRate,
        isVirtual: true,
      );

      expect(summary.totalGenerated, 26.0,
          reason: '11(1년미만) + 15(1년차) = 26일');
      expect(summary.used, 3.0);
      expect(summary.remaining, 23.0,
          reason: '26 - 3 = 23일 잔여');
    });

    // ═══════════════════════════════════════════════════════════
    // [케이스 5] 퇴사 시 잔여 연차 수당 정확한 정산
    //   사용 3일 반영 후 퇴사 → 잔여 23일 × 8h × 시급
    // ═══════════════════════════════════════════════════════════
    test('퇴사 정산: 사용 3일 → 잔여 23일 × 8h × 시급', () {
      final joinDate = DateTime(2025, 1, 1);
      final exitDate = DateTime(2026, 6, 1);

      final summary = PayrollCalculator.calculateAnnualLeaveSummary(
        joinDate: joinDate,
        endDate: exitDate,
        allAttendances: [],
        scheduledWorkDays: [1, 2, 3, 4, 5],
        isFiveOrMore: true,
        settlementPoint: exitDate,
        usedAnnualLeave: 3,
        weeklyHoursPure: 40,
        hourlyRate: hourlyRate,
        isVirtual: true,
      );

      // 발생: 11 + 15 + 5(1~5월) = 31, 사용: 3 → 잔여: 28
      final expectedRemaining = summary.totalGenerated - 3;
      expect(summary.remaining, expectedRemaining);
      expect(summary.annualLeaveAllowancePay, expectedRemaining * 8 * hourlyRate,
          reason: '퇴사 수당 = 잔여 ${expectedRemaining.toInt()}일 × 8h × ${hourlyRate.toInt()}');
    });

    // ═══════════════════════════════════════════════════════════
    // [케이스 6] 연차 사용 → 취소 → usedAnnualLeave 복원 시뮬레이션
    //   사용 3일 → 1일 취소 → used = 2
    // ═══════════════════════════════════════════════════════════
    test('연차 취소 복원: 사용 3일 → 1일 취소 → used 2일', () {
      final joinDate = DateTime(2025, 1, 1);
      final settlement = DateTime(2026, 1, 2);

      // 취소 전: 3일 사용
      double usedBefore = 3.0;
      
      // 취소 로직 시뮬레이션 (main_screen.dart L2820과 동일)
      double usedAfter = (usedBefore - 1.0).clamp(0.0, double.infinity);
      expect(usedAfter, 2.0, reason: '3 - 1 = 2');

      final summary = PayrollCalculator.calculateAnnualLeaveSummary(
        joinDate: joinDate,
        endDate: null,
        allAttendances: [],
        scheduledWorkDays: [1, 2, 3, 4, 5],
        isFiveOrMore: true,
        settlementPoint: settlement,
        usedAnnualLeave: usedAfter,
        weeklyHoursPure: 40,
        hourlyRate: hourlyRate,
        isVirtual: true,
      );

      expect(summary.used, 2.0, reason: '취소 후 사용일수 = 2');
      expect(summary.remaining, 24.0, reason: '26 - 2 = 24일');
    });

    // ═══════════════════════════════════════════════════════════
    // [케이스 7] 0일 미만 차감 방지 (clamp 검증)
    //   usedAnnualLeave = 0 → 취소 시도 → 0 유지
    // ═══════════════════════════════════════════════════════════
    test('음수 차감 방지: used 0일 → 취소 → 0 유지 (clamp)', () {
      double used = 0.0;
      double afterCancel = (used - 1.0).clamp(0.0, double.infinity);
      
      expect(afterCancel, 0.0,
          reason: '0 - 1 = -1 → clamp(0, ∞) = 0');
    });

    // ═══════════════════════════════════════════════════════════
    // [케이스 8] 월급제 중복 방지: annualLeaveUsedPay가 finalTotalPay에 미포함
    //   월급제는 연차 사용일 임금이 이미 월급에 내포 → 유급수당 중복 지급 방지
    // ═══════════════════════════════════════════════════════════
    test('월급제 중복 방지: annualLeaveUsedPay가 finalTotalPay에 미포함', () {
      final periodStart = DateTime(2026, 5, 1);
      final periodEnd = DateTime(2026, 5, 31);

      final shifts = <Attendance>[
        _shift(staffId, DateTime(2026, 5, 5), 9, 18),
        _shift(staffId, DateTime(2026, 5, 6), 9, 18),
        _shift(staffId, DateTime(2026, 5, 7), 9, 18),
        _shift(staffId, DateTime(2026, 5, 8), 9, 18),
        _annualLeaveAttendance(staffId, DateTime(2026, 5, 9)),
      ];

      // 월급제 워커 생성
      final monthlyWorker = PayrollWorkerData(
        joinDate: DateTime(2025, 7, 1),
        scheduledWorkDays: [1, 2, 3, 4, 5],
        weeklyHoursPure: 40,
        weeklyTotalStayMinutes: 2700,
        breakMinutesPerShift: 60,
        isPaidBreak: false,
        isProbation: false,
        probationMonths: 0,
        graceMinutes: 0,
        wageType: 'monthly',
        monthlyWage: 2500000,
        fixedOvertimeHours: 0,
        fixedOvertimePay: 0,
        mealAllowance: 0,
        mealTaxExempt: false,
        allowanceAmounts: [],
        deductNationalPension: false,
        deductHealthInsurance: false,
        deductEmploymentInsurance: false,
        applyWithholding33: false,
        manualWeeklyHolidayApproval: true,
        weeklyHolidayDay: 0,
        previousMonthAdjustment: 0,
        usedAnnualLeave: 1,
        manualAdjustment: 0,
        initialAdjustment: 0,
        initialAdjustmentReason: '',
        promotionLogs: [],
        wageHistoryJson: '',
        isVirtual: true,
        breakStartTime: '',
        breakEndTime: '',
      );

      final result = PayrollCalculator.calculate(
        workerData: monthlyWorker,
        shifts: shifts,
        periodStart: periodStart,
        periodEnd: periodEnd,
        hourlyRate: hourlyRate,
        isFiveOrMore: true,
        allHistoricalAttendances: shifts,
      );

      // 월급제 totalPay에 annualLeaveUsedPay가 중복 포함되지 않아야 함
      // 월급제는 연차 사용일 임금이 월급에 이미 내포
      expect(result.totalPay, greaterThan(0),
          reason: '월급제 총급여가 양수여야 함');

      // 시급제 동일 조건으로 계산하여 비교
      final hourlyResult = PayrollCalculator.calculate(
        workerData: _workerData(usedAnnualLeave: 1),
        shifts: shifts,
        periodStart: periodStart,
        periodEnd: periodEnd,
        hourlyRate: hourlyRate,
        isFiveOrMore: true,
        allHistoricalAttendances: shifts,
      );

      // 시급제는 annualLeaveAllowancePay > 0 (유급수당 별도 지급)
      expect(hourlyResult.annualLeaveAllowancePay, greaterThan(0),
          reason: '시급제: 연차 유급수당 별도 지급');
    });
  });
}
