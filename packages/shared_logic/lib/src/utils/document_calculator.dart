import '../constants/payroll_constants.dart';

class DocumentCalculator {
  /// 계약서 유형 제안. 주 40시간 이상이면 '표준', 이하면 '단시간'.
  static String suggestContractType(double weeklyHours) {
    if (weeklyHours >= PayrollConstants.shortTimeHourThreshold) {
      return 'contract_full'; // 표준 근로계약서
    } else {
      return 'contract_part'; // 단시간 근로계약서
    }
  }

  /// 15시간 미만 초단시간 근로자인지 확인 (경고 문구 용도)
  static bool isUltraShortTime(double weeklyHours) {
    return weeklyHours < PayrollConstants.ultraShortTimeHourThreshold;
  }

  /// 임금명세서를 위한 세부 내역 계산 (대략적인 추산)
  /// 실제로는 PayrollCalculator의 결과를 정제해서 보여주게 됨
  static Map<String, dynamic> generateWageBreakdown({
    required double grossPay, // 세전 총액
    required bool hasMealAllowance,
  }) {
    // 1. 비과세 식대 계산
    double mealAllowance = 0.0;
    if (hasMealAllowance &&
        grossPay >= PayrollConstants.maxTaxFreeMealAllowance) {
      mealAllowance = PayrollConstants.maxTaxFreeMealAllowance;
    } else if (hasMealAllowance && grossPay > 0) {
      mealAllowance =
          grossPay * 0.1; // 소액일 경우 임의로 10% 책정 (실제론 노무사 자문 필요영역이나 간이 계산용)
    }

    // 2. 과세 대상 금액 (총액 - 비과세)
    double taxablePay = grossPay - mealAllowance;
    if (taxablePay < 0) taxablePay = 0;

    // 3. 4대 보험 (과세대상 금액 기준)
    double insuranceDeduction = taxablePay * PayrollConstants.insuranceRate;

    // 4. 실 지급액
    double netPay = grossPay - insuranceDeduction;

    return {
      'grossPay': grossPay,
      'mealAllowance': mealAllowance,
      'taxablePay': taxablePay,
      'insuranceRate': PayrollConstants.insuranceRate,
      'insuranceDeduction': insuranceDeduction,
      'netPay': netPay,
    };
  }

  /// 보존 기한 산출 (작성일 기준 3년)
  static DateTime calculateExpiryDate(DateTime createdAt) {
    return DateTime(
      createdAt.year + PayrollConstants.defaultRetentionYears,
      createdAt.month,
      createdAt.day,
    );
  }
}
