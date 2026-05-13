import '../models/store_model.dart';
import '../models/attendance_model.dart';

enum ComplianceStatus {
  safe, // 정상 (40시간 미만)
  warning40, // 주의 (40시간 초과, 연장수당 발생)
  critical48, // 긴급 (48시간 초과, 한도 임박)
  blocked52, // 차단 (52시간 도달)
}

class ComplianceResult {
  final bool isSafe;
  final ComplianceStatus status;
  final double weeklyHours;
  final List<String> warnings;
  final List<String> blockingErrors;

  ComplianceResult({
    required this.isSafe,
    required this.status,
    required this.weeklyHours,
    this.warnings = const [],
    this.blockingErrors = const [],
  });
}

class ComplianceEngine {
  /// 금주 근로시간의 시작점(월요일 06:00)을 반환합니다.
  static DateTime getWeeklyStart(DateTime now) {
    // 월요일 06:00 기준
    DateTime monday06 = DateTime(now.year, now.month, now.day, 6);
    while (monday06.weekday != DateTime.monday) {
      monday06 = monday06.subtract(const Duration(days: 1));
    }
    // 현재 시각이 이번 주 월요일 06시 전이라면 7일 전으로 이동
    if (now.isBefore(monday06)) {
      monday06 = monday06.subtract(const Duration(days: 7));
    }
    return monday06;
  }

  /// 특정 기간(보통 금주)의 누적 근로 시간을 계산합니다.
  static double calculateWeeklyHours(
    List<Attendance> currentWeeklyAttendances,
  ) {
    double totalMinutes = 0;
    for (var att in currentWeeklyAttendances) {
      totalMinutes += att.workedMinutes;
    }
    return totalMinutes / 60.0;
  }

  /// 금주 근로 현황을 법정 한도와 비교하여 상태를 판정합니다.
  static ComplianceResult checkWeeklyCompliance({
    required Store store,
    required List<Attendance> currentWeeklyAttendances,
    required double newShiftMinutes, // 새로 추가/진행될 세션의 예정 분
  }) {
    final List<String> warnings = [];
    final List<String> errors = [];

    // 현재까지의 확정 근로 시간
    final double currentHours = calculateWeeklyHours(currentWeeklyAttendances);
    // 이번 근무를 마쳤을 때의 예상 총 시간
    final double totalProjectedHours = currentHours + (newShiftMinutes / 60.0);

    ComplianceStatus status = ComplianceStatus.safe;

    // 5인 이상 사업장일 때만 52시간 가드 활성화
    if (store.isFiveOrMore) {
      if (totalProjectedHours >= 52) {
        status = ComplianceStatus.blocked52;
        errors.add(
          '법정 최대 근로시간(주 52시간)에 도달했습니다. 사장님의 특별 승인 없이는 기록을 추가할 수 없습니다.',
        );
      } else if (totalProjectedHours > 48) {
        status = ComplianceStatus.critical48;
        warnings.add('법정 근로 한도(52시간) 임박! 긴급 관리가 필요합니다.');
      } else if (totalProjectedHours > 40) {
        status = ComplianceStatus.warning40;
        warnings.add('주 40시간 초과. 이때부터 시급의 1.5배 연장 수당이 발생합니다.');
      }
    }

    return ComplianceResult(
      isSafe: errors.isEmpty,
      status: status,
      weeklyHours: currentHours,
      warnings: warnings,
      blockingErrors: errors,
    );
  }
}
