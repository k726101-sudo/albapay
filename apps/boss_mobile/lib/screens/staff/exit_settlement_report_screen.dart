import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_logic/shared_logic.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../models/worker.dart';
import '../../services/worker_service.dart';

class ExitSettlementReportScreen extends StatefulWidget {
  final Worker worker;
  final DateTime exitDate;

  const ExitSettlementReportScreen({
    super.key,
    required this.worker,
    required this.exitDate,
  });

  @override
  State<ExitSettlementReportScreen> createState() => _ExitSettlementReportScreenState();
}

class _ExitSettlementReportScreenState extends State<ExitSettlementReportScreen> {
  late ExitSettlementResult _result;
  bool _isProcessing = false;
  List<Attendance> _allAttendances = [];
  bool _isDataLoading = true;
  final _manualWageController = TextEditingController();
  bool _isManualMode = false;

  @override
  void initState() {
    super.initState();
    _loadDataAndCalculate();
  }

  Future<void> _loadDataAndCalculate() async {
    setState(() => _isDataLoading = true);
    
    try {
      // 1. Hive에서 해당 직원의 모든 근태 기록 가져오기
      try {
        final attBox = Hive.box<Attendance>('attendances');
        _allAttendances = attBox.values
            .where((a) => a.staffId == widget.worker.id)
            .toList();
      } catch (_) {
        debugPrint('Hive attendances box not available, using empty list');
        _allAttendances = [];
      }

      // 가상 직원의 경우 Firestore에서도 출퇴근 기록 보충
      if (widget.worker.name.contains('가상') && _allAttendances.isEmpty) {
        try {
          final storeId = await WorkerService.resolveStoreId().timeout(const Duration(seconds: 3));
          if (storeId.isNotEmpty) {
            final attSnap = await FirebaseFirestore.instance
                .collection('attendance')
                .where('staffId', isEqualTo: widget.worker.id)
                .where('storeId', isEqualTo: storeId)
                .get()
                .timeout(const Duration(seconds: 5));
            _allAttendances = attSnap.docs
                .map((d) => Attendance.fromJson(d.data()))
                .toList();
          }
        } catch (_) {
          debugPrint('Fallback Firestore attendance fetch failed for virtual worker');
        }
      }

      // 2. 상점 설정 가져오기 (5인 이상 여부 등)
      bool isFiveOrMore = false;
      try {
        final storeId = await WorkerService.resolveStoreId().timeout(const Duration(seconds: 3));
        if (storeId.isNotEmpty) {
          final storeDoc = await FirebaseFirestore.instance.collection('stores').doc(storeId).get().timeout(const Duration(seconds: 3));
          isFiveOrMore = storeDoc.data()?['isFiveOrMore'] == true;
        }
      } catch (_) {
        debugPrint('Timeout or offline while fetching store info for exit settlement');
      }

      final result = PayrollCalculator.calculateExitSettlement(
        workerName: widget.worker.name,
        startDate: widget.worker.startDate,
        usedAnnualLeave: widget.worker.usedAnnualLeave,
        annualLeaveManualAdjustment: widget.worker.annualLeaveManualAdjustment,
        weeklyHours: widget.worker.weeklyHours,
        allAttendances: _allAttendances,
        scheduledWorkDays: widget.worker.workDays,
        exitDate: widget.exitDate,
        hourlyRate: widget.worker.hourlyWage,
        isFiveOrMore: isFiveOrMore,
        manualAverageDailyWage: _isManualMode ? double.tryParse(_manualWageController.text) : widget.worker.manualAverageDailyWage,
        annualLeaveInitialAdjustment: widget.worker.annualLeaveInitialAdjustment,
        annualLeaveInitialAdjustmentReason: widget.worker.annualLeaveInitialAdjustmentReason,
        promotionLogs: _parsePromotionLogs(widget.worker.leavePromotionLogsJson),
        isVirtual: widget.worker.name.contains('가상'),
        wageType: widget.worker.wageType,
        monthlyWage: widget.worker.monthlyWage,
        mealAllowance: widget.worker.allowances.firstWhere((a) => a.label == '식비', orElse: () => Allowance(label: '식비', amount: 0)).amount,
        fixedOvertimePay: widget.worker.fixedOvertimePay,
        otherAllowances: widget.worker.allowances.where((a) => a.label != '식비' && a.label != '고정연장수당').map((a) => a.amount).toList(),
      );
      
      setState(() {
        _result = result;
        if (!_isManualMode) {
          _isManualMode = _result.requiresManualInput || widget.worker.manualAverageDailyWage > 0;
          if (_isManualMode) {
            _manualWageController.text = (widget.worker.manualAverageDailyWage > 0 
                ? widget.worker.manualAverageDailyWage 
                : _result.averageDailyWage).toInt().toString();
          }
        }
      });
    } catch (e, st) {
      debugPrint('Error calculating exit settlement: $e\n$st');
      
      // 에러 시에도 최소한 재직일수와 퇴직금 자격은 정확히 계산
      DateTime parsedJoinDate;
      int workingDays;
      try {
        parsedJoinDate = DateTime.parse(widget.worker.startDate);
        workingDays = widget.exitDate.difference(parsedJoinDate).inDays + 1;
      } catch (_) {
        parsedJoinDate = DateTime.now();
        workingDays = 0;
      }
      
      // 수동 입력 또는 시급 기반 평균 임금 산출
      final manualWage = _isManualMode ? (double.tryParse(_manualWageController.text) ?? 0) : (widget.worker.manualAverageDailyWage);
      final effectiveDailyWage = manualWage > 0 ? manualWage : (widget.worker.hourlyWage * 8);
      final isSevEligible = workingDays >= 365;
      final sevPay = isSevEligible ? (effectiveDailyWage * 30) * (workingDays / 365.0) : 0.0;
      
      // 연차수당 계산 (연차저금통에서 잔여 연차 가져오기)
      final usedLeave = widget.worker.usedAnnualLeave;
      final manualAdj = widget.worker.annualLeaveManualAdjustment;
      // 1년 이상 근무: 기본 15개 + 수동 조정값 - 사용한 연차
      final baseEntitlement = isSevEligible ? 15.0 : 0.0;
      final remainLeave = (baseEntitlement + manualAdj - usedLeave).clamp(0.0, 999.0);
      final leavePayout = remainLeave * 8 * widget.worker.hourlyWage;
      
      setState(() {
        _result = ExitSettlementResult(
          workerName: widget.worker.name,
          joinDate: parsedJoinDate,
          exitDate: widget.exitDate,
          totalWorkingDays: workingDays,
          isSeveranceEligible: isSevEligible,
          exitMonthWage: 0,
          remainingLeaveDays: remainLeave,
          annualLeavePayout: leavePayout,
          severancePay: sevPay,
          averageDailyWage: effectiveDailyWage,
          paymentDeadline: widget.exitDate.add(const Duration(days: 14)), 
          requiresManualInput: true,
        );
        _isManualMode = true;
        if (_manualWageController.text.isEmpty) {
          _manualWageController.text = effectiveDailyWage.toInt().toString();
        }
      });
    } finally {
      if (mounted) {
        setState(() => _isDataLoading = false);
      }
    }
  }

