import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../models/attendance_model.dart';
import '../models/shift_model.dart';
import '../constants/payroll_constants.dart';
import 'roster_attendance.dart';
import 'app_clock.dart';

// ── 분리된 모듈 re-export (하위 호환성 유지) ──
export 'payroll/payroll_models.dart';
export 'payroll/annual_leave_calculator.dart';
export 'payroll/severance_calculator.dart';
export 'payroll/shift_substitution.dart';

import 'payroll/payroll_models.dart';
import 'payroll/annual_leave_calculator.dart';
import 'payroll/severance_calculator.dart';
import 'payroll/shift_substitution.dart';

class PayrollCalculator {
  const PayrollCalculator();

  /// Converts decimal hours (e.g., 4.5) to a human-readable string (e.g., "4시간 30분").
  static String formatHoursAsKorean(double decimalHours) {
    if (decimalHours.isNaN || decimalHours.isInfinite) return '0시간';
    if (decimalHours == 0) return '0시간';

    final sign = decimalHours < 0 ? '-' : '';
    final absVal = decimalHours.abs();
    int h = absVal.truncate();
    int m = ((absVal - h) * 60).round();

    if (h == 0) return '$sign${m}분';
    if (m == 0) return '$sign${h}시간';
    return '$sign${h}시간 ${m}분';
  }

  static double _getHourlyWageForDate(
    String wageHistoryJson,
    double defaultHourlyWage,
    DateTime targetDate,
  ) {
    if (wageHistoryJson.isEmpty) return defaultHourlyWage;
    try {
      final List<dynamic> history = jsonDecode(wageHistoryJson);
      if (history.isEmpty) return defaultHourlyWage;

      history.sort((a, b) {
        final dateA =
            DateTime.tryParse(a['effectiveDate']?.toString() ?? '') ??
            DateTime(2000);
        final dateB =
            DateTime.tryParse(b['effectiveDate']?.toString() ?? '') ??
            DateTime(2000);
        return dateB.compareTo(dateA);
      });

      for (final record in history) {
        final effectiveDateStr = record['effectiveDate']?.toString();
        if (effectiveDateStr == null) continue;
        final effectiveDate = DateTime.tryParse(effectiveDateStr);
        if (effectiveDate == null) continue;

        final eDateOnly = DateTime(
          effectiveDate.year,
          effectiveDate.month,
          effectiveDate.day,
        );
        final tDateOnly = DateTime(
          targetDate.year,
          targetDate.month,
          targetDate.day,
        );

        if (tDateOnly.compareTo(eDateOnly) >= 0) {
          return (record['hourlyWage'] as num?)?.toDouble() ??
              defaultHourlyWage;
        }
      }

      // If the target date is before all records in history, return the oldest known wage (the last element in the sorted list).
      return (history.last['hourlyWage'] as num?)?.toDouble() ??
          defaultHourlyWage;
    } catch (_) {}
    return defaultHourlyWage;
  }

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
    // ★ 진단 로그: wageHistoryJson 상태 확인
    if (workerData.wageHistoryJson.isNotEmpty) {
      print('[PayrollCalc] wageHistoryJson 활성: ${workerData.wageHistoryJson}');
    } else {
      print(
        '[PayrollCalc] ⚠️ wageHistoryJson 비어있음! hourlyRate=$hourlyRate 로 전체 기간 적용',
      );
    }

    final breakPerShift = workerData.breakMinutesPerShift;
    final paidBreak = workerData.isPaidBreak;
    // 정책: 계획 외(Unplanned) 근무는 사장님 승인(UnplannedApproved)된 건만 정산에 포함
    final mergedShifts = <Attendance>[
      ...shifts.where(isAttendanceIncludedForPayroll),
      ...substitutionShifts.where(isAttendanceIncludedForPayroll),
    ];
    final finished = mergedShifts.where((a) => a.clockOut != null).toList();

    // 수습 종료일 산출 (joinDate 기준)
    DateTime? probationEndDate;
    if (workerData.isProbation && workerData.probationMonths > 0) {
      final join = workerData.joinDate;
      probationEndDate = DateTime(
        join.year,
        join.month + workerData.probationMonths,
        join.day,
      );
    }

    int totalStayMinutes = 0;
    int totalPureMinutes = 0;
    int totalPaidBreakMinutes = 0;

    int totalOvertimeMinutes = 0;
    int totalNightMinutes = 0;
    int totalHolidayMinutes = 0;
    int totalOffDayMinutes = 0; // 월급제 휴무일(대타) 근무 분 (5/1 제외)
    int totalLaborDayMinutes = 0; // 월급제 근로자의 날(5/1) 근무 분

    double basePay = 0.0;
    double breakPay = 0.0;
    double premiumPay = 0.0;
    double laborDayAllowancePay = 0.0;
    double holidayPremiumPay = 0.0;
    double annualLeaveUsedPay = 0.0;
    int annualLeaveUsedDaysInPeriod = 0;
    final wageBreakdown = <double, double>{};

    final historicalForLeave = allHistoricalAttendances.isNotEmpty
        ? allHistoricalAttendances
        : finished;

