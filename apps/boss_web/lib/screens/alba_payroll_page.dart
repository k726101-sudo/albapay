import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_logic/shared_logic.dart';

class AlbaPayrollPage extends StatelessWidget {
  final String storeId;
  final String workerId;
  final Map<String, dynamic> worker;

  const AlbaPayrollPage({
    super.key,
    required this.storeId,
    required this.workerId,
    required this.worker,
  });

  /// Boss 화면과 동일한 식대 추출 로직 (Single Source of Truth)
  double _extractMealAllowance(Map<String, dynamic> worker) {
    double mealAllowance = 0.0;
    final allowances = (worker['allowances'] as List?) ?? [];
    for (final alw in allowances) {
      final label = (alw['label']?.toString() ?? '').replaceAll(' ', '');
      if (label.contains('식비') || label.contains('식대')) {
        mealAllowance += (alw['amount'] as num?)?.toDouble() ?? 0.0;
      }
    }
    return mealAllowance;
  }

  int _safeDayInMonth(int year, int month, int day) {
    final lastDay = DateTime(year, month + 1, 0).day;
    return day.clamp(1, lastDay);
  }

  ({DateTime start, DateTime end}) _computeSettlementPeriod(
    DateTime now,
    int settlementStartDay,
    int settlementEndDay,
  ) {
    final currentMonth = DateTime(now.year, now.month, 1);
    final previousMonth = DateTime(now.year, now.month - 1, 1);

    if (settlementStartDay <= settlementEndDay) {
      final useMonth = (now.day >= settlementStartDay && now.day <= settlementEndDay)
          ? currentMonth
          : previousMonth;
      final start = DateTime(useMonth.year, useMonth.month,
          _safeDayInMonth(useMonth.year, useMonth.month, settlementStartDay));
      final end = DateTime(useMonth.year, useMonth.month,
          _safeDayInMonth(useMonth.year, useMonth.month, settlementEndDay));
      return (start: start, end: end);
    }

    final startMonth =
        (now.day >= settlementStartDay) ? currentMonth : previousMonth;
    final endMonth = DateTime(startMonth.year, startMonth.month + 1, 1);
    final start = DateTime(startMonth.year, startMonth.month,
        _safeDayInMonth(startMonth.year, startMonth.month, settlementStartDay));
    final end = DateTime(endMonth.year, endMonth.month,
        _safeDayInMonth(endMonth.year, endMonth.month, settlementEndDay));
    return (start: start, end: end);
  }

  double _effectiveHourlyWage(Map<String, dynamic> worker, DateTime at,
      {double? minimumHourlyWage}) {
    final wage = (worker['hourlyWage'] as num?)?.toDouble() ?? 0;
    final isProbation = worker['isProbation'] as bool? ?? false;
    final probMonths = (worker['probationMonths'] as num?)?.toInt() ?? 0;
    if (!isProbation || probMonths <= 0) return wage;
    final start = DateTime.tryParse(
        worker['startDate']?.toString() ?? worker['joinDate']?.toString() ?? '');
    if (start == null) return wage;
    final probEnd = DateTime(start.year, start.month + probMonths, start.day);
    if (!at.isBefore(probEnd)) return wage;
    final probWage = (wage * 0.9).floorToDouble();
    if (minimumHourlyWage != null && minimumHourlyWage > 0) {
      return probWage < minimumHourlyWage ? minimumHourlyWage : probWage;
    }
    return probWage;
  }

