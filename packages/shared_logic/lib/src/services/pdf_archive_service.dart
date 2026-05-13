import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/document_model.dart';
import 'r2_storage_service.dart';
import 'database_service.dart';

/// PDF Immutable Archive 서비스
///
/// 서명 완료된 노무 서류를 R2에 확정 PDF로 보관합니다.
/// - 한번 저장된 PDF는 overwrite 금지 (immutable)
/// - SHA-256 해시로 위변조 검증
/// - 버전 관리: 수정 시 새 버전 생성 (v1→v2→…)
class PdfArchiveService {
  PdfArchiveService._();
  static final PdfArchiveService instance = PdfArchiveService._();

  final _r2 = R2StorageService.instance;
  final _db = DatabaseService();

  /// PDF 파일의 SHA-256 해시를 계산합니다.
  static String calculatePdfHash(Uint8List pdfBytes) {
    return sha256.convert(pdfBytes).toString();
  }

  /// 서명 완료된 문서를 R2에 확정 보관합니다.
  ///
  /// 호출 시점: 알바생 서명 완료 → 양쪽 서명 포함 확정본 PDF 생성 후
  ///
  /// 흐름:
  /// 1. SHA-256 해시 계산
  /// 2. R2 업로드 (immutable 키: documents/{storeId}/{docId}_v{version}.pdf)
  /// 3. Firestore 업데이트 (pdfR2DocId, pdfHash, pdfVersion)
  ///
  /// [doc] 서명 완료된 LaborDocument
  /// [pdfBytes] PdfGeneratorService가 생성한 확정 PDF 바이트
  ///
  /// Returns: 아카이브된 R2 문서 ID
  Future<String> archiveSignedDocument({
    required LaborDocument doc,
    required Uint8List pdfBytes,
  }) async {
    // 1. PDF 해시 계산
    final pdfHash = calculatePdfHash(pdfBytes);
    final nextVersion = doc.pdfVersion + 1;

    // 2. 임시 파일 생성 (R2 업로드는 File 객체 필요)
    final tempDir = await getTemporaryDirectory();
    final tempFile = File(
      '${tempDir.path}/${doc.id}_v$nextVersion.pdf',
    );
    await tempFile.writeAsBytes(pdfBytes);

    try {
      // 3. R2 업로드 (2-step commit)
      //    키: documents/{storeId}/{docId}_v{version}.pdf
      //    immutable: 같은 버전의 키는 절대 덮어쓰지 않음
      final r2DocId = await _r2.secureUpload(
        storeId: doc.storeId,
        docType: 'document_archive',
        file: tempFile,
        mimeType: 'application/pdf',
        skipCompression: true, // PDF는 이미지 압축 건너뜀
      );

      // 4. Firestore에 아카이브 메타데이터 기록
      await _db.updateDocumentArchive(
        storeId: doc.storeId,
        docId: doc.id,
        pdfR2DocId: r2DocId,
        pdfHash: pdfHash,
        pdfVersion: nextVersion,
      );

      debugPrint('✅ PDF Archive 완료: ${doc.id} v$nextVersion (hash: ${pdfHash.substring(0, 16)}…)');
      return r2DocId;
    } finally {
      // 임시 파일 정리
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    }
  }

  /// 보관된 확정 PDF의 서명된 다운로드 URL을 반환합니다.
  ///
  /// R2에 보관된 PDF가 있으면 서명 URL 반환, 없으면 null.
  Future<String?> getArchivedPdfUrl(LaborDocument doc) async {
    if (doc.pdfR2DocId == null || doc.pdfR2DocId!.isEmpty) {
      return null;
    }
    try {
      return await _r2.getSecureDownloadUrl(
        storeId: doc.storeId,
        docId: doc.pdfR2DocId!,
      );
    } catch (e) {
      debugPrint('⚠️ PDF Archive URL 발급 실패: $e');
      return null;
    }
  }

  /// PDF 무결성을 검증합니다.
  ///
  /// R2에서 다운로드한 PDF의 해시와 Firestore에 저장된 해시를 비교합니다.
  /// true: 무결성 통과 (위변조 없음)
  /// false: 해시 불일치 (위변조 가능성)
  /// null: 검증 불가 (해시 없음)
  bool? verifyPdfIntegrity({
    required LaborDocument doc,
    required Uint8List downloadedPdfBytes,
  }) {
    if (doc.pdfHash == null || doc.pdfHash!.isEmpty) {
      return null; // 이전 버전 문서 — 해시 없음
    }
    final currentHash = calculatePdfHash(downloadedPdfBytes);
    return currentHash == doc.pdfHash;
  }

  /// 문서의 retention 만료일을 계산합니다.
  ///
  /// 관련 노동관계법령의 보존의무를 고려한 최소 3년 보관 정책.
  /// 문서 종류에 따라 보관 기간이 다를 수 있으므로 유형별 분리 가능하도록 설계.
  static DateTime calculateRetentionUntil(LaborDocument doc) {
    const defaultYears = 3; // 기본 3년 (근로기준법 제42조, 제48조)

    // 향후 문서 유형별 보관 기간 분리 시 여기에 추가
    // switch (doc.type) {
    //   case DocumentType.contract_full:
    //   case DocumentType.contract_part:
    //     years = 3; // 근로기준법 제42조
    //   case DocumentType.wageStatement:
    //     years = 3; // 근로기준법 제48조
    //   ...
    // }

    return DateTime(
      doc.createdAt.year + defaultYears,
      doc.createdAt.month,
      doc.createdAt.day,
    );
  }
}
