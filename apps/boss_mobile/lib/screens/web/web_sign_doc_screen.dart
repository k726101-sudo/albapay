import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_logic/shared_logic.dart';

import '../alba/documents/document_signing_screen.dart';

/// 웹에서 /sign-doc?id=xxx&storeId=yyy 진입 시 보여주는 원격 서명 화면.
/// 알바생이 링크를 클릭하면 계약서 내용을 확인하고 전자 서명을 완료한다.
class WebSignDocScreen extends StatefulWidget {
  final String docId;
  final String storeId;

  const WebSignDocScreen({
    super.key,
    required this.docId,
    required this.storeId,
  });

  @override
  State<WebSignDocScreen> createState() => _WebSignDocScreenState();
}

class _WebSignDocScreenState extends State<WebSignDocScreen> {
  bool _isLoading = true;
  LaborDocument? _doc;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchDocument();
  }

  Future<void> _fetchDocument() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('stores')
          .doc(widget.storeId)
          .collection('documents')
          .doc(widget.docId)
          .get();

      if (!snap.exists) throw '서류를 찾을 수 없습니다.';

      final doc = LaborDocument.fromMap(snap.id, snap.data()!);

      // 이미 서명 완료된 서류 확인
      if (doc.signatureUrl != null && doc.signatureUrl!.isNotEmpty) {
        setState(() {
          _doc = doc;
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _doc = doc;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        title: const Text(
          '근로계약서 서명',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : _buildContent(),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 56, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              _error!,
              style: const TextStyle(fontSize: 16, color: Colors.red),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            const Text(
              '링크가 만료되었거나 잘못된 경우입니다.\n사장님에게 링크를 다시 요청해 주세요.',
              style: TextStyle(fontSize: 14, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    final doc = _doc!;
    final isSigned = doc.signatureUrl != null && doc.signatureUrl!.isNotEmpty;

    if (isSigned) {
      // 이미 서명 완료
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle, size: 72, color: Color(0xFF34C759)),
              const SizedBox(height: 20),
              const Text(
                '서명이 완료된 서류입니다.',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                doc.title,
                style: const TextStyle(fontSize: 15, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              if (doc.signedAt != null)
                Text(
                  '서명 일시: ${doc.signedAt!.toLocal().toString().substring(0, 16)}',
                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                ),
            ],
          ),
        ),
      );
    }

    // 미서명 → DocumentSigningScreen으로 바로 이동
    return DocumentSigningScreen(
      document: doc,
      allStaffDocs: const [],
    );
  }
}