  String _formatWon(double amount) {
    return amount
        .toInt()
        .toString()
        .replaceAllMapped(
            RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance
          .collection('stores')
          .doc(storeId)
          .get(),
      builder: (context, storeSnap) {
        final storeData = storeSnap.data?.data();
        final settlementStartDay =
            (storeData?['settlementStartDay'] as num?)?.toInt() ?? 1;
        final settlementEndDay =
            (storeData?['settlementEndDay'] as num?)?.toInt() ?? 31;
        final isFiveOrMore = (storeData?['isFiveOrMore'] as bool?) ?? false;
        final minimumWage =
            (storeData?['minimumHourlyWage'] as num?)?.toDouble();
        final gracePeriod =
            (storeData?['attendanceGracePeriodMinutes'] as num?)?.toInt() ?? 0;

        if (storeSnap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        return FutureBuilder<List<Attendance>>(
          future: DatabaseService().getAttendance(storeId),
          builder: (context, attSnap) {
            if (attSnap.connectionState == ConnectionState.waiting &&
                !attSnap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final allAtt = attSnap.data ?? [];
            final now = AppClock.now();
            final workerId = this.workerId;
            final period = _computeSettlementPeriod(
                now, settlementStartDay, settlementEndDay);

            // Filter to my attendance in this period
            final myAtt = allAtt.where((a) {
              if (a.staffId != workerId) return false;
              final inDay = DateTime(a.clockIn.year, a.clockIn.month, a.clockIn.day);
              return !inDay.isBefore(period.start) && !inDay.isAfter(period.end);
            }).toList();

            // Count tardy
            int tardyCount = 0;
            for (final a in myAtt) {
              final inHm =
                  '${a.clockIn.hour.toString().padLeft(2, '0')}:${a.clockIn.minute.toString().padLeft(2, '0')}';
              final sInHm =
                  (worker['checkInTime']?.toString() ?? '09:00').substring(0, 5);
              final im = _minsFromHm(inHm);
              final sm = _minsFromHm(sInHm);
              if (im > sm + gracePeriod) tardyCount++;
            }

            final hourlyWage = _effectiveHourlyWage(worker, now,
                minimumHourlyWage: minimumWage);
            final workDays =
                (worker['workDays'] as List?)?.cast<int>() ?? const [];
            final workerData = PayrollWorkerData(
              weeklyHoursPure: (worker['weeklyHours'] as num?)?.toDouble() ?? 0,
              weeklyTotalStayMinutes:
                  (worker['totalStayMinutes'] as num?)?.toInt() ?? 0,
              breakMinutesPerShift:
                  (worker['breakMinutes'] as num?)?.toInt() ?? 0,
              isPaidBreak: worker['isPaidBreak'] as bool? ?? false,
              joinDate: DateTime.tryParse(
                      worker['startDate']?.toString() ?? '') ??
                  now,
              scheduledWorkDays: workDays,
              manualWeeklyHolidayApproval: false,
              allowanceAmounts: ((worker['allowances'] as List?) ?? [])
                  .map((a) => (a['amount'] as num?)?.toDouble() ?? 0.0)
                  .toList(),
              usedAnnualLeave: (worker['usedAnnualLeave'] as num?)?.toDouble() ?? 0.0,
              endDate: worker['endDate'] != null && worker['endDate'].toString().isNotEmpty
                  ? DateTime.tryParse(worker['endDate'].toString())
                  : null,
              weeklyHolidayDay: (worker['weeklyHolidayDay'] as num?)?.toInt() ?? 0,
              graceMinutes: gracePeriod,
              // ── Boss 화면과 동기화된 추가 필드 ──
              breakStartTime: worker['breakStartTime']?.toString() ?? '',
              breakEndTime: worker['breakEndTime']?.toString() ?? '',
              mealAllowance: _extractMealAllowance(worker),
              mealTaxExempt: worker['mealTaxExempt'] as bool? ?? false,
              applyWithholding33: worker['applyWithholding33'] as bool? ?? false,
              deductNationalPension: worker['deductNationalPension'] != false,
              deductHealthInsurance: worker['deductHealthInsurance'] != false,
              deductEmploymentInsurance: worker['deductEmploymentInsurance'] != false,
              wageType: worker['wageType']?.toString() ?? 'hourly',
              monthlyWage: (worker['monthlyWage'] as num?)?.toDouble() ?? 0.0,
              fixedOvertimeHours: (worker['fixedOvertimeHours'] as num?)?.toDouble() ?? 0.0,
              fixedOvertimePay: (worker['fixedOvertimePay'] as num?)?.toDouble() ?? 0.0,
              includeMealInOrdinary: worker['includeMealInOrdinary'] as bool? ?? true,
              includeAllowanceInOrdinary: worker['includeAllowanceInOrdinary'] as bool? ?? false,
              includeFixedOtInAverage: worker['includeFixedOtInAverage'] as bool? ?? false,
            );

            PayrollCalculationResult? result;
            try {
              result = PayrollCalculator.calculate(
                workerData: workerData,
                shifts: myAtt,
                periodStart: period.start,
                periodEnd: period.end,
                hourlyRate: hourlyWage,
                isFiveOrMore: isFiveOrMore,
                allHistoricalAttendances: allAtt.where((a) => a.staffId == workerId).toList(),
              );
            } catch (e) {
              // ignore calculation errors
            }

            // Calculate cumulative worked hours (순수 근로시간 반영 기준)
            double totalWorkedHours = result?.pureLaborHours ?? 0.0;

            // 만약 급여계산이 실패했다면 임시로 체류시간이라도 합산
            if (result == null) {
              for (final a in myAtt) {
                totalWorkedHours += a.workedMinutes / 60.0;
              }
            }

            // Add current session if clocked in (진행 중인 세션은 현재 체류시간으로 가산)
            final openAtt = allAtt
                .where((a) => a.staffId == workerId && a.clockOut == null)
                .firstOrNull;
            if (openAtt != null) {
              totalWorkedHours += openAtt.workedMinutesAt(now) / 60.0;
            }

            final name = worker['name']?.toString() ?? '알바';
            final periodStr =
                '${period.start.month}/${period.start.day} ~ ${period.end.month}/${period.end.day}';

            return Scaffold(
              backgroundColor: const Color(0xFFF2F4F8),
              body: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 40),
                child: Column(
                  children: [
                    // Header
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
                      decoration: const BoxDecoration(
                        color: Color(0xFF1565C0),
                        borderRadius: BorderRadius.vertical(
                            bottom: Radius.circular(24)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                backgroundColor:
                                    Colors.white.withValues(alpha: 0.25),
                                foregroundColor: Colors.white,
                                radius: 22,
                                child: Text(
                                  name.isNotEmpty ? name[0] : '?',
                                  style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(name,
                                      style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white)),
                                  Text('정산 기간: $periodStr',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.white.withValues(alpha: 0.75))),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          const Text('이번 달 예상 급여',
                              style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text(
                            result != null
                                ? '${_formatWon(result.totalPay)}원'
                                : '계산 중...',
                            style: const TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // 누적 근무 시간 카드 (시급제 전용) / 월급제 안내
                    _card(
                      context,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (result != null && result.isMonthlyWage) ...[
                            // ★ 월급제: 시급/근무시간 지표 숨김
                            const Text('월급제 급여 안내',
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.black54)),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE3F2FD),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                '월급제 직원은 매월 약정된 기본급이 고정 지급됩니다.\n'
                                '추가 수당(연장/야간/휴일)은 실제 근무 기록에 따라 별도 산정됩니다.',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF1565C0),
                                    height: 1.5),
                              ),
                            ),
                          ] else ...[
                            // 시급제: 기존 근무시간 카드 유지
                            const Text('이번 달 누적 근무 시간',
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.black54)),
                            const SizedBox(height: 12),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  totalWorkedHours.toInt().toString(),
                                  style: const TextStyle(
                                      fontSize: 48,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFF1565C0),
                                      height: 1),
                                ),
                                const SizedBox(width: 4),
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Text(
                                    '시간 ${((totalWorkedHours * 60) % 60).toInt()}분',
                                    style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF1565C0)),
                                  ),
                                ),
                              ],
                            ),
                            if (openAtt != null)
                              const Padding(
                                padding: EdgeInsets.only(top: 4),
                                child: Row(
                                  children: [
                                    Icon(Icons.circle,
                                        size: 8, color: Color(0xFF43A047)),
                                    SizedBox(width: 4),
                                    Text('현재 근무 중 (실시간 반영)',
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: Color(0xFF43A047),
                                            fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                            const SizedBox(height: 12),
                            LinearProgressIndicator(
                              value: workDays.isNotEmpty
                                  ? (totalWorkedHours /
                                          ((worker['weeklyHours'] as num?)
                                                  ?.toDouble() ??
                                              1.0) /
                                          4)
                                      .clamp(0.0, 1.0)
                                  : 0,
                              backgroundColor: const Color(0xFFE3F2FD),
                              color: const Color(0xFF1565C0),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '시급 ${_formatWon(hourlyWage)}원',
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.black45),
                            ),
                          ],
                        ],
                      ),
                    ),

                    // 급여 내역 카드
                    if (result != null) ...[
                      _card(
                        context,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('급여 내역',
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.black54)),
                            const SizedBox(height: 12),
                            Builder(
                              builder: (context) {
                                String _fmtH(double h) => PayrollCalculator.formatHoursAsKorean(h);
                                double hrly = hourlyWage;
                                double pbH = result!.paidBreakHours; // Using result! since we're in if(result != null)
                                double wH = hrly > 0 ? result.weeklyHolidayPay / hrly : 0;

                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    if (result.isMonthlyWage) ...[
                                      // ── 월급제: 계약 확정 항목 ──
                                      _payRow('기본급', result.basePay, subtitle: '월 약정 기본급'),
                                      if (result.fixedOvertimeBasePay > 0)
                                        _payRow('고정연장수당 (약정)', result.fixedOvertimeBasePay, color: Colors.indigo, subtitle: '월 약정 고정연장수당'),
                                      if (result.mealAllowancePay > 0)
                                        _payRow('식대${result.mealNonTaxable > 0 ? ' (비과세)' : ''}', result.mealAllowancePay, color: Colors.green.shade700),
                                      const Divider(height: 16),
                                      _payRow('목표 월급 소계', result.basePay + result.fixedOvertimeBasePay + result.mealAllowancePay, bold: true),
                                      const Divider(height: 16),
                                      // ── 당월 실근로 기반 추가 ──
                                      if (result.fixedOvertimeExcessPay > 0)
                                        _payRow(
                                          result.isFiveOrMore ? '추가 가산수당 (실근로)' : '초과근무 추가수당',
                                          result.fixedOvertimeExcessPay,
                                          color: Colors.red.shade700,
                                          subtitle: result.isFiveOrMore ? '고정OT 초과 / 야간' : '약정시간 초과분 (기본시급)',
                                        ),
                                      if (result.holidayPremiumPay > 0)
                                        _payRow(
                                          result.isFiveOrMore ? '휴일근로 가산수당' : '휴무일 추가수당',
                                          result.holidayPremiumPay,
                                          color: Colors.blue.shade700,
                                          subtitle: result.isFiveOrMore ? '근로자의 날 / 비정규 출근일' : '휴무일 출근 (기본시급)',
                                        ),
                                      if (result.laborDayAllowancePay > 0)
                                        _payRow('근로자의 날 유급휴일수당', result.laborDayAllowancePay, color: Colors.blue.shade700),
                                      if (result.otherAllowancePay - result.mealAllowancePay > 0)
                                        _payRow('기타 수당', result.otherAllowancePay - result.mealAllowancePay),
                                    ] else ...[
                                      // ── 시급제 ──
                                      _payRow('기본급', result.basePay, subtitle: '${_fmtH(result.pureLaborHours)} × ${_formatWon(hrly)}원'),
                                      if (result.premiumPay > 0)
                                        _payRow('연장/야간 가산수당', result.premiumPay, color: Colors.orange.shade700, subtitle: '${_fmtH(result.premiumHours)} × ${_formatWon(hrly * 0.5)}원'),
                                      if (result.holidayPremiumPay > 0)
                                        _payRow('근로자의 날 휴일근로가산', result.holidayPremiumPay, color: Colors.blue.shade700),
                                      if (result.weeklyHolidayPay > 0)
                                        _payRow('주휴 수당', result.weeklyHolidayPay, subtitle: '${_fmtH(wH)} × ${_formatWon(hrly)}원'),
                                      if (result.breakPay > 0)
                                        _payRow('유급휴게수당', result.breakPay, subtitle: '${_fmtH(pbH)} × ${_formatWon(hrly)}원'),
                                      if (result.otherAllowancePay > 0)
                                        _payRow('기타 수당', result.otherAllowancePay),
                                    ],
                                    const Divider(height: 24),
                                    _payRow('세전 합계', result.totalPay, color: const Color(0xFF1565C0), bold: true),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      ),

                      // 근태 요약
                      _card(
                        context,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('근태 요약',
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.black54)),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                _statBox(
                                    '이번 달 출근',
                                    '${myAtt.where((a) => a.clockOut != null).length}회',
                                    const Color(0xFF1565C0)),
                                const SizedBox(width: 12),
                                _statBox(
                                    '지각',
                                    '$tardyCount회',
                                    tardyCount > 0
                                        ? Colors.redAccent
                                        : Colors.black54),
                              ],
                            ),
                            if (result.isPerfectAttendance) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE8F5E9),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(Icons.star_rounded,
                                        color: Color(0xFF2E7D32), size: 16),
                                    SizedBox(width: 6),
                                    Text('만근 달성!',
                                        style: TextStyle(
                                            color: Color(0xFF2E7D32),
                                            fontWeight: FontWeight.w700)),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),

                      // 상세 근무 내역 (새로 추가)
                      _card(
                        context,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('상세 근무 내역',
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.black54)),
                            const SizedBox(height: 16),
                            if (myAtt.isEmpty && openAtt == null)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 20),
                                child: Center(
                                    child: Text('기록된 근무 내역이 없습니다.',
                                        style: TextStyle(
                                            color: Colors.black38,
                                            fontSize: 13))),
                              )
                            else ...[
                              // 현재 근무 중인 세션 먼저 표시
                              if (openAtt != null)
                                _attendanceLogRow(openAtt, now, gracePeriod, isCurrent: true),
                              
                              // 과거 내역 (내림차순)
                              ...myAtt.reversed.map((a) => _attendanceLogRow(a, now, gracePeriod)),
                            ],
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        '* 위 금액은 사장님 최종 승인 이전의 예상액으로, 실제 지급액과 다를 수 있습니다.',
                        style: TextStyle(
                            fontSize: 11, color: Colors.black.withValues(alpha: 0.35)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _card(BuildContext context, {required Widget child}) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _payRow(String label, double amount,
      {Color? color, bool bold = false, String? subtitle}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: bold ? 15 : 13,
                      color: bold ? Colors.black87 : Colors.black54,
                      fontWeight:
                          bold ? FontWeight.w800 : FontWeight.normal)),
              Text(
                '${_formatWon(amount)}원',
                style: TextStyle(
                  fontSize: bold ? 16 : 14,
                  color: color ?? (bold ? const Color(0xFF1565C0) : Colors.black87),
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.black38)),
          ],
        ],
      ),
    );
  }

  Widget _statBox(String label, String value, Color valueColor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F7FA),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(fontSize: 11, color: Colors.black45)),
            const SizedBox(height: 4),
            Text(value,
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: valueColor)),
          ],
        ),
      ),
    );
  }

  Widget _attendanceLogRow(Attendance a, DateTime now, int graceMinutes, {bool isCurrent = false}) {
    final dateStr = '${a.clockIn.month}/${a.clockIn.day}';
    final weekday = ['일', '월', '화', '수', '목', '금', '토'][a.clockIn.weekday % 7];
    
    final inTime = _formatTime(a.clockIn);
    final outTime = a.clockOut != null ? _formatTime(a.clockOut!) : '진행중';
    
    int mins = 0;
    if (a.clockOut != null) {
      final effectiveIn = a.scheduledShiftStartIso != null && a.scheduledShiftStartIso!.isNotEmpty
          ? payrollEffectiveClockIn(
              actualClockIn: a.clockIn,
              scheduledStart: DateTime.parse(a.scheduledShiftStartIso!),
              graceMinutes: graceMinutes,
            )
          : a.clockIn;
      final effectiveOut = payrollSettlementClockOut(
        actualClockOut: a.clockOut!,
        scheduledShiftEndIso: a.scheduledShiftEndIso,
        overtimeApproved: a.overtimeApproved || a.isEditedByBoss,
        graceMinutes: graceMinutes,
      );
      mins = effectiveOut.difference(effectiveIn).inMinutes;
      if (mins > 0) {
        int breakMins = PayrollCalculator.calculateAppliedBreak(
          att: a,
          effectiveIn: effectiveIn,
          effectiveOut: effectiveOut,
          fallbackMinutes: (worker['breakMinutes'] as num?)?.toInt() ?? 0,
          breakStartTimeStr: worker['breakStartTime']?.toString() ?? '',
          breakEndTimeStr: worker['breakEndTime']?.toString() ?? '',
        );
        mins -= breakMins;
      }
      if (mins < 0) mins = 0;
    } else {
      mins = a.workedMinutesAt(now);
    }
    
    final hours = PayrollCalculator.formatHoursAsKorean(mins / 60.0);

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Container(
            width: 46,
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: isCurrent ? const Color(0xFFE8F5E9) : const Color(0xFFF5F7FA),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Text(dateStr,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: isCurrent ? const Color(0xFF2E7D32) : Colors.black87)),
                Text(weekday,
                    style: TextStyle(
                        fontSize: 10,
                        color: isCurrent ? const Color(0xFF2E7D32).withValues(alpha: 0.7) : Colors.black38)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '$inTime ~ $outTime',
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87),
                    ),
                    if (a.attendanceStatus == 'annual_leave')
                      Container(
                        margin: const EdgeInsets.only(left: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(4)),
                        child: const Text('연차', style: TextStyle(fontSize: 8, color: Colors.blue, fontWeight: FontWeight.bold)),
                      )
                    else if (a.isEditedByBoss)
                      Container(
                        margin: const EdgeInsets.only(left: 6),
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(4)),
                        child: const Text('사장님 수정됨', style: TextStyle(fontSize: 8, color: Colors.orange, fontWeight: FontWeight.bold)),
                      ),
                  ],
                ),
                if (isCurrent)
                  const Text('현재 근무 중입니다',
                      style: TextStyle(fontSize: 11, color: Color(0xFF43A047))),
              ],
            ),
          ),
          Text(
            hours,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1565C0)),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime d) {
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  int _minsFromHm(String hm) {
    final p = hm.split(':');
    if (p.length != 2) return 0;
    return (int.tryParse(p[0]) ?? 0) * 60 + (int.tryParse(p[1]) ?? 0);
  }
}
