import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_logic/shared_logic.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../models/worker.dart';
import '../services/excel_export_service.dart';
import '../widgets/store_id_gate.dart';
import '../widgets/wage_edit_dialog.dart';
import '../widgets/attendance_edit_dialog.dart';
import 'payroll/payroll_dashboard_screen.dart';

class PayrollReportPage extends StatefulWidget {
  final int pageIndex;
  const PayrollReportPage({super.key, required this.pageIndex});

  @override
  State<PayrollReportPage> createState() => _PayrollReportPageState();
}

class _PayrollReportPageState extends State<PayrollReportPage> {
  final Map<String, bool> _manualWeeklyHolidayApproval = <String, bool>{};

  int _monthOffset = 0;
  bool _isInitialized = false;

  DateTime _getEffectiveBaseDate(DateTime now, int offset, int payday, int endDay) {
    int baseShift = (now.day >= payday) ? 1 : 0;
    int targetMonth = now.month + baseShift + offset;
    
    DateTime targetPaydayDate = DateTime(now.year, targetMonth, payday);
    
    DateTime candidateEnd = DateTime(
      targetPaydayDate.year,
      targetPaydayDate.month,
      _safeDayInMonth(targetPaydayDate.year, targetPaydayDate.month, endDay)
    );
    
    if (candidateEnd.isAfter(targetPaydayDate)) {
      final prevMonth = DateTime(targetPaydayDate.year, targetPaydayDate.month - 1, 1);
      candidateEnd = DateTime(
        prevMonth.year,
        prevMonth.month,
        _safeDayInMonth(prevMonth.year, prevMonth.month, endDay)
      );
    }
    
    return candidateEnd;
  }

