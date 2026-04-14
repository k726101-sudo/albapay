// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'schedule_override.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ScheduleOverrideAdapter extends TypeAdapter<ScheduleOverride> {
  @override
  final int typeId = 3;

  @override
  ScheduleOverride read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ScheduleOverride(
      workerId: fields[0] as String,
      date: fields[1] as String,
      checkIn: fields[2] as String?,
      checkOut: fields[3] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, ScheduleOverride obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.workerId)
      ..writeByte(1)
      ..write(obj.date)
      ..writeByte(2)
      ..write(obj.checkIn)
      ..writeByte(3)
      ..write(obj.checkOut);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScheduleOverrideAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
