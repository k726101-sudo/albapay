import 'package:hive/hive.dart';

part 'store_info.g.dart';

@HiveType(typeId: 1)
class StoreInfo extends HiveObject {
  StoreInfo({
    this.storeName = '',
    this.ownerName = '',
    this.address = '',
    this.phone = '',
    this.businessNumber = '',
    this.businessType = 'food',
    this.accidentRate = 0.009,
    this.useQr = true,
    this.payDay = 10,
    this.payPeriodStartDay = 16,
    this.payPeriodEndDay = 15,
    this.isDuruNuri = false,
    this.duruNuriMonths = 36,
    this.isRegistered = false,
    this.legacyGpsRadiusUnused = 0,
    this.attendanceGracePeriodMinutes = 5,
    this.isFiveOrMore = false,
    this.isFiveOrMoreCalculatedValue = false,
    this.isFiveOrMoreChangeReason = '',
    this.branchCode = '',
  });

  @HiveField(0)
  String storeName;

  @HiveField(1)
  String ownerName;

  @HiveField(2)
  String address;

  @HiveField(3)
  String phone;

  @HiveField(4)
  String businessNumber;

  @HiveField(5)
  String businessType;

  @HiveField(6)
  double accidentRate;

  /// Reserved legacy field index (was GPS 반경). Not used; kept for Hive binary compatibility.
  @HiveField(7)
  double legacyGpsRadiusUnused;

  @HiveField(8)
  bool useQr;

  @HiveField(9)
  int payDay;

  @HiveField(10)
  int payPeriodStartDay;

  @HiveField(11)
  int payPeriodEndDay;

  @HiveField(12)
  bool isDuruNuri;

  @HiveField(13)
  int duruNuriMonths;

  @HiveField(14)
  bool isRegistered;

  @HiveField(15)
  int attendanceGracePeriodMinutes;

  @HiveField(16)
  bool isFiveOrMore;

  @HiveField(17)
  bool isFiveOrMoreCalculatedValue;

  @HiveField(18)
  String isFiveOrMoreChangeReason;

  @HiveField(19)
  String branchCode;
}
