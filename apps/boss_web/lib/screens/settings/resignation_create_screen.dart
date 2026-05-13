import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_logic/shared_logic.dart';

import '../documents/document_signing_screen.dart';

class ResignationCreateScreen extends StatefulWidget {
  const ResignationCreateScreen({super.key});

  @override
  State<ResignationCreateScreen> createState() => _ResignationCreateScreenState();
}

class _ResignationCreateScreenState extends State<ResignationCreateScreen> {
  final _reasonController = TextEditingController();
  DateTime? _exitDate;
  bool _isLoading = false;

  Future<void> _submitResignation() async {
    if (_exitDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('퇴사 예정일을 선택해주세요.')));
      return;
    }
    if (_reasonController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('퇴사 사유를 입력해주세요.')));
      return;
    }

    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw '로그인이 필요합니다.';

      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (!userDoc.exists) throw '사용자 정보를 찾을 수 없습니다.';
      
      final workerId = userDoc.data()?['workerId'];
      final storeId = userDoc.data()?['storeId'];
      final userName = userDoc.data()?['name'] ?? '알바생';

      if (workerId == null || storeId == null) {
        throw '소속 매장 및 직원 정보가 연결되어 있지 않습니다.';
      }

      final storeDoc = await FirebaseFirestore.instance.collection('stores').doc(storeId).get();
      final storeName = storeDoc.data()?['storeName'] ?? '소속 매장';

      final dateStr = '${_exitDate!.year}년 ${_exitDate!.month}월 ${_exitDate!.day}일';
      final createDateStr = '${DateTime.now().year}년 ${DateTime.now().month}월 ${DateTime.now().day}일';

      final Map<String, String> templateData = {
        'storeName': storeName,
        'workerName': userName,
        'exitDate': dateStr,
        'reason': _reasonController.text.trim(),
        'date': createDateStr,
      };

      final content = DocumentTemplates.getResignationLetter(templateData);

      final docId = FirebaseFirestore.instance.collection('dummy').doc().id;
      final dummyDoc = LaborDocument(
        id: docId,
        staffId: workerId,
        storeId: storeId,
        type: DocumentType.resignation_letter,
        status: 'draft',
        title: '사직서 ($userName)',
        content: content,
        createdAt: DateTime.now(),
      );

      // 서명 화면으로 넘어가서 서명을 받음 (문서를 먼저 DB에 쓰지 않고 넘김)
      if (!mounted) return;
      final success = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => DocumentSigningScreen(
            document: dummyDoc,
          ),
        ),
      );

      if (success == true) {
        if (!mounted) return;
        
        // 서명 완료 후 문서 상태가 'delivered'이 되도록 업데이트 (알바가 이미 서명했으므로 전달 완료 취급)
        await FirebaseFirestore.instance
            .collection('stores')
            .doc(storeId)
            .collection('documents')
            .doc(docId)
            .update({
          'status': 'delivered',
        });

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('사직서 제출이 완료되었습니다.')));
        Navigator.pop(context);

        // 사장님께 사직서 제출 알림 전송
        await FirebaseFirestore.instance
            .collection('stores').doc(storeId)
            .collection('notifications').add({
          'type': 'resignation',
          'storeId': storeId,
          'title': '사직서 제출',
          'body': '$userName 님이 사직서를 제출했습니다. (예정일: $dateStr)',
          'createdAt': FieldValue.serverTimestamp(),
          'read': false,
        });
      }

    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('오류: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('사직서 작성')),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Text('퇴사 예정일', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              InkWell(
                onTap: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now().add(const Duration(days: 7)),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (d != null) setState(() => _exitDate = d);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _exitDate == null 
                          ? '날짜를 선택해주세요' 
                          : '${_exitDate!.year}년 ${_exitDate!.month}월 ${_exitDate!.day}일',
                        style: TextStyle(color: _exitDate == null ? Colors.grey : Colors.black87),
                      ),
                      const Icon(Icons.calendar_today, color: Colors.grey, size: 20),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text('퇴직 사유', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              TextField(
                controller: _reasonController,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: '예) 개인 사정, 학업 전념 등',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.all(16),
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                '• 해당 사직서는 서명 즉시 사장님께 제출되며, 수정하거나 취소하기 어렵습니다.\n• 제출 전 사장님과 충분히 면담하시는 것을 권장합니다.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _submitResignation,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  backgroundColor: const Color(0xFF1a1a2e),
                ),
                child: const Text('서명 및 제출하기'),
              ),
            ],
          ),
    );
  }
}
