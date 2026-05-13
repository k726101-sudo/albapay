import 'package:web/web.dart' as web;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_logic/shared_logic.dart';
import 'package:url_launcher/url_launcher.dart';

class DocumentViewScreen extends StatefulWidget {
  final String docId;
  final String storeId;

  const DocumentViewScreen({
    super.key,
    required this.docId,
    required this.storeId,
  });

  @override
  State<DocumentViewScreen> createState() => _DocumentViewScreenState();
}

class _DocumentViewScreenState extends State<DocumentViewScreen> {
  bool _isLoading = true;
  LaborDocument? _doc;
  String? _error;

  @override
  void initState() {
    super.initState();
    _handleTrackingAndFetch();
  }

  Future<void> _handleTrackingAndFetch() async {
    try {
      // 1. 수신 확인 트래킹 (delivered 상태로 업데이트)
      await DatabaseService().setDocumentDelivered(
        storeId: widget.storeId,
        docId: widget.docId,
      );

      // 2. 문서 데이터 가져오기
      final snap = await FirebaseFirestore.instance
          .collection('stores')
          .doc(widget.storeId)
          .collection('documents')
          .doc(widget.docId)
          .get();

      if (!snap.exists) {
        throw '문서를 찾을 수 없습니다.';
      }

      setState(() {
        _doc = LaborDocument.fromMap(snap.id, snap.data()!);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _openPdf() async {
    final pdfUrl = _doc?.pdfUrl;
    if (pdfUrl == null || pdfUrl.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PDF 서류가 아직 생성되지 않았거나 주소가 없습니다. 사장님께 문의해 주세요.')),
        );
      }
      return;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PDF 계약서를 불러오는 중입니다...'), duration: Duration(seconds: 2)),
      );
    }

    final url = Uri.parse(pdfUrl);
    try {
      // Web에서는 externalApplication 모드가 새 창/탭을 여는 표준 방식입니다.
      final success = await launchUrl(url, mode: LaunchMode.externalApplication);
      if (!success) {
        // url_launcher가 실패할 경우 dart:html 방식으로 직접 엽니다.
        web.window.open(pdfUrl, '_blank');
      }
    } catch (e) {
      debugPrint('Error launching PDF URL: $e');
      web.window.open(pdfUrl, '_blank');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('서류 수령 및 확인'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
              : _buildContent(),
    );
  }

  Widget _buildContent() {
    if (_doc == null) return const SizedBox();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(Icons.mark_email_read_outlined, size: 80, color: Colors.blue),
              const SizedBox(height: 24),
              const Text(
                '서류가 성공적으로 교부되었습니다',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                '사업주로부터 전송된 서류를 확인해 주세요.\n귀하의 확인(링크 클릭) 시각이 기록되었습니다.',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600, height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              
              // 서류 정보 카드
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.blue.shade100),
                ),
                child: Column(
                  children: [
                    _infoRow('서류 명칭', _doc!.title),
                    const Divider(),
                    _infoRow('발행 일시', _doc!.sentAt?.toIso8601String().substring(0, 10) ?? '-'),
                    const Divider(),
                    _infoRow('상태', '교부 완료 (확인됨)'),
                  ],
                ),
              ),
              
              const SizedBox(height: 40),
              
              // PDF 보기 버튼
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton.icon(
                  onPressed: _openPdf,
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('정식 PDF 계약서 보기', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              
              const SizedBox(height: 16),
              
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('닫기', style: TextStyle(color: Colors.grey)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.blue.shade800, fontWeight: FontWeight.w500)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
