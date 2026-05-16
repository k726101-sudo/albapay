import 'package:cloud_firestore/cloud_firestore.dart';

class PayrollSettlement {
  final String id;
  final String storeId;
  final String periodKey; // e.g., "2026-04-01~2026-04-30"
  final DateTime periodStart;
  final DateTime periodEnd;
  final DateTime settlementDate;
  final String engineVersion;
  final double averageWorkers;
  
  /// 직원별 급여 요약 스냅샷 (staffId -> 데이터 맵)
  final Map<String, dynamic> staffSnapshots;
  
  /// 마감 해제 이력 [{ "who": "...", "when": "...", "reason": "..." }, ...]
  final List<Map<String, dynamic>> auditLogs;

  final String? pdfUrl;
  final String? pdfSha256;

  PayrollSettlement({
    required this.id,
    required this.storeId,
    required this.periodKey,
    required this.periodStart,
    required this.periodEnd,
    required this.settlementDate,
    required this.engineVersion,
    required this.averageWorkers,
    required this.staffSnapshots,
    this.auditLogs = const [],
    this.pdfUrl,
    this.pdfSha256,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'storeId': storeId,
    'periodKey': periodKey,
    'periodStart': periodStart.toIso8601String(),
    'periodEnd': periodEnd.toIso8601String(),
    'settlementDate': settlementDate.toIso8601String(),
    'engineVersion': engineVersion,
    'averageWorkers': averageWorkers,
    'staffSnapshots': staffSnapshots,
    'auditLogs': auditLogs,
    if (pdfUrl != null) 'pdfUrl': pdfUrl,
    if (pdfSha256 != null) 'pdfSha256': pdfSha256,
  };

  factory PayrollSettlement.fromJson(Map<String, dynamic> json, {String? id}) {
    return PayrollSettlement(
      id: json['id'] ?? id ?? '',
      storeId: json['storeId'] ?? '',
      periodKey: json['periodKey'] ?? '',
      periodStart: _parseDate(json['periodStart']) ?? DateTime.now(),
      periodEnd: _parseDate(json['periodEnd']) ?? DateTime.now(),
      settlementDate: _parseDate(json['settlementDate']) ?? DateTime.now(),
      engineVersion: json['engineVersion'] ?? '2.1.0',
      averageWorkers: (json['averageWorkers'] as num?)?.toDouble() ?? 0.0,
      staffSnapshots: json['staffSnapshots'] as Map<String, dynamic>? ?? {},
      auditLogs: (json['auditLogs'] as List<dynamic>?)
              ?.map((e) => e as Map<String, dynamic>)
              .toList() ??
          [],
      pdfUrl: json['pdfUrl'],
      pdfSha256: json['pdfSha256'],
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
