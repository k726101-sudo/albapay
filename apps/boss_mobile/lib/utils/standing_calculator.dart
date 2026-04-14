import 'package:shared_logic/shared_logic.dart';
import '../models/worker.dart';

class SettlementPeriod {
  final DateTime start;
  final DateTime end;
  const SettlementPeriod({required this.start, required this.end});
}

class StandingResult {
  final double average;
  final int totalPersonDays;
  final int totalDays;
  final int daysWithFiveOrMore;
  final bool isFiveOrMore;
  final int daysWithTenOrMore;
  final bool isTenOrMore;
  final String fiveOrMoreDecisionReason;
  final String fiveOrMoreLegalReason;

  const StandingResult({
    required this.average,
    required this.totalPersonDays,
    required this.totalDays,
    required this.daysWithFiveOrMore,
    required this.isFiveOrMore,
    required this.daysWithTenOrMore,
    required this.isTenOrMore,
    required this.fiveOrMoreDecisionReason,
    required this.fiveOrMoreLegalReason,
  });
}

DateTime dayKey(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

int safeDayInMonth(int year, int month, int day) {
  final lastDay = DateTime(year, month + 1, 0).day;
  return day.clamp(1, lastDay);
}

SettlementPeriod computeSettlementPeriod({
  required DateTime now,
  required int settlementStartDay,
  required int settlementEndDay,
}) {
  // settlementStartDay/EndDay are day-of-month (1~31).
  // If start <= end, assume it's within the same calendar month.
  // If start > end, it spans to the next month (e.g. 3/16~4/15).
  if (settlementStartDay <= settlementEndDay) {
    final start = DateTime(
      now.year,
      now.month,
      safeDayInMonth(now.year, now.month, settlementStartDay),
    );
    final end = DateTime(
      now.year,
      now.month,
      safeDayInMonth(now.year, now.month, settlementEndDay),
    );
    return SettlementPeriod(start: start, end: end);
  }

  // Cross-month period:
  // - If today is on/after startDay, period starts this month and ends next month.
  // - Otherwise period started last month and ends this month.
  final startMonth = now.day >= settlementStartDay
      ? DateTime(now.year, now.month, 1)
      : DateTime(now.year, now.month - 1, 1);

  final endMonth = DateTime(startMonth.year, startMonth.month + 1, 1);

  final start = DateTime(
    startMonth.year,
    startMonth.month,
    safeDayInMonth(startMonth.year, startMonth.month, settlementStartDay),
  );

  final end = DateTime(
    endMonth.year,
    endMonth.month,
    safeDayInMonth(endMonth.year, endMonth.month, settlementEndDay),
  );

  return SettlementPeriod(start: start, end: end);
}

StandingResult calculateStandingFromAttendances({
  required List<Attendance> attendances,
  required DateTime periodStart,
  required DateTime periodEnd,
  required List<Worker> staffList,
}) {
  final totalDays = periodEnd.difference(periodStart).inDays + 1;
  final dailyStaff = <DateTime, Set<String>>{};

  bool inRange(DateTime day) =>
      !day.isBefore(periodStart) && !day.isAfter(periodEnd);

  // 1. 실제 출퇴근 기록 반영
  for (final att in attendances) {
    final inDay = dayKey(att.clockIn);
    if (inRange(inDay)) {
      dailyStaff.putIfAbsent(inDay, () => <String>{}).add(att.staffId);
    }

    if (att.clockOut != null) {
      final outDay = dayKey(att.clockOut!);
      if (inRange(outDay)) {
        dailyStaff.putIfAbsent(outDay, () => <String>{}).add(att.staffId);
      }
    }
  }

  // 2. 가상직원 시뮬레이션 반영 (테스트 편의용)
  for (int i = 0; i < totalDays; i++) {
    final day = DateTime(periodStart.year, periodStart.month, periodStart.day + i);
    final weekday = day.weekday % 7; // 0=Sun, ..., 6=Sat (matched Worker.workDays)

    for (final staff in staffList) {
      if (staff.name.contains('가상')) {
        // 해당 요일이 가상직원의 근무요일에 포함되어 있다면 인원수로 추가
        if (staff.workDays.contains(weekday)) {
          dailyStaff.putIfAbsent(day, () => <String>{}).add(staff.id);
        }
      }
    }
  }

  int totalPersonDays = 0;
  int daysWithFiveOrMore = 0;
  int daysWithTenOrMore = 0;
  int operatingDays = 0; // New: days with at least one person

  for (int i = 0; i < totalDays; i++) {
    final day = DateTime(periodStart.year, periodStart.month, periodStart.day + i);
    final count = dailyStaff[day]?.length ?? 0;
    if (count > 0) {
      operatingDays++;
      totalPersonDays += count;
      if (count >= 5) daysWithFiveOrMore++;
      if (count >= 10) daysWithTenOrMore++;
    }
  }

  // Use operatingDays (가동일수) instead of calendar totalDays for average
  final average = operatingDays == 0 ? 0.0 : (totalPersonDays / operatingDays);
  final halfDays = operatingDays / 2.0;
  bool isFiveOrMore;
  String reason;
  if (average >= 5.0) {
    if (daysWithFiveOrMore < halfDays) {
      // 시행령 제7조의2 제2항 예외
      isFiveOrMore = false;
      reason = '[예외 적용] 한 달 평균 5인 이상이지만, 5인 이상 출근한 날이 한 달 영업일의 절반(1/2)에 못 미치므로 최종적으로 [5인 미만] 사업장으로 판정되었습니다.';
    } else {
      isFiveOrMore = true;
      reason = '[정상 적용] 한 달 평균 5인 이상 근무하며, 5인 이상 출근한 날도 영업일의 절반(1/2)을 넘으므로 최종적으로 [5인 이상] 사업장으로 판정되었습니다.';
    }
  } else {
    if (daysWithFiveOrMore >= halfDays) {
      // 시행령 제7조의2 제3항 예외
      isFiveOrMore = true;
      reason = '[특별 조항 적용] 한 달 평균 근무자는 5인 미만이지만, 5인 이상이 동시에 출근한 날이 한 달 영업일의 절반(1/2) 이상을 차지하므로 노동법상 [5인 이상] 사업장으로 간주됩니다.';
    } else {
      isFiveOrMore = false;
      reason = '[정상 적용] 한 달 평균 5인 미만이고 5인 이상 출근한 날도 영업일의 절반 미만이므로 최종적으로 [5인 미만] 사업장으로 유지됩니다.';
    }
  }
  final isTenOrMore = average >= 10.0;

  return StandingResult(
    average: average,
    totalPersonDays: totalPersonDays,
    totalDays: totalDays,
    daysWithFiveOrMore: daysWithFiveOrMore,
    isFiveOrMore: isFiveOrMore,
    daysWithTenOrMore: daysWithTenOrMore,
    isTenOrMore: isTenOrMore,
    fiveOrMoreDecisionReason: reason,
    fiveOrMoreLegalReason: reason,
  );
}

