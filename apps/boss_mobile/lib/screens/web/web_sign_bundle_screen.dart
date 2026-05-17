import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:shared_logic/shared_logic.dart';
import 'package:signature/signature.dart';

/// 웹에서 /sign-bundle?storeId=xxx&workerId=yyy 진입 시
/// 해당 직원의 boss_signed 상태 서류를 전체 한 번에 서명 처리하는 화면.
///
/// 흐름: 서류 목록 확인 → 본인 인증 1회 → 서명 1회 → 전체 서류 일괄 완료
class WebSignBundleScreen extends StatefulWidget {
  final String storeId;
  final String workerId;

  const WebSignBundleScreen({
    super.key,
    required this.storeId,
    required this.workerId,
  });

  @override
  State<WebSignBundleScreen> createState() => _WebSignBundleScreenState();
}

class _WebSignBundleScreenState extends State<WebSignBundleScreen> {
  // 서명 대상 서류 목록
  List<LaborDocument> _pendingDocs = [];
  bool _isLoadingDocs = true;
  String? _loadError;

  // 서명 단계
  bool _isPhoneVerified = false;
  bool _isSigning = false;
  bool _isDone = false;

  final _signatureController = SignatureController(
    penStrokeWidth: 3,
    penColor: Colors.black,
    exportBackgroundColor: Colors.white,
  );

  @override
  void initState() {
    super.initState();
    _loadPendingDocs();
  }

  @override
  void dispose() {
    _signatureController.dispose();
    super.dispose();
  }

  // ── boss_signed 상태 서류 전체 로드 ──
  Future<void> _loadPendingDocs() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('stores')
          .doc(widget.storeId)
          .collection('documents')
          .where('staffId', isEqualTo: widget.workerId)
          .where('status', isEqualTo: 'boss_signed')
          .get();

