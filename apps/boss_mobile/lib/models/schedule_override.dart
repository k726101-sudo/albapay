import 'package:hive/hive.dart';

part 'schedule_override.g.dart';

@HiveType(typeId: 3)
class ScheduleOverride extends HiveObject {
  ScheduleOverride({
    required this.workerId,
    required this.date,
    this.checkIn,
    this.checkOut,
    this.leaveType,
  });

  @HiveField(0)
  String workerId;
  @HiveField(1)
  String date;
  @HiveField(2)
  String? checkIn;
  @HiveField(3)
  String? checkOut;
  /// null=일반, 'annual_leave'=연차, 'sick_leave'=병가
  @HiveField(4)
  String? leaveType;

  bool get isAnnualLeave => leaveType == 'annual_leave';
}