    for (final att in finished) {
      final effectiveIn =
          att.scheduledShiftStartIso != null &&
              att.scheduledShiftStartIso!.isNotEmpty
          ? payrollEffectiveClockIn(
              actualClockIn: att.clockIn,
              scheduledStart: DateTime.parse(att.scheduledShiftStartIso!),
              graceMinutes: workerData.graceMinutes,
            )
          : att.clockIn;

      final effectiveOut = payrollSettlementClockOut(
        actualClockOut: att.clockOut!,
        scheduledShiftEndIso: att.scheduledShiftEndIso,
        overtimeApproved: att.overtimeApproved || att.isEditedByBoss,
        graceMinutes: workerData.graceMinutes,
      );
      int stayMinutes = effectiveOut.difference(effectiveIn).inMinutes;

      // 결근의 경우 체류 시간(근무 시간)을 0으로 강제
      if (att.attendanceStatus.toLowerCase() == 'absent') {
        stayMinutes = 0;
      }

      // ★ 연차유급휴가 처리 (근로기준법 제60조)
      // clockIn == clockOut (stayMinutes == 0) + isAttendanceEquivalent인 경우
      // 1일분 통상임금(계약 일일소정근로시간 x 시급) 지급
      if (stayMinutes <= 0) {
        if (att.isAttendanceEquivalent &&
            att.attendanceStatus.toLowerCase() == 'annual_leave') {
          double leaveRate = _getHourlyWageForDate(
            workerData.wageHistoryJson,
            hourlyRate,
            att.clockIn,
          );
          if (att.clockIn.year >= PayrollConstants.minimumWageEffectiveYear &&
              leaveRate < PayrollConstants.legalMinimumWage) {
            leaveRate = PayrollConstants.legalMinimumWage;
          }
          if (probationEndDate != null &&
              att.clockIn.isBefore(probationEndDate)) {
            leaveRate = (leaveRate * 0.9).floorToDouble();
          }
          final contractWorkDaysPerWeek = workerData.scheduledWorkDays.isEmpty
              ? 5.0
              : workerData.scheduledWorkDays.length.toDouble();
          final dailyContractHours = contractWorkDaysPerWeek > 0
              ? workerData.weeklyHoursPure / contractWorkDaysPerWeek
              : 8.0;
          final dailyLeavePay = dailyContractHours * leaveRate;
          annualLeaveUsedPay += dailyLeavePay;
          annualLeaveUsedDaysInPeriod++;
        }
        continue;
      }

      final appliedBreak = PayrollCalculator.calculateAppliedBreak(
        att: att,
        effectiveIn: effectiveIn,
        effectiveOut: effectiveOut,
        fallbackMinutes: breakPerShift,
        breakStartTimeStr: workerData.breakStartTime,
        breakEndTimeStr: workerData.breakEndTime,
      ).clamp(0, stayMinutes);
      final pureMinutes = stayMinutes - appliedBreak;

      totalStayMinutes += stayMinutes;
      totalPureMinutes += pureMinutes;
      if (paidBreak) totalPaidBreakMinutes += appliedBreak;

      // 기본 시급 (소급 적용 1차 평가)
      double baseRate = _getHourlyWageForDate(
        workerData.wageHistoryJson,
        hourlyRate,
        att.clockIn,
      );
      if (att.clockIn.year >= PayrollConstants.minimumWageEffectiveYear &&
          baseRate < PayrollConstants.legalMinimumWage) {
        baseRate = PayrollConstants.legalMinimumWage;
      }

      // 수습기간 90% 적용 검증
      double shiftRate = baseRate;
      if (probationEndDate != null && att.clockIn.isBefore(probationEndDate)) {
        shiftRate = (baseRate * 0.9).floorToDouble();
      }

      basePay += (pureMinutes / 60.0) * shiftRate;
      wageBreakdown[shiftRate] =
          (wageBreakdown[shiftRate] ?? 0.0) + (pureMinutes / 60.0);

      if (paidBreak) {
        breakPay += (appliedBreak / 60.0) * shiftRate;
      }

      final pmResult = _premiumTargetMinutesForAttendance(
        clockIn: effectiveIn,
        clockOut: effectiveOut,
        stayMinutes: stayMinutes,
        pureMinutes: pureMinutes,
        workerData: workerData,
      );
      // ── 가산수당 분기 (중복 가산 Double-Counting 차단) ──
      final isLaborDay = effectiveIn.month == 5 && effectiveIn.day == 1;
      final isMonthlyWorker =
          workerData.wageType == 'monthly' && workerData.monthlyWage > 0;
      final isMonthlyHolidayWork = isMonthlyWorker && pmResult.holiday > 0;

      // ★ 월급제 휴일: 연장·야간 개념 제거 (laborDayWorkPay/offDayWorkPay에서 분리 처리)
      //   월급에 유급휴일(1.0배)이 내포 → 출근 시 추가 1.0배(+0.5배 가산) 보전 필요
      //   여기서 overtime을 또 적립하면 과지급 발생
      if (isMonthlyWorker && isLaborDay && pmResult.holiday > 0) {
        totalLaborDayMinutes += pmResult.holiday;
        totalHolidayMinutes += pmResult.holiday;
        // ★ overtime/night는 적립하지 않음 — laborDayWorkPay가 전담
      } else if (isMonthlyHolidayWork) {
        totalOffDayMinutes += pmResult.holiday;
        totalHolidayMinutes += pmResult.holiday;
        // ★ overtime/night는 적립하지 않음 — offDayWorkPay가 전담
      } else {
        totalOvertimeMinutes += pmResult.overtime;
        totalNightMinutes += pmResult.night;
        totalHolidayMinutes += pmResult.holiday;
      }

      if (isFiveOrMore) {
        if (isMonthlyHolidayWork) {
          // ★ 월급제 휴일(대타+5/1): 가산 전부 스킵 — extraOffDayPay에서 통합 처리
          //   (기본 1.0 + 가산 0.5 = 1.5배 통합)
        } else if (isLaborDay) {
          // 시급제 근로자의 날: 전체 가산(연장+야간+휴일) → holidayPremiumPay 전담
          final totalPmIns =
              pmResult.overtime + pmResult.night + pmResult.holiday;
          holidayPremiumPay += (totalPmIns / 60.0) * shiftRate * 0.5;
        } else {
          // 시급제 일반 근무: 기존 로직 유지
          final totalPmIns =
              pmResult.overtime + pmResult.night + pmResult.holiday;
          premiumPay += (totalPmIns / 60.0) * shiftRate * 0.5;
        }
      }
      // ★ 5인 미만: 가산 의무 없음 (0.5배 미적용)
      //   단, totalOffDayMinutes는 적립 → 월급제 extraOffDayPay에서 기본(1.0배) 보전

      // 주휴수당 판정용 weekPure는 엔진 B에서 별도로 historical 기록을 스캔하여 합산합니다.
    }

    final pureLaborHours = totalPureMinutes / 60.0;
    final paidBreakHours = totalPaidBreakMinutes / 60.0;
    final stayHours = totalStayMinutes / 60.0;
    final premiumHours =
        (totalOvertimeMinutes + totalNightMinutes + totalHolidayMinutes) / 60.0;

    // 주휴수당에서도 동일한 소급 기준을 두기 위해 현재 기간의 마지막 날 기준으로 평가
    double referenceRate = hourlyRate;
    if (periodEnd.year >= PayrollConstants.minimumWageEffectiveYear &&
        referenceRate < PayrollConstants.legalMinimumWage) {
      referenceRate = PayrollConstants.legalMinimumWage;
    }

    // 전체 급여 기간 기준 결근 여부 스캔 (UI 상단 '만근 여부' 표기용)
    final isPerfectAttendance = _isPerfectAttendanceForRange(
      attendances: finished,
      scheduledWorkDays: workerData.scheduledWorkDays,
      rangeStart: periodStart,
      rangeEnd: periodEnd,
      isVirtual: workerData.isVirtual,
      joinDate: workerData.joinDate,
      endDate: workerData.endDate,
    );

    // 엔진 A: 주휴수당 7일 묶음 달력 생성 (weeklyHolidayDay 기준)
    final weekSegments = _generateStandardWeeksInPeriod(
      periodStart,
      periodEnd,
      workerData.weeklyHolidayDay,
    );

    // 엔진 B: 주휴수당 판별 및 합산
    double weeklyHolidayPay = 0.0;
    bool isWeeklyHolidayEligible = false;
    bool weeklyHolidayBlockedByAbsence = false;
    bool hasExtraWeekOver15 = false;

