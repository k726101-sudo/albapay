import 'dart:io';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class R2StorageException implements Exception {
  final String message;
  R2StorageException(this.message);
  @override
  String toString() => 'R2StorageException: $message';
}

class R2StorageService {
  R2StorageService._();
  static final R2StorageService instance = R2StorageService._();

  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(region: 'asia-northeast3');

  // ─────────────────────────────────────────────────────────
  // 전처리: 해시 추출 및 이미지 압축
  // ─────────────────────────────────────────────────────────

  /// 이미지 압축 (최대 해상도 1920, 80% 품질의 WebP 변환)
  Future<File> compressImage(File originalFile) async {
    final tempDir = await getTemporaryDirectory();
    final targetPath = '${tempDir.path}/temp_${DateTime.now().millisecondsSinceEpoch}.webp';

    final result = await FlutterImageCompress.compressAndGetFile(
      originalFile.absolute.path,
      targetPath,
      quality: 80,
      minWidth: 1920,
      minHeight: 1920,
      format: CompressFormat.webp,
    );

    if (result == null) {
      throw R2StorageException('Failed to compress image');
    }
    return File(result.path);
  }

  /// 파일의 SHA-256 해시값 계산
  Future<String> calculateSha256(File file) async {
    final bytes = await file.readAsBytes();
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  // ─────────────────────────────────────────────────────────
  // 파이프라인: 2-Step Commit 기반 업로드
  // ─────────────────────────────────────────────────────────

  /// R2로 안전하게 파일 업로드 (URL 발급 -> S3 PUT -> Finalize)
  Future<String> secureUpload({
    required String storeId,
    required String docType, // 예: 'contract', 'health_cert', 'profile'
    required File file,
    required String mimeType, // 예: 'image/webp', 'application/pdf'
    bool skipCompression = false,
  }) async {
    // 1. 압축 (이미지인 경우에만)
    File targetFile = file;
    if (!skipCompression && mimeType.startsWith('image/')) {
      // 강제로 webp로 압축
      targetFile = await compressImage(file);
      mimeType = 'image/webp'; 
    }

    // 2. 파일 정보 추출
    final sizeBytes = await targetFile.length();
    final hashSha256 = await calculateSha256(targetFile);
    final fileName = targetFile.path.split('/').last;

    // 3. 1단계: 업로드 URL 발급 요청
    HttpsCallableResult? generateResult;
    try {
      generateResult = await _functions.httpsCallable('generateUploadUrl').call({
        'storeId': storeId,
        'docType': docType,
        'fileName': fileName,
        'mimeType': mimeType,
        'sizeBytes': sizeBytes,
        'sha256': hashSha256,
      });
    } catch (e) {
      throw R2StorageException('Failed to generate upload URL: $e');
    }

    final data = generateResult.data as Map;
    final uploadUrl = data['uploadUrl'] as String;
    final docId = data['docId'] as String;

    // 4. 직접 업로드 (Direct S3 PUT)
    try {
      final bytes = await targetFile.readAsBytes();
      final response = await http.put(
        Uri.parse(uploadUrl),
        headers: {
          'Content-Type': mimeType,
          'Content-Length': sizeBytes.toString(),
          // 필요 시 헤더에 x-amz-checksum-sha256 등을 넣을 수 있으나 
          // 현재 presigner 설정에 따라 생략 가능 (body 검증됨)
        },
        body: bytes,
      );

      if (response.statusCode != 200) {
        throw R2StorageException('HTTP PUT failed: ${response.statusCode}');
      }
    } catch (e) {
      throw R2StorageException('Failed to upload file to R2: $e');
    }

    // 5. 2단계: 업로드 확정 (Finalize)
    try {
      await _functions.httpsCallable('finalizeUpload').call({
        'storeId': storeId,
        'docId': docId,
      });
    } catch (e) {
      throw R2StorageException('Failed to finalize upload. File might be orphaned: $e');
    }

    return docId; // DB에 확정된 문서 ID 반환
  }

  // ─────────────────────────────────────────────────────────
  // 안전한 단기 다운로드 URL 발급
  // ─────────────────────────────────────────────────────────

  /// 비공개 문서에 대한 5분짜리 Signed URL 획득
  Future<String> getSecureDownloadUrl({
    required String storeId,
    required String docId,
  }) async {
    try {
      final result = await _functions.httpsCallable('generateDownloadUrl').call({
        'storeId': storeId,
        'docId': docId,
      });
      return result.data['downloadUrl'] as String;
    } catch (e) {
      throw R2StorageException('Failed to get download URL: $e');
    }
  }
}
