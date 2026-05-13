class Store {
  final String id;
  final String name;
  final String ownerId;
  final String representativeName;
  final String representativePhoneNumber;
  final String address;
  final double latitude;
  final double longitude;
  final String? wifiSsid;
  final String? wifiBssid;
  final int settlementStartDay;
  final int settlementEndDay;
  final int payday;
  final bool isFiveOrMore; // 5인 이상 사업장 여부 (사장님 수동 설정값)
  final bool isFiveOrMore_CalculatedValue; // 시스템 계산값
  final String isFiveOrMore_ChangeReason; // 변경 사유
  /// 사업장 규모 판정 모드:
  /// 'auto'          – 2단계 자동 판정 (기본값)
  /// 'manual_under5' – 5인 미만 고정
  /// 'manual_5plus'  – 5인 이상 고정
  final String employeeSizeMode;
  final int attendanceGracePeriodMinutes; // 출퇴근 오차 허용 범위 (분)
  final String? branchCode;
  final bool gpsAttendanceEnabled; // GPS 출퇴근 검증 활성화 여부
  final int gpsRadius; // GPS 반경 (미터, 기본 100m)

  Store({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.representativeName,
    required this.representativePhoneNumber,
    required this.address,
    required this.latitude,
    required this.longitude,
    this.wifiSsid,
    this.wifiBssid,
    required this.settlementStartDay,
    required this.settlementEndDay,
    required this.payday,
    this.isFiveOrMore = false,
    this.isFiveOrMore_CalculatedValue = false,
    this.isFiveOrMore_ChangeReason = '',
    this.employeeSizeMode = 'auto',
    this.attendanceGracePeriodMinutes = 5,
    this.branchCode,
    this.gpsAttendanceEnabled = false,
    this.gpsRadius = 100,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'ownerId': ownerId,
    'representativeName': representativeName,
    'representativePhoneNumber': representativePhoneNumber,
    'address': address,
    'latitude': latitude,
    'longitude': longitude,
    'wifiSsid': wifiSsid,
    'wifiBssid': wifiBssid,
    'settlementStartDay': settlementStartDay,
    'settlementEndDay': settlementEndDay,
    'payday': payday,
    'isFiveOrMore': isFiveOrMore,
    'isFiveOrMore_CalculatedValue': isFiveOrMore_CalculatedValue,
    'isFiveOrMore_ChangeReason': isFiveOrMore_ChangeReason,
    'employeeSizeMode': employeeSizeMode,
    'attendanceGracePeriodMinutes': attendanceGracePeriodMinutes,
    'branchCode': branchCode,
    'gpsAttendanceEnabled': gpsAttendanceEnabled,
    'gpsRadius': gpsRadius,
  };

  factory Store.fromJson(Map<String, dynamic> json) => Store(
    id: json['id'],
    name: json['name'],
    ownerId: json['ownerId'],
    representativeName: json['representativeName']?.toString() ?? '',
    representativePhoneNumber:
        json['representativePhoneNumber']?.toString() ?? '',
    address: json['address']?.toString() ?? '',
    latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
    longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
    wifiSsid: json['wifiSsid']?.toString(),
    wifiBssid: json['wifiBssid']?.toString(),
    settlementStartDay: (json['settlementStartDay'] as num?)?.toInt() ?? 1,
    settlementEndDay: (json['settlementEndDay'] as num?)?.toInt() ?? 31,
    payday: (json['payday'] as num?)?.toInt() ?? 1,
    isFiveOrMore: json['isFiveOrMore'] ?? false,
    isFiveOrMore_CalculatedValue: json['isFiveOrMore_CalculatedValue'] ?? false,
    isFiveOrMore_ChangeReason:
        json['isFiveOrMore_ChangeReason']?.toString() ?? '',
    employeeSizeMode: json['employeeSizeMode']?.toString() ?? 'auto',
    attendanceGracePeriodMinutes: json['attendanceGracePeriodMinutes'] ?? 5,
    branchCode: json['branchCode']?.toString(),
    gpsAttendanceEnabled: json['gpsAttendanceEnabled'] ?? false,
    gpsRadius: (json['gpsRadius'] as num?)?.toInt() ?? 100,
  );
}