    for (int wi = 0; wi < weekSegments.length; wi++) {
      final (wStart, wEnd) = weekSegments[wi];

      // 1. 해당 주차에 대한 만근 여부를 전체 기록(historical)에서 판별
      final perfectAttendanceWeek = _isPerfectAttendanceForRange(
        attendances: historicalForLeave,
        scheduledWorkDays: workerData.scheduledWorkDays,
        rangeStart: wStart,
        rangeEnd: wEnd,
        isVirtual: workerData.isVirtual,
        joinDate: workerData.joinDate,
        endDate: workerData.endDate,
      );

      // 2. 해당 주차의 실제 순수 일한 시간 계산 모으기
      double weekPure = 0.0;
      for (final att in historicalForLeave) {
        if (att.clockOut == null) continue;
        if (_attendanceTouchesRange(att, wStart, wEnd)) {
          final effectiveIn =
              att.scheduledShiftStartIso != null &&
                  att.scheduledShiftStartIso!.isNotEmpty
              ? payrollEffectiveClockIn(
                  actualClockIn: att.clockIn,
                  scheduledStart: DateTime.parse(att.scheduledShiftStartIso!),
                  graceMinutes: workerData.graceMinutes,
                )
              : att.clockIn;
          final effectiveOut = payrollSettlementClockOut(
            actualClockOut: att.clockOut!,
            scheduledShiftEndIso: att.scheduledShiftEndIso,
            overtimeApproved: att.overtimeApproved || att.isEditedByBoss,
            graceMinutes: workerData.graceMinutes,
          );
          final stayMinutes = effectiveOut.difference(effectiveIn).inMinutes;
          if (stayMinutes > 0) {
            final appliedBreak = PayrollCalculator.calculateAppliedBreak(
              att: att,
              effectiveIn: effectiveIn,
              effectiveOut: effectiveOut,
              fallbackMinutes: breakPerShift,
              breakStartTimeStr: workerData.breakStartTime,
              breakEndTimeStr: workerData.breakEndTime,
            ).clamp(0, stayMinutes);
            weekPure += (stayMinutes - appliedBreak) / 60.0;
          }
        }
      }

      // [노무법 준수] 조퇴/지각으로 실제 근무시간(weekPure)이 15시간 미만으로 떨어져도,
      // 계약된 시간(weeklyHoursPure)이 15시간 이상이라면 주휴수당 발생 조건을 충족함.
      final baseHoursForEligibility = workerData.weeklyHoursPure > 0
          ? workerData.weeklyHoursPure
          : weekPure;

      // [노무법 예외 수동 승인]
      // 15시간 미만 계약자라도, 사장님이 대타 등으로 15시간 초과한 주에 대해
      // 수동으로 주휴수당 지급을 승인한 경우 (manualWeeklyHolidayApproval),
      // 실제 근로시간(weekPure)이 15시간 이상이라면 예외적으로 대상을 충족시킨다.
      final isApprovedException =
          workerData.manualWeeklyHolidayApproval && weekPure >= 15.0;

      // 15시간 미만 계약자가 대타 등으로 15시간 초과 근무한 주 감지
      if (workerData.weeklyHoursPure < 15.0 && weekPure >= 15.0) {
        hasExtraWeekOver15 = true;
      }

      if (baseHoursForEligibility >= 15.0 || isApprovedException) {
        if (!perfectAttendanceWeek) {
          weeklyHolidayBlockedByAbsence = true;
        }

        if (perfectAttendanceWeek || workerData.manualWeeklyHolidayApproval) {
          isWeeklyHolidayEligible = true;
        }

        // ★ 결근이어도 사장님이 [지급 승인] 스위치를 켜면 주휴수당 계산 진행
        //   스위치 OFF이고 결근일 때만 skip (기존 || 에서 && 로 변경)
        if (!workerData.manualWeeklyHolidayApproval && !perfectAttendanceWeek) {
          continue;
        }

        final maxAllowedHours =
            (workerData.weeklyHoursPure > 0 && !isApprovedException)
            ? workerData.weeklyHoursPure
            : 40.0;
        double calcHours = weekPure > maxAllowedHours
            ? maxAllowedHours
            : weekPure;
        if (calcHours > 40.0) calcHours = 40.0;

        double currentWeekRefRate = referenceRate;
        if (probationEndDate != null && wEnd.isBefore(probationEndDate)) {
          currentWeekRefRate = (currentWeekRefRate * 0.9).floorToDouble();
        }

        weeklyHolidayPay += ((calcHours / 40.0) * 8.0 * currentWeekRefRate);
      }
    }

    // 5월 1일 근로자의 날 유급휴일수당 (출근하지 않아도 지급)
    // ★ 입사일이 5/1 이전인 경우에만 지급 (5/1 이후 입사자는 대상 아님)
    for (int y = periodStart.year; y <= periodEnd.year; y++) {
      final ld = DateTime(y, 5, 1);
      final pS = DateTime(periodStart.year, periodStart.month, periodStart.day);
      final pE = DateTime(
        periodEnd.year,
        periodEnd.month,
        periodEnd.day,
        23,
        59,
        59,
      );
      final now = AppClock.now();
      final today = DateTime(now.year, now.month, now.day, 23, 59, 59);
      // ★ joinDate 검증: 근로자의 날 당일 또는 이전에 입사해야 수당 대상
      final joinDateOnly = DateTime(
        workerData.joinDate.year,
        workerData.joinDate.month,
        workerData.joinDate.day,
      );
      if (workerData.wageType != 'monthly' &&
          ld.compareTo(pS) >= 0 &&
          ld.compareTo(pE) <= 0 &&
          ld.compareTo(today) <= 0 &&
          !joinDateOnly.isAfter(ld)) {
        // ★ 입사일 <= 5/1
        final weeklyH = workerData.weeklyHoursPure > 0
            ? workerData.weeklyHoursPure
            : 40.0;
        final calcHours = weeklyH > 40.0 ? 40.0 : weeklyH;
        double currentLdRefRate = referenceRate;
        if (probationEndDate != null && ld.isBefore(probationEndDate)) {
          currentLdRefRate = (currentLdRefRate * 0.9).floorToDouble();
        }
        laborDayAllowancePay += (calcHours / 40.0) * 8.0 * currentLdRefRate;
      }
    }

    double otherAllowancePay = workerData.allowanceAmounts.fold<double>(
      0.0,
      (s, v) => s + v,
    );

    final totalPay =
        basePay +
        breakPay +
        premiumPay +
        holidayPremiumPay +
        laborDayAllowancePay +
        weeklyHolidayPay +
        otherAllowancePay;

    final effectiveWeeklyHours = workerData.weeklyHoursPure > 0
        ? workerData.weeklyHoursPure
        : (workerData.wageType == 'monthly'
              ? 40.0
              : workerData.weeklyTotalStayMinutes / 60.0);

    final needsBreakSeparationGuide =
        (effectiveWeeklyHours < 15) &&
        (workerData.weeklyTotalStayMinutes / 60.0 >= 15);
    final hasSubstitutionRisk =
        substitutionShifts.isNotEmpty &&
        ((isWeeklyHolidayEligible && effectiveWeeklyHours < 15) ||
            isFiveOrMore);
    // 연차 저금통 산출
    final leaveSummary = AnnualLeaveCalculator.calculateAnnualLeaveSummary(
      joinDate: workerData.joinDate,
      endDate: workerData.endDate,
      allAttendances: historicalForLeave,
      scheduledWorkDays: workerData.scheduledWorkDays,
      isFiveOrMore: isFiveOrMore,
      settlementPoint: periodEnd,
      usedAnnualLeave: workerData.usedAnnualLeave,
      weeklyHoursPure: effectiveWeeklyHours,
      hourlyRate: hourlyRate,
      manualAdjustment: workerData.manualAdjustment,
      initialAdjustment: workerData.initialAdjustment,
      initialAdjustmentReason: workerData.initialAdjustmentReason,
      promotionLogs: workerData.promotionLogs,
      isVirtual: workerData.isVirtual,
    );
    // ★ 연차수당 = 퇴사 정산분(미사용 잔여) + 재직 중 사용분(유급휴가 임금)
    final annualLeaveAllowancePay =
        leaveSummary.annualLeaveAllowancePay + annualLeaveUsedPay;
    final hourlyBasedTotalPay = totalPay + annualLeaveAllowancePay;

