import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_logic/shared_logic.dart';

import '../utils/compliance_alert_engine.dart';
import '../services/worker_service.dart';
import '../screens/documents/document_wizard_screen.dart';
import '../screens/contract_page.dart';
import '../screens/staff/add_staff_screen.dart';
import '../screens/payroll/payroll_dashboard_screen.dart';

/// 대시보드 통합 컴플라이언스 알림 배너 위젯
/// ComplianceAlertEngine의 결과를 시각적으로 렌더링합니다.
class ComplianceAlertBanner extends StatefulWidget {
  final String storeId;
  final Map<String, dynamic> storeData;
  final String? fiveOrMoreReason;
  final String? refreshKey;

  const ComplianceAlertBanner({
    super.key,
    required this.storeId,
    required this.storeData,
    this.fiveOrMoreReason,
    this.refreshKey,
  });

  @override
  State<ComplianceAlertBanner> createState() => _ComplianceAlertBannerState();
}

class _ComplianceAlertBannerState extends State<ComplianceAlertBanner> {
  List<ComplianceAlert>? _alerts;
  bool _loading = true;
  final Set<String> _dismissed = {};

  @override
  void initState() {
    super.initState();
    _loadAlerts();
  }

  @override
  void didUpdateWidget(ComplianceAlertBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.storeId != widget.storeId || 
        oldWidget.refreshKey != widget.refreshKey) {
      _loadAlerts();
    }
  }

  Future<void> _loadAlerts() async {
    try {
      final alerts = await ComplianceAlertEngine.generateAlerts(
        storeId: widget.storeId,
        storeData: widget.storeData,
      );
      debugPrint('[ComplianceAlertBanner] loaded ${alerts.length} alerts');
      if (mounted) {
        setState(() {
          _alerts = alerts;
          _loading = false;
        });
      }
    } catch (e, st) {
      debugPrint('[ComplianceAlertBanner] ERROR: $e\n$st');
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showDetailsBottomSheet(List<ComplianceAlert> alerts) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, size: 20, color: Color(0xFFE53935)),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      '노동법 컴플라이언스 알림',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(sheetCtx),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: alerts.map((alert) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _buildAlertCard(alert, sheetCtx),
                    )).toList(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    
    final visibleAlerts = (_alerts ?? [])
        .where((a) => !_dismissed.contains(a.id))
        .toList();
    
    if (visibleAlerts.isEmpty) {
      if (widget.fiveOrMoreReason != null && widget.fiveOrMoreReason!.isNotEmpty) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          margin: const EdgeInsets.only(top: 8),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.red.shade200),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline, color: Colors.red, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.fiveOrMoreReason!,
                  style: const TextStyle(
                    color: Colors.red,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        );
      }
      return const SizedBox.shrink();
    }

    final uniqueCodes = visibleAlerts.map((a) => a.code).toSet();
    String alertMessage;
    if (uniqueCodes.length == 1) {
      final code = uniqueCodes.first;
      if (code == 'R-05') {
        alertMessage = '근로계약서 서명이 안 된 직원이 ${visibleAlerts.length}명 있습니다.';
      } else if (code == 'R-04') {
        alertMessage = '고정연장시간을 초과한 직원이 ${visibleAlerts.length}명 있습니다.';
      } else {
        alertMessage = '해결이 필요한 노무 알림이 ${visibleAlerts.length}건 있습니다.';
      }
    } else {
      alertMessage = '긴급 조치가 필요한 노무 알림이 ${visibleAlerts.length}건 있습니다.';
    }

    final hasRed = visibleAlerts.any((a) => a.severity == AlertSeverity.red);
    final bgColor = hasRed ? const Color(0xFFFFF0F0) : const Color(0xFFFFF8E1);
    final borderColor = hasRed ? const Color(0xFFFFCDD2) : const Color(0xFFFFECB3);
    
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: InkWell(
        onTap: () => _showDetailsBottomSheet(visibleAlerts),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor, width: 1.5),
          ),
          child: Row(
            children: [
              const Text('🚨', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  alertMessage,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade900,
                  ),
                ),
              ),
              Icon(Icons.chevron_right, size: 20, color: Colors.grey.shade600),
            ],
          ),
        ),
      ),
    );
  }

  Widget _countBadge(int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count',
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildAlertCard(ComplianceAlert alert, [BuildContext? sheetCtx]) {
    final isRed = alert.severity == AlertSeverity.red;
    final isOrange = alert.severity == AlertSeverity.orange;
    
    final Color bgColor;
    final Color borderColor;
    final Color textColor;
    final String emoji;

    if (isRed) {
      bgColor = const Color(0xFFFBE8E8);
      borderColor = const Color(0xFFE53935);
      textColor = const Color(0xFFC62828);
      emoji = '🔴';
    } else if (isOrange) {
      bgColor = const Color(0xFFFFF3E0);
      borderColor = const Color(0xFFFF9800);
      textColor = const Color(0xFFE65100);
      emoji = '🟠';
    } else {
      bgColor = const Color(0xFFFFFDE7);
      borderColor = const Color(0xFFFDD835);
      textColor = const Color(0xFFF57F17);
      emoji = '🟡';
    }

    return InkWell(
      onTap: () {
        if (sheetCtx != null) Navigator.pop(sheetCtx);
        _handleAlertTap(alert);
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderColor.withOpacity(0.5)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          alert.title,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    alert.message,
                    style: TextStyle(
                      fontSize: 11,
                      color: textColor.withOpacity(0.85),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            Column(
              children: [
                Icon(Icons.chevron_right, size: 18, color: textColor.withOpacity(0.5)),
                const SizedBox(height: 4),
                InkWell(
                  onTap: () => setState(() => _dismissed.add(alert.id)),
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(Icons.close, size: 14, color: textColor.withOpacity(0.4)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _handleAlertTap(ComplianceAlert alert) {
    switch (alert.actionType) {
      case AlertActionType.createContract:
        _navigateToContract(alert);
        break;
      case AlertActionType.editWage:
        final worker = WorkerService.getAll()
            .where((w) => w.id == alert.workerId)
            .firstOrNull;
        if (worker != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AddStaffScreen(initialWorker: worker),
            ),
          );
        }
        break;
      case AlertActionType.viewPayroll:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const PayrollDashboardScreen(),
          ),
        );
        break;
      case AlertActionType.viewAttendance:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const PayrollDashboardScreen(),
          ),
        );
        break;
      case AlertActionType.viewSettings:
        break;
      case AlertActionType.goToSchedule:
        // 메인 대시보드 근무표 확인 유도
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        }
        break;
    }
  }

  /// R-05 알림 클릭 시:
  /// - 계약서가 이미 존재 → ContractPage (서명 플로우)
  /// - 계약서 없음 → DocumentWizardScreen (서류 일괄 작성)
  Future<void> _navigateToContract(ComplianceAlert alert) async {
    final worker = WorkerService.getAll()
        .where((w) => w.id == alert.workerId)
        .firstOrNull;
    if (worker == null) return;

    // Firestore에서 해당 직원의 노무서류 조회
    try {
      final docsSnap = await FirebaseFirestore.instance
          .collection('stores')
          .doc(widget.storeId)
          .collection('documents')
          .where('staffId', isEqualTo: worker.id)
          .get();

      final docs = <LaborDocument>[];
      for (final d in docsSnap.docs) {
        try {
          docs.add(LaborDocument.fromMap(d.id, d.data()));
        } catch (_) {}
      }

      // 계약서 존재 여부 확인
      final contractDoc = docs.where((d) =>
          d.type == DocumentType.contract_full ||
          d.type == DocumentType.contract_part ||
          d.type == DocumentType.laborContract).firstOrNull;

      if (!mounted) return;

      if (contractDoc != null) {
        // ★ 이미 계약서가 있으면 → ContractPage (서명 진행)
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ContractPage(
              worker: worker,
              documentId: contractDoc.id,
              storeId: widget.storeId,
              initialDocument: contractDoc,
            ),
          ),
        );
      } else {
        // ★ 계약서 없음 → DocumentWizardScreen (서류 일괄 작성)
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DocumentWizardScreen(
              worker: worker,
              storeId: widget.storeId,
              documents: docs,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('[ComplianceAlertBanner] contract navigation error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('서류 조회 실패: $e')),
      );
    }
  }
}
