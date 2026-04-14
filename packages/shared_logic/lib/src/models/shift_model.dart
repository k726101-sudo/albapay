class Shift {
  final String id;
  final String staffId;
  final String storeId;
  final DateTime startTime;
  final DateTime endTime;
  final int totalStayMinutes; // 총 체류 시간(분)
  final int breakMinutes; // 휴게 시간(분)
  final bool isPaidBreak; // 휴게 유급 여부
  final String? memo;

  int get pureLaborMinutes {
    final v = totalStayMinutes - breakMinutes;
    return v > 0 ? v : 0;
  }

  Shift({
    required this.id,
    required this.staffId,
    required this.storeId,
    required this.startTime,
    required this.endTime,
    this.totalStayMinutes = 0,
    this.breakMinutes = 0,
    this.isPaidBreak = false,
    this.memo,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'staffId': staffId,
        'storeId': storeId,
        'startTime': startTime.toIso8601String(),
        'endTime': endTime.toIso8601String(),
        'totalStayMinutes': totalStayMinutes,
        'breakMinutes': breakMinutes,
        'isPaidBreak': isPaidBreak,
        'pureLaborMinutes': pureLaborMinutes,
        'memo': memo,
      };

  factory Shift.fromJson(Map<String, dynamic> json) => Shift(
        id: json['id'],
        staffId: json['staffId'],
        storeId: json['storeId'],
        startTime: DateTime.parse(json['startTime']),
        endTime: DateTime.parse(json['endTime']),
        totalStayMinutes: (json['totalStayMinutes'] is num)
            ? (json['totalStayMinutes'] as num).toInt()
            : 0,
        breakMinutes:
            (json['breakMinutes'] is num) ? (json['breakMinutes'] as num).toInt() : 0,
        isPaidBreak: json['isPaidBreak'] == true,
        memo: json['memo'],
      );
}