    // ──────────────────────────────────────────────
    // ★ 월급제 로직: 기본급/수당 분리 산출 (2026.5.9 포괄임금 오남용 방지 지침 준수)
    // - 정액급제라도 기본급과 각종 수당을 구분하여 산출
    // - 실근로시간 기반 연장수당 산출 및 고정OT 차액 자동 보전
    // ──────────────────────────────────────────────
    final isMonthly =
        workerData.wageType == 'monthly' && workerData.monthlyWage > 0;
    double finalTotalPay = hourlyBasedTotalPay;
    double monthlyBasePayCalc = 0.0;
    double proRataRatio = 1.0;
    double fixedOvertimeExcessHours = 0.0;
    double fixedOvertimeExcessPay = 0.0;
    bool minimumWageWarning = false;
    bool minimumWageHardBlock = false;
    double calculatedConservativeHourly = 0.0;
    double calculatedReferenceHourly = 0.0;
    double calculatedScheduledHours = 0.0;
    double calculatedMealPay = 0.0;
    double calculatedWeeklyHolidayPay = 0.0;
    double calculatedFixedOTBasePay = 0.0;
    double calculatedWeeklyHolidayHours = 0.0;
    double sLegal = 0.0;
    double sRef = 0.0;
    double calculatedLaborDayWorkPay = 0.0;
    double calculatedLaborDayWorkHours = 0.0;
    double calculatedOffDayWorkPay = 0.0;
    double calculatedOffDayWorkHours = 0.0;
    double calculatedBaseHourlyWage = 0.0;

