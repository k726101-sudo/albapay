import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:shared_logic/shared_logic.dart';

class SecurityMetadataHelper {
  /// 수령 확인, 전자서명 등에 필요한 보안 위치/기기/네트워크 메타데이터를 통합하여 추출합니다.
  static Future<Map<String, dynamic>> captureMetadata(String role) async {
    final metadata = <String, dynamic>{
      'timestamp': DateTime.now().toIso8601String(),
      'role': role,
    };

    // 1. 기기 정보
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (kIsWeb) {
        final webBrowserInfo = await deviceInfo.webBrowserInfo;
        metadata['device'] = webBrowserInfo.userAgent;
        metadata['deviceId'] = webBrowserInfo.platform ?? 'web';
      } else if (defaultTargetPlatform == TargetPlatform.android) {
        final androidInfo = await deviceInfo.androidInfo;
        metadata['device'] = '${androidInfo.brand} ${androidInfo.model}';
        metadata['deviceId'] = androidInfo.id;
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        final iosInfo = await deviceInfo.iosInfo;
        metadata['device'] = '${iosInfo.name} ${iosInfo.model}';
        metadata['deviceId'] = iosInfo.identifierForVendor ?? 'unknown';
      } else {
        metadata['device'] = 'Unknown Platform';
        metadata['deviceId'] = 'Unknown';
      }
    } catch (e) {
      metadata['device'] = 'Error capturing device info';
      metadata['deviceId'] = 'Unknown';
    }

    // 2. IP 주소
    try {
      if (kIsWeb) {
        // 웹 통신 특성 상 클라이언트에서 다이렉트로 외부망 IP 추출이 어려워 UserAgent 등으로 대체하거나
        // 네트워크 플러그인이 반환해주는 범용 IP로 폴백
        metadata['ipAddress'] = 'Captured via Web/Browser';
      } else {
        final info = NetworkInfo();
        metadata['ipAddress'] = await info.getWifiIP() ?? 'Unknown IP';
      }
    } catch (e) {
      metadata['ipAddress'] = 'Error capturing IP';
    }

    // 3. GPS
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 3),
          ),
        );
        metadata['gps'] = '${position.latitude}, ${position.longitude}';
      } else {
        metadata['gps'] = 'Permission Denied';
      }
    } catch (e) {
      metadata['gps'] = 'Error capturing GPS';
    }

    return metadata;
  }

  /// 노무 서류의 무결성 해시를 생성합니다 (SHA-256).
  /// 문서의 핵심 불변 데이터(유형, 직원ID, 본문, 구조화 데이터, 생성일시)를 해시합니다.
  /// 이 해시는 PDF 하단에 인쇄되며, Firestore에도 저장되어 위변조 검증에 사용됩니다.
  static String generateDocumentHash({
    required String type,
    required String staffId,
    required String content,
    String? dataJson,
    required String createdAt,
  }) {
    final input = '$type|$staffId|$content|${dataJson ?? ""}|$createdAt';
    return sha256.convert(utf8.encode(input)).toString();
  }
}