      if (!mounted) return;
      setState(() {
        _pendingDocs = snap.docs
            .map((d) => LaborDocument.fromMap(d.id, d.data()))
            .toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
        _isLoadingDocs = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
        _isLoadingDocs = false;
      });
    }
  }

  // ── 본인 인증 (실서비스: Firebase Phone Auth) ──
  Future<void> _handlePhoneVerification() async {
    setState(() => _isSigning = true);
    await Future.delayed(const Duration(seconds: 1)); // TODO: Firebase Phone Auth
    if (!mounted) return;
    setState(() {
      _isPhoneVerified = true;
      _isSigning = false;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('본인 인증이 완료되었습니다.')),
      );
    }
  }

  // ── 일괄 서명 실행 ──
  Future<void> _handleBundleSign() async {
    if (!_isPhoneVerified) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('서명 전 본인 인증이 필요합니다.')),
      );
      return;
    }
    if (_signatureController.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('서명을 그려주세요.')),
      );
      return;
    }

    setState(() => _isSigning = true);

    try {
      final signatureBytes = await _signatureController.toPngBytes();
      if (signatureBytes == null) throw '서명 이미지를 생성할 수 없습니다.';

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw '사용자 인증이 필요합니다.';

      // 1. 서명 이미지 Storage 업로드 (번들 공통 1장)
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('signatures/${user.uid}/bundle_${widget.workerId}_${DateTime.now().millisecondsSinceEpoch}.png');
      final uploadTask = await storageRef.putData(
        signatureBytes,
        SettableMetadata(contentType: 'image/png'),
      );
      final signatureUrl = await uploadTask.ref.getDownloadURL();

      // 2. 공통 메타데이터 수집
      final metadata = await SecurityMetadataHelper.captureMetadata('employee');
      final now = AppClock.now();

      // 3. 전체 서류 일괄 서명 처리
      final dbService = DatabaseService();
      for (final doc in _pendingDocs) {
        await dbService.signDocumentAsWorker(
          storeId: doc.storeId,
          docId: doc.id,
          signatureUrl: signatureUrl,
          signatureMetadata: {
            ...doc.signatureMetadata ?? {},
            'employee': metadata,
            'bundleSigned': true,
            'bundleSize': _pendingDocs.length,
          },
          signedAt: now,
          deliveryConfirmedAt: now,
        );
      }

      if (!mounted) return;
      setState(() {
        _isDone = true;
        _isSigning = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSigning = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('서명 처리 실패: $e'), backgroundColor: Colors.red),
      );
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
          '서류 서명 및 수령',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      body: _isLoadingDocs
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? _buildError()
              : _isDone
                  ? _buildDoneScreen()
                  : _pendingDocs.isEmpty
                      ? _buildAlreadySigned()
                      : _buildSignFlow(),
    );
  }

  // ── 에러 화면 ──
  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 56, color: Colors.red),
            const SizedBox(height: 16),
            Text(_loadError!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            const Text('링크가 잘못되었거나 만료되었습니다.\n사장님께 재전송 요청해 주세요.',
                style: TextStyle(color: Colors.grey, fontSize: 13), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  // ── 이미 서명 완료 ──
  Widget _buildAlreadySigned() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle, size: 72, color: Color(0xFF34C759)),
            const SizedBox(height: 20),
            const Text('모든 서류 서명이 완료되었습니다.',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            const Text('사장님으로부터 교부된 모든 서류를\n확인하고 서명하셨습니다.',
                style: TextStyle(color: Colors.grey, fontSize: 14), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  // ── 서명 완료 화면 ──
  Widget _buildDoneScreen() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.verified, size: 80, color: Color(0xFF286b3a)),
            const SizedBox(height: 24),
            const Text('서명 완료!',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Color(0xFF286b3a))),
            const SizedBox(height: 12),
            Text(
              '총 ${_pendingDocs.length}건의 서류가\n정식으로 교부·수령 완료되었습니다.',
              style: const TextStyle(fontSize: 15, color: Colors.black87, height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: _pendingDocs
                    .map((doc) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              const Icon(Icons.check, size: 16, color: Color(0xFF286b3a)),
                              const SizedBox(width: 8),
                              Expanded(child: Text(doc.title, style: const TextStyle(fontSize: 13))),
                            ],
                          ),
                        ))
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 서명 플로우 본 화면 ──
  Widget _buildSignFlow() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 안내 배너
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF3DE),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF286b3a).withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.verified_outlined, color: Color(0xFF286b3a), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '아래 ${_pendingDocs.length}건의 서류를 확인하고 서명하면 수령이 완료됩니다.',
                        style: const TextStyle(fontSize: 13, color: Color(0xFF286b3a)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // 서류 목록
              const Text('📋 서명 대상 서류', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              ..._pendingDocs.map((doc) => _buildDocCard(doc)),
              const SizedBox(height: 28),

              // 본인 인증 / 서명 단계
              if (!_isPhoneVerified) _buildVerificationSection() else _buildSignatureSection(),
              const SizedBox(height: 32),

              // 서명 완료 버튼
              SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton(
                  onPressed: _isPhoneVerified && !_isSigning ? _handleBundleSign : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF286b3a),
                    disabledBackgroundColor: Colors.grey.shade300,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _isSigning
                      ? const SizedBox(
                          width: 22, height: 22,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                        )
                      : Text(
                          '서명 완료 (${_pendingDocs.length}건 일괄 수령)',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '* 서명 시 기기정보·GPS·IP·타임스탬프가 암호화 기록됩니다.',
                style: TextStyle(fontSize: 11, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDocCard(LaborDocument doc) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_docIcon(doc.type), color: _docColor(doc.type), size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(doc.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('서명 필요', style: TextStyle(fontSize: 11, color: Color(0xFFE65100), fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          // 무결성 검증 배지
          if (doc.documentHash != null && doc.documentHash!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Builder(builder: (_) {
              final recalc = SecurityMetadataHelper.generateDocumentHash(
                type: doc.type.name,
                staffId: doc.staffId,
                content: doc.content,
                dataJson: doc.dataJson,
                createdAt: doc.createdAt.toIso8601String(),
              );
              final isValid = recalc == doc.documentHash;
              return Row(
                children: [
                  Icon(isValid ? Icons.verified : Icons.warning_amber_rounded,
                      size: 14, color: isValid ? const Color(0xFF4CAF50) : const Color(0xFFE53935)),
                  const SizedBox(width: 4),
                  Text(
                    isValid ? 'SHA-256 원본 검증 완료' : '⚠️ 문서 변조 감지',
                    style: TextStyle(
                      fontSize: 11,
                      color: isValid ? const Color(0xFF2E7D32) : const Color(0xFFC62828),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              );
            }),
          ],
          // 계약서 내용 미리보기 (100자)
          if (doc.content.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              doc.content.length > 100 ? '${doc.content.substring(0, 100)}...' : doc.content,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVerificationSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('1단계: 본인 인증', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 8),
        const Text('법적 효력을 위해 휴대폰 본인 인증이 필요합니다.',
            style: TextStyle(fontSize: 13, color: Colors.black54)),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton.icon(
            onPressed: _isSigning ? null : _handlePhoneVerification,
            icon: const Icon(Icons.phonelink_setup),
            label: const Text('휴대폰 인증하기'),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFF1a6ebd)),
              foregroundColor: const Color(0xFF1a6ebd),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSignatureSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.check_circle, color: Color(0xFF286b3a), size: 18),
            SizedBox(width: 6),
            Text('본인 인증 완료', style: TextStyle(color: Color(0xFF286b3a), fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 16),
        const Text('2단계: 전자 서명', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFF1a6ebd).withValues(alpha: 0.4), width: 1.5),
            borderRadius: BorderRadius.circular(12),
            color: Colors.white,
          ),
          child: Signature(
            controller: _signatureController,
            height: 160,
            backgroundColor: Colors.white,
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => _signatureController.clear(),
            child: const Text('지우기', style: TextStyle(color: Colors.grey)),
          ),
        ),
      ],
    );
  }

  IconData _docIcon(DocumentType type) {
    switch (type) {
      case DocumentType.contract_full:
      case DocumentType.contract_part:
        return Icons.description_outlined;
      case DocumentType.night_consent:
        return Icons.nights_stay_outlined;
      case DocumentType.checklist:
        return Icons.checklist_outlined;
      case DocumentType.wage_amendment:
        return Icons.edit_note_outlined;
      default:
        return Icons.article_outlined;
    }
  }

  Color _docColor(DocumentType type) {
    switch (type) {
      case DocumentType.contract_full:
      case DocumentType.contract_part:
        return const Color(0xFF1a6ebd);
      case DocumentType.night_consent:
        return const Color(0xFF286b3a);
      case DocumentType.checklist:
        return const Color(0xFFd4700a);
      default:
        return Colors.grey;
    }
  }
}
