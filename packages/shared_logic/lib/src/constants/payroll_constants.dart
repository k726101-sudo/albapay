class PayrollConstants {
  /// 4대 보험 총 요율 (기본값: 9.4%)
  static double insuranceRate = 0.094;

  /// 비과세 식대 월 최대 한도 (기본값: 200,000원)
  static double maxTaxFreeMealAllowance = 200000;

  /// 단시간 근로자 분기 기준 시간 (주당)
  static double shortTimeHourThreshold = 40.0;

  /// 초단시간 근로자(주휴/연차 미보장) 분기 기준 시간 (주당)
  static double ultraShortTimeHourThreshold = 15.0;

  /// 법적 보존 기한 (년)
  static int defaultRetentionYears = 3;

  /// 당해 연도 최저 임금 (기본값: 10,320원 - 2026년 기준)
  static double legalMinimumWage = 10320.0;

  /// 이전 연도 최저 임금 (합의서 비교 출력용)
  static double previousMinimumWage = 10030.0;

  /// 위 최저임금이 효력을 발휘하는 기준 연도 (소급 적용 기준점)
  static int minimumWageEffectiveYear = 2026;
}
