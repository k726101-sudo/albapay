import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/app_clock.dart';

enum DocumentType {
  // 신규 스펙
  contract_full,
  contract_part,
  night_consent,
  checklist,
  worker_record,
  minor_consent,
  wage_amendment,
  leave_promotion_first,   // 연차 사용촉진 1차 통보서 (근로기준법 제61조)
  leave_promotion_second,  // 연차 사용촉진 2차 통보서 (사용시기 지정)
  resignation_letter,

  // 추가 스펙 (LDMS)
  attendance_record,
  wage_ledger,
  annual_leave_ledger,

  // 기존 호환(이전에 저장된 문서 타입)
  laborContract,
  nightHolidayConsent,
  employeeRegistry,
  parentalConsent,
  wageStatement,
  pledge,
}

class LaborDocument {
  final String id;
  final String staffId; // worker.id
  final String storeId;
  final DocumentType type;

  // draft / ready / signed / sent / delivered
  final String status;

  final String title;
  // 텍스트 기반 미리보기/서명 화면에서 사용
  final String content;
  final DateTime createdAt;
  final DateTime? signedAt;
  final DateTime? sentAt;
  final DateTime? deliveredAt;
  final String? pdfUrl;
  final String? signatureUrl;

  // LDMS 스펙
  final DateTime? expiryDate;
  final String? dataJson; // 구조화된 데이터 (시간 그리드, 임금 등)
  final DateTime? deliveryConfirmedAt;
  final String? deliveryConfirmedIp;
  final String? deliveryConfirmedUserAgent;
  final Map<String, dynamic>?
  signatureMetadata; // 알바생 서명 메타데이터 (IP, DeviceInfo, GPS 등)

  // 하이브리드 교차 검증 — 사장님 서명 데이터 (분리 보관)
  final String? bossSignatureUrl;
  final Map<String, dynamic>?
  bossSignatureMetadata; // 사장님 기기 ID, GPS, IP, 타임스탬프

  // 문서 무결성 검증 — SHA-256 해시
  // hash = SHA256(type + staffId + content + dataJson + createdAt)
  final String? documentHash;

  // ── PDF Immutable Archive (R2 확정본) ──
  final String? pdfR2DocId;       // R2 문서 ID (서명 완료 시 생성)
  final String? pdfHash;          // PDF 파일의 SHA-256 해시
  final int pdfVersion;           // PDF 버전 (수정 시 v2, v3… overwrite 금지)

  // ── Soft Delete ──
  final bool isDeleted;           // soft delete 플래그
  final DateTime? deletedAt;      // 삭제 시점
  final String? deletedBy;        // 삭제한 사용자 UID

  // ── Retention 정책 ──
  // 관련 노동관계법령의 보존의무를 고려한 최소 3년 보관 정책
  final DateTime? retentionUntil; // 보관 만료일 (기본: createdAt + 3년)

