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
  final int operatingDays;
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
    required this.operatingDays,
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

  // ── 1. 실제 출퇴근 기록 반영 (1차 기준) ──
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

  // ── 2. 계약 기반 보조 반영 (2차 보조: 출퇴근 누락 방지) ──
  // 조건: active 상태 + 해당 요일이 근무요일 + 최근 30일 내 출퇴근 기록 ≥ 1건
  // 제외: 퇴직자(inactive), 파견직(dispatch)
  final recentCutoff = periodEnd.subtract(const Duration(days: 30));
  final staffRecentActivity = <String, bool>{};

  for (final staff in staffList) {
    if (staff.status == 'inactive') continue;
    if (staff.workerType == 'dispatch') continue;

    // 최근 30일 내 활동 여부 캐싱
    if (!staffRecentActivity.containsKey(staff.id)) {
      staffRecentActivity[staff.id] = attendances.any((a) =>
          a.staffId == staff.id &&
          !a.clockIn.isBefore(recentCutoff));
    }
  }

  for (int i = 0; i < totalDays; i++) {
    final day = DateTime(periodStart.year, periodStart.month, periodStart.day + i);
    final weekday = day.weekday % 7; // 0=Sun, ..., 6=Sat (matched Worker.workDays)

    for (final staff in staffList) {
      if (staff.status == 'inactive') continue;
      if (staff.workerType == 'dispatch') continue;

      // 가상직원: 기존 로직 유지 (테스트 시뮬레이션용)
      if (staff.name.contains('가상')) {
        if (staff.workDays.contains(weekday)) {
          dailyStaff.putIfAbsent(day, () => <String>{}).add(staff.id);
        }
        continue;
      }

      // 실제 직원: 해당 날짜에 이미 attendance로 집계되었으면 스킵
      if (dailyStaff[day]?.contains(staff.id) ?? false) continue;

      // 계약 근무요일 일치 + 최근 30일 활동 존재 → 인원 추가
      if (staff.workDays.contains(weekday) &&
          (staffRecentActivity[staff.id] ?? false)) {
        dailyStaff.putIfAbsent(day, () => <String>{}).add(staff.id);
      }
    }
  }

  int totalPersonDays = 0;
  int daysWithFiveOrMore = 0;
  int daysWithTenOrMore = 0;
  int operatingDays = 0; // 가동일수: 1명 이상 근무한 날

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

  // 평균 산출: 가동일수 기준
  final average = operatingDays == 0 ? 0.0 : (totalPersonDays / operatingDays);
  final halfDays = operatingDays / 2.0;
  bool isFiveOrMore;
  String reason;
  if (average >= 5.0) {
    if (daysWithFiveOrMore < halfDays) {
      // 시행령 제7조의2 제2항 예외
      isFiveOrMore = false;
      reason = '[참고] 근무기록·계약정보 기준 평균 약 ${average.toStringAsFixed(1)}명이나, 5인 이상 근무일이 영업일의 절반 미만이므로 5인 미만으로 추정됩니다. (노무 판단 참고용)';
    } else {
      isFiveOrMore = true;
      reason = '[참고] 근무기록·계약정보 기준 평균 약 ${average.toStringAsFixed(1)}명이며, 5인 이상 근무일이 영업일 절반을 넘으므로 5인 이상으로 추정됩니다. (노무 판단 참고용)';
    }
  } else {
    if (operatingDays > 0 && daysWithFiveOrMore >= halfDays) {
      // 시행령 제7조의2 제3항 예외
      isFiveOrMore = true;
      reason = '[참고] 평균 약 ${average.toStringAsFixed(1)}명이나, 5인 이상 근무일이 영업일 절반 이상이므로 5인 이상으로 추정됩니다. (근로기준법 시행령 제7조의2 참조 / 노무 판단 참고용)';
    } else {
      isFiveOrMore = false;
      reason = '[참고] 근무기록·계약정보 기준 평균 약 ${average.toStringAsFixed(1)}명이며, 5인 미만으로 추정됩니다. (노무 판단 참고용)';
    }
  }
  final isTenOrMore = average >= 10.0;

  return StandingResult(
    average: average,
    totalPersonDays: totalPersonDays,
    totalDays: totalDays,
    operatingDays: operatingDays,
    daysWithFiveOrMore: daysWithFiveOrMore,
    isFiveOrMore: isFiveOrMore,
    daysWithTenOrMore: daysWithTenOrMore,
    isTenOrMore: isTenOrMore,
    fiveOrMoreDecisionReason: reason,
    fiveOrMoreLegalReason: reason,
  );
}