  Widget _buildPeriodNavigator(({DateTime start, DateTime end}) period) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: () => setState(() => _monthOffset--),
            icon: const Icon(Icons.chevron_left, color: Colors.white),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
          ),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '${period.start.year}.${period.start.month.toString().padLeft(2, '0')}.${period.start.day.toString().padLeft(2, '0')} '
                '~ ${period.end.year}.${period.end.month.toString().padLeft(2, '0')}.${period.end.day.toString().padLeft(2, '0')}',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
          ),
          IconButton(
            onPressed: () => setState(() => _monthOffset++),
            icon: const Icon(Icons.chevron_right, color: Colors.white),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }

  Widget _pageDot({required bool active}) {
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        color: active ? Colors.white : Colors.white.withValues(alpha: 0.3),
        shape: BoxShape.circle,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StoreIdGate(
      builder: (context, storeId) {
        final storesRef = FirebaseFirestore.instance.collection('stores').doc(storeId);

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: storesRef.snapshots(),
          builder: (context, storeSnapshot) {
            final storeData = storeSnapshot.data?.data();
            final isFiveOrMoreByStore = (storeData?['isFiveOrMore'] as bool?) ?? false;

            if (storeSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                backgroundColor: Color(0xFFF2F2F7),
                body: Center(child: CircularProgressIndicator()),
              );
            }

            return ValueListenableBuilder<Box<Worker>>(
              valueListenable: Hive.box<Worker>('workers').listenable(),
              builder: (context, box, _) {
                // 1. 재직자 + 해당 정산 기간 내 퇴사자 목록 추출
                final now = AppClock.now();
                final storeData = storeSnapshot.data?.data();
                final settlementStartDay = (storeData?['settlementStartDay'] as num?)?.toInt() ?? 1;
                final settlementEndDay = (storeData?['settlementEndDay'] as num?)?.toInt() ?? 31;
                
                if (!_isInitialized) {
                  _isInitialized = true;
                }
                
                final payday = (storeData?['payday'] as num?)?.toInt() ?? 1;
                final baseDate = _getEffectiveBaseDate(now, _monthOffset, payday, settlementEndDay);
                final period = _computeSettlementPeriod(baseDate, settlementStartDay, settlementEndDay);

                final staffList = Hive.box<Worker>('workers').values.where((w) {
                  if (w.workerType == 'dispatch') return false;
                  if (w.status == 'active') return true;
                  if (w.status == 'inactive' && w.endDate != null && w.endDate!.isNotEmpty) {
                    final exitDate = DateTime.tryParse(w.endDate!);
                    // 퇴사일이 현재 정산 기간 시작일 이후라면 리포트에 노출
                    if (exitDate != null && exitDate.isAfter(period.start.subtract(const Duration(days: 1)))) {
                      return true;
                    }
                  }
                  return false;
                }).toList()..sort((a, b) => a.name.compareTo(b.name));

                return StreamBuilder<List<Attendance>>(
                  stream: DatabaseService().streamAttendance(storeId),
                  builder: (context, attSnapshot) {
                    final allAttendance = attSnapshot.data ?? [];
                    
                    // 2. 검색 범위를 퇴사자 고려하여 넉넉하게 확장 (정산 마감일 이후 퇴사자분 포함)
                    final periodAttendance = allAttendance.where((att) {
                      final inDay = _dayKey(att.clockIn);
                      final outDay = att.clockOut != null ? _dayKey(att.clockOut!) : null;
                      
                      // 시작일은 고정, 종료일은 현재 시점까지 넉넉히 (퇴사자분 확보)
                      final inOk = !inDay.isBefore(period.start) && !inDay.isAfter(period.end.add(const Duration(days: 31)));
                      final outOk = outDay != null ? (!outDay.isBefore(period.start) && !outDay.isAfter(period.end.add(const Duration(days: 31)))) : false;
                      return inOk || outOk;
                    }).toList();

                    double totalLaborCost = 0;
                    final staffSummaries = <String, PayrollCalculationResult>{};
                    final staffTardyCount = <String, int>{};
                    final staffAttendanceMap = <String, List<Attendance>>{};
                    final staffWorkerDataMap = <String, PayrollWorkerData>{};
                    final staffAllHistoryMap = <String, List<Attendance>>{};
                    final staffEffectiveWageMap = <String, double>{};

                    for (final staff in staffList) {
                      final staffAttendance = periodAttendance.where((a) => a.staffId == staff.id).toList();
                      staffAttendanceMap[staff.id] = staffAttendance;
                      int tardy = 0;
                      final gracePeriod = (storeData?['attendanceGracePeriodMinutes'] as num?)?.toInt() ?? 0;
                      
                      for (final a in staffAttendance) {
                        final inHm = '${a.clockIn.hour.toString().padLeft(2,'0')}:${a.clockIn.minute.toString().padLeft(2,'0')}';
                        final sInHm = staff.checkInTime.substring(0, 5);
                        final im = _mins(inHm);
                        final sm = _mins(sInHm);
                        if (im > sm + gracePeriod) tardy++;
                      }
                      staffTardyCount[staff.id] = tardy;

                      final effectiveWage = _effectiveHourlyWage(
                        staff,
                        now,
                        minimumHourlyWage: (storeData?['minimumHourlyWage'] as num?)?.toDouble(),
                      );
                      final approved = _manualWeeklyHolidayApproval[staff.id] ?? staff.weeklyHolidayPay;

                      final staffAllHistory = allAttendance.where((a) => a.staffId == staff.id).toList();
                      
                      // 식비/식대 항목 추출 (비과세 적용용)
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
                        joinDate: DateTime.tryParse(staff.joinDate.isNotEmpty ? staff.joinDate : staff.startDate) ?? AppClock.now(),
                        scheduledWorkDays: staff.workDays,
                        manualWeeklyHolidayApproval: approved,
                        allowanceAmounts: staff.allowances.map((a) => a.amount).toList(),
                        usedAnnualLeave: staff.usedAnnualLeave,
                        manualAdjustment: staff.annualLeaveManualAdjustment,
                        endDate: staff.endDate != null && staff.endDate!.isNotEmpty ? DateTime.tryParse(staff.endDate!) : null,
                        previousMonthAdjustment: staff.previousMonthAdjustment,
                        mealAllowance: mealAllowance,
                        applyWithholding33: staff.applyWithholding33,
                        deductNationalPension: staff.deductNationalPension,
                        deductHealthInsurance: staff.deductHealthInsurance,
                        deductEmploymentInsurance: staff.deductEmploymentInsurance,
                        isVirtual: staff.name.contains('가상'),
                        breakStartTime: staff.breakStartTime,
                        breakEndTime: staff.breakEndTime,
                        graceMinutes: (storeData?['attendanceGracePeriodMinutes'] as num?)?.toInt() ?? 0,
                        wageType: staff.wageType,
                        monthlyWage: staff.monthlyWage,
                        fixedOvertimeHours: staff.fixedOvertimeHours,
                        fixedOvertimePay: staff.fixedOvertimePay,
                        mealTaxExempt: staff.mealTaxExempt,
                        isProbation: staff.isProbation,
                        probationMonths: staff.probationMonths,
                        wageHistoryJson: staff.wageHistoryJson,
                        weeklyHolidayDay: staff.weeklyHolidayDay,
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
                        isFiveOrMore: isFiveOrMoreByStore,
                        allHistoricalAttendances: staffAllHistory,
                      );

                      staffSummaries[staff.id] = result;
                      staffWorkerDataMap[staff.id] = workerData;
                      staffAllHistoryMap[staff.id] = staffAllHistory;
                      staffEffectiveWageMap[staff.id] = effectiveWage;
                      
                      totalLaborCost += result.netPay;
                    }

                    return Scaffold(
                      backgroundColor: const Color(0xFFF2F2F7),
                      appBar: AppBar(
                        backgroundColor: const Color(0xFF1a1a2e),
                        title: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('실시간 리포트', style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.6))),
                            const Text('급여 현황', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w500)),
                          ],
                        ),
                        actions: [
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                            child: TextButton.icon(
                              style: TextButton.styleFrom(
                                backgroundColor: Colors.white.withValues(alpha: 0.1),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              icon: const Icon(Icons.analytics_outlined, size: 16),
                              label: const Text('급여 리포트', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => const PayrollDashboardScreen()),
                                );
                              },
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10).copyWith(right: 12, left: 4),
                            child: TextButton.icon(
                              style: TextButton.styleFrom(
                                backgroundColor: Colors.green.withValues(alpha: 0.2),
                                foregroundColor: Colors.greenAccent,
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              icon: const Icon(Icons.table_view_outlined, size: 16),
                              label: const Text('엑셀 추출', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              onPressed: () async {
                                final List<({Worker worker, PayrollCalculationResult result})> excelData = [];
                                for (final staff in staffList) {
                                  final summary = staffSummaries[staff.id];
                                  if (summary != null) {
                                    excelData.add((worker: staff, result: summary));
                                  }
                                }
                                await ExcelExportService.exportPayroll(
                                  payrollData: excelData,
                                  storeName: storeData?['name']?.toString() ?? '알바매니저',
                                  periodStart: period.start,
                                  periodEnd: period.end,
                                );
                              },
                            ),
                          ),
                        ],
                        bottom: PreferredSize(
                          preferredSize: const Size.fromHeight(22),
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _pageDot(active: widget.pageIndex == 0),
                                const SizedBox(width: 4),
                                _pageDot(active: widget.pageIndex == 1),
                                const SizedBox(width: 4),
                                _pageDot(active: widget.pageIndex == 2),
                              ],
                            ),
                          ),
                        ),
                      ),
                      body: SafeArea(
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 600),
                            child: Column(
                              children: [
                                Container(
                                  width: double.infinity,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF1a1a2e),
                                  ),
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _buildPeriodNavigator(period),
                                      const Text('해당 기간 총 예상 인건비', style: TextStyle(color: Colors.white70, fontSize: 14)),
                                      const SizedBox(height: 8),
                                      Text(
                                        '${totalLaborCost.toInt().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}원',
                                        style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: ListView.builder(
                                    padding: const EdgeInsets.only(top: 12, bottom: 40),
                                    itemCount: staffList.length,
                                    itemBuilder: (context, index) {
                                      final staff = staffList[index];
                                      final summary = staffSummaries[staff.id];
                                      final tardyCount = staffTardyCount[staff.id] ?? 0;
                                      final attendance = staffAttendanceMap[staff.id] ?? [];
                                      if (summary == null) return const SizedBox();

                                      final isInactive = staff.status == 'inactive';
                                      DateTime localPeriodEnd = period.end;
                                      if (isInactive && staff.endDate != null && staff.endDate!.isNotEmpty) {
                                        final exitDate = DateTime.tryParse(staff.endDate!);
                                        if (exitDate != null && exitDate.isAfter(period.end)) {
                                          localPeriodEnd = exitDate;
                                        }
                                      }

                                      final displayedTotal = summary.netPay;
                                      
                                      final workerData = staffWorkerDataMap[staff.id]!;
                                      final staffAllHistory = staffAllHistoryMap[staff.id]!;
                                      final effectiveWage = staffEffectiveWageMap[staff.id]!;
                                      
                                      final filteredAttendance = attendance
                                          .where((a) => !a.clockIn.isAfter(localPeriodEnd.add(const Duration(hours: 23, minutes: 59))))
                                          .toList();
                      final dbMinWage = (storeData?['minimumHourlyWage'] as num?)?.toDouble();
                                      final minWage = (dbMinWage != null && dbMinWage > 0) ? dbMinWage : PayrollConstants.legalMinimumWage;
                                      
                                      return Card(
                                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  elevation: 0,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: () => _showPayrollDetailModal(context, staff, summary, tardyCount, displayedTotal, filteredAttendance, period.start, localPeriodEnd, workerData, isFiveOrMoreByStore, staffAllHistory, effectiveWage, minWage),
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Row(
                                        children: [
                                          CircleAvatar(
                                            backgroundColor: const Color(0xFF1a6ebd),
                                            foregroundColor: Colors.white,
                                            child: Text(staff.name[0]),
                                          ),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Text(staff.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                                    if (isInactive)
                                                      Container(
                                                        margin: const EdgeInsets.only(left: 8),
                                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                        decoration: BoxDecoration(
                                                          color: Colors.red.shade50,
                                                          borderRadius: BorderRadius.circular(4),
                                                        ),
                                                        child: Text('퇴사(${staff.endDate})', style: TextStyle(fontSize: 10, color: Colors.red.shade700, fontWeight: FontWeight.bold)),
                                                      ),
                                                  ],
                                                ),
                                                const SizedBox(height: 4),
                                                Text(isInactive ? '최종 정산 완료' : '누적 ${summary.pureLaborHours.toStringAsFixed(1)}시간', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                                              ],
                                            ),
                                          ),
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.end,
                                            children: [
                                              Text(
                                                '${displayedTotal.toInt().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}원',
                                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1a6ebd)),
                                              ),
                                              const SizedBox(height: 4),
                                              const Text('상세보기 >', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                                  ),
                                ),
                              ],
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

  void _showPayrollDetailModal(BuildContext context, Worker staff, PayrollCalculationResult initialSummary, int tardyCount, double initialDisplayedTotal, List<Attendance> shifts, DateTime periodStart, DateTime periodEnd, PayrollWorkerData workerData, bool isFiveOrMore, List<Attendance> allHistoricalAttendances, double effectiveWage, [double minWage = 0]) {
    final sortedShifts = List<Attendance>.from(shifts)..sort((a, b) => b.clockIn.compareTo(a.clockIn));
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) {
        return DraggableScrollableSheet(
          initialChildSize: 0.65,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (_, scrollController) {
            PayrollCalculationResult summary = initialSummary;
            PayrollWorkerData currentWorkerData = workerData;
            return StatefulBuilder(
              builder: (context, setStateModal) {
                return Container(
              padding: const EdgeInsets.all(24),
              child: ListView(
                controller: scrollController,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 5,
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  Text('${staff.name} 님의 급여 상세', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  if (staff.status == 'inactive')
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('퇴사 정산 (정산 종료일: ${DateFormat('yyyy-MM-dd').format(periodEnd)})', style: const TextStyle(color: Colors.red, fontSize: 13, fontWeight: FontWeight.bold)),
                    ),
                  const SizedBox(height: 24),
                  
                  _detailRow('누적 확정 급여 (세전)', '${summary.totalPay.toInt().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}원', isBold: true),
                  
                  // 비과세 식대 항목 추가
                  if (summary.mealNonTaxable > 0)
                    _detailRow('└ 비과세 식대 (보험료 제외)', '-${summary.mealNonTaxable.toInt().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}원', color: Colors.green.shade700, fontSize: 13),

                  _detailRow(
                    '4대 보험 공제 (예상)', 
                    '-${summary.insuranceDeduction.toInt().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}원', 
                    color: Colors.grey.shade700,
                    subtext: '(과세 대상 ${summary.taxableWage.toInt().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}원의 9.4%)',
                  ),
                  
                  // 전월 정산금 입력 행
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('전월 정산금 (수동)', style: TextStyle(fontSize: 14)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${summary.previousMonthAdjustment.toInt() > 0 ? '+' : ''}${NumberFormat('#,###').format(summary.previousMonthAdjustment.toInt())}원', 
                             style: TextStyle(color: summary.previousMonthAdjustment != 0 ? Colors.blue : Colors.grey)),
                        IconButton(
                          icon: const Icon(Icons.edit_note, size: 20),
                          onPressed: () => _editAdjustment(context, staff),
                        ),
                      ],
                    ),
                  ),
                  
                  const Divider(height: 32),
                  _detailRow('최종 실지급액 (Net)', '${summary.netPay.toInt().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}원', isBold: true, color: const Color(0xFF1a6ebd), fontSize: 18),
                  const Divider(height: 30),
                  
                  _detailRow('순수 근로 시간', '${summary.pureLaborHours.toStringAsFixed(1)}시간'),
                  _detailRow(
                    '기본 시급',
                    staff.wageType == 'monthly' ? '' : '${staff.hourlyWage.toInt().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}원',
                    trailing: Row(
                      children: [
                        if (staff.wageType == 'monthly')
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1a6ebd).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('월급제', style: TextStyle(fontSize: 12, color: Color(0xFF1a6ebd), fontWeight: FontWeight.bold)),
                          ),
                        InkWell(
                          onTap: () async {
                            final changed = await showWageEditDialog(context, staff);
                            if (changed == true && mounted) {
                              // Trigger UI update
                              setState(() {});
                            }
                          },
                          child: Container(
                            margin: const EdgeInsets.only(left: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1a6ebd).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('수정', style: TextStyle(fontSize: 11, color: Color(0xFF1a6ebd), fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Builder(
                    builder: (context) {
                      String _fH(double h) => h == h.toInt() ? h.toInt().toString() : h.toStringAsFixed(1);
                      String _fW(num amt) => amt.toInt().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
                      final hw = staff.hourlyWage;
                      final wH = hw > 0 ? summary.weeklyHolidayPay / hw : 0.0;
                      // 시급 분리 표시 (임금변경합의서 반영)
                      final breakdown = summary.basePayBreakdownByWage;
                      String basePaySubtext;
                      if (breakdown.length > 1) {
                        basePaySubtext = breakdown.entries.map((e) => '${_fH(e.value)}시간 × ${_fW(e.key)}원').join(' + ');
                      } else {
                        basePaySubtext = '${_fH(summary.pureLaborHours)}시간 × ${_fW(hw)}원';
                      }
                      return Column(
                        children: [
                          _detailRow('기본급', '${_fW(summary.basePay)}원', subtext: basePaySubtext),
                          const SizedBox(height: 12),
                          if (summary.premiumPay > 0)
                            _detailRow('가산 수당 (연장/야간/휴일)', '+${_fW(summary.premiumPay)}원', color: Colors.orange.shade800, subtext: '${_fH(summary.premiumHours)}시간 × ${_fW(hw * 0.5)}원'),
                          // ── 주휴 수당 ──
                          // 토글 스위치 노출 조건:
                          //   1) 결근으로 주휴수당이 차단된 경우 (weeklyHolidayBlockedByAbsence)
                          //   2) 15시간 미만 계약자가 대타로 15시간 초과 (hasExtraWeekOver15)
                          Builder(builder: (_) {
                            final showToggle = summary.weeklyHolidayBlockedByAbsence || summary.hasExtraWeekOver15;
                            final showRow = summary.weeklyHolidayPay > 0 || showToggle;
                            if (!showRow) return const SizedBox.shrink();
                            return Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('주휴 수당', style: TextStyle(fontSize: 14, color: Colors.grey.shade800)),
                                        if (summary.weeklyHolidayPay > 0)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 4),
                                            child: Text('${_fH(wH)}시간 × ${_fW(hw)}원 (주휴 발생 기준이 되는 시간 명시)', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                                          ),
                                        if (showToggle)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 4),
                                            child: Text(
                                              summary.weeklyHolidayBlockedByAbsence
                                                  ? (currentWorkerData.manualWeeklyHolidayApproval
                                                      ? '⚠️ 결근 발생 (주휴수당 공제 가능)'
                                                      : '⚠️ 결근으로 주휴수당이 공제되었습니다')
                                                  : '⚠️ 15시간 미만 계약이지만 초과 근무가 감지되었습니다',
                                              style: TextStyle(
                                                fontSize: 11, 
                                                color: summary.weeklyHolidayBlockedByAbsence && currentWorkerData.manualWeeklyHolidayApproval 
                                                    ? Colors.red.shade600 
                                                    : Colors.orange.shade700,
                                                fontWeight: summary.weeklyHolidayBlockedByAbsence && currentWorkerData.manualWeeklyHolidayApproval
                                                    ? FontWeight.bold
                                                    : FontWeight.normal,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      Text(
                                        '+${_fW(summary.weeklyHolidayPay)}원',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: (!showToggle || currentWorkerData.manualWeeklyHolidayApproval) ? Colors.black : Colors.grey,
                                          decoration: (showToggle && !currentWorkerData.manualWeeklyHolidayApproval) ? TextDecoration.lineThrough : null,
                                        ),
                                      ),
                                      if (showToggle) ...[
                                        const SizedBox(width: 8),
                                        Switch(
                                          value: currentWorkerData.manualWeeklyHolidayApproval,
                                          activeTrackColor: Colors.blue.withValues(alpha: 0.5),
                                          activeThumbColor: Colors.blue,
                                          onChanged: (val) async {
                                            currentWorkerData.manualWeeklyHolidayApproval = val;
                                            _manualWeeklyHolidayApproval[staff.id] = val;
                                            
                                            // 즉각적 계산 엔진 호출
                                            summary = PayrollCalculator.calculate(
                                              workerData: currentWorkerData,
                                              shifts: shifts.where((a) => !a.clockIn.isAfter(periodEnd.add(const Duration(hours: 23, minutes: 59)))).toList(),
                                              periodStart: periodStart,
                                              periodEnd: periodEnd,
                                              hourlyRate: effectiveWage,
                                              isFiveOrMore: isFiveOrMore,
                                              allHistoricalAttendances: allHistoricalAttendances,
                                            );
                                            
                                            // 모달 내부 실시간 업데이트
                                            setStateModal(() {});
                                            // 백그라운드 카드 실시간 업데이트
                                            setState(() {});
                                            
                                            // 백엔드 동기화 (비동기)
                                            await DatabaseService().upsertWorker(
                                              storeId: staff.storeId,
                                              workerId: staff.id,
                                              data: {'weeklyHolidayPay': val},
                                            );
                                          },
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            );
                          }),
                          if (summary.breakPay > 0)
                            _detailRow('유급휴게수당', '+${_fW(summary.breakPay)}원', subtext: '${_fH(summary.paidBreakHours)}시간 × ${_fW(hw)}원 (휴게로 인정해 준 총시간 명시)'),
                          if (summary.otherAllowancePay > 0)
                            _detailRow('기타 수당', '+${_fW(summary.otherAllowancePay)}원'),
                        ],
                      );
                    },
                  ),

                  if (summary.annualLeaveAllowancePay > 0)
                    _detailRow('퇴사 연차정산 수당', '+${summary.annualLeaveAllowancePay.toInt().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}원', color: Colors.redAccent, isBold: true),

                  const Divider(height: 30),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('연차 저금통', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      Row(
                        children: [
                          TextButton(
                            onPressed: () => _showLeaveOverrideDialog(context, staff),
                            child: const Text('수동 조정(Override)', style: TextStyle(fontSize: 12, color: Colors.orange)),
                          ),
                          TextButton(
                            onPressed: () => _showLeaveDeductionDialog(context, staff),
                            child: const Text('사용 기록+', style: TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.teal.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.teal.shade100),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _detailRow('잔여 연차', '${summary.annualLeaveSummary.remaining.toStringAsFixed(1)}개', color: Colors.teal.shade800),
                        _detailRow('총 발생 규모', '${summary.annualLeaveSummary.totalGenerated.toStringAsFixed(1)}개'),
                        _detailRow('누적 사용량', '${summary.annualLeaveSummary.used.toStringAsFixed(1)}개'),
                        if (summary.annualLeaveSummary.blockedAnnualRateDetail != null && !summary.annualLeaveSummary.blockedAnnualRateDetail!.passed)
                           Padding(
                             padding: const EdgeInsets.only(top: 8),
                             child: Text(
                               '⚠️ 출근율 부족(${(summary.annualLeaveSummary.blockedAnnualRateDetail!.rate * 100).toStringAsFixed(0)}%)으로 1년차 연차 미발생',
                               style: const TextStyle(fontSize: 11, color: Colors.redAccent, fontWeight: FontWeight.bold),
                             ),
                           ),
                        const Divider(height: 24),
                        const Text('계산 산식 및 근거', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54)),
                        const SizedBox(height: 8),
                        ...summary.annualLeaveSummary.calculationBasis.map((b) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text('• $b', style: const TextStyle(fontSize: 11, color: Colors.black87)),
                        )),
                      ],
                    ),
                  ),

                  const Divider(height: 30),
                  const Text('근태 요약', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _statBox('이번 달 지각', '$tardyCount회', tardyCount > 0 ? Colors.redAccent : Colors.black87),
                      _statBox('만근 여부', summary.isPerfectAttendance ? '달성' : '미달성', summary.isPerfectAttendance ? Colors.green : Colors.grey),
                    ],
                  ),
                  const SizedBox(height: 30),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('일별 근무 내역', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      TextButton.icon(
                        onPressed: () => _showAddAttendanceDialog(context, staff),
                        icon: const Icon(Icons.add_circle_outline, size: 16, color: Color(0xFF1a6ebd)),
                        label: const Text('수동 추가', style: TextStyle(fontSize: 12, color: Color(0xFF1a6ebd))),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (sortedShifts.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Center(child: Text('기록된 근무 내역이 없습니다.', style: TextStyle(color: Colors.grey, fontSize: 13))),
                    )
                  else
                    ...sortedShifts.map((a) => _attendanceLogRow(a, staff, onUpdate: (updated, isDeleted) {
                      if (isDeleted) {
                        sortedShifts.removeWhere((x) => x.id == a.id);
                        allHistoricalAttendances.removeWhere((x) => x.id == a.id);
                      } else if (updated != null) {
                        final idx = sortedShifts.indexWhere((x) => x.id == a.id);
                        if (idx != -1) sortedShifts[idx] = updated;
                        final idxAll = allHistoricalAttendances.indexWhere((x) => x.id == a.id);
                        if (idxAll != -1) {
                          allHistoricalAttendances[idxAll] = updated;
                        } else {
                          allHistoricalAttendances.add(updated);
                        }
                        sortedShifts.sort((a, b) => b.clockIn.compareTo(a.clockIn));
                      }
                      
                      try {
                        summary = PayrollCalculator.calculate(
                          workerData: currentWorkerData,
                          shifts: sortedShifts,
                          periodStart: periodStart,
                          periodEnd: periodEnd,
                          hourlyRate: effectiveWage,
                          isFiveOrMore: isFiveOrMore,
                          allHistoricalAttendances: allHistoricalAttendances,
                        );
                      } catch (_) {}
                      setStateModal(() {});
                    })),
                  
                  const Divider(height: 40),
                  const Center(
                    child: Text(
                      '본 계산은 입력된 출퇴근 데이터를 근거로 산출되었으며,\n최종 법적 판단은 노무사 등 전문가의 확인이 필요합니다.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 10, color: Colors.grey, height: 1.5),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: () => _sendWageStatement(context, staff, summary, periodEnd),
                      icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                      label: const Text('명세서 최종 확인 및 알림톡 발송', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1A1A2E),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            );
              },
            );
          },
        );
      },
    );
  }

  Widget _attendanceLogRow(Attendance a, Worker staff, {Function(Attendance? updated, bool isDeleted)? onUpdate}) {
    final dateStr = '${a.clockIn.month}/${a.clockIn.day}';
    final weekday = ['일', '월', '화', '수', '목', '금', '토'][a.clockIn.weekday % 7];
    
    final inTime = _formatTime(a.clockIn);
    final outTime = a.clockOut != null ? _formatTime(a.clockOut!) : '진행중';
    
    int pureMinutes = a.workedMinutes;
    if (a.clockOut != null && pureMinutes > 0) {
      int breakMins = PayrollCalculator.calculateAppliedBreak(
        att: a,
        effectiveIn: a.clockIn,
        effectiveOut: a.clockOut!,
        fallbackMinutes: staff.breakMinutes.toInt(),
        breakStartTimeStr: staff.breakStartTime,
        breakEndTimeStr: staff.breakEndTime,
      );
      pureMinutes = a.clockOut!.difference(a.clockIn).inMinutes - breakMins;
      if (pureMinutes < 0) pureMinutes = 0;
    }
    
    final hours = (pureMinutes / 60.0).toStringAsFixed(1);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 44,
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Text(dateStr, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                Text(weekday, style: const TextStyle(fontSize: 9, color: Colors.grey)),
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
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
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
                if (a.voluntaryWaiverNote != null)
                  Text(a.voluntaryWaiverNote!, style: const TextStyle(fontSize: 10, color: Colors.blueGrey)),
              ],
            ),
          ),
          InkWell(
            onTap: () async {
              final result = await showAttendanceEditDialog(context, a);
              if (mounted) {
                if (result == 'deleted') {
                  if (onUpdate != null) onUpdate(null, true);
                  setState(() {});
                } else if (result is Attendance) {
                  if (onUpdate != null) onUpdate(result, false);
                  setState(() {});
                }
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(6)),
              child: const Text('수정', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$hours시간',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1a6ebd)),
          ),
        ],
      ),
    );
  }

  Future<void> _sendWageStatement(BuildContext context, Worker staff, PayrollCalculationResult summary, DateTime periodEnd) async {
    // 임금명세서 생성 및 전송 로직
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final periodStart = DateTime(periodEnd.year, periodEnd.month, 1);
      final Map<String, dynamic> wageDataMap = {
        'netPay': summary.netPay,
        'totalPay': summary.totalPay,
        'basePay': summary.basePay,
        'premiumPay': summary.premiumPay,
        'weeklyHolidayPay': summary.weeklyHolidayPay,
        'breakPay': summary.breakPay,
        'otherAllowancePay': summary.otherAllowancePay,
        'annualLeaveAllowancePay': summary.annualLeaveAllowancePay,
        'taxableWage': summary.taxableWage,
        'insuranceDeduction': summary.insuranceDeduction,
        'mealNonTaxable': summary.mealNonTaxable,
        'previousMonthAdjustment': summary.previousMonthAdjustment,
        'pureLaborHours': summary.pureLaborHours,
        'hourlyRate': staff.hourlyWage,
        'periodStart': periodStart.toIso8601String(),
        'periodEnd': periodEnd.toIso8601String(),
        'workerName': staff.name,
        'workerBirthDate': staff.birthDate,
      };

      final doc = LaborDocument(
        id: '${staff.id}_wage_${periodEnd.year}_${periodEnd.month}',
        staffId: staff.id,
        storeId: staff.storeId.isEmpty ? 'unknown' : staff.storeId,
        type: DocumentType.wageStatement, // or wage_ledger
        title: '${periodEnd.year}년 ${periodEnd.month}월 임금명세서',
        content: '수령액: ${summary.netPay.toInt()}원\n(급여명세서 상세내역은 앱 내 문서함에서 확인하세요)',
        createdAt: AppClock.now(),
        status: 'sent',
        expiryDate: DocumentCalculator.calculateExpiryDate(AppClock.now()),
        dataJson: jsonEncode(wageDataMap),
      );

      await DatabaseService().saveDocument(doc);

      if (context.mounted) Navigator.pop(context); // close loader
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('임금명세서가 알바생에게 성공적으로 발송되었습니다.')),
        );
        Navigator.pop(context); // close modal
      }
    } catch (e) {
      if (context.mounted) Navigator.pop(context);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text('전송 중 오류 발생: $e')),
        );
      }
    }
  }

  String _formatTime(DateTime d) {
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  Widget _detailRow(String label, String value, {bool isBold = false, Color? color, Widget? trailing, double? fontSize, String? subtext}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: TextStyle(fontSize: isBold ? 16 : 14, color: Colors.grey.shade700, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
              Row(
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: fontSize ?? (isBold ? 18 : 14),
                      color: color ?? Colors.black87,
                      fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
                    ),
                  ),
                  ?trailing,
                ],
              ),
            ],
          ),
          if (subtext != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(subtext, style: TextStyle(fontSize: (fontSize ?? 14) - 3, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
            ),
        ],
      ),
    );
  }

  Widget _statBox(String label, String value, Color valueColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: valueColor)),
        ],
      ),
    );
  }

  int _mins(String hm) {
    final p = hm.split(':');
    if (p.length != 2) return 0;
    return (int.tryParse(p[0]) ?? 0) * 60 + (int.tryParse(p[1]) ?? 0);
  }

  DateTime _dayKey(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  double _effectiveHourlyWage(Worker worker, DateTime at, {double? minimumHourlyWage}) {
    if (!worker.isProbation || worker.probationMonths <= 0) return worker.hourlyWage;
    final start = DateTime.tryParse(worker.startDate);
    if (start == null) return worker.hourlyWage;
    final probationEnd = DateTime(start.year, start.month + worker.probationMonths, start.day);
    if (!at.isBefore(probationEnd)) return worker.hourlyWage;

    final probationWage = (worker.hourlyWage * 0.9).floorToDouble();
    if (minimumHourlyWage != null && minimumHourlyWage > 0) {
      return probationWage < minimumHourlyWage ? minimumHourlyWage : probationWage;
    }
    return probationWage;
  }

  int _safeDayInMonth(int year, int month, int day) {
    final lastDay = DateTime(year, month + 1, 0).day;
    return day.clamp(1, lastDay);
  }

  ({DateTime start, DateTime end}) _computeSettlementPeriod(DateTime now, int settlementStartDay, int settlementEndDay) {
    final currentMonth = DateTime(now.year, now.month, 1);
    final previousMonth = DateTime(now.year, now.month - 1, 1);

    if (settlementStartDay <= settlementEndDay) {
      final useMonth = (now.day >= settlementStartDay && now.day <= settlementEndDay) ? currentMonth : previousMonth;
      final start = DateTime(useMonth.year, useMonth.month, _safeDayInMonth(useMonth.year, useMonth.month, settlementStartDay));
      final end = DateTime(useMonth.year, useMonth.month, _safeDayInMonth(useMonth.year, useMonth.month, settlementEndDay));
      return (start: start, end: end);
    }

    final startMonth = (now.day >= settlementStartDay) ? currentMonth : previousMonth;
    final endMonth = DateTime(startMonth.year, startMonth.month + 1, 1);
    final start = DateTime(startMonth.year, startMonth.month, _safeDayInMonth(startMonth.year, startMonth.month, settlementStartDay));
    final end = DateTime(endMonth.year, endMonth.month, _safeDayInMonth(endMonth.year, endMonth.month, settlementEndDay));
    return (start: start, end: end);
  }

  void _showLeaveDeductionDialog(BuildContext context, Worker staff) {
    final daysController = TextEditingController();
    final reasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('연차 사용 등록'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: daysController,
                  decoration: const InputDecoration(
                    labelText: '사용 일수 (예: 1.0 또는 0.5)',
                    hintText: '숫자만 입력',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: reasonController,
                  decoration: const InputDecoration(
                    labelText: '사용 사유 (필수)',
                    hintText: '예: 개인 사정, 병가 등',
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '※ 사용 기록은 노무 증거력을 위해 3년간 보관됩니다.',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
            ElevatedButton(
              onPressed: () async {
                final days = double.tryParse(daysController.text);
                final reason = reasonController.text.trim();
                if (days == null || days <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('올바른 사용 일수를 입력해주세요.')));
                  return;
                }
                if (reason.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('사용 사유를 입력해주세요.')));
                  return;
                }

                final log = LeaveUsageLog(
                  id: AppClock.now().millisecondsSinceEpoch.toString(),
                  usedDays: days,
                  reason: reason,
                  createdAtIso: AppClock.now().toIso8601String(),
                );

                final updatedLogs = List<LeaveUsageLog>.from(staff.leaveUsageLogs)..add(log);
                final updatedUsedAmount = staff.usedAnnualLeave + days;

                // Update Hive
                staff.usedAnnualLeave = updatedUsedAmount;
                staff.leaveUsageLogs = updatedLogs;
                await staff.save();

                if (context.mounted) {
                  Navigator.pop(context); // Close dialog
                  Navigator.pop(context); // Close payroll modal to refresh
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('연차 사용이 등록되었습니다.')));
                  setState(() {});
                }
              },
              child: const Text('등록'),
            ),
          ],
        );
      },
    );
  }
  void _showLeaveOverrideDialog(BuildContext context, Worker staff) {
    final adjustmentController = TextEditingController(text: staff.annualLeaveManualAdjustment.toString());
    final reasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('연차 수동 조정(Override)'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '시스템 계산값 외에 사장님이 직접 부여하거나 차감할 연차 개수를 입력하세요.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: adjustmentController,
                  decoration: const InputDecoration(
                    labelText: '누적 조정 개수 (예: +1.5 또는 -1.0)',
                    hintText: '기존 조정값 포함 전체 수치를 입력',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: reasonController,
                  decoration: const InputDecoration(
                    labelText: '조정 사유 (필수)',
                    hintText: '예: 작년 미사용분 이월, 수동 보정 등',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
            ElevatedButton(
              onPressed: () async {
                final adj = double.tryParse(adjustmentController.text);
                final reason = reasonController.text.trim();
                if (adj == null) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('올바른 숫자를 입력해주세요.')));
                  return;
                }
                if (reason.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('조정 사유를 입력해주세요.')));
                  return;
                }

                final log = LeaveUsageLog(
                  id: 'override_${AppClock.now().millisecondsSinceEpoch}',
                  usedDays: 0, // 사용이 아닌 조정이므로 0
                  reason: '[조정] $reason (값: $adj)',
                  createdAtIso: AppClock.now().toIso8601String(),
                );

                final updatedLogs = List<LeaveUsageLog>.from(staff.leaveUsageLogs)..add(log);

                // Update Hive
                staff.annualLeaveManualAdjustment = adj;
                staff.leaveUsageLogs = updatedLogs;
                await staff.save();

                if (context.mounted) {
                  Navigator.pop(context); // Close dialog
                  Navigator.pop(context); // Close payroll modal to refresh
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('연차 조정값이 반영되었습니다.')));
                  setState(() {});
                }
              },
              child: const Text('반영'),
            ),
          ],
        );
      },
    );
  }

  void _editAdjustment(BuildContext context, Worker staff) {
    final controller = TextEditingController(text: staff.previousMonthAdjustment.toInt().toString());
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${staff.name}님 전월 정산금 입력'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('세무사 고지액과의 차액을 입력하세요.\n(예: 추가지급은 5000, 과지급 공제는 -5000)', style: TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(signed: true),
              decoration: const InputDecoration(
                labelText: '정산 금액 (원)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
          ElevatedButton(
            onPressed: () async {
              final val = double.tryParse(controller.text) ?? 0.0;
              staff.previousMonthAdjustment = val;
              await staff.save();
              if (context.mounted) {
                Navigator.pop(context);
                setState(() {});
              }
            },
            child: const Text('저장'),
          ),
        ],
      ),
    );
  }

  void _showAddAttendanceDialog(BuildContext context, Worker staff) {
    DateTime pickedDate = AppClock.now();
    TimeOfDay inTime = const TimeOfDay(hour: 9, minute: 0);
    TimeOfDay outTime = const TimeOfDay(hour: 18, minute: 0);
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (stCtx, setDialogState) {
            return AlertDialog(
              title: const Text('근무 기록 수동 추가'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('직원이 깜빡하고 출퇴근을 찍지 않았을 때 사장님이 직접 기록을 추가할 수 있습니다.', style: TextStyle(fontSize: 11, color: Colors.blueGrey)),
                    const SizedBox(height: 16),
                    const Text('근무 일자', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('${pickedDate.year}/${pickedDate.month}/${pickedDate.day}'),
                      trailing: const Icon(Icons.calendar_today, size: 20),
                      onTap: () async {
                        final d = await showDatePicker(
                          context: ctx,
                          initialDate: pickedDate,
                          firstDate: AppClock.now().subtract(const Duration(days: 365)),
                          lastDate: AppClock.now().add(const Duration(days: 31)),
                        );
                        if (d != null) setDialogState(() => pickedDate = d);
                      },
                    ),
                    const SizedBox(height: 12),
                    const Text('출근 시각', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('${inTime.hour.toString().padLeft(2, '0')}:${inTime.minute.toString().padLeft(2, '0')}'),
                      trailing: const Icon(Icons.access_time, size: 20),
                      onTap: () async {
                        final t = await showTimePicker(context: ctx, initialTime: inTime);
                        if (t != null) setDialogState(() => inTime = t);
                      },
                    ),
                    const SizedBox(height: 12),
                    const Text('퇴근 시각', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('${outTime.hour.toString().padLeft(2, '0')}:${outTime.minute.toString().padLeft(2, '0')}'),
                      trailing: const Icon(Icons.access_time, size: 20),
                      onTap: () async {
                        final t = await showTimePicker(context: ctx, initialTime: outTime);
                        if (t != null) setDialogState(() => outTime = t);
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
                FilledButton(
                  onPressed: isSaving ? null : () async {
                    setDialogState(() => isSaving = true);
                    try {
                      final cIn = DateTime(pickedDate.year, pickedDate.month, pickedDate.day, inTime.hour, inTime.minute);
                      var cOut = DateTime(pickedDate.year, pickedDate.month, pickedDate.day, outTime.hour, outTime.minute);
                      if (cOut.isBefore(cIn)) {
                        cOut = cOut.add(const Duration(days: 1)); // 익일 퇴근 처리
                      }
                      
                      final att = Attendance(
                        id: 'manual_${AppClock.now().millisecondsSinceEpoch}',
                        staffId: staff.id,
                        storeId: staff.storeId,
                        clockIn: cIn,
                        clockOut: cOut,
                        originalClockIn: cIn,
                        originalClockOut: cOut,
                        type: AttendanceType.mobile,
                        isAutoApproved: true,
                        attendanceStatus: 'Normal', // 정상 승인 처리
                        isEditedByBoss: true,
                        editedByBossAt: AppClock.now(),
                      );
                      
                      await DatabaseService().recordAttendance(att);
                      if (ctx.mounted) {
                        Navigator.pop(ctx, true);
                        Navigator.pop(context); // 팝업 닫고
                        setState(() {}); // 재계산 위해 화면 리프레시
                      }
                    } catch (e) {
                      setDialogState(() => isSaving = false);
                      if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('저장 실패: $e')));
                    }
                  },
                  child: isSaving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('추가'),
                ),
              ],
            );
          }
        );
      },
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
