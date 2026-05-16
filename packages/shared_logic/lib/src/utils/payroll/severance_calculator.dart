/// 퇴직금 정산 계산 엔진
///
/// [payroll_calculator.dart]에서 분리된 퇴직금 정산 로직입니다.
/// - 평균임금 기반 퇴직금 산출
/// - 통상임금 하한선 적용 (근로기준법 제2조 제2항)
/// - 연차수당/일할급여 포함 정산
library;

import '../../models/attendance_model.dart';
import 'annual_leave_calculator.dart';
import 'payroll_models.dart';

class SeveranceCalculator {
  const SeveranceCalculator();

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
  }) {
    final joinDate = DateTime.parse(startDate);
    final totalWorkingDays = exitDate.difference(joinDate).inDays + 1;
    // [퇴직급여보장법 제4조] 1년 이상 + 주 15시간 이상 근로자만 퇴직금 대상
    final isSeveranceEligible = totalWorkingDays >= 365 && weeklyHours >= 15;

    // 1. 연차수당 계산 (출퇴근 데이터 부족 시에도 나머지 정산은 진행)
    double remainingLeave = 0;
    double annualLeavePayout = 0;
    try {
      final annualLeaveSummary =
          AnnualLeaveCalculator.calculateAnnualLeaveSummary(
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
            initialAdjustment: annualLeaveInitialAdjustment,
            initialAdjustmentReason: annualLeaveInitialAdjustmentReason,
            promotionLogs: promotionLogs,
            isVirtual: isVirtual,
          );
      remainingLeave = annualLeaveSummary.remaining;
      annualLeavePayout = annualLeaveSummary.annualLeaveAllowancePay;
    } catch (e) {
      // 연차 계산 실패해도 퇴직금/일할급여는 정상 진행
    }

    // 2. 퇴직금 계산 (평균임금 기반)
    double severancePay = 0;
    double averageDailyWage = manualAverageDailyWage ?? 0;
    bool requiresManualInput = false;

    if (isSeveranceEligible) {
      // [근로기준법 제2조 제1항 제6호] "사유 발생일 이전 3개월" = 역월 기준
      final threeMonthsAgo = _subtractCalendarMonths(exitDate, 3);
      final calendarDaysIn3Months = exitDate.difference(threeMonthsAgo).inDays;

      // 최근 3개월 실근무 데이터 확인
      final last3MonthsAttendances = allAttendances
          .where(
            (a) =>
                a.clockIn.isAfter(threeMonthsAgo) &&
                a.clockIn.isBefore(exitDate.add(const Duration(days: 1))),
          )
          .toList();

      // 실제 출근한 날짜(기록) 수 체크
      final workedDays = last3MonthsAttendances
          .map((a) => "${a.clockIn.year}-${a.clockIn.month}-${a.clockIn.day}")
          .toSet()
          .length;

      // 기록이 30일 미만이면(간소화 기준) 데이터 부족으로 판단
      if (workedDays < 30 &&
          (manualAverageDailyWage == null || manualAverageDailyWage <= 0)) {
        requiresManualInput = true;
      }

      if (manualAverageDailyWage == null || manualAverageDailyWage <= 0) {
        final isMonthly = wageType == 'monthly' && monthlyWage > 0;
        final contractWorkDaysPerWeek = scheduledWorkDays.isEmpty
            ? 5.0
            : scheduledWorkDays.length.toDouble();
        final hoursMultiplier = weeklyHours >= 40.0
            ? 8.0
            : (weeklyHours / contractWorkDaysPerWeek).clamp(0.0, 8.0);

        if (isMonthly) {
          final totalOtherAllowances = otherAllowances.fold(
            0.0,
            (a, b) => a + b,
          );

          // 1. 통상임금(일급) 계산
          final ordinaryMonthlyWage = monthlyWage + 
              (includeMealInOrdinary ? mealAllowance : 0) +
              (includeAllowanceInOrdinary ? totalOtherAllowances : 0);
          final weeklyHolidayH = weeklyHours >= 15
              ? (weeklyHours / contractWorkDaysPerWeek)
              : 0.0;
          final scheduledH = ((weeklyHours + weeklyHolidayH) * 4.345)
              .ceilToDouble();
          final ordinaryHourlyRate = scheduledH > 0
              ? (ordinaryMonthlyWage / scheduledH)
              : 0.0;
          final ordinaryDailyWage = hoursMultiplier * ordinaryHourlyRate;

          // 2. 평균임금(일급) 계산: (월총급여 * 3) / 3개월총일수
          final grossMonthlyWage =
              monthlyWage +
              mealAllowance +
              totalOtherAllowances +
              (includeFixedOtInAverage ? fixedOvertimePay : 0);
          final totalWageLast3Months = grossMonthlyWage * 3.0;

          double calculatedAverage =
              totalWageLast3Months / calendarDaysIn3Months.toDouble();

          averageDailyWage = calculatedAverage > ordinaryDailyWage
              ? calculatedAverage
              : ordinaryDailyWage;

          // 월급제는 시간급(hourlyRate)을 통상시급으로 덮어씀 (잔여 연차수당 및 일할급여 계산용)
          hourlyRate = ordinaryHourlyRate;

          // [버그 수정] 통상시급이 갱신되었으므로, 시급 0원(DB 기본값)으로 잘못 산정되었을 수 있는 잔여 연차수당을 재계산
          if (remainingLeave > 0) {
            annualLeavePayout = remainingLeave * hoursMultiplier * hourlyRate;
          }
        } else {
          double totalWageLast3Months = 0;
          final weeklyHoursPureCapped = weeklyHours.clamp(0.0, 40.0);

          if (workedDays < 30) {
            // 기록 부족 시(가상직원 등) 소정근로시간 기반 이론적 3개월 총액 추산
            final weeklyTotalPaidHours =
                weeklyHoursPureCapped +
                hoursMultiplier; // weeklyHours >= 15 보장됨
            totalWageLast3Months =
                weeklyTotalPaidHours *
                (calendarDaysIn3Months / 7.0) *
                hourlyRate;
          } else {
            // 실제 근무시간 합산
            for (final att in last3MonthsAttendances) {
              if (att.clockOut == null) continue;
              final minutes = att.clockOut!.difference(att.clockIn).inMinutes;
              totalWageLast3Months += (minutes / 60.0) * hourlyRate;
            }
            // 실제 출근 기록에 주휴수당분 직접 가산 (역월 기준)
            totalWageLast3Months +=
                hoursMultiplier * hourlyRate * (calendarDaysIn3Months / 7.0);
          }

          // 연차수당 가산: 실제 발생일수 기반 (15일 고정 가정 제거)
          final actualAnnualDays = _estimateAnnualLeaveDays(
            joinDate: joinDate,
            exitDate: exitDate,
            isFiveOrMore: isFiveOrMore,
          );
          final annualLeaveAddition =
              (actualAnnualDays * hoursMultiplier * hourlyRate) *
              (calendarDaysIn3Months / 365.0);
          totalWageLast3Months += annualLeaveAddition;

          double calculatedAverage =
              totalWageLast3Months / calendarDaysIn3Months.toDouble();

          // [근로기준법 제2조 제2항] 평균임금이 통상임금보다 적으면 통상임금액을 평균임금으로 한다.
          final ordinaryDailyWage = hoursMultiplier * hourlyRate;

          averageDailyWage = calculatedAverage > ordinaryDailyWage
              ? calculatedAverage
              : ordinaryDailyWage;
        }
      }

      severancePay = (averageDailyWage * 30) * (totalWorkingDays / 365.0);
    }

    // 3. 퇴사월 일할 급여
    final firstDayOfExitMonth = DateTime(exitDate.year, exitDate.month, 1);
    double exitMonthWage = 0;
    final exitMonthAttendances = allAttendances
        .where(
          (a) =>
              a.clockIn.isAfter(
                firstDayOfExitMonth.subtract(const Duration(seconds: 1)),
              ) &&
              a.clockIn.isBefore(exitDate.add(const Duration(days: 1))),
        )
        .toList();

    for (final att in exitMonthAttendances) {
      if (att.clockOut == null) continue;
      final minutes = att.clockOut!.difference(att.clockIn).inMinutes;
      exitMonthWage += (minutes / 60.0) * hourlyRate;
    }

    final List<String> basis = [];
    if (isVirtual) {
      basis.add('[시뮬레이션 모드] 가상의 근무 데이터로 계산됨');
      basis.add('');
    }

    basis.add('[고급 노무 설정]');
    basis.add(' - 식대 통상임금 포함: ${includeMealInOrdinary ? 'ON' : 'OFF'}');
    basis.add(' - 고정수당 통상임금 포함: ${includeAllowanceInOrdinary ? 'ON' : 'OFF'}');
    basis.add(' - 고정OT 평균임금 포함: ${includeFixedOtInAverage ? 'ON' : 'OFF'}');
    basis.add('');
    
    if (wageType == 'monthly') {
      basis.add('[월급제 산정 기준]');
      basis.add(' - 월 기본급: ${monthlyWage.toInt()}원');
      basis.add(' - 월 식대: ${mealAllowance.toInt()}원');
      if (otherAllowances.isNotEmpty) {
        final totalOtherAllowances = otherAllowances.fold(0.0, (a, b) => a + b);
        basis.add(' - 기타 수당 합계: ${totalOtherAllowances.toInt()}원');
      }
      if (fixedOvertimePay > 0) {
        basis.add(' - 고정연장수당: ${fixedOvertimePay.toInt()}원');
      }
      basis.add('');
    }
    
    basis.add('[잔여 연차수당]');
    basis.add(' - 잔여 연차: ${remainingLeave.toStringAsFixed(1)}일');
    if (remainingLeave > 0) {
      final contractWorkDaysPerWeek = scheduledWorkDays.isEmpty
          ? 5.0
          : scheduledWorkDays.length.toDouble();
      final hoursMultiplier = weeklyHours >= 40.0
          ? 8.0
          : (weeklyHours / contractWorkDaysPerWeek).clamp(0.0, 8.0);
      if (weeklyHours >= 40.0) {
        basis.add(' - 1일 소정근로시간: ${hoursMultiplier.toStringAsFixed(1)}시간');
      } else {
        basis.add(' - 1일 소정근로시간: ${hoursMultiplier.toStringAsFixed(2)}시간');
        basis.add('   (주 ${weeklyHours.toStringAsFixed(0)}시간 ÷ 주 ${contractWorkDaysPerWeek.toInt()}일)');
      }
      basis.add(
        ' - 계산식: 잔여 ${remainingLeave.toStringAsFixed(1)}일 × ${hoursMultiplier.toStringAsFixed(1)}시간 × ${hourlyRate.toInt()}원 = ${annualLeavePayout.toInt()}원',
      );
    } else {
      basis.add(' - 정산할 연차수당 없음');
    }

    basis.add('');
    basis.add('[법정 퇴직금]');
    if (isSeveranceEligible) {
      basis.add(' - 총 재직일수: $totalWorkingDays일');
      basis.add(' - 1일 평균임금: ${averageDailyWage.toInt()}원');
      basis.add('   (1일 평균임금과 통상임금을 비교하여 더 높은 금액 적용)');
      basis.add(
        ' - 계산식: ${averageDailyWage.toInt()}원 × 30일 × ($totalWorkingDays일 ÷ 365일) = ${severancePay.toInt()}원',
      );
    } else {
      basis.add(' - 대상 아님 (1년 미만 또는 주 15시간 미만 근무)');
    }

    basis.add('');
    basis.add('※ 위 금액은 세전(稅前) 금액입니다.');
    basis.add('※ 실제 수령액은 퇴직소득세(원천징수) 차감 후 달라질 수 있습니다.');
    basis.add('※ 실제 퇴직금은 출근기록·지급내역·근로계약에 따라 달라질 수 있습니다.');

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
      calculationBasis: basis,
    );
  }

  // ─── 헬퍼 메서드 ───

  /// 역월 기준 N개월 전 날짜 산출 (말일 보정 포함)
  /// 예: 5월 31일의 3개월 전 = 2월 28일 (윤년: 2월 29일)
  static DateTime _subtractCalendarMonths(DateTime from, int months) {
    int targetYear = from.year;
    int targetMonth = from.month - months;
    while (targetMonth <= 0) {
      targetMonth += 12;
      targetYear -= 1;
    }
    final lastDayOfTarget = DateTime(targetYear, targetMonth + 1, 0).day;
    final targetDay = from.day > lastDayOfTarget ? lastDayOfTarget : from.day;
    return DateTime(targetYear, targetMonth, targetDay);
  }

  /// 퇴직일 기준 직전 1년 연차 발생일수 추정 (평균임금 산입용)
  /// 실제 AnnualLeaveCalculator의 발생 로직과 동일한 규칙 적용
  static double _estimateAnnualLeaveDays({
    required DateTime joinDate,
    required DateTime exitDate,
    required bool isFiveOrMore,
  }) {
    if (!isFiveOrMore) return 0; // 5인 미만 → 연차 법적 의무 없음

    final years = _yearsDiff(joinDate, exitDate);
    if (years < 1) {
      // 1년 미만: 매월 만근 시 1일 (최대 11일)
      return _monthsDiff(joinDate, exitDate).clamp(0, 11).toDouble();
    }
    // 1년 이상: 15일 + 장기근속 가산 (3년차부터 2년마다 +1, 최대 25일)
    final bonus = years > 1 ? (years - 1) ~/ 2 : 0;
    return (15 + bonus).clamp(15, 25).toDouble();
  }

  static int _yearsDiff(DateTime from, DateTime to) {
    int years = to.year - from.year;
    if (to.month < from.month ||
        (to.month == from.month && to.day < from.day)) {
      years--;
    }
    return years < 0 ? 0 : years;
  }

  static int _monthsDiff(DateTime from, DateTime to) {
    int months = (to.year - from.year) * 12 + (to.month - from.month);
    final lastDayOfTo = DateTime(to.year, to.month + 1, 0).day;
    final isLastDayOfTo = to.day == lastDayOfTo;
    if (to.day < from.day && !isLastDayOfTo) {
      months--;
    }
    return months < 0 ? 0 : months;
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
  final List<String> calculationBasis;

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
    this.calculationBasis = const [],
  });

  double get totalSettlementAmount =>
      exitMonthWage + annualLeavePayout + severancePay;

  Map<String, dynamic> toMap() {
    return {
      'workerName': workerName,
      'joinDate': joinDate.toIso8601String(),
      'exitDate': exitDate.toIso8601String(),
      'totalWorkingDays': totalWorkingDays,
      'isSeveranceEligible': isSeveranceEligible,
      'exitMonthWage': exitMonthWage,
      'remainingLeaveDays': remainingLeaveDays,
      'annualLeavePayout': annualLeavePayout,
      'severancePay': severancePay,
      'averageDailyWage': averageDailyWage,
      'paymentDeadline': paymentDeadline.toIso8601String(),
      'requiresManualInput': requiresManualInput,
      'calculationBasis': calculationBasis,
      'totalSettlementAmount': totalSettlementAmount,
    };
  }
}
