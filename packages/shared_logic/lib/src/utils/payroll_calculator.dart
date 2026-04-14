import '../models/attendance_model.dart';
import '../models/shift_model.dart';
import '../constants/payroll_constants.dart';
import 'roster_attendance.dart';

class FinalPayrollResult {
  final double basePay;
  final double breakPay;
  final double extraPay;
  final double weeklyHolidayPay;
  final double totalPay;

  const FinalPayrollResult({
    required this.basePay,
    required this.breakPay,
    required this.extraPay,
    required this.weeklyHolidayPay,
    required this.totalPay,
  });
}

class PayrollWorkerData {
  /// 계약(소정) 기준 주간 순수 근로시간(휴게 제외, pureLaborHours 합) - hours
  final double weeklyHoursPure;

  /// 계약(소정) 기준 주간 체류시간(휴게 포함, totalStayMinutes) - minutes
  final int weeklyTotalStayMinutes;

  final int breakMinutesPerShift;
  final bool isPaidBreak;
  final DateTime joinDate;
  final List<int> scheduledWorkDays;
  final bool manualWeeklyHolidayApproval;

  /// 기타수당(기타 고정/수당 항목) 금액들
  final List<double> allowanceAmounts;

  /// 총 사용한 연차 개수 (사장님이 직접 관리)
  final double usedAnnualLeave;

  /// 사장님이 수동으로 가감한 연차 개수 (Override)
  final double manualAdjustment;

  /// 퇴사일 (null이면 재직 중)
  final DateTime? endDate;

  /// 전월 정산금 (수동 입력)
  final double previousMonthAdjustment;

  /// 비과세 대상 식대 (사장님 설정값)
  final double mealAllowance;

  /// 세금 및 4대보험 공제 필드들
  final bool applyWithholding33;
  final bool deductNationalPension;
  final bool deductHealthInsurance;
  final bool deductEmploymentInsurance;

  /// 가상직원 여부 (사장님 테스트용 프리패스 권한 부여)
  final bool isVirtual;

  const PayrollWorkerData({
    required this.weeklyHoursPure,
    required this.weeklyTotalStayMinutes,
    required this.breakMinutesPerShift,
    required this.isPaidBreak,
    required this.joinDate,
    required this.scheduledWorkDays,
    this.manualWeeklyHolidayApproval = false,
    this.allowanceAmounts = const [],
    this.usedAnnualLeave = 0.0,
    this.manualAdjustment = 0.0,
    this.endDate,
    this.previousMonthAdjustment = 0.0,
    this.mealAllowance = 0.0,
    this.applyWithholding33 = false,
    this.deductNationalPension = false,
    this.deductHealthInsurance = false,
    this.deductEmploymentInsurance = false,
    this.isVirtual = false,
  });
}

class AnnualLeaveAttendanceRate {
  /// 소정 근로일 대비 실제 출근일 수
  final int workedDays;
  final int expectedDays;
  final double rate; // 0.0 ~ 1.0
  final bool passed; // >= 80%?

  const AnnualLeaveAttendanceRate({
    required this.workedDays,
    required this.expectedDays,
    required this.rate,
    required this.passed,
  });
}

/// 연차 저금통 산출 결과
class AnnualLeaveSummary {
  /// 총 발생 연차 (입사~현재까지 누적)
  final double totalGenerated;

  /// 사용한 연차
  final double used;

  /// 잔여 연차 = totalGenerated - used
  final double remaining;

  /// 퇴사 정산 연차수당 (잔여 × 일일소정근로시간 × 시급)
  final double annualLeaveAllowancePay;

  /// 1년 주기 15개 부여 시 80% 미달로 미발생한 경우의 상세 정보
  final AnnualLeaveAttendanceRate? blockedAnnualRateDetail;

  /// 사장님이 수동으로 가감한 연차 개수 (UI 표시용)
  final double manualAdjustment;

  /// 연차 산출 각 단계의 근거 문장들
  final List<String> calculationBasis;

  const AnnualLeaveSummary({
    required this.totalGenerated,
    required this.used,
    required this.remaining,
    this.annualLeaveAllowancePay = 0.0,
    this.blockedAnnualRateDetail,
    this.manualAdjustment = 0.0,
    this.calculationBasis = const [],
  });
}

class PayrollCalculationResult {
  final double basePay;
  final double breakPay;
  final double premiumPay;
  final double weeklyHolidayPay;
  final double otherAllowancePay;
  final double annualLeaveAllowancePay;
  final double totalPay;

  final double pureLaborHours;
  final double paidBreakHours;
  final double stayHours;
  final double premiumHours;

  final bool needsBreakSeparationGuide;
  final bool isWeeklyHolidayEligible;
  final bool hasSubstitutionRisk;
  final int newlyGrantedAnnualLeave; // 호환성 유지
  final bool isPerfectAttendance;
  final bool weeklyHolidayBlockedByAbsence;

  /// 연차 저금통 전체 요약
  final AnnualLeaveSummary annualLeaveSummary;

  // --- 대한민국 노무 표준 가이드 준수 필드 추가 ---
  final double taxableWage;        // 과세 대상액 (A)
  final double insuranceDeduction; // 4대 보험 공제액 (B)
  final double mealNonTaxable;     // 비과세 식대 항목
  final double previousMonthAdjustment; // 전월 정산금 (C)
  final double netPay;             // 최종 실지급액 (A + 비과세 - B + C)

  const PayrollCalculationResult({
    required this.basePay,
    required this.breakPay,
    required this.premiumPay,
    required this.weeklyHolidayPay,
    required this.otherAllowancePay,
    required this.totalPay,
    required this.pureLaborHours,
    required this.paidBreakHours,
    required this.stayHours,
    required this.premiumHours,
    required this.needsBreakSeparationGuide,
    required this.isWeeklyHolidayEligible,
    required this.hasSubstitutionRisk,
    required this.newlyGrantedAnnualLeave,
    required this.isPerfectAttendance,
    required this.weeklyHolidayBlockedByAbsence,
    required this.annualLeaveSummary,
    this.annualLeaveAllowancePay = 0.0,
    this.taxableWage = 0.0,
    this.insuranceDeduction = 0.0,
    this.mealNonTaxable = 0.0,
    this.previousMonthAdjustment = 0.0,
    this.netPay = 0.0,
  });
}

