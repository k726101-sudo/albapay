import 'package:flutter/material.dart';
import 'package:shared_logic/shared_logic.dart';

import '../../models/worker.dart';
import '../../utils/renewal_engine.dart';
import '../../services/worker_service.dart';

class ContractRenewalScreen extends StatefulWidget {
  const ContractRenewalScreen({super.key});

  @override
  State<ContractRenewalScreen> createState() => _ContractRenewalScreenState();
}

class _ContractRenewalScreenState extends State<ContractRenewalScreen> {
  bool _isLoading = false;
  late List<Worker> _pendingWorkers;

  @override
  void initState() {
    super.initState();
    _pendingWorkers = RenewalEngine.getPendingRenewals();
  }

  Future<void> _handleApproveAndDistribute() async {
    if (_pendingWorkers.isEmpty) return;
    
    setState(() => _isLoading = true);
    
    try {
      final db = DatabaseService();
      final now = AppClock.now();
      
      for (final worker in _pendingWorkers) {
        // 1. Update Worker Wage in DB (★ 시급 인하 방지: 기존 시급이 높으면 유지)
        if (worker.hourlyWage < PayrollConstants.legalMinimumWage) {
          worker.hourlyWage = PayrollConstants.legalMinimumWage;
        }
        await WorkerService.save(worker);

        // 2. Generate LaborDocument stub for signature
        final docContent = '본 합의서에 따라 시급이 ${PayrollConstants.legalMinimumWage.toInt()}원으로 상향 적용됩니다.';
        final docId = '${worker.id}_amendment_${PayrollConstants.minimumWageEffectiveYear}';
        final documentHash = SecurityMetadataHelper.generateDocumentHash(
          type: DocumentType.wage_amendment.name,
          staffId: worker.id,
          content: docContent,
          createdAt: now.toIso8601String(),
        );

        final doc = LaborDocument(
          id: docId,
          storeId: worker.storeId,
          staffId: worker.id,
          type: DocumentType.wage_amendment,
          title: '${PayrollConstants.minimumWageEffectiveYear}년 임금 변경 합의서',
          content: docContent,
          createdAt: now,
          status: 'sent',
          expiryDate: DocumentCalculator.calculateExpiryDate(now),
          documentHash: documentHash,
        );
        
        await db.saveDocument(doc);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('총 ${_pendingWorkers.length}명에 대한 시급 인상 및 합의서 배포가 완료되었습니다.')),
      );
      Navigator.pop(context);

    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('배포 중 오류 발생: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('최저임금 일괄 갱신'),
        backgroundColor: const Color(0xFF1a1a2e),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              color: const Color(0xFFFBE8E8),
              child: const Text(
                '아래 직원들은 이번 연도 최저임금 기준에 미달하여 시급 인상이 필요합니다. [승인] 시 시급이 자동으로 상향 조정되며 합의서가 전송됩니다.',
                style: TextStyle(color: Color(0xFFC0392B), fontSize: 13, height: 1.4),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _pendingWorkers.length,
                itemBuilder: (context, index) {
                  final worker = _pendingWorkers[index];
                  final workerLabel = worker.workerType == 'regular' ? '정규직' : (worker.workerType == 'dispatch' ? '파견직' : '단기/알바');
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      title: Text('${worker.name} ($workerLabel)', style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(
                        '기존: ${worker.hourlyWage.toInt()}원  →  변경: ${PayrollConstants.legalMinimumWage.toInt()}원\n(+${(PayrollConstants.legalMinimumWage - worker.hourlyWage).toInt()}원 인상)',
                        style: const TextStyle(color: Color(0xFF1a6ebd), height: 1.5, fontWeight: FontWeight.w500),
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _handleApproveAndDistribute,
                  icon: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Icon(Icons.send, color: Colors.white),
                  label: Text(
                    _isLoading ? '배포 중...' : '전체 승인 및 배포',
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE24B4A),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}
