import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_logic/shared_logic.dart';

class AlbaResignationScreen extends StatefulWidget {
  final String storeId;
  final String workerId;

  const AlbaResignationScreen({
    super.key,
    required this.storeId,
    required this.workerId,
  });

  @override
  State<AlbaResignationScreen> createState() => _AlbaResignationScreenState();
}

class _AlbaResignationScreenState extends State<AlbaResignationScreen> {
  final _db = FirebaseFirestore.instance;
  bool _isProcessing = false;
  
  DateTime? _exitDate;
  final TextEditingController _reasonController = TextEditingController();

  Future<void> _submitResignation() async {
    if (_exitDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('퇴사 예정일을 선택해 주세요.')),
      );
      return;
    }

    final reason = _reasonController.text.trim();
    if (reason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('사직 사유를 입력해 주세요.')),
      );
      return;
    }

    setState(() => _isProcessing = true);
    try {
      // 1. Fetch store and worker info
      final storeDoc = await _db.collection('stores').doc(widget.storeId).get();
      final workerDoc = await _db.collection('stores').doc(widget.storeId).collection('workers').doc(widget.workerId).get();
      
      final storeName = storeDoc.data()?['storeName']?.toString() ?? '본 매장';
      final workerName = workerDoc.data()?['name']?.toString() ?? '알바생';

      // 2. Format dates
      final exitDateStr = _exitDate!.toIso8601String().substring(0, 10);
      final now = AppClock.now();
      final todayStr = '${now.year}년 ${now.month.toString().padLeft(2, '0')}월 ${now.day.toString().padLeft(2, '0')}일';

      // 3. Generate Resignation Letter Content
      final content = DocumentTemplates.getResignationLetter({
        'storeName': storeName,
        'workerName': workerName,
        'exitDate': exitDateStr,
        'reason': reason,
        'date': todayStr,
      });

      // 4. Capture Metadata (Sign)
      final meta = await SecurityMetadataHelper.captureMetadata('employee');

      // 5. Create LaborDocument in Firestore
      final docId = '${widget.workerId}_resignation_${now.millisecondsSinceEpoch}';
      final docData = {
        'id': docId,
        'type': DocumentType.resignation_letter.name,
        'title': '사직서 ($workerName)',
        'content': content,
        'status': 'completed', // 사직서는 제출 즉시 본인 서명(작성)이 완료된 것으로 간주
        'staffId': widget.workerId,
        'storeId': widget.storeId,
        'createdAt': FieldValue.serverTimestamp(),
        'acknowledgedAt': FieldValue.serverTimestamp(),
        'employeeMetadata': meta,
      };

      await _db
          .collection('stores')
          .doc(widget.storeId)
          .collection('documents')
          .doc(docId)
          .set(docData);

      // 알람 등을 보낼 수 있지만, 여기서는 관리자 노무 화면에 바로 뜸.

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('제출 완료'),
            content: const Text('사직서가 성공적으로 제출되었습니다.\\n매장 관리자에게 전달되었습니다.'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.pop(context); // close screen
                },
                child: const Text('확인'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('제출 중 오류가 발생했습니다: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('사직서 작성 및 제출'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '퇴사 예정일과 사직 사유를 입력하여 사직서를 제출할 수 있습니다. 제출된 사직서는 관리자에게 즉시 전달되며 서명 및 교부 효력을 갖습니다.',
              style: TextStyle(color: Colors.black54, height: 1.5),
            ),
            const SizedBox(height: 32),
            
            // Exit Date
            const Text('퇴사 예정일 (마지막 근무일)', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            InkWell(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _exitDate ?? DateTime.now(),
                  firstDate: DateTime.now().subtract(const Duration(days: 30)),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (picked != null) {
                  setState(() => _exitDate = picked);
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _exitDate == null 
                        ? '날짜 선택' 
                        : '${_exitDate!.year}년 ${_exitDate!.month}월 ${_exitDate!.day}일',
                      style: TextStyle(
                        fontSize: 16, 
                        color: _exitDate == null ? Colors.grey : Colors.black87,
                      ),
                    ),
                    const Icon(Icons.calendar_today, color: Colors.grey),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Reason
            const Text('사직 사유', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _reasonController,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: '예) 개인 사정, 학업, 이사 등',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
              ),
            ),
            
            const SizedBox(height: 40),
            
            ElevatedButton(
              onPressed: _isProcessing ? null : _submitResignation,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A1A2E),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _isProcessing
                  ? const SizedBox(
                      width: 24, height: 24, 
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Text('사직서 작성 및 제출', style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