class ShiftSwapResult {
  final Shift firstSwapped;
  final Shift secondSwapped;
  final Map<String, String> payrollOwnerByShiftId;

  const ShiftSwapResult({
    required this.firstSwapped,
    required this.secondSwapped,
    required this.payrollOwnerByShiftId,
  });
}

class SubstitutionProcessResult {
  final double updatedActualHours;
  final bool isWeeklyHolidayEligible;
  final bool isFiveOrMore;
  final List<String> riskAlerts;

  const SubstitutionProcessResult({
    required this.updatedActualHours,
    required this.isWeeklyHolidayEligible,
    required this.isFiveOrMore,
    required this.riskAlerts,
  });
}

class PayrollCalculator {
  const PayrollCalculator();

  static PayrollCalculationResult calculate({
    required PayrollWorkerData workerData,
    required List<Attendance> shifts,
    List<Attendance> substitutionShifts = const [],
    required DateTime periodStart,
    required DateTime periodEnd,
    required double hourlyRate,
    required bool isFiveOrMore,
    List<Attendance> allHistoricalAttendances = const [],
  }) {
    final breakPerShift = workerData.breakMinutesPerShift;
    final paidBreak = workerData.isPaidBreak;
    // 정책: 계획 외(Unplanned) 근무는 사장님 승인(UnplannedApproved)된 건만 정산에 포함
    final mergedShifts = <Attendance>[
      ...shifts.where(_isAttendanceIncludedForPayroll),
      ...substitutionShifts.where(_isAttendanceIncludedForPayroll),
    ];
    final finished = mergedShifts.where((a) => a.clockOut != null).toList();

    int totalStayMinutes = 0;
    int totalPureMinutes = 0;
    int totalPaidBreakMinutes = 0;

    int totalPremiumTargetMinutes = 0;

    double basePay = 0.0;
    double breakPay = 0.0;
    double premiumPay = 0.0;

    // 1주간 eligibility 판정을 위해 periodStart~periodEnd를 week 단위로 분할
    final weekSegments = _weekSegments(periodStart, periodEnd);
    final weekPureLaborHours = List<double>.filled(weekSegments.length, 0.0);

    for (final att in finished) {
      final effectiveOut = payrollSettlementClockOut(
        actualClockOut: att.clockOut!,
        scheduledShiftEndIso: att.scheduledShiftEndIso,
        overtimeApproved: att.overtimeApproved,
      );
      final stayMinutes = effectiveOut.difference(att.clockIn).inMinutes;
      if (stayMinutes <= 0) continue;

      final appliedBreak = _breakMinutes(att, fallbackMinutes: breakPerShift)
          .clamp(0, stayMinutes);
      final pureMinutes = stayMinutes - appliedBreak;

      totalStayMinutes += stayMinutes;
      totalPureMinutes += pureMinutes;
      if (paidBreak) totalPaidBreakMinutes += appliedBreak;

      // 소급 적용 확인: 해가 바뀌었는데 아직 시급이 안 올랐다면 강제로 올려서 계산 (체불 방지)
      double shiftRate = hourlyRate;
      if (att.clockIn.year >= PayrollConstants.minimumWageEffectiveYear && shiftRate < PayrollConstants.legalMinimumWage) {
        shiftRate = PayrollConstants.legalMinimumWage;
      }

      basePay += (pureMinutes / 60.0) * shiftRate;
      if (paidBreak) {
        breakPay += (appliedBreak / 60.0) * shiftRate;
      }

      if (isFiveOrMore) {
        final pmIns = _premiumTargetMinutesForAttendance(
          clockIn: att.clockIn,
          clockOut: effectiveOut,
          stayMinutes: stayMinutes,
          pureMinutes: pureMinutes,
        );
        totalPremiumTargetMinutes += pmIns;
        premiumPay += (pmIns / 60.0) * shiftRate * 0.5;
      }

      // 주휴수당 eligibility: inDay/outDay가 week 구간에 포함되면 해당 week에 pure hours 누적
      for (int wi = 0; wi < weekSegments.length; wi++) {
        final (wStart, wEnd) = weekSegments[wi];
        if (_attendanceTouchesRange(att, wStart, wEnd)) {
          weekPureLaborHours[wi] += pureMinutes / 60.0;
        }
      }
    }

    final pureLaborHours = totalPureMinutes / 60.0;
    final paidBreakHours = totalPaidBreakMinutes / 60.0;
    final stayHours = totalStayMinutes / 60.0;
    final premiumHours = totalPremiumTargetMinutes / 60.0;

    // 주휴수당에서도 동일한 소급 기준을 두기 위해 현재 기간의 마지막 날 기준으로 평가
    double referenceRate = hourlyRate;
    if (periodEnd.year >= PayrollConstants.minimumWageEffectiveYear && referenceRate < PayrollConstants.legalMinimumWage) {
      referenceRate = PayrollConstants.legalMinimumWage;
    }

    double weeklyHolidayPay = 0.0;
    bool isWeeklyHolidayEligible = false;
    bool isPerfectAttendance = true;
    bool weeklyHolidayBlockedByAbsence = false;
    for (int wi = 0; wi < weekPureLaborHours.length; wi++) {
      final weekPure = weekPureLaborHours[wi];
      final (wStart, wEnd) = weekSegments[wi];
      final perfectAttendanceWeek = _isPerfectAttendanceForWeek(
        attendances: finished,
        scheduledWorkDays: workerData.scheduledWorkDays,
        weekStart: wStart,
        weekEnd: wEnd,
        isVirtual: workerData.isVirtual,
      );
      if (!perfectAttendanceWeek) {
        isPerfectAttendance = false;
      }
      
      // [노무법 준수] 조퇴/지각으로 실제 근무시간(weekPure)이 15시간 미만으로 떨어져도, 
      // 계약된 시간(weeklyHoursPure)이 15시간 이상이라면 주휴수당 발생 조건을 충족함.
      final baseHoursForEligibility = workerData.weeklyHoursPure > 0 ? workerData.weeklyHoursPure : weekPure;
      if (baseHoursForEligibility >= 15.0) {
        if (!perfectAttendanceWeek) {
          weeklyHolidayBlockedByAbsence = true;
        }
        // eligibility는 법적 대상 여부를 뜻하고, 실제 합산은 수동 승인 시에만 반영합니다.
        if (perfectAttendanceWeek || workerData.manualWeeklyHolidayApproval) {
          isWeeklyHolidayEligible = true;
        }
        if (!workerData.manualWeeklyHolidayApproval) {
          continue;
        }

        // [노무법 준수] 대근(추가근로)으로 실근로시간이 초과되어도 주휴수당은 계약된 '소정근로시간'을 상한으로 산정
        final maxAllowedHours = workerData.weeklyHoursPure > 0 ? workerData.weeklyHoursPure : 40.0;
        double calcHours = weekPure > maxAllowedHours ? maxAllowedHours : weekPure;
        if (calcHours > 40.0) calcHours = 40.0;

        weeklyHolidayPay += ((calcHours / 40.0) * 8.0 * referenceRate);
      }
    }

    final otherAllowancePay =
        workerData.allowanceAmounts.fold<double>(0.0, (s, v) => s + v);

    final totalPay =
        basePay + breakPay + premiumPay + weeklyHolidayPay + otherAllowancePay;

    final needsBreakSeparationGuide = (workerData.weeklyHoursPure < 15) &&
        (workerData.weeklyTotalStayMinutes / 60.0 >= 15);
    final hasSubstitutionRisk = substitutionShifts.isNotEmpty &&
        ((isWeeklyHolidayEligible && workerData.weeklyHoursPure < 15) ||
            isFiveOrMore);
    // 연차 저금통 산출
    final historicalForLeave = allHistoricalAttendances.isNotEmpty
        ? allHistoricalAttendances
        : finished;
    final leaveSummary = calculateAnnualLeaveSummary(
      joinDate: workerData.joinDate,
      endDate: workerData.endDate,
      allAttendances: historicalForLeave,
      scheduledWorkDays: workerData.scheduledWorkDays,
      isFiveOrMore: isFiveOrMore,
      settlementPoint: periodEnd,
      usedAnnualLeave: workerData.usedAnnualLeave,
      weeklyHoursPure: workerData.weeklyHoursPure,
      hourlyRate: hourlyRate,
      manualAdjustment: workerData.manualAdjustment,
      isVirtual: workerData.isVirtual,
    );
    final annualLeaveAllowancePay = leaveSummary.annualLeaveAllowancePay;
    final finalTotalPay = totalPay + annualLeaveAllowancePay;

    // --- 대한민국 노무 표준 가이드 산식 적용 ---
    // 1. 비과세 식대 (설정된 식대 중 최대 20만 원까지만 적용)
    final mealNonTaxable = workerData.mealAllowance >= 200000 ? 200000.0 : workerData.mealAllowance;
    
    // 2. 과세 대상액 (A)
    final taxableWage = (finalTotalPay - mealNonTaxable).clamp(0.0, double.infinity);
    
    // 3. 보험 및 세금 공제액 (B)
    double insuranceDeduction = 0.0;
    if (workerData.applyWithholding33) {
      // 3.3% 사업소득세
      insuranceDeduction = taxableWage * 0.033;
    } else {
      // 4대 보험 적용: 국민(4.5%) + 건강/장기요양(대략 4%) + 고용(0.9%) = 합산율(rate) 계산
      double totalRate = 0.0;
      if (workerData.deductNationalPension) totalRate += 0.045;
      if (workerData.deductHealthInsurance) totalRate += 0.04;    // 건강/장기 약식
      if (workerData.deductEmploymentInsurance) totalRate += 0.009;
      // 아무것도 켜져있지 않으면 0%
      insuranceDeduction = taxableWage * totalRate;
    }
    
    // 4. 최종 실지급액 = 세전 총액 - 공제액 + 전월 정산금(C)
    final netPay = finalTotalPay - insuranceDeduction + workerData.previousMonthAdjustment;

    return PayrollCalculationResult(
      basePay: basePay,
      breakPay: breakPay,
      premiumPay: premiumPay,
      weeklyHolidayPay: weeklyHolidayPay,
      otherAllowancePay: otherAllowancePay,
      annualLeaveAllowancePay: annualLeaveAllowancePay,
      totalPay: finalTotalPay,
      pureLaborHours: pureLaborHours,
      paidBreakHours: paidBreakHours,
      stayHours: stayHours,
      premiumHours: premiumHours,
      needsBreakSeparationGuide: needsBreakSeparationGuide,
      isWeeklyHolidayEligible: isWeeklyHolidayEligible,
      hasSubstitutionRisk: hasSubstitutionRisk,
      newlyGrantedAnnualLeave: leaveSummary.totalGenerated.round(),
      isPerfectAttendance: isPerfectAttendance,
      weeklyHolidayBlockedByAbsence: weeklyHolidayBlockedByAbsence,
      annualLeaveSummary: leaveSummary,
      taxableWage: taxableWage,
      insuranceDeduction: insuranceDeduction,
      mealNonTaxable: mealNonTaxable,
      previousMonthAdjustment: workerData.previousMonthAdjustment,
      netPay: netPay,
    );
  }