  LaborDocument({
    required this.id,
    required this.staffId,
    required this.storeId,
    required this.type,
    this.status = 'draft',
    required this.title,
    this.content = '',
    required this.createdAt,
    this.signedAt,
    this.sentAt,
    this.deliveredAt,
    this.pdfUrl,
    this.signatureUrl,
    this.expiryDate,
    this.dataJson,
    this.deliveryConfirmedAt,
    this.deliveryConfirmedIp,
    this.deliveryConfirmedUserAgent,
    this.signatureMetadata,
    this.bossSignatureUrl,
    this.bossSignatureMetadata,
    this.documentHash,
    this.pdfR2DocId,
    this.pdfHash,
    this.pdfVersion = 0,
    this.isDeleted = false,
    this.deletedAt,
    this.deletedBy,
    this.retentionUntil,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'staffId': staffId,
    'storeId': storeId,
    'type': type.name,
    'status': status,
    'title': title,
    'content': content,
    'createdAt': createdAt.toIso8601String(),
    'signedAt': signedAt?.toIso8601String(),
    'sentAt': sentAt?.toIso8601String(),
    'deliveredAt': deliveredAt?.toIso8601String(),
    'pdfUrl': pdfUrl,
    'signatureUrl': signatureUrl,
    'expiryDate': expiryDate?.toIso8601String(),
    'dataJson': dataJson,
    'deliveryConfirmedAt': deliveryConfirmedAt?.toIso8601String(),
    'deliveryConfirmedIp': deliveryConfirmedIp,
    'deliveryConfirmedUserAgent': deliveryConfirmedUserAgent,
    'signatureMetadata': signatureMetadata,
    'bossSignatureUrl': bossSignatureUrl,
    'bossSignatureMetadata': bossSignatureMetadata,
    'documentHash': documentHash,
    // PDF Archive
    if (pdfR2DocId != null) 'pdfR2DocId': pdfR2DocId,
    if (pdfHash != null) 'pdfHash': pdfHash,
    if (pdfVersion > 0) 'pdfVersion': pdfVersion,
    // Soft Delete
    'isDeleted': isDeleted,
    if (deletedAt != null) 'deletedAt': deletedAt!.toIso8601String(),
    if (deletedBy != null) 'deletedBy': deletedBy,
    // Retention
    if (retentionUntil != null) 'retentionUntil': retentionUntil!.toIso8601String(),
  };

  factory LaborDocument.fromMap(String id, Map<String, dynamic> map) =>
      LaborDocument(
        id: id,
        staffId: map['staffId']?.toString() ?? '',
        storeId: map['storeId']?.toString() ?? '',
        type: DocumentType.values.byName(
          map['type']?.toString() ?? 'contract_full',
        ),
        status: _normalizeStatus(map['status']?.toString()),
        title: map['title']?.toString() ?? '',
        content: map['content']?.toString() ?? '',
        createdAt: _parseDate(map['createdAt']) ?? AppClock.now(),
        signedAt: _parseDate(map['signedAt']),
        sentAt: _parseDate(map['sentAt']),
        deliveredAt: _parseDate(map['deliveredAt']),
        pdfUrl: map['pdfUrl']?.toString(),
        signatureUrl: map['signatureUrl']?.toString(),
        expiryDate: _parseDate(map['expiryDate']),
        dataJson: map['dataJson']?.toString(),
        deliveryConfirmedAt: _parseDate(map['deliveryConfirmedAt']),
        deliveryConfirmedIp: map['deliveryConfirmedIp']?.toString(),
        deliveryConfirmedUserAgent: map['deliveryConfirmedUserAgent']
            ?.toString(),
        signatureMetadata: map['signatureMetadata'] as Map<String, dynamic>?,
        bossSignatureUrl: map['bossSignatureUrl']?.toString(),
        bossSignatureMetadata:
            map['bossSignatureMetadata'] as Map<String, dynamic>?,
        documentHash: map['documentHash']?.toString(),
        pdfR2DocId: map['pdfR2DocId']?.toString(),
        pdfHash: map['pdfHash']?.toString(),
        pdfVersion: (map['pdfVersion'] as num?)?.toInt() ?? 0,
        isDeleted: map['isDeleted'] == true,
        deletedAt: _parseDate(map['deletedAt']),
        deletedBy: map['deletedBy']?.toString(),
        retentionUntil: _parseDate(map['retentionUntil']),
      );

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is String) return DateTime.tryParse(value);
    if (value is Timestamp) return value.toDate();
    try {
      // Fallback for JS dynamic properties if not correctly cast
      dynamic ds = value;
      if (ds.seconds != null && ds.nanoseconds != null) {
        return DateTime.fromMicrosecondsSinceEpoch(
          (ds.seconds as int) * 1000000 + (ds.nanoseconds as int) ~/ 1000,
        );
      }
    } catch (_) {}
    return null;
  }

  // 이전 스키마의 pending/signed/expired → draft/signed/draft
  static String _normalizeStatus(String? raw) {
    final s = raw?.trim() ?? '';
    if (s.isEmpty) return 'draft';
    if (s == 'pending') return 'draft';
    if (s == 'signed') return 'signed';
    if (s == 'expired') return 'draft';
    // 이미 draft/ready/signed/sent/delivered 형태면 그대로
    if (s == 'draft' ||
        s == 'ready' ||
        s == 'boss_signed' ||
        s == 'signed' ||
        s == 'sent' ||
        s == 'delivered' ||
        s == 'completed')
      return s;
    return 'draft';
  }
}
