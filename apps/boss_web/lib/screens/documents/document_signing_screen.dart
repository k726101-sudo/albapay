import 'package:flutter/material.dart';
import 'package:shared_logic/shared_logic.dart';
import 'package:signature/signature.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';

class DocumentSigningScreen extends StatefulWidget {
  final LaborDocument document;
  /// 같은 직원의 전체 서류 목록 - 계약서 서명 시 보관용 서류들도 함께 종결 처리
  final List<LaborDocument> allStaffDocs;

  const DocumentSigningScreen({
    super.key,
    required this.document,
    this.allStaffDocs = const [],
  });

  @override
  State<DocumentSigningScreen> createState() => _DocumentSigningScreenState();
}

class _DocumentSigningScreenState extends State<DocumentSigningScreen> {
  final SignatureController _signatureController = SignatureController(
    penStrokeWidth: 3,
    penColor: Colors.black,
    exportBackgroundColor: Colors.white,
  );

  bool _isPhoneVerified = false;
  bool _isLoading = false;
  final _dbService = DatabaseService();

  void _handlePhoneVerification() async {
    setState(() => _isLoading = true);
    // 실서비스: Firebase Phone Auth 연동
    await Future.delayed(const Duration(seconds: 1));
    setState(() {
      _isPhoneVerified = true;
      _isLoading = false;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('본인 인증이 완료되었습니다.')),
      );
    }
  }

// Deleted local _captureMetadata inline.

  Future<void> _handleSign() async {
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

    setState(() => _isLoading = true);

    try {
      final signatureBytes = await _signatureController.toPngBytes();
      if (signatureBytes == null) throw '서명 이미지를 생성할 수 없습니다.';

      // 사용자 격리 규칙 적용: signatures/{auth.uid}/{filename}
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw '사용자 인증이 필요합니다.';
      
      final storageRef = FirebaseStorage.instance.ref().child('signatures/${user.uid}/${widget.document.id}_worker.png');
      final uploadTask = await storageRef.putData(
        signatureBytes,
        SettableMetadata(contentType: 'image/png'),
      );
      final signatureUrl = await uploadTask.ref.getDownloadURL();

      final metadata = await SecurityMetadataHelper.captureMetadata('employee');
      final now = AppClock.now();

      // 알바생 서명 메타데이터 (2차 메타데이터) — 사장님 1차 메타 위에 결합
      final employeeMeta = <String, dynamic>{
        ...widget.document.signatureMetadata ?? {},
        'employee': metadata,
      };

      // ── 1. 계약서(현재 서류) 서명 완료 처리 ──
      // ★ 보안 규칙 준수: 서명 관련 필드만 update (content/hash/bossSignature 불변)
      await _dbService.signDocumentAsWorker(
        storeId: widget.document.storeId,
        docId: widget.document.id,
        signatureUrl: signatureUrl,
        signatureMetadata: employeeMeta,
        signedAt: now,
        deliveryConfirmedAt: now, // 최종 교부 확정 타임스탬프
      );

      // ── 2. 같은 직원의 보관용 서류들 (체크리스트, 동의서 등) 일괄 종결 ──
      // 알바생이 계약서에 서명하는 순간을 '교부 완료' 기점으로 보고 모든 번들 문서 종결
      final bundleDocs = widget.allStaffDocs.where((d) =>
          d.id != widget.document.id &&
          (d.status == 'sent' || d.status == 'draft')
      ).toList();

      for (final bundleDoc in bundleDocs) {
        await _dbService.signDocumentAsWorker(
          storeId: bundleDoc.storeId,
          docId: bundleDoc.id,
          signatureUrl: bundleDoc.signatureUrl ?? '',
          signatureMetadata: {
            ...bundleDoc.signatureMetadata ?? {},
            'employee': metadata,
          },
          signedAt: bundleDoc.signedAt ?? now,
          deliveryConfirmedAt: now, // 동일 교부 완료 타임스탬프
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ 서명이 완료되었습니다. 근로계약서가 정식으로 교부되었습니다.'),
            backgroundColor: Color(0xFF286b3a),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('서명 저장 실패: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8FA),
      appBar: AppBar(title: Text(widget.document.title)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 교부 확인 안내
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF3DE),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF286b3a).withValues(alpha: 0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.verified_outlined, color: Color(0xFF286b3a), size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '아래 내용을 확인하고 서명하면 근로계약서 수령이 완료됩니다.',
                      style: TextStyle(fontSize: 13, color: Color(0xFF286b3a)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ★ 문서 무결성 검증 배지
            Builder(builder: (_) {
              final doc = widget.document;
              if (doc.documentHash != null && doc.documentHash!.isNotEmpty) {
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
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: isValid ? const Color(0xFFE8F5E9) : const Color(0xFFFDE8E8),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: isValid ? const Color(0xFF4CAF50) : const Color(0xFFE53935)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isValid ? Icons.verified : Icons.warning_amber_rounded,
                        size: 18,
                        color: isValid ? const Color(0xFF4CAF50) : const Color(0xFFE53935),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isValid
                              ? '✅ 원본 문서 확인됨 — SHA-256 무결성 검증 통과'
                              : '⚠️ 문서 위변조 감지 — 해시값 불일치. 서명 전 관리자에게 문의하세요.',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isValid ? const Color(0xFF2E7D32) : const Color(0xFFC62828),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }
              return const SizedBox.shrink(); // 이전 버전 문서 — 해시 없음
            }),

            // 계약서 내용
            Container(
              padding: const EdgeInsets.all(16),
              height: 300,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                child: Text(widget.document.content, style: const TextStyle(height: 1.5)),
              ),
            ),
            const SizedBox(height: 32),
            if (!_isPhoneVerified)
              _buildVerificationSection()
            else
              _buildSignatureSection(),
            const SizedBox(height: 48),
            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      onPressed: _isPhoneVerified ? _handleSign : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF286b3a),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        '서명 완료 및 수령 확인',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildVerificationSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('1단계: 본인 인증', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('법적 효력을 위해 휴대폰 본인 인증이 필요합니다.'),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _isLoading ? null : _handlePhoneVerification,
          icon: const Icon(Icons.phonelink_setup),
          label: const Text('휴대폰 인증하기'),
        ),
      ],
    );
  }

  Widget _buildSignatureSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('2단계: 전자 서명', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.blue.shade200, width: 1.5),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Signature(
            controller: _signatureController,
            height: 150,
            backgroundColor: Colors.white,
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => _signatureController.clear(),
              child: const Text('지우기'),
            ),
          ],
        ),
        const Text(
          '* 서명 시 기기 정보(기기모델, GPS, IP, 타임스탬프)가 암호화 기록됩니다.',
          style: TextStyle(fontSize: 11, color: Colors.grey),
        ),
      ],
    );
  }
}
