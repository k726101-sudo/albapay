import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:signature/signature.dart';
import 'package:geolocator/geolocator.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

class SignaturePadScreen extends StatefulWidget {
  final String title;
  
  const SignaturePadScreen({super.key, required this.title});

  @override
  State<SignaturePadScreen> createState() => _SignaturePadScreenState();
}

class _SignaturePadScreenState extends State<SignaturePadScreen> {
  final SignatureController _controller = SignatureController(
    penStrokeWidth: 3,
    penColor: Colors.black,
    exportBackgroundColor: Colors.white, // 배경색을 흰색으로 지정하여 PDF 호환성 개선
  );

  bool _isProcessing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _captureMetadata() async {
    final metadata = <String, dynamic>{
      'timestamp': DateTime.now().toIso8601String(),
    };

    // 1. Device Info
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (kIsWeb) {
        final webBrowserInfo = await deviceInfo.webBrowserInfo;
        metadata['device'] = webBrowserInfo.userAgent;
      } else if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        metadata['device'] = '${androidInfo.brand} ${androidInfo.model}';
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        metadata['device'] = '${iosInfo.name} ${iosInfo.model}';
      } else {
        metadata['device'] = 'Unknown Platform';
      }
      debugPrint('Metadata: Device info captured');
    } catch (e) {
      debugPrint('Metadata Error: Device info failed: $e');
      metadata['device'] = 'Error capturing device info';
    }

    // 2. Network Info (IP)
    try {
      final info = NetworkInfo();
      metadata['ipAddress'] = await info.getWifiIP() ?? 'Unknown IP';
      debugPrint('Metadata: IP captured');
    } catch (e) {
      debugPrint('Metadata Error: IP failed: $e');
      metadata['ipAddress'] = 'Error capturing IP';
    }

    // 3. Geolocation
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      
      if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
        // GPS 활성화 여부 빠르게 확인
        final isServiceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!isServiceEnabled) {
           metadata['gps'] = 'GPS Disabled';
        } else {
          // 타임아웃을 2초로 단축하여 사용자 경험 개선
          final position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.medium,
              timeLimit: Duration(seconds: 2),
            ),
          );
          metadata['gps'] = '${position.latitude}, ${position.longitude}';
          debugPrint('Metadata: GPS captured');
        }
      } else {
        metadata['gps'] = 'Permission Denied';
      }
    } catch (e) {
      debugPrint('Metadata Warning: GPS failed or timed out: $e');
      metadata['gps'] = 'Timeout/Error capturing GPS';
    }

    return metadata;
  }

  Future<void> _handleSave() async {
    if (_controller.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('서명을 먼저 입력해주세요.')),
      );
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final Uint8List? signatureBytes = await _controller.toPngBytes();
      final metadata = await _captureMetadata();

      if (mounted) {
        Navigator.pop(context, {
          'signatureBytes': signatureBytes,
          'metadata': metadata,
        });
      }
    } catch (e) {
      setState(() => _isProcessing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('서명 저장 중 오류가 발생했습니다: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          TextButton(
            onPressed: _controller.clear,
            child: const Text('초기화', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Signature(
              controller: _controller,
              backgroundColor: Colors.grey.shade200,
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              '위 공간에 정자로 서명해 주세요.\n(서명 시 법적 분쟁 방지를 위해 IP, 기기정보, 위치정보가 함께 기록됩니다.)',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isProcessing ? null : _handleSave,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A1A2E),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isProcessing 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white))
                  : const Text('서명 완료', style: TextStyle(color: Colors.white, fontSize: 16)),
              ),
            ),
          )
        ],
      ),
    );
  }
}
