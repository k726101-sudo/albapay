import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_logic/shared_logic.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/worker.dart';
import '../../services/worker_service.dart';
import '../../utils/pdf/pdf_generator_service.dart';
import 'exception_approval_screen.dart';
import '../../widgets/store_id_gate.dart';
import '../staff/add_staff_screen.dart';

class PayrollDashboardScreen extends StatefulWidget {
  const PayrollDashboardScreen({super.key});

  @override
  State<PayrollDashboardScreen> createState() => _PayrollDashboardScreenState();
}

class _PayrollDashboardScreenState extends State<PayrollDashboardScreen> {
  final Map<String, bool> _manualWeeklyHolidayApproval = <String, bool>{};
  bool _isFinalizing = false;
  
  int _monthOffset = 0;
  bool _isInitialized = false;
  
  String? _lastStoreId;
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _storeStream;
  Stream<List<Attendance>>? _attendanceStream;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final box = Hive.box('user_settings');
    final storeId = box.get('currentStoreId');
    if (storeId != null && storeId != _lastStoreId) {
      _lastStoreId = storeId;
      _storeStream = FirebaseFirestore.instance.collection('stores').doc(storeId).snapshots();
      _attendanceStream = DatabaseService().streamAttendance(storeId);
    }
  }

  DateTime _getBaseDate(DateTime now, int offset) {
    int y = now.year;
    int m = now.month + offset;
    int d = now.day;
    while (m <= 0) {
      m += 12;
      y -= 1;
    }
    while (m > 12) {
      m -= 12;
      y += 1;
    }
    int maxDays = DateTime(y, m + 1, 0).day;
    return DateTime(y, m, d > maxDays ? maxDays : d);
  }

  Future<void> _finalizeAndSendPayslips({
    required BuildContext context,
    required String storeId,
    required List<Worker> staffList,
    required Map<String, PayrollCalculationResult> staffSummaries,
    required DateTime periodStart,
    required DateTime periodEnd,
    required bool isFiveOrMore,
    required String isFiveOrMoreSource,
    required int daysWithFiveOrMore,
    required int operatingDays,
    required double averageWorkers,
    required String fiveOrMoreDecisionReason,
  }) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('급여 확정 및 발송'),
        content: Text(
          '${periodStart.month}월/${periodStart.day} ~ ${periodEnd.month}/${periodEnd.day} 기간의 급여를 확정하시겠습니까?\n\n'
          '확정 시 각 알바생의 웹 화면에 급여명세서가 즉시 교부됩니다.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('확정 및 발송')),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isFinalizing = true);

    try {
      final db = DatabaseService();
      final now = AppClock.now();
      int count = 0;

      for (final staff in staffList) {
        final summary = staffSummaries[staff.id];
        if (summary == null) continue;

        final docId = 'wage_${staff.id}_${periodStart.year}${periodStart.month.toString().padLeft(2, '0')}';
        final title = '${periodStart.year}년 ${periodStart.month}월 급여명세서';

        // 법적 보존용 데이터 구조화
        final payrollData = {
          'periodStart': periodStart.toIso8601String(),
          'periodEnd': periodEnd.toIso8601String(),
          'basePay': summary.basePay,
          'premiumPay': summary.premiumPay,
          'laborDayAllowancePay': summary.laborDayAllowancePay,
          'holidayPremiumPay': summary.holidayPremiumPay,
          'weeklyHolidayPay': summary.weeklyHolidayPay,
          'breakPay': summary.breakPay,
          'otherAllowancePay': summary.otherAllowancePay,
          'totalPay': summary.totalPay,
          'pureLaborHours': summary.pureLaborHours,
          'hourlyRate': staff.hourlyWage,
          // ★ 정산기간 5인 판정 스냅샷 (확정 시점 박제 — 과거 명세서 무결성 보장)
          'isFiveOrMore': isFiveOrMore,
          'isFiveOrMoreSource': isFiveOrMoreSource,
          'daysWithFiveOrMore': daysWithFiveOrMore,
          'operatingDays': operatingDays,
          'averageWorkers': averageWorkers,
          'fiveOrMoreDecisionReason': fiveOrMoreDecisionReason,
        };

        // 최소 3년 보관 (근로기준법 제48조)
        final retentionDate = DateTime(now.year + 3, now.month, now.day);
        final docWithRetention = LaborDocument(
          id: docId,
          staffId: staff.id,
          storeId: storeId,
          type: DocumentType.wageStatement,
          title: title,
          status: 'sent',
          createdAt: now,
          sentAt: now,
          dataJson: jsonEncode(payrollData),
          retentionUntil: retentionDate,
        );

        await db.saveDocument(docWithRetention);

        // ★ R2 자동 아카이브 (임금명세서 PDF 확정본 보관)
        try {
          final pdfBytes = await PdfGeneratorService.generateWageStatement(
            document: docWithRetention,
            wageData: payrollData,
          );
          await PdfArchiveService.instance.archiveSignedDocument(
            doc: docWithRetention,
            pdfBytes: pdfBytes,
          );
        } catch (archiveError) {
          debugPrint('⚠️ 임금명세서 R2 아카이브 실패 (발송은 정상 완료): $archiveError');
        }
        count++;
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ $count명의 급여명세서 발송이 완료되었습니다.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ 발송 중 오류 발생: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isFinalizing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StoreIdGate(
      builder: (context, storeId) {
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _storeStream ?? const Stream.empty(),
          builder: (context, storeSnapshot) {
            final storeData = storeSnapshot.data?.data();
            final settlementStartDay =
                (storeData?['settlementStartDay'] as num?)?.toInt() ?? 1;
            final settlementEndDay =
                (storeData?['settlementEndDay'] as num?)?.toInt() ?? 31;
            final gracePeriod =
                (storeData?['attendanceGracePeriodMinutes'] as num?)?.toInt() ?? 0;

            if (storeSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            return ValueListenableBuilder<Box<Worker>>(
              valueListenable: Hive.box<Worker>('workers').listenable(),
              builder: (context, box, _) {
                final staffList = WorkerService.getAll();

                return StreamBuilder<List<Attendance>>(
                  stream: _attendanceStream ?? const Stream.empty(),
                  builder: (context, attSnapshot) {
                    if (attSnapshot.hasError) {
                      return Center(child: Text('출퇴근 데이터 스트림 에러: ${attSnapshot.error}', style: const TextStyle(color: Colors.red)));
                    }
                    if (attSnapshot.connectionState == ConnectionState.waiting) {
                       return const Center(child: CircularProgressIndicator());
                    }
                    final allAttendance = attSnapshot.data ?? [];
                    final now = AppClock.now();
                    
                    if (!_isInitialized) {
                      final payday = (storeData?['payday'] as num?)?.toInt() ?? 1;
                      if (now.day < payday) {
                        _monthOffset = -1;
                      }
                      _isInitialized = true;
                    }
                    
                    final baseDate = _getBaseDate(now, _monthOffset);
                    final period = _computeSettlementPeriod(
                      baseDate,
                      settlementStartDay,
                      settlementEndDay,
                    );

                    final periodAttendance = allAttendance.where((att) {
                      final inDay = _dayKey(att.clockIn);
                      final outDay =
                          att.clockOut != null ? _dayKey(att.clockOut!) : null;
                      final inOk = !inDay.isBefore(period.start) &&
                          !inDay.isAfter(period.end);
                      final outOk = outDay != null
                          ? (!outDay.isBefore(period.start) &&
                              !outDay.isAfter(period.end))
                          : false;
                      return inOk || outOk;
                    }).toList();

                    final standing = _calculateStandingFromAttendances(
                      periodAttendance,
                      period.start,
                      period.end,
                      staffList,
                    );

                    double totalLaborCost = 0;
                    final staffSummaries = <String, PayrollCalculationResult>{};
                    final staffRiskExpectedHoliday = <String, double>{};
                    int weeklyHolidayExceptionTotal = 0;
                    int breakSeparationRiskCount = 0;
                    final isFiveOrMoreByStore =
                        (storeData?['isFiveOrMore'] as bool?) ?? false;

                    for (final staff in staffList) {
                      final staffAttendance = periodAttendance
                          .where((a) => a.staffId == staff.id)
                          .toList();
                      final effectiveWage = _effectiveHourlyWage(
                        staff,
                        now,
                        minimumHourlyWage:
                            (storeData?['minimumHourlyWage'] as num?)?.toDouble(),
                      );
                      final approved =
                          _manualWeeklyHolidayApproval[staff.id] ?? staff.weeklyHolidayPay;
                      // 연차 저금통: 전체 출퇴근 이력 전달
                      final staffAllHistory = allAttendance
                          .where((a) => a.staffId == staff.id)
                          .toList();
                      double mealAllowance = 0.0;
                      for (final alw in staff.allowances) {
                        final label = alw.label.replaceAll(' ', '');
                        if (label.contains('식비') || label.contains('식대')) {
                          mealAllowance += alw.amount;
                        }
                      }

                      final workerData = PayrollWorkerData(
                        weeklyHoursPure: staff.weeklyHours,
                        weeklyTotalStayMinutes: staff.totalStayMinutes,
                        breakMinutesPerShift: staff.breakMinutes.toInt(),
                        isPaidBreak: staff.isPaidBreak,
                        joinDate: RobustDateParser.parseWithFallback(
                              staff.joinDate.isNotEmpty
                                  ? staff.joinDate
                                  : staff.startDate,
                              fallback: AppClock.now(),
                            ),
                        scheduledWorkDays: staff.workDays,
                        manualWeeklyHolidayApproval: approved,
                        allowanceAmounts:
                            staff.allowances.map((a) => a.amount).toList(),
                        usedAnnualLeave: staff.usedAnnualLeave,
                        manualAdjustment: staff.annualLeaveManualAdjustment,
                        endDate: staff.endDate != null && staff.endDate!.isNotEmpty
                            ? DateTime.tryParse(staff.endDate!)
                            : null,
                        previousMonthAdjustment: staff.previousMonthAdjustment,
                        applyWithholding33: staff.applyWithholding33,
                        deductNationalPension: staff.deductNationalPension,
                        deductHealthInsurance: staff.deductHealthInsurance,
                        deductEmploymentInsurance: staff.deductEmploymentInsurance,
                        isVirtual: staff.name.contains('가상'),
                        weeklyHolidayDay: staff.weeklyHolidayDay,
                        breakStartTime: staff.breakStartTime,
                        breakEndTime: staff.breakEndTime,
                        graceMinutes: gracePeriod,
                        wageType: staff.wageType,
                        monthlyWage: staff.monthlyWage,
                        fixedOvertimeHours: staff.fixedOvertimeHours,
                        fixedOvertimePay: staff.fixedOvertimePay,
                        mealAllowance: mealAllowance,
                        mealTaxExempt: staff.mealTaxExempt,
                        isProbation: staff.isProbation,
                        probationMonths: staff.probationMonths,
                        wageHistoryJson: staff.wageHistoryJson,
                        promotionLogs: _parsePromotionLogs(staff.leavePromotionLogsJson),
                      );

                      final isInactive = staff.status == 'inactive';
                      DateTime localPeriodEnd = period.end;
                      
                      // 퇴사자의 경우 정산 종료일을 퇴사일로 연장 (사장님 요청: 15일 이후 근무분 합산)
                      if (isInactive && staff.endDate != null && staff.endDate!.isNotEmpty) {
                        final exitDate = DateTime.tryParse(staff.endDate!);
                        if (exitDate != null && exitDate.isAfter(period.end)) {
                          localPeriodEnd = exitDate;
                        }
                      }

                      final result = PayrollCalculator.calculate(
                        workerData: workerData,
                        shifts: staffAttendance.where((a) => !a.clockIn.isAfter(localPeriodEnd.add(const Duration(hours: 23, minutes: 59)))).toList(),
                        periodStart: period.start,
                        periodEnd: localPeriodEnd,
                        hourlyRate: effectiveWage,
                        isFiveOrMore: standing.isFiveOrMore || isFiveOrMoreByStore,
                        allHistoricalAttendances: staffAllHistory,
                      );

                      staffSummaries[staff.id] = result;
                      final totalWithoutWeeklyHoliday =
                          result.totalPay - result.weeklyHolidayPay;
                      final displayedTotal = approved
                          ? totalWithoutWeeklyHoliday + result.weeklyHolidayPay
                          : totalWithoutWeeklyHoliday;
                      totalLaborCost += displayedTotal;
                      if (result.needsBreakSeparationGuide) {
                        breakSeparationRiskCount++;
                      }

                        final weekRange = _currentWeekRange(now);
                        final weekStaffAttendance = allAttendance.where((a) {
                          if (a.staffId != staff.id || a.clockOut == null) return false;
                          final d = _dayKey(a.clockIn);
                          return !d.isBefore(weekRange.start) && !d.isAfter(weekRange.end);
                        }).toList();
                        final weekPureHours = _pureHoursForRisk(
                          weekStaffAttendance,
                          defaultBreakMinutes: staff.breakMinutes.toInt(),
                        );
                        if (staff.weeklyHours < 15 && weekPureHours >= 15) {
                          final calcHours = weekPureHours > 40 ? 40.0 : weekPureHours;
                          final expected = ((calcHours / 40.0) * 8.0 * effectiveWage);
                          staffRiskExpectedHoliday[staff.id] = expected;
                        }
                    }

                    if (staffList.isEmpty) {
                      return Scaffold(
                        appBar: AppBar(
                          leadingWidth: 100,
                          leading: TextButton.icon(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.arrow_back_ios, size: 16, color: Colors.black87),
                            label: const Text('이전 화면', style: TextStyle(color: Colors.black87, fontSize: 13, height: 1.1)),
                          ),
                          title: const Text('초기 세팅 안내'),
                          centerTitle: true,
                        ),
                        body: _buildOnboardingGuide(context, storeId),
                      );
                    }

                    return Scaffold(
                      appBar: AppBar(
                        leadingWidth: 100,
                        leading: TextButton.icon(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.arrow_back_ios, size: 16, color: Colors.black87),
                          label: const Text('이전 화면', style: TextStyle(color: Colors.black87, fontSize: 13, height: 1.1)),
                        ),
                        title: const Text('급여 리포트'),
                        actions: [
                          TextButton(
                            onPressed: () => _finalizeIsFiveOrMoreBeforePayroll(
                              context: context,
                              storeId: storeId,
                              periodAttendance: periodAttendance,
                              periodStart: period.start,
                              periodEnd: period.end,
                            ),
                            child: const Text('최종 판정 반영'),
                          ),
                        ],
                      ),
                      body: SafeArea(
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 600),
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildPeriodNavigator(period),
                                  const SizedBox(height: 16),
                                  _buildTotalInfoCard(totalLaborCost),
                                  const SizedBox(height: 32),
                                  _buildStandingCard(
                                    context,
                                    standing: standing,
                                  ),
                                  const SizedBox(height: 32),
                                  _buildExceptionAlert(
                                    context,
                                    weeklyHolidayExceptionTotal,
                                    breakSeparationRiskCount,
                                  ),
                                  const SizedBox(height: 32),
                                  const Text(
                                    '직원별 상세요약',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  ListView.separated(
                                    shrinkWrap: true,
                                    physics: const NeverScrollableScrollPhysics(),
                                    itemCount: staffList.length,
                                    separatorBuilder: (_, index) =>
                                        const SizedBox(height: 12),
                                    itemBuilder: (context, index) {
                                      final staff = staffList[index];
                                      final summary = staffSummaries[staff.id];
                                      final expectedRisk = staffRiskExpectedHoliday[staff.id];
                                      final approved =
                                          _manualWeeklyHolidayApproval[staff.id] ?? staff.weeklyHolidayPay;
                                      return _buildStaffSummaryCard(
                                        staff,
                                        summary,
                                        manualWeeklyHolidayApproved: approved,
                                        onManualWeeklyHolidayApprovalChanged: (v) async {
                                          _manualWeeklyHolidayApproval[staff.id] = v;
                                          
                                          // DB에 상태 영구 유지
                                          await FirebaseFirestore.instance
                                              .collection('stores')
                                              .doc(storeId)
                                              .collection('staffs')
                                              .doc(staff.id)
                                              .update({'weeklyHolidayPay': v});
                                              
                                          if (context.mounted) {
                                            setState(() {});
                                          }
                                        },
                                        expectedHolidayRiskAmount: expectedRisk,
                                        minWage: ((storeData?['minimumHourlyWage'] as num?)?.toDouble() ?? 0) > 0
                                            ? (storeData?['minimumHourlyWage'] as num?)!.toDouble() 
                                            : PayrollConstants.legalMinimumWage,
                                      );
                                    },
                                  ),
                                  const SizedBox(height: 16),
                                  if (_isFinalizing)
                                    const Center(child: CircularProgressIndicator())
                                  else
                                    SizedBox(
                                      width: double.infinity,
                                      height: 56,
                                      child: FilledButton.icon(
                                        onPressed: () => _finalizeAndSendPayslips(
                                          context: context,
                                          storeId: storeId,
                                          staffList: staffList,
                                          staffSummaries: staffSummaries,
                                          periodStart: period.start,
                                          periodEnd: period.end,
                                          isFiveOrMore: standing.isFiveOrMore || isFiveOrMoreByStore,
                                          isFiveOrMoreSource: isFiveOrMoreByStore ? 'manual_store' : 'auto',
                                          daysWithFiveOrMore: standing.daysWithFiveOrMore,
                                          operatingDays: standing.operatingDays,
                                          averageWorkers: standing.average,
                                          fiveOrMoreDecisionReason: standing.isFiveOrMore
                                              ? '자동 산정: 평균 ${standing.average.toStringAsFixed(1)}명, 5인↑ ${standing.daysWithFiveOrMore}/${standing.operatingDays}일'
                                              : (isFiveOrMoreByStore ? '사장님 수동 설정 (5인 이상)' : '자동 산정: 5인 미만'),
                                        ),
                                        icon: const Icon(Icons.send_to_mobile),
                                        label: const Text(
                                          '이번 달 급여 확정 및 명세서 발송',
                                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                        ),
                                        style: FilledButton.styleFrom(
                                          backgroundColor: const Color(0xFF1565C0),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                        ),
                                      ),
                                    ),
                                  const SizedBox(height: 48),
                                  const Center(
                                    child: Text(
                                      '※ 본 계산은 입력된 출퇴근 데이터를 근거로 산출된 법적 참고용이며,\n최종 법적 판단은 노무사 등 전문가의 확인이 필요합니다.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(fontSize: 10, color: Colors.black54, height: 1.5),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildTotalInfoCard(double totalCost) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Colors.blue, Colors.blueAccent]),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('이번 달 총 예상 인건비', style: TextStyle(color: Colors.white70, fontSize: 16)),
          const SizedBox(height: 8),
          Text(
            '${totalCost.toInt().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}원',
            style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildPeriodNavigator(({DateTime start, DateTime end}) period) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: () => setState(() => _monthOffset--),
            icon: const Icon(Icons.chevron_left, color: Colors.black87),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
          ),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '${period.start.year}.${period.start.month.toString().padLeft(2, '0')}.${period.start.day.toString().padLeft(2, '0')} '
                '~ ${period.end.year}.${period.end.month.toString().padLeft(2, '0')}.${period.end.day.toString().padLeft(2, '0')}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.black87),
              ),
            ),
          ),
          IconButton(
            onPressed: () => setState(() => _monthOffset++),
            icon: const Icon(Icons.chevron_right, color: Colors.black87),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }

  Future<void> _finalizeIsFiveOrMoreBeforePayroll({
    required BuildContext context,
    required String storeId,
    required List<Attendance> periodAttendance,
    required DateTime periodStart,
    required DateTime periodEnd,
  }) async {
    final Map<String, List<int>> virtualStaffSchedules = {};
    for (final s in WorkerService.getAll()) {
      if (s.name.contains('가상')) {
        virtualStaffSchedules[s.id] = s.workDays;
      }
    }

    final finalIsFiveOrMore = PayrollCalculator.isFiveOrMore(
      settlementAttendances: periodAttendance,
      periodStart: periodStart,
      periodEnd: periodEnd,
      virtualStaffSchedules: virtualStaffSchedules,
    );

    await FirebaseFirestore.instance
        .collection('stores')
        .doc(storeId)
        .set({'isFiveOrMore': finalIsFiveOrMore}, SetOptions(merge: true));

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          finalIsFiveOrMore
              ? '최종 판정 완료: 상시근로자 5인 이상으로 최신화했습니다.'
              : '최종 판정 완료: 상시근로자 5인 미만으로 최신화했습니다.',
        ),
      ),
    );
  }

  Widget _buildExceptionAlert(
      BuildContext context, int weeklyExceptionCount, int breakSeparationRiskCount) {
    final hasException = weeklyExceptionCount > 0 || breakSeparationRiskCount > 0;
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const ExceptionApprovalScreen()),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: hasException ? Colors.orange.shade50 : Colors.blue.shade50,
          border: Border.all(
            color: hasException ? Colors.orange.shade200 : Colors.blue.shade200,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              hasException ? Icons.warning_amber_rounded : Icons.info_outline,
              color: hasException ? Colors.orange : Colors.blue,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                hasException
                    ? (breakSeparationRiskCount > 0
                        ? '휴게시간의 실질적 분리(지휘감독 배제) 여부를 점검하십시오.'
                        : '주휴수당 예외 검토가 필요한 주가 $weeklyExceptionCount건 있습니다.')
                    : '주휴수당(만근) 미발생 예외는 현재 없습니다.',
                style: TextStyle(
                  color: hasException
                      ? Colors.orange.shade800
                      : Colors.blue.shade800,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: hasException ? Colors.orange : Colors.blue,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStandingCard(
    BuildContext context, {
    required StandingResult standing,
  }) {
    final isFive = standing.isFiveOrMore;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isFive ? Colors.orange.shade50 : Colors.green.shade50,
        border: Border.all(
          color: isFive ? Colors.orange.shade200 : Colors.green.shade200,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isFive ? Icons.warning_amber_rounded : Icons.check_circle,
                color: isFive ? Colors.orange.shade700 : Colors.green.shade700,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isFive ? '법적 상태: 5인 이상' : '법적 상태: 5인 이하',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isFive ? Colors.orange.shade800 : Colors.green.shade800,
                  ),
                ),
              ),
              IconButton(
                tooltip: '기준 안내',
                onPressed: () => _showLegalGuideDialog(context),
                icon: Icon(
                  Icons.help_outline_rounded,
                  color:
                      isFive ? Colors.orange.shade800 : Colors.green.shade800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text('평균(연인원/기간일): ${standing.average.toStringAsFixed(2)}명'),
          Text('기간일수: ${standing.totalDays}일 · 5인 이상 출근일: ${standing.daysWithFiveOrMore}일'),
          if (isFive) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 16, color: Colors.orange.shade900),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '공공데이터 연동 업데이트 전까지는 달력의 법정공휴일(삼일절, 명절, 대체공휴일 등) 근무 가산수당을 아래의 "기타수당"을 통해 수동으로 합산해 주세요. (단, 1일 8시간 연장근무, 규칙적인 "주휴일" 및 5월 1일 "근로자의 날"은 시스템이 이미 완전 자동으로 정산해 줍니다.)',
                      style: TextStyle(fontSize: 12, color: Colors.orange.shade900, height: 1.4, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Future<void> _showLegalGuideDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('5인 이상/이하 사업장 기준 안내'),
        content: const SingleChildScrollView(
          child: Text(
            '💡 판정 공식 (상시근로자 수)\n\n'
            '산정 기간 동안 사용한 근로자의 \'연인원\' / 산정 기간 중 매장 \'영업 일수\'\n'
            '앱은 출퇴근 기록을 바탕으로 매일 자동 계산합니다.\n\n'
            '⚖️ 법적 주요 변화 (5인 이상 시 적용)\n\n'
            '가산수당 지급: 연장·야간·휴일 근로 시 시급의 1.5배 지급 의무.\n\n'
            '연차유급휴가: 조건 충족 시 연차 휴가 부여 또는 수당 지급 의무.\n\n'
            '해고 제한: 정당한 이유 없는 해고 금지 및 해고 서면 통지 의무.\n\n'
            '※ 주의: 대근이 많아져 일시적으로 평균 5인이 넘더라도 그달은 5인 이상 사업장으로 간주됩니다.\n\n'
            '🚨 [특별 조항 판정 기준]\n'
            '한 달 평균 근로자 수가 5인 미만이더라도, 예외적으로 5인 이상이 동시에 출근한 날이 한 달 영업일의 과반수(1/2) 이상을 차지하면 노동법 특별 조항에 의해 [5인 이상 사업장]으로 자동 간주됩니다.',
            style: TextStyle(height: 1.4),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  Widget _buildStaffSummaryCard(
    Worker staff,
    PayrollCalculationResult? summary,
    {required bool manualWeeklyHolidayApproved,
    required ValueChanged<bool> onManualWeeklyHolidayApprovalChanged,
    double? expectedHolidayRiskAmount,
    double minWage = 0}
  ) {
    if (summary == null) return const SizedBox();
    final sumMatches = _salarySumMatches(summary);
    final totalWithoutWeeklyHoliday = summary.totalPay - summary.weeklyHolidayPay;
    return Builder(
      builder: (context) {
        bool localApproved = manualWeeklyHolidayApproved;
        
        return StatefulBuilder(
          builder: (context, setStateLocal) {
        final displayedTotal = localApproved
            ? totalWithoutWeeklyHoliday + summary.weeklyHolidayPay
            : totalWithoutWeeklyHoliday;
            
        return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(child: Text(staff.name[0])),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(staff.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Text(
                        '시급: ${staff.hourlyWage.toStringAsFixed(0)}원',
                        style: const TextStyle(color: Colors.black54, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${displayedTotal.toInt().toString().replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (Match m) => "${m[1]},")}원',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.blue),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0),
              child: Divider(height: 1, color: Colors.black12),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Builder(
                  builder: (context) {
                    String _fH(double h) => PayrollCalculator.formatHoursAsKorean(h);
                    String _fW(num amt) => amt.toInt().toString().replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (m) => "${m[1]},");
                    final hw = staff.hourlyWage;

                    bool hasProbation = staff.isProbation && staff.probationMonths > 0;
                    double effectiveHrly = hw;
                    String rateText = '${_fW(hw)}원';
                    if (hasProbation && summary.pureLaborHours > 0 && summary.basePay < summary.pureLaborHours * hw) {
                      effectiveHrly = (summary.basePay / summary.pureLaborHours).roundToDouble();
                      rateText = '${_fW(effectiveHrly)}원 (수습적용)';
                    }
                    final wHours = effectiveHrly > 0 ? summary.weeklyHolidayPay / effectiveHrly : 0.0;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text('순수근로 ${_fH(summary.pureLaborHours)} / 체류 ${_fH(summary.stayHours)}',
                              style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        ),
                        if (hasProbation && minWage > 0 && effectiveHrly < minWage)
                          Container(
                            margin: const EdgeInsets.only(bottom: 8, top: 4),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              border: Border.all(color: Colors.red.shade200),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.warning_amber_rounded, color: Colors.red, size: 16),
                                SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    '최저임금 미달 경고: 수습 90% 시급이 법정 최저임금을 하회합니다.',
                                    style: TextStyle(color: Colors.red, fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        Builder(builder: (context) {
                          final expectedBasePay = (summary.pureLaborHours * effectiveHrly).roundToDouble();
                          final isProratedBase = (summary.basePay - expectedBasePay).abs() > 10;
                          if (isProratedBase && summary.basePayBreakdownByWage.isNotEmpty) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '기본급: ${_fH(summary.pureLaborHours)}시간 (일자별 변경 시급 적용) = ${_fW(summary.basePay)}원',
                                  style: const TextStyle(fontSize: 12, color: Colors.black87),
                                ),
                                ...summary.basePayBreakdownByWage.entries.map((e) {
                                  final rate = e.key;
                                  final hours = e.value;
                                  final subAmount = rate * hours;
                                  return Padding(
                                    padding: const EdgeInsets.only(left: 8.0, top: 2.0),
                                    child: Text(
                                      '↳ ${_fH(hours)}시간 × ${_fW(rate)}원 = ${_fW(subAmount)}원',
                                      style: const TextStyle(fontSize: 11, color: Colors.blueGrey),
                                    ),
                                  );
                                }),
                              ],
                            );
                          }
                          return Text(
                            '기본급: ${_fH(summary.pureLaborHours)} × $rateText = ${_fW(summary.basePay)}원',
                            style: const TextStyle(fontSize: 12, color: Colors.black87),
                          );
                        }),
                        if (summary.breakPay > 0)
                          Builder(builder: (context) {
                            final expectedBreakPay = (summary.paidBreakHours * effectiveHrly).roundToDouble();
                            final isProratedBreak = (summary.breakPay - expectedBreakPay).abs() > 10;
                            if (isProratedBreak) {
                              return Text(
                                '유급휴게수당: ${_fH(summary.paidBreakHours)}시간 (일자별 변경 시급 적용) = ${_fW(summary.breakPay)}원',
                                style: const TextStyle(fontSize: 12, color: Colors.black87),
                              );
                            }
                            return Text(
                              '유급휴게수당: ${_fH(summary.paidBreakHours)} × $rateText = ${_fW(summary.breakPay)}원 (휴게로 인정해 준 총시간 명시)',
                              style: const TextStyle(fontSize: 12, color: Colors.black87),
                            );
                          }),
                        if (summary.otherAllowancePay > 0)
                          Text(
                            '기타수당: ${_fW(summary.otherAllowancePay)}원',
                            style: const TextStyle(fontSize: 12, color: Colors.black87),
                          ),
                        if (summary.premiumPay > 0)
                          Text(
                            '연장/야간 가산수당: ${_fH(summary.premiumHours)} × ${_fW(effectiveHrly * 0.5)}원 = ${_fW(summary.premiumPay)}원',
                            style: const TextStyle(fontSize: 12, color: Colors.indigo),
                          ),
                        if (summary.holidayPremiumPay > 0)
                          Text(
                            '근로자의 날 휴일근로가산: +${_fW(summary.holidayPremiumPay)}원',
                            style: const TextStyle(fontSize: 12, color: Colors.indigo),
                          ),
                        if (summary.laborDayAllowancePay > 0)
                          Builder(
                            builder: (context) {
                              final allowanceHours = effectiveHrly > 0 ? summary.laborDayAllowancePay / effectiveHrly : 0.0;
                              final calcHours = allowanceHours * 5.0;
                              return Text(
                                '근로자의 날 유급휴일수당: (${_fH(calcHours)} / 40시간) × 8시간 × $rateText = +${_fW(summary.laborDayAllowancePay)}원',
                                style: const TextStyle(fontSize: 12, color: Colors.blueAccent),
                              );
                            },
                          ),
                        if (summary.isWeeklyHolidayEligible)
                          Text(
                            localApproved
                                ? '주휴수당(승인반영): ${_fH(wHours)} × $rateText = ${_fW(summary.weeklyHolidayPay)}원 (주휴 발생 기준이 되는 시간 명시)'
                                : '주휴수당: 승인 필요(현재 합계 미포함)',
                            style: const TextStyle(fontSize: 12, color: Colors.black87),
                          )
                        else
                          const Text('주휴수당: 미대상', style: TextStyle(fontSize: 12, color: Colors.black87)),
                      ],
                    );
                  },
                ),
                if (summary.annualLeaveAllowancePay > 0)
                  Text(
                    '퇴사 연차정산 수당: +${summary.annualLeaveAllowancePay.toInt().toString().replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (Match m) => "${m[1]},")}원',
                    style: const TextStyle(fontSize: 12, color: Colors.redAccent, fontWeight: FontWeight.bold),
                  ),
                const SizedBox(height: 4),
                _buildAnnualLeaveChip(summary),
                if (!sumMatches)
                  const Text(
                    '합계 검증 경고: 항목 합과 총액이 일치하지 않습니다.',
                    style: TextStyle(fontSize: 11, color: Colors.redAccent),
                  ),
                Text(
                  '이번 달 신규 연차: ${summary.newlyGrantedAnnualLeave}개',
                  style: const TextStyle(fontSize: 12, color: Colors.teal),
                ),
                if (staff.weeklyHours < 15)
                  const Text(
                    '만근이어도 주 15시간 미만이면 주휴수당 미발생',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                if (expectedHolidayRiskAmount != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: localApproved
                          ? Colors.yellow[200]
                          : Colors.yellow[100],
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                '⚠️ 주휴수당 발생 리스크 안내',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Row(
                              children: [
                                Switch(
                                  value: localApproved,
                                  onChanged: (v) {
                                    setStateLocal(() {
                                      localApproved = v;
                                    });
                                    onManualWeeklyHolidayApprovalChanged(v);
                                  },
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                const Text(
                                  '지급 승인',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        if (localApproved)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 4),
                            child: Text(
                              '지급 예정 합계에 포함됨',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.teal,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        const SizedBox(height: 4),
                        Text(
                          '이번 주 실근로가 15시간을 초과했습니다. 주휴수당 발생 대상일 수 있습니다. '
                          '(예상액: ${expectedHolidayRiskAmount.toInt().toString().replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (Match m) => "${m[1]},")}원)',
                          style: const TextStyle(fontSize: 11, height: 1.35),
                        ),
                        if (summary.weeklyHolidayBlockedByAbsence)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              localApproved 
                                  ? '⚠️ 결근 발생 (주휴수당 공제 가능)' 
                                  : '⚠️ 결근으로 주휴수당이 공제되었습니다',
                              style: TextStyle(
                                fontSize: 11,
                                color: localApproved ? Colors.red.shade600 : Colors.redAccent,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        const SizedBox(height: 6),
                        const Text(
                          '※ 위 금액은 실근로 기준 법적 참고용이며, 최종 지급 여부는 사장님이 결정합니다.',
                          style: TextStyle(fontSize: 10, color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
          },
        );
      }
    );
  }

  Widget _buildAnnualLeaveChip(PayrollCalculationResult summary) {
    final sl = summary.annualLeaveSummary;
    final blocked = sl.blockedAnnualRateDetail;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.teal.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.teal.shade100),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.calendar_today_outlined, size: 12, color: Colors.teal.shade700),
                  const SizedBox(width: 4),
                  Text(
                    '누적 확정 잔여: ${sl.remaining.toStringAsFixed(1)}개',
                    style: TextStyle(fontSize: 13, color: Colors.teal.shade900, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '수식: (${(sl.totalGenerated - sl.manualAdjustment).toStringAsFixed(1)}[시스템] ${sl.manualAdjustment >= 0 ? '+' : ''}${sl.manualAdjustment.toStringAsFixed(1)}[조정]) - ${sl.used.toStringAsFixed(1)}[사용]',
                style: TextStyle(fontSize: 10, color: Colors.teal.shade700),
              ),
            ],
          ),
        ),
        if (blocked != null && !blocked.passed)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '[출근율 부족] ${blocked.workedDays}일/${blocked.expectedDays}일 (${(blocked.rate * 100).toStringAsFixed(0)}%)로 연차 미발생',
              style: const TextStyle(fontSize: 10, color: Colors.redAccent, fontWeight: FontWeight.w500),
            ),
          ),
      ],
    );
  }

  bool _salarySumMatches(PayrollCalculationResult summary) {
    final sum = summary.basePay +
        summary.breakPay +
        summary.premiumPay +
        summary.holidayPremiumPay +
        summary.laborDayAllowancePay +
        summary.weeklyHolidayPay +
        summary.otherAllowancePay;
    return (sum - summary.totalPay).abs() < 0.5;
  }

  ({DateTime start, DateTime end}) _currentWeekRange(DateTime now) {
    final start = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - DateTime.monday));
    final end = start.add(const Duration(days: 6));
    return (start: start, end: end);
  }

  double _pureHoursForRisk(List<Attendance> attendance, {required int defaultBreakMinutes}) {
    int pureMinutes = 0;
    for (final a in attendance) {
      if (a.clockOut == null) continue;
      final stay = a.clockOut!.difference(a.clockIn).inMinutes;
      if (stay <= 0) continue;
      int breakMinutes = defaultBreakMinutes;
      if (a.breakStart != null && a.breakEnd != null) {
        final v = a.breakEnd!.difference(a.breakStart!).inMinutes;
        breakMinutes = v > 0 ? v : 0;
      }
      pureMinutes += (stay - breakMinutes).clamp(0, stay);
    }
    return pureMinutes / 60.0;
  }

  DateTime _dayKey(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  double _effectiveHourlyWage(
    Worker worker,
    DateTime at, {
    double? minimumHourlyWage,
  }) {
    double wage = worker.hourlyWage;
    if (minimumHourlyWage != null && minimumHourlyWage > 0 && wage < minimumHourlyWage) {
      return minimumHourlyWage;
    }
    return wage;
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
    // 오늘 날짜를 포함하는 "현재 정산 구간"을 계산한다.
    // day-of-month만 저장된 설정값을 연/월 경계(연말/연초 포함)에 맞춰 보정한다.
    final currentMonth = DateTime(now.year, now.month, 1);
    final previousMonth = DateTime(now.year, now.month - 1, 1);

    if (settlementStartDay <= settlementEndDay) {
      final useMonth = (now.day >= settlementStartDay && now.day <= settlementEndDay)
          ? currentMonth
          : previousMonth;
      final start = DateTime(
        useMonth.year,
        useMonth.month,
        _safeDayInMonth(useMonth.year, useMonth.month, settlementStartDay),
      );
      final end = DateTime(
        useMonth.year,
        useMonth.month,
        _safeDayInMonth(useMonth.year, useMonth.month, settlementEndDay),
      );
      return (start: start, end: end);
    }

    // e.g. 16~15 형태: 시작 월과 종료 월이 다르다.
    final startMonth = (now.day >= settlementStartDay) ? currentMonth : previousMonth;
    final endMonth = DateTime(startMonth.year, startMonth.month + 1, 1);
    final start = DateTime(
      startMonth.year,
      startMonth.month,
      _safeDayInMonth(startMonth.year, startMonth.month, settlementStartDay),
    );
    final end = DateTime(
      endMonth.year,
      endMonth.month,
      _safeDayInMonth(endMonth.year, endMonth.month, settlementEndDay),
    );
    return (start: start, end: end);
  }

  StandingResult _calculateStandingFromAttendances(
    List<Attendance> attendances,
    DateTime periodStart,
    DateTime periodEnd,
    List<Worker> staffList,
  ) {
    final totalDays = periodEnd.difference(periodStart).inDays + 1;
    final dailyStaff = <DateTime, Set<String>>{};

    // 1. 실제 출퇴근 기록 반영
    for (final att in attendances) {
      final day = _dayKey(att.clockIn);
      if (!day.isBefore(periodStart) && !day.isAfter(periodEnd)) {
        dailyStaff.putIfAbsent(day, () => <String>{}).add(att.staffId);
      }

      if (att.clockOut != null) {
        final outDay = _dayKey(att.clockOut!);
        if (!outDay.isBefore(periodStart) && !outDay.isAfter(periodEnd)) {
          dailyStaff.putIfAbsent(outDay, () => <String>{}).add(att.staffId);
        }
      }
    }

    // 2. 가상직원 시뮬레이션 반영 (테스트 편의용)
    for (int i = 0; i < totalDays; i++) {
        final day = DateTime(periodStart.year, periodStart.month, periodStart.day + i);
        final weekday = day.weekday % 7; // 0=Sun, ..., 6=Sat

        for (final staff in staffList) {
            if (staff.name.contains('가상')) {
                if (staff.workDays.contains(weekday)) {
                    dailyStaff.putIfAbsent(day, () => <String>{}).add(staff.id);
                }
            }
        }
    }

    int totalPersonDays = 0;
    int daysWithFiveOrMore = 0;
    int operatingDays = 0; // New: days with at least one person

    for (int i = 0; i < totalDays; i++) {
        final day = DateTime(periodStart.year, periodStart.month, periodStart.day + i);
        final count = dailyStaff[day]?.length ?? 0;
        if (count > 0) {
            operatingDays++;
            totalPersonDays += count;
            if (count >= 5) daysWithFiveOrMore++;
        }
    }

    final average = operatingDays == 0 ? 0.0 : (totalPersonDays / operatingDays);
    final halfDays = operatingDays / 2.0;
    bool isFiveOrMore;
    String reason;
    if (average >= 5.0) {
      if (daysWithFiveOrMore < halfDays) {
        isFiveOrMore = false;
        reason = '평균 5인 이상이나 5인 이상 출근일이 영업일의 1/2 미만이어서 5인 미만으로 판정';
      } else {
        isFiveOrMore = true;
        reason = '평균 5인 이상이며 5인 이상 출근일이 영업일의 1/2 이상이어서 5인 이상으로 판정';
      }
    } else {
      if (daysWithFiveOrMore >= halfDays) {
        isFiveOrMore = true;
        reason = '평균 5인 미만이나 5인 이상 출근일이 영업일의 1/2 이상이어서 5인 이상으로 판정';
      } else {
        isFiveOrMore = false;
        reason = '평균 5인 미만이고 5인 이상 출근일이 영업일의 1/2 미만이어서 5인 미만으로 판정';
      }
    }

    return StandingResult(
      average: average,
      totalPersonDays: totalPersonDays,
      totalDays: totalDays,
      operatingDays: operatingDays,
      daysWithFiveOrMore: daysWithFiveOrMore,
      isFiveOrMore: isFiveOrMore,
      fiveOrMoreDecisionReason: reason,
    );
  }

  Widget _buildOnboardingGuide(BuildContext context, String storeId) {
    return Container(
      color: const Color(0xFFF2F2F7),
      width: double.infinity,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
        child: Column(
          children: [
            Icon(Icons.storefront, size: 80, color: Colors.blue.shade300),
            const SizedBox(height: 24),
            const Text(
              '우리 매장 세팅을 시작해볼까요?',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '가장 완벽한 노무관리의 시작!\n아래 순서대로 첫 직원을 등록해 보세요.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 48),
            _buildStepRow(
              number: '1',
              title: '직원 등록',
              desc: '시급, 근무시간 등 기본 정보를 입력합니다.',
            ),
            _buildStepRow(
              number: '2',
              title: '초대 코드 발송',
              desc: '알바생에게 접속 코드를 카톡으로 전송합니다.',
            ),
            _buildStepRow(
              number: '3',
              title: '노무서류 자동 작성',
              desc: '근로계약서, 임금명세서 등 필수 문서를 생성합니다.',
            ),
            _buildStepRow(
              number: '4',
              title: '서류 교부 및 확인',
              desc: '알바생이 앱에서 서명하면 출근 준비 끝!',
            ),
            const SizedBox(height: 48),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const AddStaffScreen(),
                    ),
                  );
                },
                icon: const Icon(Icons.person_add),
                label: const Text(
                  '첫 직원 등록하러 가기',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1565C0),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepRow({required String number, required String title, required String desc}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: const BoxDecoration(
              color: Color(0xFF1565C0),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              number,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(desc, style: const TextStyle(fontSize: 13, color: Colors.black54)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<LeavePromotionStatus> _parsePromotionLogs(String json) {
    if (json.isEmpty) return [];
    try {
      final List<dynamic> list = (jsonDecode(json) as List?) ?? [];
      return list.map((e) => LeavePromotionStatus.fromMap((e as Map).cast<String, dynamic>())).toList();
    } catch (_) {
      return [];
    }
  }
}

class StandingResult {
  final double average;
  final int totalPersonDays;
  final int totalDays;
  final int operatingDays;
  final int daysWithFiveOrMore;
  final bool isFiveOrMore;
  final String fiveOrMoreDecisionReason;

  const StandingResult({
    required this.average,
    required this.totalPersonDays,
    required this.totalDays,
    required this.operatingDays,
    required this.daysWithFiveOrMore,
    required this.isFiveOrMore,
    required this.fiveOrMoreDecisionReason,
  });
}

extension ColorSharp on Color {
  Color get sharp800 => Colors.orange.shade800; 
}
