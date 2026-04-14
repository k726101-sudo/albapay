import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:shared_logic/shared_logic.dart';
import 'package:signature/signature.dart';
import 'package:geolocator/geolocator.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

import '../../models/worker.dart';

/// 사장님 원터치 일괄 서명 화면.
/// 특정 직원에게 귀속된 모든 [draft] 상태 서류를 한 번에 사장님이 서명합니다.
/// 서명 완료 시 bossSignatureMetadata를 저장하고 상태를 [sent]로 일괄 변경합니다.
class BatchSigningScreen extends StatefulWidget {
  final Worker worker;
  final List<LaborDocument> draftDocuments;
  final String storeId;

  const BatchSigningScreen({
    super.key,
    required this.worker,
    required this.draftDocuments,
    required this.storeId,
  });

  @override
  State<BatchSigningScreen> createState() => _BatchSigningScreenState();
}

class _BatchSigningScreenState extends State<BatchSigningScreen> {
  final SignatureController _controller = SignatureController(
    penStrokeWidth: 3.5,
    penColor: Colors.black,
    exportBackgroundColor: Colors.transparent,
  );

  bool _agreed = false;
  bool _isProcessing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _captureBossMetadata() async {
    final metadata = <String, dynamic>{
      'timestamp': DateTime.now().toIso8601String(),
      'role': 'boss',
    };

    // 1. 기기 정보
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (kIsWeb) {
        final webInfo = await deviceInfo.webBrowserInfo;
        metadata['device'] = webInfo.userAgent ?? 'Web Browser';
        metadata['deviceId'] = webInfo.platform ?? 'web';
      } else if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        metadata['device'] = '${androidInfo.brand} ${androidInfo.model}';
        metadata['deviceId'] = androidInfo.id;
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        metadata['device'] = '${iosInfo.name} ${iosInfo.model}';
        metadata['deviceId'] = iosInfo.identifierForVendor ?? 'unknown';
      }
    } catch (_) {
      metadata['device'] = 'Unknown';
      metadata['deviceId'] = 'Unknown';
    }

    // 2. IP 주소
    try {
      final info = NetworkInfo();
      metadata['ipAddress'] = await info.getWifiIP() ?? 'Unknown IP';
    } catch (_) {
      metadata['ipAddress'] = 'Unknown IP';
    }

    // 3. GPS
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.whileInUse || perm == LocationPermission.always) {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 4),
          ),
        );
        metadata['gps'] = '${pos.latitude}, ${pos.longitude}';
      } else {
        metadata['gps'] = 'Permission Denied';
      }
    } catch (_) {
      metadata['gps'] = 'GPS Error';
    }

    return metadata;
  }

  Future<void> _handleBatchSign() async {
    if (!_agreed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('동의 체크박스를 먼저 확인해 주세요.')),
      );
      return;
    }
    if (_controller.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('서명란에 서명을 그려주세요.')),
      );
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final Uint8List? sigBytes = await _controller.toPngBytes();
      // 서명 이미지는 현재 로컬 처리; 실서비스에서는 Firebase Storage 업로드 후 URL 수령
      final String bossSignatureUrl = sigBytes != null
          ? 'data:image/png;base64,local_signature' 
          : '';

      final bossMeta = await _captureBossMetadata();
      final db = DatabaseService();
      final now = AppClock.now();

      // 모든 초안 서류에 사장님 서명 메타 저장 + 상태를 [sent]로 일괄 설정
      for (final doc in widget.draftDocuments) {
        final updated = LaborDocument(
          id: doc.id,
          staffId: doc.staffId,
          storeId: doc.storeId,
          type: doc.type,
          title: doc.title,
          content: doc.content,
          createdAt: doc.createdAt,
          signedAt: doc.signedAt,
          sentAt: now,
          pdfUrl: doc.pdfUrl,
          signatureUrl: doc.signatureUrl,
          expiryDate: doc.expiryDate,
          dataJson: doc.dataJson,
          deliveryConfirmedAt: doc.deliveryConfirmedAt,
          signatureMetadata: doc.signatureMetadata,
          // 사장님 서명 데이터 (1차 메타데이터)
          bossSignatureUrl: bossSignatureUrl,
          bossSignatureMetadata: bossMeta,
          // 상태: [교부 대기] sent
          status: 'sent',
        );
        await db.saveDocument(updated);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ ${widget.worker.name}님 서류 ${widget.draftDocuments.length}종 일괄 서명 완료. 알바생 교부 대기 상태로 변경되었습니다.',
            ),
            backgroundColor: const Color(0xFF286b3a),
            duration: const Duration(seconds: 3),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('서명 저장 실패: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8FA),
      appBar: AppBar(
        title: Text('${widget.worker.name}님 일괄 서명'),
        backgroundColor: const Color(0xFF1A1A2E),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 안내 박스
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFE6F1FB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF185FA5).withValues(alpha: 0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.info_outline, color: Color(0xFF185FA5), size: 18),
                      SizedBox(width: 8),
                      Text(
                        '일괄 서명 안내',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF185FA5),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '아래 항목에 동의하시고 서명하시면, 해당 직원의 모든 노무서류에 사장님 서명이 일괄 적용됩니다.\n\n서명 시 기기 정보(기기모델, 기기 ID, GPS, IP, 타임스탬프)가 함께 암호화 기록됩니다.',
                    style: TextStyle(fontSize: 13, color: Color(0xFF185FA5), height: 1.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 서류 목록
            const Text(
              '서명 대상 서류',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            ...widget.draftDocuments.map((doc) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE5E5EA)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A2E).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.description_outlined, size: 16, color: Color(0xFF1A1A2E)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(doc.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF0DC),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text('서명 필요', style: TextStyle(fontSize: 11, color: Color(0xFF854F0B))),
                  ),
                ],
              ),
            )),
            const SizedBox(height: 24),

            // 동의 체크박스
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => setState(() => _agreed = !_agreed),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _agreed ? const Color(0xFFEAF3DE) : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _agreed ? const Color(0xFF286b3a) : const Color(0xFFDDDDDD),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _agreed ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                      color: _agreed ? const Color(0xFF286b3a) : Colors.grey,
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        '위 서류들의 내용을 모두 확인하였으며, 본인(사업주)이 일괄 서명에 동의합니다.',
                        style: TextStyle(fontSize: 13, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // 서명 패드
            const Text(
              '사장님 서명',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Container(
              height: 180,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _agreed ? const Color(0xFF1a6ebd) : const Color(0xFFDDDDDD),
                  width: _agreed ? 1.5 : 1.0,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: Signature(
                  controller: _controller,
                  backgroundColor: Colors.white,
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _controller.clear,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('지우기'),
                style: TextButton.styleFrom(foregroundColor: Colors.grey),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '* 이 서명은 위 모든 서류에 동시에 적용됩니다.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 30),

            // 최종 서명 버튼
            SizedBox(
              width: double.infinity,
              height: 54,
              child: FilledButton(
                onPressed: _isProcessing ? null : _handleBatchSign,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1A1A2E),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: _isProcessing
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                      )
                    : const Text(
                        '일괄 서명 완료 및 알바생 교부',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
