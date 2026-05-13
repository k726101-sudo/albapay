import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_logic/shared_logic.dart';

class DocumentAcknowledgeDialog extends StatefulWidget {
  final String storeId;
  final LaborDocument document;
  final VoidCallback onAcknowledged;
  final bool isPreview;

  const DocumentAcknowledgeDialog({
    super.key,
    required this.storeId,
    required this.document,
    required this.onAcknowledged,
    this.isPreview = false,
  });

  @override
  State<DocumentAcknowledgeDialog> createState() => _DocumentAcknowledgeDialogState();
}

class _DocumentAcknowledgeDialogState extends State<DocumentAcknowledgeDialog> {
  bool _isProcessing = false;

// platform info logic moved to helper

  Future<void> _handleAcknowledge() async {
    setState(() => _isProcessing = true);
    try {
      final dbService = DatabaseService();
      
      final meta = await SecurityMetadataHelper.captureMetadata('employee');

      await dbService.acknowledgeDocument(
        storeId: widget.storeId,
        docId: widget.document.id,
        metadata: meta,
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
            const SizedBox(height: 12),

            // ★ 문서 무결성 검증 배지
            // 미리보기 모드이거나 서명이 완료되지 않은 문서에서는 검증을 Bypass
            Builder(builder: (_) {
              final doc = widget.document;
              
              // 서명 완료 후 최종 문서만 무결성 검증 수행
              // isPreview == true → 스킵
              // status가 'signed' 또는 'sent' 또는 'delivered'가 아닌 경우 → 스킵
              final isSignedFinal = !widget.isPreview && 
                  (doc.status == 'signed' || doc.status == 'sent' || doc.status == 'delivered');
              
              if (isSignedFinal && doc.documentHash != null && doc.documentHash!.isNotEmpty) {
                final recalculated = SecurityMetadataHelper.generateDocumentHash(
                  type: doc.type.name,
                  staffId: doc.staffId,
                  content: doc.content,
                  dataJson: doc.dataJson,
                  createdAt: doc.createdAt.toIso8601String(),
                );
                final isValid = recalculated == doc.documentHash;
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: isValid ? const Color(0xFFE8F5E9) : const Color(0xFFFDE8E8),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: isValid ? const Color(0xFF4CAF50) : const Color(0xFFE53935)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isValid ? Icons.verified : Icons.warning_amber_rounded,
                        size: 16,
                        color: isValid ? const Color(0xFF4CAF50) : const Color(0xFFE53935),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isValid
                              ? '✅ 원본 문서 확인됨 (SHA-256 무결성 검증 통과)'
                              : '⚠️ 문서 위변조 감지 — 관리자에게 문의하세요',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isValid ? const Color(0xFF2E7D32) : const Color(0xFFC62828),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }
              return const SizedBox.shrink();
            }),

            const SizedBox(height: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F9FA),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE9ECEF)),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        widget.document.content,
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.6,
                          color: Color(0xFF495057),
                        ),
                      ),
                      // ★ 서명란 표시
                      if (widget.document.bossSignatureUrl != null || widget.document.signatureUrl != null) ...[
                        const SizedBox(height: 24),
                        const Divider(),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildSignatureBox('사업주', widget.document.bossSignatureUrl),
                            _buildSignatureBox('근로자', widget.document.signatureUrl),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                    ],
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

  Widget _buildSignatureBox(String label, String? imageUrl) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF888888))),
        const SizedBox(height: 6),
        Container(
          width: 130,
          height: 70,
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE5E5EA)),
            borderRadius: BorderRadius.circular(10),
            color: Colors.white,
          ),
          child: imageUrl != null && imageUrl.isNotEmpty
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Center(
                      child: Icon(Icons.broken_image_outlined, color: Colors.grey, size: 24),
                    ),
                  ),
                )
              : const Center(
                  child: Text('서명 전', style: TextStyle(color: Color(0xFFBBBBBB), fontSize: 12)),
                ),
        ),
      ],
    );
  }
}
