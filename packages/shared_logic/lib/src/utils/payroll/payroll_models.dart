/// 급여 계산 입출력 모델 클래스 모음
///
/// [payroll_calculator.dart]에서 분리된 순수 데이터 모델입니다.
/// 계산 로직은 포함하지 않으며, 입력(WorkerData)과 출력(Result) 구조만 정의합니다.
library;

import '../../models/attendance_model.dart';
import '../../models/shift_model.dart';
import 'annual_leave_calculator.dart';

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
  bool manualWeeklyHolidayApproval;

  /// 기타수당(기타 고정/수당 항목) 금액들
  final List<double> allowanceAmounts;

  /// 총 사용한 연차 개수 (사장님이 직접 관리)
  final double usedAnnualLeave;

  /// 사장님이 수동으로 가감한 연차 개수 (Override)
  final double manualAdjustment;

  /// 앱 도입 이전 기초 연차 개수 (사장님 수동 입력)
  final double initialAdjustment;

  /// 기초 연차 수정 사유 로그
  final String initialAdjustmentReason;

  /// 퇴사일 (null이면 재직 중)
  final DateTime? endDate;

  /// 전월 정산금 (수동 입력)
  final double previousMonthAdjustment;

  /// 비과세 대상 식대 (사장님 설정값)
  final double mealAllowance;

  /// 식대 비과세 적용 여부 (사장님 선택)
  final bool mealTaxExempt;

  /// 시급 변경 이력 (JSON 직렬화 저장). `[{"effectiveDate":"2026-01-01","hourlyWage":10320},...]`
  final String wageHistoryJson;

  /// 세금 및 4대보험 공제 필드들
  final bool applyWithholding33;
  final bool deductNationalPension;
  final bool deductHealthInsurance;
  final bool deductEmploymentInsurance;

  /// 가상직원 여부 (사장님 테스트용 프리패스 권한 부여)
  final bool isVirtual;

  /// 주휴일 지정 요일 (일=0 ... 토=6)
  final int weeklyHolidayDay;

  /// 정해진 휴게 시작 시간 (예: "14:00")
  final String breakStartTime;

  /// 정해진 휴게 종료 시간 (예: "14:30")
  final String breakEndTime;

  /// 지각/조퇴 허용 시간 (분 단위)
  final int graceMinutes;

  /// 연차 사용촉진 로그 (기존 저장분)
  final List<LeavePromotionStatus> promotionLogs;

  /// 급여 형태: 'hourly' | 'monthly'
  final String wageType;

  /// 월급 총액 (월급제일 때만 사용)
  final double monthlyWage;

  /// 포괄임금제: 고정 연장근로시간 (시간)
  final double fixedOvertimeHours;

  /// 포괄임금제: 고정 연장수당 (원)
  final double fixedOvertimePay;

  /// 수습 적용 여부
  final bool isProbation;

  /// 수습 개월 수
  final int probationMonths;

  PayrollWorkerData({
    required this.weeklyHoursPure,
    required this.weeklyTotalStayMinutes,
    required this.breakMinutesPerShift,
    required this.isPaidBreak,
    required this.joinDate,
    required this.scheduledWorkDays,
    required this.manualWeeklyHolidayApproval,
    this.allowanceAmounts = const [],
    this.usedAnnualLeave = 0.0,
    this.manualAdjustment = 0.0,
    this.initialAdjustment = 0.0,
    this.initialAdjustmentReason = '',
    this.endDate,
    this.previousMonthAdjustment = 0.0,
    this.mealAllowance = 0.0,
    this.applyWithholding33 = false,
    this.deductNationalPension = false,
    this.deductHealthInsurance = false,
    this.deductEmploymentInsurance = false,
    this.isVirtual = false,
    this.weeklyHolidayDay = 0,
    this.breakStartTime = '',
    this.breakEndTime = '',
    this.graceMinutes = 0,
    this.promotionLogs = const [],
    this.wageType = 'hourly',
    this.monthlyWage = 0.0,
    this.fixedOvertimeHours = 0.0,
    this.fixedOvertimePay = 0.0,
    this.mealTaxExempt = false,
    this.wageHistoryJson = '',
    this.isProbation = false,
    this.probationMonths = 0,
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

  /// 근로자의 날(유급휴일) 기본 보장 수당 (안 일해도 받는 돈)
  final double laborDayAllowancePay;

  /// 휴일근로(5/1 등) 가산 수당 (5인 이상 사업장에서 출근했을 때 가산되는 돈)
  final double holidayPremiumPay;

  final bool needsBreakSeparationGuide;
  final bool isWeeklyHolidayEligible;
  final bool hasSubstitutionRisk;
  final int newlyGrantedAnnualLeave; // 호환성 유지
  final bool isPerfectAttendance;
  final bool weeklyHolidayBlockedByAbsence;

  /// 15시간 미만 계약자가 대타 등으로 15시간을 초과한 주가 존재하는지 여부
  final bool hasExtraWeekOver15;

  /// 연차 저금통 전체 요약
  final AnnualLeaveSummary annualLeaveSummary;

  // --- 대한민국 노무 표준 가이드 준수 필드 추가 ---
  final double taxableWage; // 과세 대상액 (A)
  final double insuranceDeduction; // 4대 보험/3.3% 총 공제액 (B)

  // 개별 세부 공제 항목
  final double nationalPension;
  final double healthInsurance;
  final double longTermCareInsurance;
  final double employmentInsurance;
  final double businessIncomeTax;
  final double localIncomeTax;

  final double mealNonTaxable; // 비과세 식대 항목
  final double previousMonthAdjustment; // 전월 정산금 (C)
  final double netPay; // 최종 실지급액 (A + 비과세 - B + C)

  // --- 월급제 관련 필드 ---
  /// 월급제 여부
  final bool isMonthlyWage;

  /// 월급제 기본급 (사장님 입력값 그대로)
  final double monthlyBasePay;

  /// 일할 계산 비율 (1.0 = 전월 재직)
  final double proRataRatio;

  /// 실제 연장 초과시간 (고정 연장시간 초과분)
  final double fixedOvertimeExcessHours;

  /// 실제 연장 초과수당 (추가 지급 필요)
  final double fixedOvertimeExcessPay;

  /// 최저임금 미달 경고 플래그 (2단계 Warning: 기본급+식대 기준)
  final bool minimumWageWarning;

  // --- 초보수적 방어형 엔진 필드 (구성→합산) ---
  /// 식대 (별도 행 표기용)
  final double mealAllowancePay;

  /// 통상시급 = 기본급 / S (법정 수당 계산 기준, 보수적)
  final double conservativeHourlyWage;

  /// 참고 시급 = (기본급+식대+기타) / S (총보상 참고용)
  final double referenceHourlyWage;

  /// 월 소정근로시간 (가변형 S)
  final double scheduledMonthlyHours;

  /// 주휴수당 (월급에 포함, 명세서 표시용)
  final double weeklyHolidayPayInMonthly;

  /// 고정연장수당 (약정 시간 기반 별도 산출)
  final double fixedOvertimeBasePay;

  /// 고정연장 약정시간 (명세서 "월 XX시간" 표기용)
  final double fixedOvertimeAgreedHours;

  /// 주휴시간 (명세서 "통상시급 × 주휴시간" 표기용)
  final double weeklyHolidayHoursInMonthly;

  /// 1단계 Hard Block: 기본급/S < 최저임금
  final bool minimumWageHardBlock;

  /// SHA-256 해시 (분쟁 방어 증거 봉인)
  final String payslipHash;

  /// S_Legal: 법적 기준 소정근로시간 (달력 기반 주수)
  final double scheduledMonthlyHoursLegal;

  /// S_Ref: 참고용 소정근로시간 (4.345 고정)
  final double scheduledMonthlyHoursRef;

  /// 5인 이상 사업장 여부 (UI 라벨 분기용)
  final bool isFiveOrMore;

  /// 근로자의 날(5/1) 출근 수당
  final double laborDayWorkPay;

  /// 근로자의 날(5/1) 출근 시간
  final double laborDayWorkHours;

  /// 휴무일(대타) 출근 수당
  final double offDayWorkPay;

  /// 휴무일(대타) 출근 시간
  final double offDayWorkHours;

  /// 기본시급 (baseSalary/sRef, 식대 제외) — UI 주휴수당 표시 전용
  final double baseHourlyWage;

  /// 시급별 기본급 계산 내역 (key: 적용시급, value: 적용시간)
  final Map<double, double> basePayBreakdownByWage;

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
    this.laborDayAllowancePay = 0.0,
    this.holidayPremiumPay = 0.0,
    required this.needsBreakSeparationGuide,
    required this.isWeeklyHolidayEligible,
    required this.hasSubstitutionRisk,
    required this.newlyGrantedAnnualLeave,
    required this.isPerfectAttendance,
    required this.weeklyHolidayBlockedByAbsence,
    this.hasExtraWeekOver15 = false,
    required this.annualLeaveSummary,
    this.annualLeaveAllowancePay = 0.0,
    this.taxableWage = 0.0,
    this.insuranceDeduction = 0.0,
    this.nationalPension = 0.0,
    this.healthInsurance = 0.0,
    this.longTermCareInsurance = 0.0,
    this.employmentInsurance = 0.0,
    this.businessIncomeTax = 0.0,
    this.localIncomeTax = 0.0,
    this.mealNonTaxable = 0.0,
    this.previousMonthAdjustment = 0.0,
    this.netPay = 0.0,
    this.isMonthlyWage = false,
    this.monthlyBasePay = 0.0,
    this.proRataRatio = 1.0,
    this.fixedOvertimeExcessHours = 0.0,
    this.fixedOvertimeExcessPay = 0.0,
    this.minimumWageWarning = false,
    this.mealAllowancePay = 0.0,
    this.conservativeHourlyWage = 0.0,
    this.referenceHourlyWage = 0.0,
    this.scheduledMonthlyHours = 0.0,
    this.weeklyHolidayPayInMonthly = 0.0,
    this.fixedOvertimeBasePay = 0.0,
    this.fixedOvertimeAgreedHours = 0.0,
    this.weeklyHolidayHoursInMonthly = 0.0,
    this.minimumWageHardBlock = false,
    this.payslipHash = '',
    this.scheduledMonthlyHoursLegal = 0.0,
    this.scheduledMonthlyHoursRef = 0.0,
    this.isFiveOrMore = true,
    this.laborDayWorkPay = 0.0,
    this.laborDayWorkHours = 0.0,
    this.offDayWorkPay = 0.0,
    this.offDayWorkHours = 0.0,
    this.baseHourlyWage = 0.0,
    this.basePayBreakdownByWage = const {},
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