  static bool _isAttendanceIncludedForPayroll(Attendance attendance) {
    final status = attendance.attendanceStatus.trim().toLowerCase();
    if (status == 'unplanned' ||
        status == 'pending_approval' ||
        status == 'pending_overtime') {
      return false;
    }
    return true;
  }

  /// 연차 저금통 전체 누적 요약 산출
  ///
  /// - 1년 미만: 입사일 기준 1개월 단위 만근 시 +1개 (최대 11개)
  /// - 1년 이상: 해당 1년 구간의 80% 출근율 검증 후 +15개
  /// - 퇴사 시 잔여 연차 × 계약 일일소정근로시간 × 시급 = 연차수당
  static AnnualLeaveSummary calculateAnnualLeaveSummary({
    required DateTime joinDate,
    required DateTime? endDate,
    required List<Attendance> allAttendances,
    required List<int> scheduledWorkDays,
    required bool isFiveOrMore,
    required DateTime settlementPoint,
    required double usedAnnualLeave,
    required double weeklyHoursPure,
    required double hourlyRate,
    double manualAdjustment = 0.0,
    bool isVirtual = false,
  }) {
    final basis = <String>[
      "입사일: ${joinDate.year}-${joinDate.month.toString().padLeft(2, '0')}-${joinDate.day.toString().padLeft(2, '0')} (${isFiveOrMore ? '5인이상' : '5인미만'})"
    ];
    if (!isFiveOrMore) {
      return const AnnualLeaveSummary(
        totalGenerated: 0,
        used: 0,
        remaining: 0,
        calculationBasis: ["5인 미만 사업장: 연차 법적 의무 없음"],
      );
    }
    
    // [수정/확인] 초단시간 근로자(주 15시간 미만) 연차 발생 제외 (근로기준법 제18조 제3항)
    if (weeklyHoursPure < 15) {
      return const AnnualLeaveSummary(
        totalGenerated: 0,
        used: 0,
        remaining: 0,
        calculationBasis: ["초단시간 근로자(주 15시간 미만): 연차 발생 대상 아님"],
      );
    }

    // 계약 일일 소정 근로시간 (계약 주간시간 / 주간 근무일수)
    final contractWorkDaysPerWeek =
        scheduledWorkDays.isEmpty ? 5.0 : scheduledWorkDays.length.toDouble();
    final dailyContractHours =
        contractWorkDaysPerWeek > 0 ? weeklyHoursPure / contractWorkDaysPerWeek : 8.0;

    double totalGenerated = 0;
    AnnualLeaveAttendanceRate? blockedDetail;

    // ─── 1단계: 입사일 기준 1개월 단위로 1년 미만 연차 계산 ───
    // 각 월 구간: _addSafeMonths(joinDate, m) ~ _addSafeMonths(joinDate, m+1) - 1일
    // 1년 미만 구간: 0 ~ 11개월차 (각 만근이면 +1)
    final oneYearPoint = DateTime(joinDate.year + 1, joinDate.month, joinDate.day);

    // 정산 시점 기준 경과 완전 개월 수 (최대 11)
    final cutPoint = settlementPoint.isBefore(oneYearPoint) ? settlementPoint : oneYearPoint;
    final monthsElapsed = _monthsDiff(joinDate, cutPoint);
    final monthsToCheck = monthsElapsed.clamp(0, 11);

    for (int m = 0; m < monthsToCheck; m++) {
      final mStart = _addSafeMonths(joinDate, m);
      final mNext = _addSafeMonths(joinDate, m + 1);
      final mEnd = mNext.subtract(const Duration(days: 1));
      
      // 이 단위 구간이 정산 시점을 넘으면 최종일로 클리핑
      final mEndClipped = mEnd.isAfter(settlementPoint) ? settlementPoint : mEnd;

      final expected = _expectedWorkDays(mStart, mEndClipped, scheduledWorkDays);
      final workedSet = _workedDaysSet(allAttendances, mStart, mEndClipped);
      final worked = workedSet.length;

      // [핵심 개편] 사장님의 가상 근무표 테스트를 위해, 입사 후 기록이 없는 구간은 '만근'으로 기본 가정함
      // [프리패스] 가상직원인 경우 기록이 있어도 무조건 만근으로 처리
      bool isAutoPassed = isVirtual;
      if (!isAutoPassed && expected > 0) {
        final hasAnyDataInPeriod = allAttendances.any((a) =>
          a.clockIn.isAfter(mStart.subtract(const Duration(seconds: 1))) && 
          a.clockIn.isBefore(mEndClipped.add(const Duration(seconds: 1))));

        // 데이터가 아예 없는 구간은 '만근 가정'으로 처리하여 연차 발생 보장
        if (!hasAnyDataInPeriod) {
          isAutoPassed = true;
        }
      }

      final statusText = "($worked/$expected)";
      if (isAutoPassed || (expected > 0 && worked >= expected)) {
        totalGenerated += 1;
        final passLabel = isAutoPassed ? "만근 가정 (기록 없음, +1개)" : "만근 (+1개)";
        basis.add("${mStart.year}-${mStart.month.toString().padLeft(2, '0')}-${mStart.day.toString().padLeft(2, '0')} ~ ${mEnd.year}-${mEnd.month.toString().padLeft(2, '0')}-${mEnd.day.toString().padLeft(2, '0')}: $passLabel $statusText");
      } else if (expected > 0) {
        basis.add("${mStart.year}-${mStart.month.toString().padLeft(2, '0')}-${mStart.day.toString().padLeft(2, '0')} ~ ${mEnd.year}-${mEnd.month.toString().padLeft(2, '0')}-${mEnd.day.toString().padLeft(2, '0')}: 결근/미달 (0개) $statusText");
      }
    }

    // ─── 2단계: 1년 주기 15개 + 80% 출근율 검증 ───
    if (!settlementPoint.isBefore(oneYearPoint)) {
      final yearsPassed = _yearsDiff(joinDate, settlementPoint);
      for (int y = 1; y <= yearsPassed; y++) {
        final yearStart = DateTime(joinDate.year + y - 1, joinDate.month, joinDate.day);
        final yearEnd = DateTime(joinDate.year + y, joinDate.month, joinDate.day)
            .subtract(const Duration(days: 1));
        final yearEndClipped =
            yearEnd.isAfter(settlementPoint) ? settlementPoint : yearEnd;

        final expected = _expectedWorkDays(yearStart, yearEndClipped, scheduledWorkDays);
        final workedSet = _workedDaysSet(allAttendances, yearStart, yearEndClipped);
        
        // [핵심 개편] 해당 연도에 근태 기록이 아예 없는 구간은 출근율 100%로 간주함
        bool isLegacyAutoPassed = false;
        if (expected > 0) {
          final hasAnyDataInYear = allAttendances.any((a) =>
            a.clockIn.isAfter(yearStart.subtract(const Duration(seconds: 1))) && 
            a.clockIn.isBefore(yearEndClipped.add(const Duration(seconds: 1))));
          if (!hasAnyDataInYear) {
            isLegacyAutoPassed = true;
          }
        }
        
        if (isVirtual) isLegacyAutoPassed = true;

        final rate = expected > 0 ? (isLegacyAutoPassed ? 1.0 : workedSet.length / expected) : 1.0;
        final passed = rate >= 0.8;

        if (passed) {
          final additionalDays = (y > 1) ? ((y - 1) ~/ 2) : 0;
          final grantedThisYear = (15 + additionalDays).clamp(15, 25);
          
          totalGenerated += grantedThisYear;
          final passLabel = isLegacyAutoPassed ? "만근 가정 (기록 없음) " : "출근율 ${(rate * 100).toStringAsFixed(1)}% ";
          basis.add("$y년차(${yearStart.year}~${yearEnd.year}): $passLabel (+$grantedThisYear개)");
        } else {
          blockedDetail = AnnualLeaveAttendanceRate(
            workedDays: workedSet.length,
            expectedDays: expected,
            rate: rate,
            passed: false,
          );
          basis.add("$y년차(${yearStart.year}~${yearEnd.year}): 출근율 부족 ${(rate * 100).toStringAsFixed(1)}% (0개)");
        }
      }
    }

    if (manualAdjustment != 0) {
      totalGenerated += manualAdjustment;
      final sign = manualAdjustment > 0 ? '+' : '';
      basis.add("관리자 수동 조정: $sign$manualAdjustment개");
    }

    final remaining = (totalGenerated - usedAnnualLeave).clamp(0.0, double.infinity).toDouble();

    // ─── 3단계: 퇴사 정산 연차수당 ───
    double annualLeaveAllowancePay = 0;
    final isTerminated = endDate != null &&
        !endDate.isAfter(settlementPoint);
    if (isTerminated && remaining > 0) {
      annualLeaveAllowancePay = remaining * dailyContractHours * hourlyRate;
    }

    return AnnualLeaveSummary(
      totalGenerated: totalGenerated,
      used: usedAnnualLeave,
      remaining: remaining,
      annualLeaveAllowancePay: annualLeaveAllowancePay,
      blockedAnnualRateDetail: blockedDetail,
      manualAdjustment: manualAdjustment,
      calculationBasis: basis,
    );
  }

