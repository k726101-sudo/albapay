import 'package:hive/hive.dart';

part 'schedule_override.g.dart';

@HiveType(typeId: 3)
class ScheduleOverride extends HiveObject {
  ScheduleOverride({
    required this.workerId,
    required this.date,
    this.checkIn,
    this.checkOut,
  });

  @HiveField(0)
  String workerId;
  @HiveField(1)
  String date;
  @HiveField(2)
  String? checkIn;
  @HiveField(3)
  String? checkOut;
}
