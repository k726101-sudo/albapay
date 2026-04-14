import 'package:flutter/material.dart';
import 'package:shared_logic/shared_logic.dart';
import 'package:web/web.dart' as web;

class DocumentAcknowledgeDialog extends StatefulWidget {
  final String storeId;
  final LaborDocument document;
  final VoidCallback onAcknowledged;

  const DocumentAcknowledgeDialog({
    super.key,
    required this.storeId,
    required this.document,
    required this.onAcknowledged,
  });

  @override
  State<DocumentAcknowledgeDialog> createState() => _DocumentAcknowledgeDialogState();
}

class _DocumentAcknowledgeDialogState extends State<DocumentAcknowledgeDialog> {
  bool _isProcessing = false;

  Future<void> _handleAcknowledge() async {
    setState(() => _isProcessing = true);
    try {
      final dbService = DatabaseService();
      
      // 기초적인 기약 정보 수집 (Web)
      final userAgent = web.window.navigator.userAgent;
      
      // IP는 클라이언트에서 직접 가져오기 어려우므로(CORS 등), 
      // 실제 환경에서는 Cloud Functions나 별도 API를 거쳐야 하지만
      // 여기서는 클라이언트 추정치 or Placeholder를 저장하거나 
      // 추후 백엔드 결합을 위해 필드만 업데이트합니다.
      const ip = 'Captured via Web'; 

      await dbService.acknowledgeDocument(
        storeId: widget.storeId,
        docId: widget.document.id,
        ip: ip,
        userAgent: userAgent,
      );

      widget.onAcknowledged();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('확인 중 오류가 발생했습니다: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 700),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.description_outlined, color: Color(0xFF1A1A2E), size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.document.title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              '아래 서류 내용을 확인해 주세요. 확인 버튼을 누르면 정식으로 교부받은 것으로 간주됩니다.',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F9FA),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE9ECEF)),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    widget.document.content,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.6,
                      color: Color(0xFF495057),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isProcessing ? null : _handleAcknowledge,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A1A2E),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: _isProcessing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text(
                      '서류를 확인했으며 교부에 동의합니다',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