  /// 하위 호환성 유지용 (기존 호출부에서 사용)
  static int calculateAnnualLeave({
    required DateTime joinDate,
    required List<Attendance> attendances,
    required List<int> scheduledWorkDays,
    required bool isFiveOrMore,
    required DateTime settlementPoint,
  }) {
    if (!isFiveOrMore) return 0;
    final summary = calculateAnnualLeaveSummary(
      joinDate: joinDate,
      endDate: null,
      allAttendances: attendances,
      scheduledWorkDays: scheduledWorkDays,
      isFiveOrMore: isFiveOrMore,
      settlementPoint: settlementPoint,
      usedAnnualLeave: 0,
      weeklyHoursPure: 40,
      hourlyRate: 0,
    );
    return summary.totalGenerated.floor();
  }

  // ─── 연차 계산 보조 헬퍼 ───

  static int _monthsDiff(DateTime from, DateTime to) {
    int months = (to.year - from.year) * 12 + (to.month - from.month);

    // 날짜가 부족한 경우 1개월 차감
    // 단, 종료일이 해당 월의 말일이고, 시작일의 일자보다 크거나 같으면(혹은 시작일도 말일이면) 꽉 찬 것으로 봅니다.
    final lastDayOfTo = DateTime(to.year, to.month + 1, 0).day;
    bool isLastDayOfTo = to.day == lastDayOfTo;

    if (to.day < from.day && !isLastDayOfTo) {
      months--;
    }
    return months < 0 ? 0 : months;
  }

