import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:hive/hive.dart';
import 'package:shared_logic/shared_logic.dart';

import '../models/worker.dart';
import '../models/schedule_override.dart';
import '../services/worker_service.dart';
import '../utils/standing_calculator.dart';

/// 통합 컴플라이언스 알림 엔진
/// 대시보드에 표시할 법적·재무·운영 경고를 생성합니다.
class ComplianceAlertEngine {
  /// 모든 활성 직원에 대해 컴플라이언스 체크를 수행하고 알림 목록을 반환합니다.
  static Future<List<ComplianceAlert>> generateAlerts({
    required String storeId,
    required Map<String, dynamic> storeData,
  }) async {
    final alerts = <ComplianceAlert>[];
    final workers = WorkerService.getAll()
        .where((w) => w.status == 'active' && w.workerType != 'dispatch')
        .toList();
    
    if (workers.isEmpty || storeId.isEmpty) return alerts;

    // ── Schedule Override Box (Hive) 열기 ──
    Box<ScheduleOverride> overrideBox;
    if (Hive.isBoxOpen('schedule_overrides_$storeId')) {
      overrideBox = Hive.box<ScheduleOverride>('schedule_overrides_$storeId');
    } else {
      overrideBox = await Hive.openBox<ScheduleOverride>('schedule_overrides_$storeId');
    }

    // ── 근로계약서 문서 조회 (1회 일괄) ──
    // ★ 서류는 stores/{storeId}/documents/ 하위 컬렉션에 저장됨
    List<LaborDocument> allDocs = [];
    try {
      final docsSnap = await FirebaseFirestore.instance
          .collection('stores')
          .doc(storeId)
          .collection('documents')
          .get();
      
      for (final doc in docsSnap.docs) {
        try {
          allDocs.add(LaborDocument.fromMap(doc.id, doc.data()));
        } catch (e) {
          // 파싱 불가능한 문서 건너뜀 (type enum 불일치 등)
          debugPrint('[ComplianceAlert] doc parse skip: ${doc.id} → $e');
        }
      }
    } catch (e) {
      debugPrint('[ComplianceAlert] docs query error: $e');
      // 문서 조회 실패해도 R-05 외 다른 알림은 계속 진행
    }

    // ── 급여 정산 기간 ──
    // ★ 현재 + 전월 정산기간 모두 체크 (초과근무는 즉시 감지해야 함)
    final now = AppClock.now();
    final settlementStartDay =
        (storeData['settlementStartDay'] as num?)?.toInt() ?? 1;
    final settlementEndDay =
        (storeData['settlementEndDay'] as num?)?.toInt() ?? 31;
    final payday = (storeData['payday'] as num?)?.toInt() ?? 
                   (storeData['payDay'] as num?)?.toInt() ??
                   (storeData['wagePaymentDay'] as num?)?.toInt() ?? 10; // 기본값 10일
    // payday 전이면 전월 데이터는 '현재 급여주기'에 해당
    final bool prevIsCurrent = now.day < payday;
    debugPrint('[ComplianceAlert] today=${now.day}, payday=$payday, prevIsCurrent=$prevIsCurrent');
    
    late final SettlementPeriod period;
    late final SettlementPeriod prevPeriod;
    try {
      period = computeSettlementPeriod(
        now: now,
        settlementStartDay: settlementStartDay,
        settlementEndDay: settlementEndDay,
      );
      // ★ 항상 전월도 체크 — 초과근무 알람은 즉시 감지되어야 함
      final prevMonth = DateTime(now.year, now.month - 1, now.day.clamp(1, 28));
      prevPeriod = computeSettlementPeriod(
        now: prevMonth,
        settlementStartDay: settlementStartDay,
        settlementEndDay: settlementEndDay,
      );
    } catch (e) {
      debugPrint('[ComplianceAlert] settlement period error: $e');
      return alerts;
    }

    // ── 출석 기록 (현재 + 전월 정산 기간) ──
    List<Attendance> periodAttendances = [];
    List<Attendance> prevPeriodAttendances = [];
    try {
      final attendanceSnap = await FirebaseFirestore.instance
          .collection('attendance')
          .where('storeId', isEqualTo: storeId)
          .get();
      
      final periodStart = period.start;
      final periodEndExclusive = period.end.add(const Duration(days: 1));
      
      // 전월 정산기간 범위
      final prevStart = prevPeriod.start;
      final prevEndExclusive = prevPeriod.end.add(const Duration(days: 1));
      
      for (final doc in attendanceSnap.docs) {
        try {
          final att = Attendance.fromJson(doc.data(), id: doc.id);
          // ★ DateTime 객체로 직접 비교 (Timestamp/String 모두 대응)
          if (!att.clockIn.isBefore(periodStart) && att.clockIn.isBefore(periodEndExclusive)) {
            periodAttendances.add(att);
          }
          if (!att.clockIn.isBefore(prevStart) && att.clockIn.isBefore(prevEndExclusive)) {
            prevPeriodAttendances.add(att);
          }
        } catch (_) {
          // 파싱 불가한 출석 기록 건너뜀
        }
      }
    } catch (e) {
      debugPrint('[ComplianceAlert] attendance query error: $e');
    }

    debugPrint('[ComplianceAlert] workers: ${workers.length}명 → ${workers.map((w) => '${w.name}(${w.id.substring(0, 6)})').join(', ')}');
    debugPrint('[ComplianceAlert] allDocs: ${allDocs.length}건');
    debugPrint('[ComplianceAlert] 출석: ${periodAttendances.length}건 (정산기간: ${period.start.toIso8601String().substring(0,10)} ~ ${period.end.toIso8601String().substring(0,10)})');
    debugPrint('[ComplianceAlert] 전월출석: ${prevPeriodAttendances.length}건 (${prevPeriod.start.toIso8601String().substring(0,10)} ~ ${prevPeriod.end.toIso8601String().substring(0,10)})');

    for (final worker in workers) {
      // ════════════════════════════════════════════
      // ════════════════════════════════════════════
      // R-05: 근로계약서 미작성/미교부 감지 (Phase 1)
      // 법적 기준: 근로기준법 제17조 — "근로자에게 교부"가 완료되어야 함
      // ════════════════════════════════════════════
      try {
        if (worker.isPaperContract) {
          debugPrint('[R-05] ${worker.name}: isPaperContract=true → Skip alert');
        } else {
          final workerDocs = allDocs.where((d) => d.staffId == worker.id).toList();
          final contractDocs = workerDocs.where((d) =>
              d.type == DocumentType.contract_full ||
              d.type == DocumentType.contract_part ||
              d.type == DocumentType.laborContract).toList();
          
          // ★ 교부 완료 = 양측 서명 + 근로자에게 전달 완료
          final deliveredContracts = contractDocs.where((d) =>
              d.status == 'signed' || d.status == 'completed' || 
              d.status == 'sent' || d.status == 'delivered').toList();
          
          // 사장님만 서명한 계약서 (교부 미완료)
          final bossOnlyContracts = contractDocs.where((d) =>
              d.status == 'boss_signed').toList();
          
          debugPrint('[R-05] ${worker.name}: 전체문서=${workerDocs.length}, 계약서=${contractDocs.length}(${contractDocs.map((d) => '${d.type.name}:${d.status}').join(',')}), 교부완료=${deliveredContracts.length}, 사장서명만=${bossOnlyContracts.length}');

          if (deliveredContracts.isEmpty) {
            if (bossOnlyContracts.isNotEmpty) {
              // 사장님은 서명했지만 근로자 서명/교부 미완료
              alerts.add(ComplianceAlert(
                id: 'R05_${worker.id}',
                code: 'R-05',
                phase: AlertPhase.phase1,
              severity: AlertSeverity.orange,
              workerName: worker.name,
              workerId: worker.id,
              title: '근로계약서 교부 미완료',
              message: '${worker.name} 근로계약서 근로자 서명 및 교부가 필요합니다.',
              actionType: AlertActionType.createContract,
            ));
          } else if (contractDocs.isNotEmpty) {
            // 계약서는 있지만 아직 서명 전 (draft/ready)
            alerts.add(ComplianceAlert(
              id: 'R05_${worker.id}',
              code: 'R-05',
              phase: AlertPhase.phase1,
              severity: AlertSeverity.red,
              workerName: worker.name,
              workerId: worker.id,
              title: '근로계약서 서명 미완료',
              message: '${worker.name} 근로계약서가 작성되었으나 서명이 필요합니다! (과태료 최대 500만 원)',
              actionType: AlertActionType.createContract,
            ));
          } else {
            // 계약서 자체가 없음
            alerts.add(ComplianceAlert(
              id: 'R05_${worker.id}',
              code: 'R-05',
              phase: AlertPhase.phase1,
              severity: AlertSeverity.red,
              workerName: worker.name,
              workerId: worker.id,
              title: '근로계약서 미작성',
              message: '${worker.name} 근로계약서 미작성 상태입니다! (과태료 최대 500만 원)',
              actionType: AlertActionType.createContract,
            ));
          }
        }
        }
      } catch (e) {
        debugPrint('[ComplianceAlert] R-05 check error for ${worker.name}: $e');
      }

      // ════════════════════════════════════════════
      // R-01: 최저임금 미달 감지 (Phase 1)
      // ════════════════════════════════════════════
      try {
        if (worker.wageType == 'monthly') {
          // 월급제: (기본급 + 식대) / S_Ref
          // ★ S_Ref는 직원별 소정근로시간에 따라 다름 (209h는 40h/주 기준)
          final mealAmount = worker.allowances
              .where((a) => a.label == '식대' || a.label == '식비')
              .fold<double>(0, (sum, a) => sum + a.amount);
          
          final weeklyH = worker.weeklyHours > 0 ? worker.weeklyHours : 40.0;
          final workDaysPerWeek = worker.workDays.isNotEmpty
              ? worker.workDays.length.toDouble()
              : 5.0;
          final weeklyHolidayH = weeklyH >= 15 ? weeklyH / workDaysPerWeek : 0.0;
          final sRef = ((weeklyH + weeklyHolidayH) * 4.345).ceilToDouble();

          final hourly = worker.monthlyWage > 0 && sRef > 0
              ? (worker.monthlyWage + mealAmount) / sRef
              : 0.0;
          if (hourly > 0 && hourly < PayrollConstants.legalMinimumWage) {
            alerts.add(ComplianceAlert(
              id: 'R01_${worker.id}',
              code: 'R-01',
              phase: AlertPhase.phase1,
              severity: AlertSeverity.red,
              workerName: worker.name,
              workerId: worker.id,
              title: '최저임금 미달',
              message: '${worker.name} 통상시급(${hourly.floor()}원)이 최저임금(${PayrollConstants.legalMinimumWage.toInt()}원)에 미달합니다. (S_Ref ${sRef.toInt()}h)',
              actionType: AlertActionType.editWage,
            ));
          }
        } else {
          if (worker.hourlyWage > 0 && worker.hourlyWage < PayrollConstants.legalMinimumWage) {
            alerts.add(ComplianceAlert(
              id: 'R01_${worker.id}',
              code: 'R-01',
              phase: AlertPhase.phase1,
              severity: AlertSeverity.red,
              workerName: worker.name,
              workerId: worker.id,
              title: '최저임금 미달',
              message: '${worker.name} 시급(${worker.hourlyWage.toInt()}원)이 최저임금(${PayrollConstants.legalMinimumWage.toInt()}원)에 미달합니다.',
              actionType: AlertActionType.editWage,
            ));
          }
        }
      } catch (e) {
        debugPrint('[ComplianceAlert] R-01 check error for ${worker.name}: $e');
      }

      // ════════════════════════════════════════════
      // R-04: 고정OT 방어선 돌파 감지 (Phase 2)
      // ════════════════════════════════════════════
      try {
        if (worker.wageType == 'monthly') {
          // ★ fixedOvertimeHours가 0이어도 fixedOvertimePay가 설정된 경우 역산
          double effectiveOTHours = worker.fixedOvertimeHours;
          
          if (effectiveOTHours <= 0 && worker.fixedOvertimePay > 0) {
            // 통상시급 역산으로 고정OT시간 산출
            final mealAmt = worker.allowances
                .where((a) => a.label == '식대' || a.label == '식비')
                .fold<double>(0, (sum, a) => sum + a.amount);
            final weeklyH = worker.weeklyHours > 0 ? worker.weeklyHours : 40.0;
            final workDaysPerWeek = worker.workDays.isNotEmpty
                ? worker.workDays.length.toDouble()
                : 5.0;
            final dailyHForCalc = weeklyH / workDaysPerWeek;
            final weeklyHolidayH = weeklyH >= 15 ? dailyHForCalc : 0.0;
            final sRef = ((weeklyH + weeklyHolidayH) * 4.345).ceilToDouble();
            final ordinaryHourly = sRef > 0
                ? (worker.monthlyWage + mealAmt) / sRef
                : 0.0;
            
            final isFiveOrMore = storeData['isFiveOrMore'] == true;
            final multiplier = isFiveOrMore ? 1.5 : 1.0;
            if (ordinaryHourly > 0) {
              effectiveOTHours = (worker.fixedOvertimePay / (ordinaryHourly * multiplier) * 10).floorToDouble() / 10.0;
            }
            debugPrint('[R-04] ${worker.name}: fixedOTHours=0 → fixedOTPay=${worker.fixedOvertimePay}로 역산=${effectiveOTHours.toStringAsFixed(1)}h');
          }
          
          debugPrint('[R-04] ${worker.name}: wageType=${worker.wageType}, '
              'fixedOTHours=${worker.fixedOvertimeHours}, fixedOTPay=${worker.fixedOvertimePay}, '
              'effectiveOTH=${effectiveOTHours.toStringAsFixed(1)}');
          
          if (effectiveOTHours > 0) {
            // ★ 현재 + 전월 정산기간 체크 로직 수정 (요청사항 반영)
            // 전월 정산분은 '급여일(payday)'까지만 알람을 띄웁니다.
            final periodsToCheck = <({String label, List<Attendance> attendances})>[
              (label: '현재', attendances: periodAttendances),
              if (prevPeriodAttendances.isNotEmpty && now.day <= payday)
                (label: '전월', attendances: prevPeriodAttendances),
            ];
            
            for (final p in periodsToCheck) {
              final workerAttendances = p.attendances
                  .where((a) => a.staffId == worker.id)
                  .toList();
              
              final dailyH = worker.weeklyHours > 0
                  ? worker.weeklyHours / (worker.workDays.isNotEmpty
                      ? worker.workDays.length
                      : 5)
                  : 8.0;
              final dailyLimitMin = (dailyH * 60).round();
              
              double totalOvertimeMinutes = 0;
              for (final att in workerAttendances) {
                if (att.clockOut == null) continue;
                final worked = att.clockOut!.difference(att.clockIn).inMinutes;
                // ★ 실제 휴게 기록 우선, 없으면 worker 기본값, 그것도 없으면 0
                int breakMin = 0;
                if (att.breakStart != null && att.breakEnd != null) {
                  breakMin = att.breakEnd!.difference(att.breakStart!).inMinutes.clamp(0, worked);
                } else if (worker.breakMinutes > 0) {
                  breakMin = worker.breakMinutes.toInt();
                }
                final netMinutes = (worked - breakMin).clamp(0, 1440);
                if (netMinutes > dailyLimitMin) {
                  totalOvertimeMinutes += (netMinutes - dailyLimitMin);
                }
              }
              
              final overtimeHours = totalOvertimeMinutes / 60.0;
              debugPrint('[R-04] ${worker.name}(${p.label}): 출석=${workerAttendances.length}건, '
                  '소정근로=${dailyH}h/일(${dailyLimitMin}min), 연장누적=${overtimeHours.toStringAsFixed(1)}h, '
                  '고정OT=${effectiveOTHours.toStringAsFixed(1)}h → '
                  '${overtimeHours > effectiveOTHours ? "⚠ 초과!" : "정상"}');
              
              if (overtimeHours > effectiveOTHours) {
                final excessHours = overtimeHours - effectiveOTHours;
                alerts.add(ComplianceAlert(
                  id: 'R04_${worker.id}_${p.label}',
                  code: 'R-04',
                  phase: AlertPhase.phase2,
                  severity: AlertSeverity.orange, // 주황색(안내)으로 완화
                  workerName: worker.name,
                  workerId: worker.id,
                  title: '고정연장시간 초과 안내',
                  message: '${worker.name}님의 실제 연장근로가 약정된 고정연장시간(${effectiveOTHours.toStringAsFixed(1)}h)을 ${excessHours.toStringAsFixed(1)}h 초과했습니다. 초과 수당은 이번 급여 정산에 자동으로 합산됩니다.',
                  actionType: AlertActionType.viewAttendance,
                ));
                break; // 초과 발견 시 중복 알람 방지
              }
            }
          }
        }
      } catch (e) {
        debugPrint('[ComplianceAlert] R-04 check error for ${worker.name}: $e');
      }

      // ════════════════════════════════════════════
      // M-01: 월급제 직원 무단결근 감지 (Phase 1)
      // ════════════════════════════════════════════
      try {
        if (worker.wageType == 'monthly') {
          int absenceCount = 0;
          final today = AppClock.now();
          final yesterday = DateTime(today.year, today.month, today.day).subtract(const Duration(days: 1));
          
          final combinedAttendances = [...prevPeriodAttendances, ...periodAttendances];
          
          // 검사 범위: (승인됨) 전월 정산 시작일부터 어제까지 (급여 정산 완료 전이라고 가정)
          final checkStartDate = prevPeriod.start.isBefore(period.start) ? prevPeriod.start : period.start;
          
          DateTime d = checkStartDate;
          while (!d.isAfter(yesterday)) {
            final ymd = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
            final key = '${worker.id}_$ymd';
            final override = overrideBox.get(key);
            
            bool isExpectedToWork = false;
            if (override != null) {
              if (override.isAnnualLeave) {
                isExpectedToWork = false; // 연차 방어
              } else if (override.checkIn == null && override.checkOut == null) {
                isExpectedToWork = false; // 대타 근무 / 사장님 휴무 지정 방어
              } else {
                isExpectedToWork = true; // 스케줄 추가됨
              }
            } else {
              if (worker.workDays.contains(d.weekday)) {
                isExpectedToWork = true; // 약정 근무일
              }
            }
            
            if (isExpectedToWork) {
              final hasAttendance = combinedAttendances.any((att) => 
                att.clockIn.year == d.year && att.clockIn.month == d.month && att.clockIn.day == d.day
              );
              if (!hasAttendance) {
                absenceCount++;
              }
            }
            d = d.add(const Duration(days: 1));
          }
          
          if (absenceCount > 0) {
            alerts.add(ComplianceAlert(
              id: 'M01_${worker.id}',
              code: 'M-01',
              phase: AlertPhase.phase1,
              severity: AlertSeverity.orange,
              workerName: worker.name,
              workerId: worker.id,
              title: '월급제 결근 감지',
              message: '${worker.name}님의 출근 기록이 없는 날이 ${absenceCount}건 있습니다. 단순 미체크인지 실제 결근인지 근무표를 확인해 주세요.',
              actionType: AlertActionType.goToSchedule,
            ));
          }
        }
      } catch (e) {
        debugPrint('[ComplianceAlert] M-01 check error for ${worker.name}: $e');
      }
    }

    // ════════════════════════════════════════════
    // O-01 & R-02: 급여 지급일 알림 (Phase 2)
    // ════════════════════════════════════════════
    try {
      // ★ 단순 접근: "오늘 기준 가장 가까운 급여일" 계산
      // prevPeriod.end 기반 추론은 정산기간 교차(16~15)에서 잘못된 월을 산출하므로 제거
      final todayDate = DateTime(now.year, now.month, now.day);
      
      // 이번 달 급여일
      int lastDayThisMonth = DateTime(now.year, now.month + 1, 0).day;
      int safePaydayThisMonth = payday.clamp(1, lastDayThisMonth);
      final thisMonthPayday = DateTime(now.year, now.month, safePaydayThisMonth);
      
      // 다음 달 급여일
      int nextMonth = now.month + 1;
      int nextYear = now.year;
      if (nextMonth > 12) { nextMonth = 1; nextYear += 1; }
      int lastDayNextMonth = DateTime(nextYear, nextMonth + 1, 0).day;
      int safePaydayNextMonth = payday.clamp(1, lastDayNextMonth);
      final nextMonthPayday = DateTime(nextYear, nextMonth, safePaydayNextMonth);
      
      // 지난 달 급여일
      int prevMonth = now.month - 1;
      int prevYear = now.year;
      if (prevMonth < 1) { prevMonth = 12; prevYear -= 1; }
      int lastDayPrevMonth = DateTime(prevYear, prevMonth + 1, 0).day;
      int safePaydayPrevMonth = payday.clamp(1, lastDayPrevMonth);
      final prevMonthPayday = DateTime(prevYear, prevMonth, safePaydayPrevMonth);
      
      // 가장 가까운 미래 급여일 선택
      final DateTime payDeadline;
      if (!thisMonthPayday.isBefore(todayDate)) {
        payDeadline = thisMonthPayday; // 이번 달 급여일이 아직 안 지남
      } else {
        payDeadline = nextMonthPayday; // 이번 달 급여일 지남 → 다음 달
      }
      
      // 직전 급여일 이후 경과일 (기한 초과 판정용)
      final DateTime lastPayday;
      if (thisMonthPayday.isBefore(todayDate)) {
        lastPayday = thisMonthPayday;
      } else {
        lastPayday = prevMonthPayday;
      }
      
      final daysUntilDeadline = payDeadline.difference(todayDate).inDays;
      final daysSinceLastPayday = todayDate.difference(lastPayday).inDays;
      
      debugPrint('[ComplianceAlert] payday=$payday, today=${todayDate.toIso8601String().substring(0,10)}, '
          'nextPayday=${payDeadline.toIso8601String().substring(0,10)}, daysUntil=$daysUntilDeadline, '
          'lastPayday=${lastPayday.toIso8601String().substring(0,10)}, daysSince=$daysSinceLastPayday');
      
      if (workers.isNotEmpty) {
        if (daysUntilDeadline <= 0) {
          alerts.add(ComplianceAlert(
            id: 'R02_store',
            code: 'R-02',
            phase: AlertPhase.phase2,
            severity: AlertSeverity.red,
            workerName: '',
            workerId: '',
            title: '급여 지급 기한 초과',
            message: '급여 지급 기한이 ${(-daysUntilDeadline)}일 지났습니다. 임금체불 위험!',
            actionType: AlertActionType.viewPayroll,
          ));
        } else if (daysUntilDeadline <= 3) {
          alerts.add(ComplianceAlert(
            id: 'O01_store',
            code: 'O-01',
            phase: AlertPhase.phase2,
            severity: AlertSeverity.orange,
            workerName: '',
            workerId: '',
            title: '급여 지급일 임박',
            message: '급여 지급 기한이 ${daysUntilDeadline}일 남았습니다. 정산을 준비하세요.',
            actionType: AlertActionType.viewPayroll,
          ));
        }
      }
    } catch (e) {
      debugPrint('[ComplianceAlert] O-01/R-02 check error: $e');
    }

    // ═══════════════════════════════════════
    // 정렬: Phase 1 > Phase 2 > Phase 3, 심각도 red > orange > yellow
    // ═══════════════════════════════════════
    alerts.sort((a, b) {
      final phaseCmp = a.phase.index.compareTo(b.phase.index);
      if (phaseCmp != 0) return phaseCmp;
      return a.severity.index.compareTo(b.severity.index);
    });

    return alerts;
  }
}

/// 알림 데이터 모델
class ComplianceAlert {
  final String id;
  final String code;
  final AlertPhase phase;
  final AlertSeverity severity;
  final String workerName;
  final String workerId;
  final String title;
  final String message;
  final AlertActionType actionType;

  const ComplianceAlert({
    required this.id,
    required this.code,
    required this.phase,
    required this.severity,
    required this.workerName,
    required this.workerId,
    required this.title,
    required this.message,
    required this.actionType,
  });
}

enum AlertPhase { phase1, phase2, phase3 }
enum AlertSeverity { red, orange, yellow }
enum AlertActionType {
  createContract,
  editWage,
  viewPayroll,
  viewAttendance,
  viewSettings,
  goToSchedule,
}