  Future<void> _generateAndSavePDF() async {
    final pdf = pw.Document();
    
    // 한글 폰트 로드 (NanumGothic)
    final font = await PdfGoogleFonts.nanumGothicBold();
    final normalFont = await PdfGoogleFonts.nanumGothicRegular();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Padding(
            padding: const pw.EdgeInsets.all(30),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Center(
                  child: pw.Text('퇴사 정산 확인서', style: pw.TextStyle(font: font, fontSize: 26)),
                ),
                pw.SizedBox(height: 40),
                _pdfRow(font, '성 명', widget.worker.name),
                _pdfRow(font, '입사 일자', widget.worker.startDate),
                _pdfRow(font, '퇴사 일자', DateFormat('yyyy-MM-dd').format(widget.exitDate)),
                _pdfRow(font, '재직 기간', '${widget.worker.startDate} ~ ${DateFormat('yyyy-MM-dd').format(widget.exitDate)} (총 ${_result.totalWorkingDays}일)'),
                pw.SizedBox(height: 20),
                pw.Divider(),
                pw.SizedBox(height: 20),
                pw.Text('[정산 내역]', style: pw.TextStyle(font: font, fontSize: 18)),
                pw.SizedBox(height: 10),
                _pdfMoneyRow(normalFont, '1. 퇴사 당월 근로 급여', _result.exitMonthWage),
                _pdfMoneyRow(normalFont, '2. 미사용 연차수당 (${_result.remainingLeaveDays}개)', _result.annualLeavePayout),
                _pdfMoneyRow(normalFont, '3. 법정 퇴직금', _result.severancePay),
                pw.SizedBox(height: 20),
                pw.Divider(thickness: 2),
                pw.SizedBox(height: 10),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('총 정산 합계액', style: pw.TextStyle(font: font, fontSize: 20)),
                    pw.Text('${NumberFormat('#,###').format(_result.totalSettlementAmount)} 원', style: pw.TextStyle(font: font, fontSize: 22)),
                  ],
                ),
                pw.SizedBox(height: 60),
                pw.Text('위 금액을 퇴사 정산금으로 확인하며, 퇴사 후 14일 이내인 ${DateFormat('yyyy년 MM월 dd일').format(_result.paymentDeadline)}까지 지급할 것을 확약합니다.', 
                  style: pw.TextStyle(font: normalFont, fontSize: 12, color: PdfColors.grey700)),
                pw.SizedBox(height: 40),
                pw.Align(
                  alignment: pw.Alignment.centerRight,
                  child: pw.Text('발행일: ${DateFormat('yyyy년 MM월 dd일').format(AppClock.now())}', style: pw.TextStyle(font: normalFont)),
                ),
                pw.Align(
                  alignment: pw.Alignment.centerRight,
                  child: pw.Text('(인)', style: pw.TextStyle(font: normalFont)),
                ),
              ],
            ),
          );
        },
      ),
    );

    await Printing.sharePdf(bytes: await pdf.save(), filename: '퇴사정산서_${widget.worker.name}.pdf');
  }

  pw.Widget _pdfRow(pw.Font font, String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 5),
      child: pw.Row(
        children: [
          pw.SizedBox(width: 80, child: pw.Text(label, style: pw.TextStyle(font: font, color: PdfColors.grey))),
          pw.Text(value, style: pw.TextStyle(font: font)),
        ],
      ),
    );
  }

  pw.Widget _pdfMoneyRow(pw.Font font, String label, double amount) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 8),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: pw.TextStyle(font: font)),
          pw.Text('${NumberFormat('#,###').format(amount)} 원', style: pw.TextStyle(font: font)),
        ],
      ),
    );
  }

  Future<void> _finalizeTermination() async {
    setState(() => _isProcessing = true);
    try {
      await WorkerService.deactivate(
        widget.worker.id,
        widget.exitDate.toIso8601String().substring(0, 10),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${widget.worker.name}님의 퇴사 처리가 완료되었습니다.')),
        );
        Navigator.pop(context);
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('퇴사 처리 중 오류가 발생했습니다.')));
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isDataLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('퇴사 정산 리포트'),
        backgroundColor: const Color(0xFF1a1a2e),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _buildInfoCard(),
            const SizedBox(height: 20),
            _buildManualInputSection(),
            const SizedBox(height: 24),
            _buildSettlementDetail(),
            const SizedBox(height: 30),
            _buildDeadlineNotice(),
            const SizedBox(height: 40),
            _buildActionButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
      ),
      child: Column(
        children: [
          _row('직원명', widget.worker.name),
          _row('입사일', widget.worker.startDate),
          _row('퇴사일', DateFormat('yyyy-MM-dd').format(widget.exitDate)),
          _row('재직일수', '${_result.totalWorkingDays}일'),
        ],
      ),
    );
  }

  Widget _buildSettlementDetail() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('상세 정산 내역', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 12),
        _detailRow('당월 일할 급여', _result.exitMonthWage),
        _detailRow('잔여 연차수당 (${_result.remainingLeaveDays}개)', _result.annualLeavePayout),
        _detailRow('퇴직금', _result.severancePay, subtext: _result.isSeveranceEligible ? '1년 이상 근무' : '1년 미만 근무(미대상)'),
        const Divider(height: 40),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('총 지급액', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            Text(
              '${NumberFormat('#,###').format(_result.totalSettlementAmount)}원',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22, color: Color(0xFF1a6ebd)),
            ),
          ],
        ),
        if (_result.calculationBasis.isNotEmpty) ...[
          const SizedBox(height: 24),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('계산 근거 보기', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Text(
                    _result.calculationBasis.join('\n'),
                    style: const TextStyle(fontSize: 12, color: Colors.black87, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDeadlineNotice() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFCEBEB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE24B4A).withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFE24B4A)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('임금 지급 의무 기한', style: TextStyle(color: Color(0xFFE24B4A), fontWeight: FontWeight.bold)),
                Text(
                  '${DateFormat('yyyy년 MM월 dd일').format(_result.paymentDeadline)}까지 (퇴사 후 14일)',
                  style: const TextStyle(color: Color(0xFFE24B4A), fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 50,
          child: OutlinedButton.icon(
            onPressed: _generateAndSavePDF,
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text('정산서 PDF로 저장'),
            style: OutlinedButton.styleFrom(foregroundColor: Colors.blueGrey),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 55,
          child: FilledButton(
            onPressed: _isProcessing ? null : _finalizeTermination,
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1a1a2e)),
            child: _isProcessing
                ? const CircularProgressIndicator(color: Colors.white)
                : const Text('최종 퇴사 처리 로컬 저장', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildManualInputSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _isManualMode ? const Color(0xFFFFF9C4) : const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _isManualMode ? Colors.orange.shade300 : Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('평균 임금 설정', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              Switch(
                value: _isManualMode,
                onChanged: (v) {
                  setState(() {
                    _isManualMode = v;
                    if (v && _manualWageController.text.isEmpty) {
                      _manualWageController.text = _result.averageDailyWage.toInt().toString();
                    }
                    _loadDataAndCalculate();
                  });
                },
                activeThumbColor: Colors.orange,
              ),
            ],
          ),
          const Text('급여 기록이 부족하거나 시스템 도입 전 데이터 보정이 필요할 때 사용하세요.', 
            style: TextStyle(fontSize: 12, color: Colors.black54)),
          if (_isManualMode) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _manualWageController,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(
                labelText: '1일 평균 임금 (원)',
                hintText: '예: 85000',
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
              ),
              onChanged: (v) {
                // 실시간 반영을 위해 딜레이 후 계산 트리거 (debounce 효과)
                _loadDataAndCalculate();
                // 사장님이 입력하신 값은 직원 정보에도 저장합니다.
                widget.worker.manualAverageDailyWage = double.tryParse(v) ?? 0.0;
                widget.worker.save();
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _detailRow(String label, double amount, {String? subtext}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label),
                if (subtext != null) Text(subtext, style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ),
          Text('${NumberFormat('#,###').format(amount)}원'),
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