  /// 31일 입사자가 말일(2월 등)을 지날 때 날짜가 튀는 현상을 방지하는 안전한 월 덧셈
  static DateTime _addSafeMonths(DateTime from, int months) {
    int nextYear = from.year + ((from.month + months - 1) ~/ 12);
    int nextMonth = (from.month + months - 1) % 12 + 1;
    // 해당 월의 실제 최대 일수 확인
    int lastDay = DateTime(nextYear, nextMonth + 1, 0).day;
    int nextDay = from.day > lastDay ? lastDay : from.day;
    return DateTime(nextYear, nextMonth, nextDay);
  }

  static int _yearsDiff(DateTime from, DateTime to) {
    int years = to.year - from.year;
    if (to.month < from.month ||
        (to.month == from.month && to.day < from.day)) {
      years--;
    }
    return years < 0 ? 0 : years;
  }

  static int _expectedWorkDays(
    DateTime from,
    DateTime to,
    List<int> scheduledWorkDays,
  ) {
    int count = 0;
    for (DateTime d = from;
        !d.isAfter(to);
        d = d.add(const Duration(days: 1))) {
      final code = d.weekday == DateTime.sunday ? 0 : d.weekday;
      if (scheduledWorkDays.contains(code)) count++;
    }
    return count;
  }

  static Set<String> _workedDaysSet(
    List<Attendance> attendances,
    DateTime from,
    DateTime to,
  ) {
    final set = <String>{};
    for (final att in attendances) {
      final d = DateTime(att.clockIn.year, att.clockIn.month, att.clockIn.day);
      if (d.isBefore(from) || d.isAfter(to)) continue;
      set.add('${d.year}-${d.month}-${d.day}');
    }
    return set;
  }

