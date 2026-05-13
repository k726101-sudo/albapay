enum SubstitutionStatus { pending, approved, rejected, cancelled }

class Substitution {
  final String id;
  final String storeId;
  final String requesterId;
  final String proposerId; // Person who will cover the shift
  final String shiftId; // Original shift ID being replaced
  final DateTime startTime;
  final DateTime endTime;
  final SubstitutionStatus status;
  final bool isSafe; // Whether it passes all legal blocks
  final List<String> warnings; // Legal warnings (e.g., 15h threshold)
  final List<String> errors; // Legal blocks (e.g., 52h limit)

  Substitution({
    required this.id,
    required this.storeId,
    required this.requesterId,
    required this.proposerId,
    required this.shiftId,
    required this.startTime,
    required this.endTime,
    this.status = SubstitutionStatus.pending,
    this.isSafe = true,
    this.warnings = const [],
    this.errors = const [],
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'storeId': storeId,
    'requesterId': requesterId,
    'proposerId': proposerId,
    'shiftId': shiftId,
    'startTime': startTime.toIso8601String(),
    'endTime': endTime.toIso8601String(),
    'status': status.name,
    'isSafe': isSafe,
    'warnings': warnings,
    'errors': errors,
  };

  factory Substitution.fromJson(Map<String, dynamic> json) => Substitution(
    id: json['id'],
    storeId: json['storeId'],
    requesterId: json['requesterId'],
    proposerId: json['proposerId'],
    shiftId: json['shiftId'],
    startTime: DateTime.parse(json['startTime']),
    endTime: DateTime.parse(json['endTime']),
    status: SubstitutionStatus.values.byName(json['status']),
    isSafe: json['isSafe'] ?? true,
    warnings: List<String>.from(json['warnings'] ?? []),
    errors: List<String>.from(json['errors'] ?? []),
  );
}