    if (isMonthly) {
      // ★ 기본급 = monthlyWage (순수 기본급, 식대·고정OT 미포함)
      //   add_staff_screen에서 기본급만 monthlyWage에 저장하고,
      //   식대(mealAllowance)와 고정OT(fixedOvertimePay)는 별도 필드로 저장됨
      //   예: monthlyWage=2,156,880 / mealAllowance=200,000 / fixedOT=143,120
      //       → 총급여 = 2,156,880 + 200,000 + 143,120 = 2,500,000원
      final baseSalary = workerData.monthlyWage;
      final mealPay = workerData.mealAllowance;
      final fixedOTHours = workerData.fixedOvertimeHours;

      // ================================================================
      // 1. 가변형 소정근로시간(S) 이중 구조
      //    주휴시간(A) = 주당 소정근로시간 / 소정근로일수
      //    S_Legal = (주당근로 + 주휴) × (해당월 일수 / 7)  [달력 기반, 법적 판정용]
      //    S_Ref   = (주당근로 + 주휴) × 4.345             [고정, 참고용]
      //    최저임금 판정은 반드시 S_Legal 사용
      //    주 6일제, 3일제 등 모든 근무 형태 대응
      // ================================================================
      final weeklyH = workerData.weeklyHoursPure > 0
          ? workerData.weeklyHoursPure
          : 40.0;
      final workDaysPerWeek = workerData.scheduledWorkDays.isNotEmpty
          ? workerData.scheduledWorkDays.length.toDouble()
          : 5.0; // fallback
      final weeklyHolidayH = weeklyH >= 15 ? weeklyH / workDaysPerWeek : 0.0;

      // S_Legal: 달력 기반 (법적 판정용 - 더 보수적)
      final daysInMonth = DateTime(
        periodStart.year,
        periodStart.month + 1,
        0,
      ).day;
      final weeksInMonthLegal = daysInMonth / 7.0;
      sLegal = (weeklyH + weeklyHolidayH) * weeksInMonthLegal;

      // S_Ref: 고정 4.345 → ceil (209시간 기준, 정부 고시)
      sRef = ((weeklyH + weeklyHolidayH) * 4.345).ceilToDouble();

      // baseMonthlyHours: 주휴수당 표시용 (달력 기반, 지급 계산에는 사용 안 함)
      final baseMonthlyHours = weeklyH * weeksInMonthLegal;

      // ================================================================
      // 2. 통상시급 (최저임금 검증 + 초과연장 가산수당 계산 전용)
      // ================================================================

      // 중도 입/퇴사자 출근일수 분별 (수습 비율을 구하기 위해 먼저 위치시킴)
      final periodMonth = periodStart.month;
      final periodYear = periodStart.year;
      final totalDaysInMonth = DateTime(periodYear, periodMonth + 1, 0).day;

      final joinDate = workerData.joinDate;
      final endDate = workerData.endDate;

      final isMidMonthJoin = joinDate.isAfter(periodStart);
      final isMidMonthQuit = endDate != null && endDate.isBefore(periodEnd);

      final activeStart = isMidMonthJoin ? joinDate : periodStart;
      final activeEnd = isMidMonthQuit ? endDate : periodEnd;
      final activeDays = activeEnd.difference(activeStart).inDays + 1;

      // 전체 기간에 대한 출근 비율 (중도 입퇴사 고려)
      if (isMidMonthJoin || isMidMonthQuit) {
        proRataRatio = (activeDays / totalDaysInMonth).clamp(0.0, 1.0);
      } else {
        proRataRatio = 1.0;
      }

      // 수습기간 혼합 비율(effectiveRatio) 산출 (옵션 A 정교한 일할계산)
      double effectiveRatio = proRataRatio;
      if (probationEndDate != null && activeStart.isBefore(probationEndDate)) {
        if (activeEnd.isBefore(probationEndDate)) {
          // 전 기간 수습 (전부 90%)
          effectiveRatio = proRataRatio * 0.9;
        } else {
          // 수습과 정상이 섞인 달
          final probationDays = probationEndDate!
              .difference(activeStart)
              .inDays;
          final normalDays = activeDays - probationDays;

          final probationRatio = (probationDays / totalDaysInMonth) * 0.9;
          final normalRatio = (normalDays / totalDaysInMonth) * 1.0;
          effectiveRatio = probationRatio + normalRatio;
        }
      }

      // 수습 반영 시급 도출 (초과연장 계산 시 단가 하락 반영)
      final probationDiscountOnly = proRataRatio > 0
          ? (effectiveRatio / proRataRatio)
          : 1.0;

      final realOtherAllowance = (otherAllowancePay - mealPay).clamp(
        0.0,
        double.infinity,
      );

      final conservativeHourly = sRef > 0
          ? ((baseSalary + 
              (workerData.includeMealInOrdinary ? mealPay : 0) + 
              (workerData.includeAllowanceInOrdinary ? realOtherAllowance : 0)
             ) * probationDiscountOnly) / sRef
          : 0.0; // 초과연장 가산수당 및 최저임금 검증 전용

      // ★ 기본시급 (baseSalary / sRef, 식대 제외) — UI 주휴수당 표시 전용
      final baseHourly = sRef > 0
          ? (baseSalary * probationDiscountOnly) / sRef
          : 0.0;

      // ★ [Contract DB Pass-through] 고정연장수당 = DB 계약 확정값 사용
      final fixedOTPayCalc = workerData.fixedOvertimePay;

      // 총보상 = 기본급 + 고정OT + 식대 + 기타수당
      final totalCompensation = baseSalary + fixedOTPayCalc + mealPay;
      final referenceHourly = sRef > 0 ? totalCompensation / sRef : 0.0;

      // 주휴수당 (기본급에 포함, 명세서 표시용 — 기본시급 기준)
      // ★ 월급제 주휴시간: S_Ref 고정 기준 비율 산출 (달력 의존 제거)
      //   공식: sRef × (weeklyHolidayH / (weeklyH + weeklyHolidayH))
      //   예시: 209 × (8 / 48) = 34.8333... → 34.8h (소수 1자리 반올림)
      //   ★ 반올림 후 금액 산출 → UI 표시 시간과 검산 금액이 정확히 일치
      final weeklyHolidayHoursRaw = (weeklyH + weeklyHolidayH) > 0
          ? sRef * (weeklyHolidayH / (weeklyH + weeklyHolidayH))
          : 0.0;
      final weeklyHolidayHoursFixed = double.parse(
        weeklyHolidayHoursRaw.toStringAsFixed(1),
      );
      final weeklyHolidayPayCalc = baseHourly * weeklyHolidayHoursFixed;

      monthlyBasePayCalc = baseSalary;

      // ================================================================
      // 3. 일할 계산 및 수습 비례 적용 (Pro-rata)
      // ================================================================

      // proRata 및 수습(effectiveRatio) 적용된 각 구성요소
      final proRataBase = baseSalary * effectiveRatio;
      final proRataMeal = mealPay * effectiveRatio;
      final proRataFixedOT = fixedOTPayCalc * effectiveRatio;

      // mealPay가 allowanceAmounts에 이미 포함되어 있으므로 중복 합산을 방지하기 위해 기타수당에서 차감
      final proRataOtherAllowance = realOtherAllowance * effectiveRatio;

      // 총 지급액 = 구성요소 합산 + 연차수당 + 근로자의날수당 + 휴일근로가산
      // ★ laborDayAllowancePay는 월급제에서 이미 0 (L930 조건으로 차단됨)
      // ★ holidayPremiumPay는 실제 5/1 출근 기록이 있을 때만 L791-799에서 적립됨
      // ★ 월급제: 연차 사용일 임금은 이미 월급에 내포 → annualLeaveUsedPay 제외
      //   퇴사 정산분(미사용 잔여 연차)만 추가 지급
      final monthlyAnnualLeavePay =
          annualLeaveAllowancePay - annualLeaveUsedPay;
      finalTotalPay =
          proRataBase +
          proRataFixedOT +
          proRataMeal +
          proRataOtherAllowance +
          monthlyAnnualLeavePay +
          laborDayAllowancePay +
          holidayPremiumPay;

      // 명세서 상 "기타 수당" 표기를 위해 덮어쓰기 (식대 제외한 순수 기타 수당)
      otherAllowancePay =
          proRataOtherAllowance +
          proRataMeal; // UI에서 식대를 기타수당과 합쳐서 보여줌 (만약 분리된 UI가 없다면)
      // ================================================================
      // 4. 2단계 최저임금 '데드라인' 검증
      //    정부 고시 기준 S_Ref(4.345) 사용 (예: 209시간 기준 고시 금액 통과)
      //    [1단계 Hard Block]: 기본급 / S_Ref < 10,320 → 저장 차단
      //    [2단계 Warning]: (기본급 + 식대) / S_Ref < 10,320 → 경고
      // ================================================================
      // 1단계: 기본급만으로 검증 (S_Ref 기준 - 정부 고시 동일)
      final minWageHourlyRef = sRef > 0 ? baseSalary / sRef : 0.0;
      if (sRef > 0 && minWageHourlyRef < PayrollConstants.legalMinimumWage) {
        minimumWageHardBlock = true;
        minimumWageWarning = true;
      }
      // 2단계: 기본급 + 식대 합산 검증
      if (!minimumWageHardBlock && sRef > 0) {
        final combinedHourly = (baseSalary + mealPay) / sRef;
        if (combinedHourly < PayrollConstants.legalMinimumWage) {
          minimumWageWarning = true;
        }
      }

      // S_Legal 방패 경고는 월급제(고정급)에서 비활성화
      // 월급제는 S_Ref(4.345) 단일 기준으로만 검증
      // S_Legal은 시급제의 '예상 월급' 계산에서만 활용

      // ================================================================
      // 5. 실근로시간 기반 연장수당 차액 보전 + 5인 규모 분기
      //    ★ 초과연장: 기본급에 미포함 → isFiveOrMore ? 1.5배 : 1.0배
      //    ★ 야간가산: 기본 1.0배는 월급에 이미 산입 → 순수 가산분 0.5배만 추가
      //    ★ 5인 미만: 야간가산 면제 (0원)
      //    휴일근로가산(holidayPremiumPay)은 이미 L791에서 별도 적립됨
      // ================================================================
      final overtimeHoursOnly = totalOvertimeMinutes / 60.0;
      final nightOnlyPremiumHours = totalNightMinutes / 60.0;
      final holidayHoursOnly = totalHolidayMinutes / 60.0;

      // ★ 5인 미만: 야간가산 면제 → nightHours = 0
      final effectiveNightHours = isFiveOrMore ? nightOnlyPremiumHours : 0.0;
      // ★ 5인 규모에 따른 연장가산율: 5인 이상 1.5배, 5인 미만 1.0배
      final double overtimeMultiplier = isFiveOrMore ? 1.5 : 1.0;

      if (fixedOTHours > 0) {
        // 고정 OT 약정 있음: 순수 연장근로가 약정시간 초과 시 차액 보전
        if (overtimeHoursOnly > fixedOTHours) {
          fixedOvertimeExcessHours = overtimeHoursOnly - fixedOTHours;
        } else {
          fixedOvertimeExcessHours = 0.0;
        }

        // 초과연장 × 가산율 + 야간 × 0.5 (순수 가산분만, 기본 1.0은 월급에 포함)
        fixedOvertimeExcessPay =
            (fixedOvertimeExcessHours *
                conservativeHourly *
                overtimeMultiplier) +
            (effectiveNightHours * conservativeHourly * 0.5);
        finalTotalPay += fixedOvertimeExcessPay;
      } else if (premiumHours > 0) {
        // 고정OT 약정 없음: 실제 연장 전액 추가 지급
        fixedOvertimeExcessHours = overtimeHoursOnly;
        fixedOvertimeExcessPay =
            (overtimeHoursOnly * conservativeHourly * overtimeMultiplier) +
            (effectiveNightHours * conservativeHourly * 0.5);
        finalTotalPay += fixedOvertimeExcessPay;
      }

      // ================================================================
      // 6. 휴일근무 수당 — 근로자의 날(5/1)과 휴무일(대타) 분리
      //    ★ 5인 이상: 1.5배 (기본 1.0 + 가산 0.5)
      //    ★ 5인 미만: 1.0배 (기본만, 가산 의무 없음)
      // ================================================================
      final holidayMultiplier = isFiveOrMore ? 1.5 : 1.0;

      // 6-1. 근로자의 날(5/1) 출근수당
      double laborDayWorkPay = 0.0;
      final laborDayHours = totalLaborDayMinutes / 60.0;
      if (laborDayHours > 0) {
        laborDayWorkPay =
            laborDayHours * conservativeHourly * holidayMultiplier;
        finalTotalPay += laborDayWorkPay;
      }

      // 6-2. 휴무일(대타) 출근수당
      double offDayWorkPay = 0.0;
      final offDayHours = totalOffDayMinutes / 60.0;
      if (offDayHours > 0) {
        offDayWorkPay = offDayHours * conservativeHourly * holidayMultiplier;
        finalTotalPay += offDayWorkPay;
      }

      // 외부 스코프에 저장 (Result 전달용)
      calculatedLaborDayWorkPay = laborDayWorkPay;
      calculatedLaborDayWorkHours = laborDayHours;
      calculatedOffDayWorkPay = offDayWorkPay;
      calculatedOffDayWorkHours = offDayHours;

      // 월급제는 UI의 "가산 수당" 행에 약정된 고정OT와 초과 연장수당 + 휴일수당을 합쳐서 보여줍니다.
      premiumPay =
          proRataFixedOT +
          fixedOvertimeExcessPay +
          laborDayWorkPay +
          offDayWorkPay;

      // 임금명세서용 중간값 저장 (proRataRatio 반영됨: 정상근무=1.0, 중도입퇴사=비율)
      calculatedConservativeHourly = conservativeHourly;
      calculatedReferenceHourly = referenceHourly;
      calculatedScheduledHours = sRef; // ★ S_Ref(209h) 기준 통일 — S_Legal 사용 금지
      calculatedMealPay = proRataMeal;
      calculatedWeeklyHolidayPay = weeklyHolidayPayCalc * proRataRatio;
      calculatedFixedOTBasePay = proRataFixedOT;
      calculatedWeeklyHolidayHours = weeklyHolidayHoursFixed;
      calculatedBaseHourlyWage = baseHourly;
    }