  static bool isFiveOrMore({
    required List<Attendance> settlementAttendances,
    required DateTime periodStart,
    required DateTime periodEnd,
    Map<String, List<int>>? virtualStaffSchedules, // New: staffId -> workDays
  }) {
    final totalDays = periodEnd.difference(periodStart).inDays + 1;
    if (totalDays <= 0) return false;

    final dailyStaff = <DateTime, Set<String>>{};
    
    // 1. 실제 출퇴근 기록 반영
    for (final att in settlementAttendances) {
      final day = DateTime(att.clockIn.year, att.clockIn.month, att.clockIn.day);
      if (day.isBefore(periodStart) || day.isAfter(periodEnd)) continue;
      dailyStaff.putIfAbsent(day, () => <String>{}).add(att.staffId);
    }

    // 2. 가상직원 시뮬레이션 반영 (테스트 편의용)
    if (virtualStaffSchedules != null && virtualStaffSchedules.isNotEmpty) {
      for (int i = 0; i < totalDays; i++) {
        final day = DateTime(periodStart.year, periodStart.month, periodStart.day + i);
        final weekday = day.weekday % 7; // 0=Sun, ..., 6=Sat

        virtualStaffSchedules.forEach((staffId, workDays) {
          if (workDays.contains(weekday)) {
            dailyStaff.putIfAbsent(day, () => <String>{}).add(staffId);
          }
        });
      }
    }

    int totalPersonDays = 0;
    int operatingDays = 0;
    for (int i = 0; i < totalDays; i++) {
      final day = DateTime(periodStart.year, periodStart.month, periodStart.day + i);
      final count = dailyStaff[day]?.length ?? 0;
      if (count > 0) {
        operatingDays++;
        totalPersonDays += count;
      }
    }

    final avg = operatingDays == 0 ? 0.0 : (totalPersonDays / operatingDays);
    return avg >= 5.0;
  }

  static bool isWeeklyHolidayEligible({
    required List<Attendance> weeklyAttendances,
    int defaultBreakMinutesPerShift = 0,
  }) {
    double pureHours = 0;
    for (final att in weeklyAttendances) {
      if (att.clockOut == null) continue;
      final effectiveOut = payrollSettlementClockOut(
        actualClockOut: att.clockOut!,
        scheduledShiftEndIso: att.scheduledShiftEndIso,
        overtimeApproved: att.overtimeApproved,
      );
      final stayMinutes = effectiveOut.difference(att.clockIn).inMinutes;
      if (stayMinutes <= 0) continue;
      final breakMinutes = _breakMinutes(att, fallbackMinutes: defaultBreakMinutesPerShift)
          .clamp(0, stayMinutes);
      pureHours += (stayMinutes - breakMinutes) / 60.0;
    }
    return pureHours >= 15.0;
  }

  static ShiftSwapResult processShiftSwap({
    required Shift firstAssignedShift,
    required Shift secondAssignedShift,
    required List<Attendance> attendances,
  }) {
    final firstSwapped = _copyShift(firstAssignedShift, staffId: secondAssignedShift.staffId);
    final secondSwapped = _copyShift(secondAssignedShift, staffId: firstAssignedShift.staffId);

    final payrollOwnerByShiftId = <String, String>{};
    payrollOwnerByShiftId[firstAssignedShift.id] =
        _actualRecorderForShift(firstAssignedShift, attendances) ?? firstSwapped.staffId;
    payrollOwnerByShiftId[secondAssignedShift.id] =
        _actualRecorderForShift(secondAssignedShift, attendances) ?? secondSwapped.staffId;

    return ShiftSwapResult(
      firstSwapped: firstSwapped,
      secondSwapped: secondSwapped,
      payrollOwnerByShiftId: payrollOwnerByShiftId,
    );
  }

  static Shift _copyShift(Shift original, {String? staffId}) {
    return Shift(
      id: original.id,
      staffId: staffId ?? original.staffId,
      storeId: original.storeId,
      startTime: original.startTime,
      endTime: original.endTime,
    );
  }

  static SubstitutionProcessResult processSubstitution({
    required Shift substitutionShift,
    required List<Attendance> substituteWeeklyAttendances,
    required bool isFiveOrMoreStore,
    int defaultBreakMinutesPerShift = 0,
    void Function(String message)? notifyOwner,
  }) {
    final allAttendances = [...substituteWeeklyAttendances];
    final alreadyCovered = substituteWeeklyAttendances.any(
      (a) =>
          a.clockIn.isAtSameMomentAs(substitutionShift.startTime) &&
          a.clockOut?.isAtSameMomentAs(substitutionShift.endTime) == true,
    );
    if (!alreadyCovered) {
      allAttendances.add(
        Attendance(
          id: 'virtual_sub_${substitutionShift.id}',
          staffId: substitutionShift.staffId,
          storeId: substitutionShift.storeId,
          clockIn: substitutionShift.startTime,
          clockOut: substitutionShift.endTime,
          type: AttendanceType.web,
        ),
      );
    }

    double totalPureHours = 0;
    for (final att in allAttendances) {
      if (att.clockOut == null) continue;
      final effectiveOut = payrollSettlementClockOut(
        actualClockOut: att.clockOut!,
        scheduledShiftEndIso: att.scheduledShiftEndIso,
        overtimeApproved: att.overtimeApproved,
      );
      final stayMinutes = effectiveOut.difference(att.clockIn).inMinutes;
      if (stayMinutes <= 0) continue;
      final breakMinutes = _breakMinutes(att, fallbackMinutes: defaultBreakMinutesPerShift)
          .clamp(0, stayMinutes);
      totalPureHours += (stayMinutes - breakMinutes) / 60.0;
    }

    final weeklyEligible = totalPureHours >= 15.0;
    final alerts = <String>[];
    if (weeklyEligible) {
      alerts.add('대체근무 반영 후 주 15시간 이상으로 주휴수당 검토 대상입니다.');
    }
    if (isFiveOrMoreStore) {
      alerts.add('5인 이상 사업장 기준으로 연장/야간/휴일 가산수당 적용 여부를 확인하세요.');
    }
    for (final msg in alerts) {
      notifyOwner?.call(msg);
    }

    return SubstitutionProcessResult(
      updatedActualHours: totalPureHours,
      isWeeklyHolidayEligible: weeklyEligible,
      isFiveOrMore: isFiveOrMoreStore,
      riskAlerts: alerts,
    );
  }