    // --- 대한민국 노무 표준 가이드 산식 적용 ---
    // 1. 비과세 식대: 사장님이 비과세 적용을 선택한 경우에만 적용 (최대 20만 원)
    final mealNonTaxable = workerData.mealTaxExempt
        ? (workerData.mealAllowance >= 200000
              ? 200000.0
              : workerData.mealAllowance)
        : 0.0;

    // 2. 과세 대상액 (A)
    final taxableWage = (finalTotalPay - mealNonTaxable).clamp(
      0.0,
      double.infinity,
    );

    // 3. 보험 및 세금 공제액 (B)
    double insuranceDeduction = 0.0;

    double nationalPension = 0.0;
    double healthInsurance = 0.0;
    double longTermCareInsurance = 0.0;
    double employmentInsurance = 0.0;
    double businessIncomeTax = 0.0;
    double localIncomeTax = 0.0;

    if (workerData.applyWithholding33) {
      // 3.3% 사업소득세: 국세 3%, 지방세 0.3%
      businessIncomeTax = ((taxableWage * 0.03) / 10).floor() * 10.0;
      localIncomeTax = ((taxableWage * 0.003) / 10).floor() * 10.0;
      insuranceDeduction = businessIncomeTax + localIncomeTax;
    } else {
      // 4대 보험 적용 (각 항목별 원 단위 절사 계산)
      if (workerData.deductNationalPension) {
        nationalPension = ((taxableWage * 0.045) / 10).floor() * 10.0;
      }
      if (workerData.deductHealthInsurance) {
        // 건강보험 (약 3.545% 기준 적용)
        healthInsurance = ((taxableWage * 0.03545) / 10).floor() * 10.0;
        // 장기요양 (건강보험료의 약 12.95%)
        longTermCareInsurance =
            ((healthInsurance * 0.1295) / 10).floor() * 10.0;
      }
      if (workerData.deductEmploymentInsurance) {
        // 고용보험 (실업급여 0.9%)
        employmentInsurance = ((taxableWage * 0.009) / 10).floor() * 10.0;
      }
      insuranceDeduction =
          nationalPension +
          healthInsurance +
          longTermCareInsurance +
          employmentInsurance;
    }

    // 4. 최종 실지급액 = 세전 총액 - 공제액 + 전월 정산금(C)
    final netPay =
        finalTotalPay - insuranceDeduction + workerData.previousMonthAdjustment;