  static FinalPayrollResult calculateFinalPayroll({
    required double totalPureLaborHours,
    required double totalPaidBreakHours,
    required double overtimeHours,
    required double hourlyRate,
    required bool isFiveOrMore,
    required bool isWeeklyHolidayEligible,
    required double Function() calculateHolidayPay,
  }) {
    final basePay = totalPureLaborHours * hourlyRate;
    final breakPay = totalPaidBreakHours * hourlyRate;
    final extraPay = isFiveOrMore ? (overtimeHours * hourlyRate * 0.5) : 0.0;
    final weeklyHolidayPay = isWeeklyHolidayEligible ? calculateHolidayPay() : 0.0;
    final totalPay = basePay + breakPay + extraPay + weeklyHolidayPay;
    return FinalPayrollResult(
      basePay: basePay,
      breakPay: breakPay,
      extraPay: extraPay,
      weeklyHolidayPay: weeklyHolidayPay,
      totalPay: totalPay,
    );
  }

  static int _breakMinutes(Attendance att, {required int fallbackMinutes}) {
    if (att.breakStart != null && att.breakEnd != null) {
      final v = att.breakEnd!.difference(att.breakStart!).inMinutes;
      return v > 0 ? v : 0;
    }
    return fallbackMinutes > 0 ? fallbackMinutes : 0;
  }

  static List<(DateTime, DateTime)> _weekSegments(
    DateTime periodStart,
    DateTime periodEnd,
  ) {
    final segments = <(DateTime, DateTime)>[];
    var cursor = DateTime(periodStart.year, periodStart.month, periodStart.day);
    final end = DateTime(periodEnd.year, periodEnd.month, periodEnd.day);
    while (!cursor.isAfter(end)) {
      final segEnd = cursor.add(const Duration(days: 6));
      final realEnd = segEnd.isAfter(end) ? end : segEnd;
      segments.add((cursor, realEnd));
      cursor = cursor.add(const Duration(days: 7));
    }
    return segments;
  }

  static bool _attendanceTouchesRange(
    Attendance att,
    DateTime rangeStart,
    DateTime rangeEnd,
  ) {
    final inDay = DateTime(att.clockIn.year, att.clockIn.month, att.clockIn.day);
    final inTouches = !inDay.isBefore(rangeStart) && !inDay.isAfter(rangeEnd);
    if (inTouches) return true;

    final out = att.clockOut;
    if (out == null) return false;

    final outDay = DateTime(out.year, out.month, out.day);
    return !outDay.isBefore(rangeStart) && !outDay.isAfter(rangeEnd);
  }

  static int _premiumTargetMinutesForAttendance({
    required DateTime clockIn,
    required DateTime clockOut,
    required int stayMinutes,
    required int pureMinutes,
  }) {
    if (stayMinutes <= 0 || pureMinutes <= 0) return 0;

    // 연장(하루 8시간 초과) 대상
    final overtimePure = (pureMinutes - 480).clamp(0, pureMinutes);

    // 야간(22:00~06:00) 대상
    final nightStay = _overlapNightMinutes(clockIn, clockOut);
    final nightPure = ((nightStay * pureMinutes) / stayMinutes).round();

    // 휴일(토/일) 대상 -> [수정] 노무법상 주말이 무조건 휴일(주휴일/공휴일)은 아닙니다. 
    // 특히 주말 알바의 경우 주말이 '소정근로일'이므로 1.5배 가산 대상이 아닙니다.
    // 임의로 토/일 전체를 1.5배 가산하지 않도록 수정합니다. (추후 법정공휴일 API 연동 필요)
    final isHoliday = false; 
    final holidayPure = isHoliday ? pureMinutes : 0;

    return overtimePure + nightPure + holidayPure;
  }

  static int _overlapNightMinutes(DateTime start, DateTime end) {
    int overlap = 0;
    DateTime cursor = DateTime(start.year, start.month, start.day);
    final lastDay = DateTime(end.year, end.month, end.day);

    while (!cursor.isAfter(lastDay)) {
      final nightStart = DateTime(cursor.year, cursor.month, cursor.day, 22);
      final nightEnd = DateTime(cursor.year, cursor.month, cursor.day + 1, 6);
      final from = start.isAfter(nightStart) ? start : nightStart;
      final to = end.isBefore(nightEnd) ? end : nightEnd;
      if (to.isAfter(from)) {
        overlap += to.difference(from).inMinutes;
      }
      cursor = DateTime(cursor.year, cursor.month, cursor.day + 1);
    }

    return overlap;
  }

  static bool _isPerfectAttendanceForWeek({
    required List<Attendance> attendances,
    required List<int> scheduledWorkDays,
    required DateTime weekStart,
    required DateTime weekEnd,
    bool isVirtual = false,
  }) {
    if (isVirtual) return true;
    final expectedDays = <String>{};
    for (var d = weekStart;
        !d.isAfter(weekEnd);
        d = d.add(const Duration(days: 1))) {
      final code = d.weekday == DateTime.sunday ? 0 : d.weekday;
      if (!scheduledWorkDays.contains(code)) continue;
      expectedDays.add('${d.year}-${d.month}-${d.day}');
    }
    if (expectedDays.isEmpty) return true;

    final workedDays = <String>{};
    for (final a in attendances) {
      final day = DateTime(a.clockIn.year, a.clockIn.month, a.clockIn.day);
      if (day.isBefore(weekStart) || day.isAfter(weekEnd)) continue;
      workedDays.add('${day.year}-${day.month}-${day.day}');
    }
    for (final expected in expectedDays) {
      if (!workedDays.contains(expected)) return false;
    }
    return true;
  }