    return PayrollCalculationResult(
      basePay: isMonthly ? monthlyBasePayCalc * proRataRatio : basePay,
      breakPay: isMonthly ? 0.0 : breakPay,
      premiumPay: premiumPay,
      laborDayAllowancePay: laborDayAllowancePay,
      holidayPremiumPay: holidayPremiumPay,
      weeklyHolidayPay: isMonthly ? 0.0 : weeklyHolidayPay, // 월급제는 주휴가 월급에 내포
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
      hasExtraWeekOver15: hasExtraWeekOver15,
      annualLeaveSummary: leaveSummary,
      taxableWage: taxableWage,
      insuranceDeduction: insuranceDeduction,
      nationalPension: nationalPension,
      healthInsurance: healthInsurance,
      longTermCareInsurance: longTermCareInsurance,
      employmentInsurance: employmentInsurance,
      businessIncomeTax: businessIncomeTax,
      localIncomeTax: localIncomeTax,
      mealNonTaxable: mealNonTaxable,
      previousMonthAdjustment: workerData.previousMonthAdjustment,
      netPay: netPay,
      isMonthlyWage: workerData.wageType == 'monthly',
      monthlyBasePay: monthlyBasePayCalc,
      proRataRatio: proRataRatio,
      fixedOvertimeExcessHours: fixedOvertimeExcessHours,
      fixedOvertimeExcessPay: fixedOvertimeExcessPay,
      minimumWageWarning: minimumWageWarning,
      mealAllowancePay: calculatedMealPay,
      conservativeHourlyWage: calculatedConservativeHourly,
      referenceHourlyWage: calculatedReferenceHourly,
      scheduledMonthlyHours: calculatedScheduledHours,
      weeklyHolidayPayInMonthly: calculatedWeeklyHolidayPay,
      fixedOvertimeBasePay: calculatedFixedOTBasePay,
      fixedOvertimeAgreedHours: workerData.wageType == 'monthly'
          ? workerData.fixedOvertimeHours
          : 0.0,
      weeklyHolidayHoursInMonthly: workerData.wageType == 'monthly'
          ? calculatedWeeklyHolidayHours
          : 0.0,
      minimumWageHardBlock: minimumWageHardBlock,
      scheduledMonthlyHoursLegal: sLegal,
      scheduledMonthlyHoursRef: sRef,
      isFiveOrMore: isFiveOrMore,
      laborDayWorkPay: calculatedLaborDayWorkPay,
      laborDayWorkHours: calculatedLaborDayWorkHours,
      offDayWorkPay: calculatedOffDayWorkPay,
      offDayWorkHours: calculatedOffDayWorkHours,
      baseHourlyWage: calculatedBaseHourlyWage,
      payslipHash: _generatePayslipHash(
        basePay: monthlyBasePayCalc,
        mealPay: calculatedMealPay,
        fixedOTPay: calculatedFixedOTBasePay,
        excessOTPay: fixedOvertimeExcessPay,
        totalPay: finalTotalPay,
        periodDate: periodStart,
      ),
      basePayBreakdownByWage: wageBreakdown,
    );
  }

  /// SHA-256 해시 생성 (분쟁 방어 증거 봉인)
  static String _generatePayslipHash({
    required double basePay,
    required double mealPay,
    required double fixedOTPay,
    required double excessOTPay,
    required double totalPay,
    required DateTime periodDate,
  }) {
    final hashInput =
        'base:${basePay.toStringAsFixed(0)}'
        '|meal:${mealPay.toStringAsFixed(0)}'
        '|fixedOT:${fixedOTPay.toStringAsFixed(0)}'
        '|excessOT:${excessOTPay.toStringAsFixed(0)}'
        '|total:${totalPay.toStringAsFixed(0)}'
        '|date:${periodDate.toIso8601String()}';
    return sha256.convert(utf8.encode(hashInput)).toString();
  }

  /// 급여 정산에 포함할 출근 기록인지 판별
  ///
  /// 【attendanceStatus 생명주기】
  ///   Normal           → 정상 출근 (급여 포함 ✅)
  ///   UnplannedApproved → 스케줄 외 근무 승인됨 (급여 포함 ✅)
  ///   early_clock_out  → 조기 퇴근 확정 (급여 포함 ✅)
  ///   Unplanned        → 스케줄 외 출근 (사장 승인 전, 급여 제외 ❌)
  ///   pending_approval → 조기 출근 승인 대기 (급여 제외 ❌)
  ///   pending_overtime → 연장 근무 승인 대기 (급여 제외 ❌)
  ///   early_leave_pending → 조기 퇴근 승인 대기 (급여 제외 ❌)
  ///
  /// ⚠️ 'rejected' 상태는 현재 미사용. 반려 시 'Normal' + overtimeApproved=false로 복원됨.
  static bool isAttendanceIncludedForPayroll(Attendance attendance) {
    final status = attendance.attendanceStatus.trim().toLowerCase();
    if (status == 'unplanned' ||
        status == 'pending_approval' ||
        status == 'pending_overtime' ||
        status == 'early_leave_pending') {
      return false;
    }
    return true;
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
      final day = DateTime(
        att.clockIn.year,
        att.clockIn.month,
        att.clockIn.day,
      );
      if (day.isBefore(periodStart) || day.isAfter(periodEnd)) continue;
      dailyStaff.putIfAbsent(day, () => <String>{}).add(att.staffId);
    }

    // 2. 가상직원 시뮬레이션 반영 (테스트 편의용)
    if (virtualStaffSchedules != null && virtualStaffSchedules.isNotEmpty) {
      for (int i = 0; i < totalDays; i++) {
        final day = DateTime(
          periodStart.year,
          periodStart.month,
          periodStart.day + i,
        );
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
    int daysWithFiveOrMore = 0;
    int daysWithLessThanFive = 0;

    for (int i = 0; i < totalDays; i++) {
      final day = DateTime(
        periodStart.year,
        periodStart.month,
        periodStart.day + i,
      );
      final count = dailyStaff[day]?.length ?? 0;
      if (count > 0) {
        operatingDays++;
        totalPersonDays += count;
        if (count >= 5) {
          daysWithFiveOrMore++;
        } else {
          daysWithLessThanFive++;
        }
      }
    }

    if (operatingDays == 0) return false;

    final avg = totalPersonDays / operatingDays;

    // 근로기준법 시행령 제7조의2 (상시 사용하는 근로자 수의 산정 방법) 예외 조항 적용
    if (avg < 5.0) {
      // 평균 5명 미만이더라도 5명 이상인 일수가 가동일수의 1/2 이상이면 5인 이상 사업장으로 본다
      if (daysWithFiveOrMore >= (operatingDays / 2.0)) {
        return true;
      }
      return false;
    } else {
      // 평균 5명 이상이더라도 5명 미만인 일수가 가동일수의 1/2 이상이면 5인 미만 사업장으로 본다
      if (daysWithLessThanFive >= (operatingDays / 2.0)) {
        return false;
      }
      return true;
    }
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
        overtimeApproved: att.overtimeApproved || att.isEditedByBoss,
      );
      final stayMinutes = effectiveOut.difference(att.clockIn).inMinutes;
      if (stayMinutes <= 0) continue;
      final breakMinutes = calculateAppliedBreak(
        att: att,
        effectiveIn: att.clockIn,
        effectiveOut: effectiveOut,
        fallbackMinutes: defaultBreakMinutesPerShift,
        breakStartTimeStr: '',
        breakEndTimeStr: '',
      ).clamp(0, stayMinutes);
      pureHours += (stayMinutes - breakMinutes) / 60.0;
    }
    return pureHours >= 15.0;
  }

  // ─── 하위 호환 위임 메서드 (분리된 모듈로 전달) ───

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
    double initialAdjustment = 0.0,
    String initialAdjustmentReason = '',
    List<LeavePromotionStatus> promotionLogs = const [],
    bool isVirtual = false,
  }) => AnnualLeaveCalculator.calculateAnnualLeaveSummary(
    joinDate: joinDate,
    endDate: endDate,
    allAttendances: allAttendances,
    scheduledWorkDays: scheduledWorkDays,
    isFiveOrMore: isFiveOrMore,
    settlementPoint: settlementPoint,
    usedAnnualLeave: usedAnnualLeave,
    weeklyHoursPure: weeklyHoursPure,
    hourlyRate: hourlyRate,
    manualAdjustment: manualAdjustment,
    initialAdjustment: initialAdjustment,
    initialAdjustmentReason: initialAdjustmentReason,
    promotionLogs: promotionLogs,
    isVirtual: isVirtual,
  );

  static int calculateAnnualLeave({
    required DateTime joinDate,
    required List<Attendance> attendances,
    required List<int> scheduledWorkDays,
    required bool isFiveOrMore,
    required DateTime settlementPoint,
  }) => AnnualLeaveCalculator.calculateAnnualLeave(
    joinDate: joinDate,
    attendances: attendances,
    scheduledWorkDays: scheduledWorkDays,
    isFiveOrMore: isFiveOrMore,
    settlementPoint: settlementPoint,
  );

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
    double annualLeaveInitialAdjustment = 0.0,
    String annualLeaveInitialAdjustmentReason = '',
    List<LeavePromotionStatus> promotionLogs = const [],
    bool isVirtual = false,
    String wageType = 'hourly',
    double monthlyWage = 0.0,
    double mealAllowance = 0.0,
    double fixedOvertimePay = 0.0,
    List<double> otherAllowances = const [],
    bool includeMealInOrdinary = true,
    bool includeAllowanceInOrdinary = false,
    bool includeFixedOtInAverage = false,
  }) => SeveranceCalculator.calculateExitSettlement(
    workerName: workerName,
    startDate: startDate,
    usedAnnualLeave: usedAnnualLeave,
    annualLeaveManualAdjustment: annualLeaveManualAdjustment,
    weeklyHours: weeklyHours,
    allAttendances: allAttendances,
    scheduledWorkDays: scheduledWorkDays,
    exitDate: exitDate,
    hourlyRate: hourlyRate,
    isFiveOrMore: isFiveOrMore,
    manualAverageDailyWage: manualAverageDailyWage,
    annualLeaveInitialAdjustment: annualLeaveInitialAdjustment,
    annualLeaveInitialAdjustmentReason: annualLeaveInitialAdjustmentReason,
    promotionLogs: promotionLogs,
    isVirtual: isVirtual,
    wageType: wageType,
    monthlyWage: monthlyWage,
    mealAllowance: mealAllowance,
    fixedOvertimePay: fixedOvertimePay,
    otherAllowances: otherAllowances,
    includeMealInOrdinary: includeMealInOrdinary,
    includeAllowanceInOrdinary: includeAllowanceInOrdinary,
    includeFixedOtInAverage: includeFixedOtInAverage,
  );

  static ShiftSwapResult processShiftSwap({
    required Shift firstAssignedShift,
    required Shift secondAssignedShift,
    required List<Attendance> attendances,
  }) => ShiftSubstitutionCalculator.processShiftSwap(
    firstAssignedShift: firstAssignedShift,
    secondAssignedShift: secondAssignedShift,
    attendances: attendances,
  );

  static SubstitutionProcessResult processSubstitution({
    required Shift substitutionShift,
    required List<Attendance> substituteWeeklyAttendances,
    required bool isFiveOrMoreStore,
    int defaultBreakMinutesPerShift = 0,
    void Function(String message)? notifyOwner,
  }) => ShiftSubstitutionCalculator.processSubstitution(
    substitutionShift: substitutionShift,
    substituteWeeklyAttendances: substituteWeeklyAttendances,
    isFiveOrMoreStore: isFiveOrMoreStore,
    defaultBreakMinutesPerShift: defaultBreakMinutesPerShift,
    notifyOwner: notifyOwner,
  );

  static FinalPayrollResult calculateFinalPayroll({
    required double totalPureLaborHours,
    required double totalPaidBreakHours,
    required double overtimeHours,
    required double hourlyRate,
    required bool isFiveOrMore,
    required bool isWeeklyHolidayEligible,
    required double Function() calculateHolidayPay,
  }) => ShiftSubstitutionCalculator.calculateFinalPayroll(
    totalPureLaborHours: totalPureLaborHours,
    totalPaidBreakHours: totalPaidBreakHours,
    overtimeHours: overtimeHours,
    hourlyRate: hourlyRate,
    isFiveOrMore: isFiveOrMore,
    isWeeklyHolidayEligible: isWeeklyHolidayEligible,
    calculateHolidayPay: calculateHolidayPay,
  );

  static DateTime _parseTimeOnDate(DateTime date, String timeStr) {
    try {
      final parts = timeStr.split(':');
      if (parts.length == 2) {
        final h = int.parse(parts[0]);
        final m = int.parse(parts[1]);
        return DateTime(date.year, date.month, date.day, h, m);
      }
    } catch (_) {}
    return date;
  }

  static int calculateAppliedBreak({
    required Attendance att,
    required DateTime effectiveIn,
    required DateTime effectiveOut,
    required int fallbackMinutes,
    required String breakStartTimeStr,
    required String breakEndTimeStr,
  }) {
    // 고정값 차감: 사장님이 설정한(또는 계약된) 휴게시간을 그대로 사용
    // (자동 법정 휴게시간 적용은 '무조건 공제'로 인한 실무적 위험성 때문에 폐기됨)
    int breakMins = fallbackMinutes;

    return breakMins;
  }

  static List<(DateTime, DateTime)> _generateStandardWeeksInPeriod(
    DateTime periodStart,
    DateTime periodEnd,
    int weeklyHolidayDay,
  ) {
    final weeks = <(DateTime, DateTime)>[];
    var cursor = DateTime(periodStart.year, periodStart.month, periodStart.day);
    final end = DateTime(periodEnd.year, periodEnd.month, periodEnd.day);

    while (!cursor.isAfter(end)) {
      final code = cursor.weekday == 7 ? 0 : cursor.weekday;
      if (code == weeklyHolidayDay) {
        final weekStart = cursor.subtract(const Duration(days: 6));
        final weekEnd = cursor;
        weeks.add((weekStart, weekEnd));
      }
      cursor = cursor.add(const Duration(days: 1));
    }
    return weeks;
  }

  static bool _attendanceTouchesRange(
    Attendance att,
    DateTime rangeStart,
    DateTime rangeEnd,
  ) {
    final inDay = DateTime(
      att.clockIn.year,
      att.clockIn.month,
      att.clockIn.day,
    );
    final inTouches = !inDay.isBefore(rangeStart) && !inDay.isAfter(rangeEnd);
    if (inTouches) return true;

    final out = att.clockOut;
    if (out == null) return false;

    final outDay = DateTime(out.year, out.month, out.day);
    return !outDay.isBefore(rangeStart) && !outDay.isAfter(rangeEnd);
  }

  static ({int overtime, int night, int holiday})
  _premiumTargetMinutesForAttendance({
    required DateTime clockIn,
    required DateTime clockOut,
    required int stayMinutes,
    required int pureMinutes,
    required PayrollWorkerData workerData,
  }) {
    if (stayMinutes <= 0 || pureMinutes <= 0)
      return (overtime: 0, night: 0, holiday: 0);

    // 연장(하루 8시간 초과) 대상
    final overtimePure = (pureMinutes - 480).clamp(0, pureMinutes);

    // 야간(22:00~06:00) 대상
    final nightStay = _overlapNightMinutes(clockIn, clockOut);
    final nightPure = ((nightStay * pureMinutes) / stayMinutes).round();

    // 휴일(토/일) 및 대타 근로 대상 -> [개편] 고정 OT에서 차감하지 않기 위해 분리
    bool isHoliday = false;
    if (clockIn.month == 5 && clockIn.day == 1) {
      isHoliday = true;
    } else if (workerData.scheduledWorkDays.length == 7) {
      final clockInDay = clockIn.weekday == 7 ? 0 : clockIn.weekday;
      if (clockInDay == workerData.weeklyHolidayDay) {
        isHoliday = true;
      }
    } else {
      // 주 7일 근무자가 아닌 경우, 원래 휴무일(대타)에 출근했는지 판별
      final clockInDay = clockIn.weekday == 7 ? 0 : clockIn.weekday;
      if (!workerData.scheduledWorkDays.contains(clockInDay)) {
        isHoliday = true;
      }
    }

    final holidayPure = isHoliday ? pureMinutes : 0;

    return (overtime: overtimePure, night: nightPure, holiday: holidayPure);
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

  static bool _isPerfectAttendanceForRange({
    required List<Attendance> attendances,
    required List<int> scheduledWorkDays,
    required DateTime rangeStart,
    required DateTime rangeEnd,
    bool isVirtual = false,
    DateTime? joinDate,
    DateTime? endDate,
  }) {
    final now = AppClock.now();
    final today = DateTime(now.year, now.month, now.day);
    final joinOnly = joinDate != null
        ? DateTime(joinDate.year, joinDate.month, joinDate.day)
        : null;
    final endOnly = endDate != null
        ? DateTime(endDate.year, endDate.month, endDate.day)
        : null;

    DateTime? firstAttendanceDate;
    for (final a in attendances) {
      final d = DateTime(a.clockIn.year, a.clockIn.month, a.clockIn.day);
      if (firstAttendanceDate == null || d.isBefore(firstAttendanceDate)) {
        firstAttendanceDate = d;
      }
    }

    final expectedDays = <String>{};
    for (
      var d = rangeStart;
      !d.isAfter(rangeEnd);
      d = d.add(const Duration(days: 1))
    ) {
      // 오늘 이후(미래) 날짜는 아직 출근 기록이 없는 게 당연하므로 결근 판정에서 제외.
      // 오늘도 제외: 아직 근무 중(clockOut=null)이면 결근으로 오판하기 때문.
      if (!d.isBefore(today)) continue;

      // 앱 도입 이전(첫 출퇴근 기록 이전)의 날짜는 결근 판정에서 제외 (앱 사용 초기 불이익 방지)
      final dOnly = DateTime(d.year, d.month, d.day);
      if (firstAttendanceDate != null && dOnly.isBefore(firstAttendanceDate))
        continue;

      // 입사일 이전이거나 퇴사일 이후인 날짜는 근무 의무가 없으므로 제외
      if (joinOnly != null && dOnly.isBefore(joinOnly)) continue;
      if (endOnly != null && dOnly.isAfter(endOnly)) continue;

      // 근로기준법상 근로자의 날(5월 1일)은 모든 사업장 적용 법정 유급휴일이므로
      // 출근 기록이 없더라도 결근(무단 결근)으로 처리하지 않음 (만근 산정 시 출근으로 간주)
      if (d.month == 5 && d.day == 1) continue;

      final code = d.weekday == DateTime.sunday ? 0 : d.weekday;
      if (!scheduledWorkDays.contains(code)) continue;
      expectedDays.add('${d.year}-${d.month}-${d.day}');
    }
    if (expectedDays.isEmpty) return true;

    final workedDays = <String>{};
    for (final a in attendances) {
      if (a.attendanceStatus.toLowerCase() == 'absent') continue;
      
      final day = DateTime(a.clockIn.year, a.clockIn.month, a.clockIn.day);
      if (day.isBefore(rangeStart) || day.isAfter(rangeEnd)) continue;
      // 실제 출퇴근 기록 또는 연차/유급휴일 간주일(isAttendanceEquivalent)
      // → 근로기준법 제60조 제6항: 연차 사용일은 출근한 것으로 봄
      if (a.clockOut != null || a.isAttendanceEquivalent) {
        workedDays.add('${day.year}-${day.month}-${day.day}');
      }
    }
    for (final expected in expectedDays) {
      if (!workedDays.contains(expected)) {
        return false;
      }
    }
    return true;
  }

  static int _safeDayInMonth(int year, int month, int day) {
    final lastDay = DateTime(year, month + 1, 0).day;
    return day.clamp(1, lastDay);
  }
}