  static int _safeDayInMonth(int year, int month, int day) {
    final lastDay = DateTime(year, month + 1, 0).day;
    return day.clamp(1, lastDay);
  }

  static String? _actualRecorderForShift(Shift shift, List<Attendance> attendances) {
    for (final att in attendances) {
      final out = att.clockOut;
      if (out == null) continue;
      final sameWindow = att.clockIn.isAtSameMomentAs(shift.startTime) &&
          out.isAtSameMomentAs(shift.endTime);
      if (sameWindow) return att.staffId;
    }
    return null;
  }

  static ExitSettlementResult calculateExitSettlement({
    required String workerName,
    required String startDate,
    required double usedAnnualLeave,
    required double annualLeaveManualAdjustment,
    required double weeklyHours,
    required List<Attendance> allAttendances,
    required List<int> scheduledWorkDays,
    required DateTime exitDate,
    required double hourlyRate,
    required bool isFiveOrMore,
    double? manualAverageDailyWage,
    bool isVirtual = false,
  }) {
    final joinDate = DateTime.parse(startDate);
    final totalWorkingDays = exitDate.difference(joinDate).inDays + 1;
    final isSeveranceEligible = totalWorkingDays >= 365;

    // 1. 연차수당 계산
    final annualLeaveSummary = calculateAnnualLeaveSummary(
      joinDate: joinDate,
      endDate: exitDate,
      allAttendances: allAttendances,
      scheduledWorkDays: scheduledWorkDays,
      isFiveOrMore: isFiveOrMore,
      settlementPoint: exitDate,
      usedAnnualLeave: usedAnnualLeave,
      weeklyHoursPure: weeklyHours,
      hourlyRate: hourlyRate,
      manualAdjustment: annualLeaveManualAdjustment,
      isVirtual: isVirtual,
    );
    final remainingLeave = annualLeaveSummary.remaining;
    final annualLeavePayout = remainingLeave * 8 * hourlyRate;

    // 2. 퇴직금 계산 (평균임금 기반)
    double severancePay = 0;
    double averageDailyWage = manualAverageDailyWage ?? 0;
    bool requiresManualInput = false;

    if (isSeveranceEligible) {
      final threeMonthsAgo = exitDate.subtract(const Duration(days: 90));
      
      // 최근 3개월 실근무 데이터 확인
      final last3MonthsAttendances = allAttendances.where((a) => 
        a.clockIn.isAfter(threeMonthsAgo) && a.clockIn.isBefore(exitDate.add(const Duration(days: 1)))
      ).toList();

      // 실제 출근한 날짜(기록) 수 체크
      final workedDays = last3MonthsAttendances.map((a) => "${a.clockIn.year}-${a.clockIn.month}-${a.clockIn.day}").toSet().length;

      // 기록이 30일 미만이면(간소화 기준) 데이터 부족으로 판단 (가상직원은 면제)
      if (!isVirtual && workedDays < 30 && (manualAverageDailyWage == null || manualAverageDailyWage <= 0)) {
        requiresManualInput = true;
      }

      if (manualAverageDailyWage == null || manualAverageDailyWage <= 0) {
        double totalWageLast3Months = 0;
        for (final att in last3MonthsAttendances) {
          if (att.clockOut == null) continue;
          final minutes = att.clockOut!.difference(att.clockIn).inMinutes;
          totalWageLast3Months += (minutes / 60.0) * hourlyRate;
        }
        averageDailyWage = totalWageLast3Months / 90.0;
      }

      severancePay = (averageDailyWage * 30) * (totalWorkingDays / 365.0);
    }

    // 3. 퇴사월 일할 급여
    final firstDayOfExitMonth = DateTime(exitDate.year, exitDate.month, 1);
    double exitMonthWage = 0;
    final exitMonthAttendances = allAttendances.where((a) =>
      a.clockIn.isAfter(firstDayOfExitMonth.subtract(const Duration(seconds: 1))) &&
      a.clockIn.isBefore(exitDate.add(const Duration(days: 1)))
    ).toList();

    for (final att in exitMonthAttendances) {
      if (att.clockOut == null) continue;
      final minutes = att.clockOut!.difference(att.clockIn).inMinutes;
      exitMonthWage += (minutes / 60.0) * hourlyRate;
    }

    return ExitSettlementResult(
      workerName: workerName,
      joinDate: joinDate,
      exitDate: exitDate,
      totalWorkingDays: totalWorkingDays,
      isSeveranceEligible: isSeveranceEligible,
      exitMonthWage: exitMonthWage,
      remainingLeaveDays: remainingLeave,
      annualLeavePayout: annualLeavePayout,
      severancePay: severancePay,
      averageDailyWage: averageDailyWage,
      paymentDeadline: exitDate.add(const Duration(days: 14)),
      requiresManualInput: requiresManualInput,
    );
  }
}

class ExitSettlementResult {
  final String workerName;
  final DateTime joinDate;
  final DateTime exitDate;
  final int totalWorkingDays;
  final bool isSeveranceEligible;
  final double exitMonthWage;
  final double remainingLeaveDays;
  final double annualLeavePayout;
  final double severancePay;
  final double averageDailyWage;
  final DateTime paymentDeadline;
  final bool requiresManualInput;

  ExitSettlementResult({
    required this.workerName,
    required this.joinDate,
    required this.exitDate,
    required this.totalWorkingDays,
    required this.isSeveranceEligible,
    required this.exitMonthWage,
    required this.remainingLeaveDays,
    required this.annualLeavePayout,
    required this.severancePay,
    required this.averageDailyWage,
    required this.paymentDeadline,
    this.requiresManualInput = false,
  });

  double get totalSettlementAmount => 
      exitMonthWage + annualLeavePayout + severancePay;
}

