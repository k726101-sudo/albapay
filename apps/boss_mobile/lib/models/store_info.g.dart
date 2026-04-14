// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'store_info.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class StoreInfoAdapter extends TypeAdapter<StoreInfo> {
  @override
  final int typeId = 1;

  @override
  StoreInfo read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return StoreInfo(
      storeName: fields[0] as String,
      ownerName: fields[1] as String,
      address: fields[2] as String,
      phone: fields[3] as String,
      businessNumber: fields[4] as String,
      businessType: fields[5] as String,
      accidentRate: fields[6] as double,
      useQr: fields[8] as bool,
      payDay: fields[9] as int,
      payPeriodStartDay: fields[10] as int,
      payPeriodEndDay: fields[11] as int,
      isDuruNuri: fields[12] as bool,
      duruNuriMonths: fields[13] as int,
      isRegistered: fields[14] as bool,
      legacyGpsRadiusUnused: fields[7] as double,
      attendanceGracePeriodMinutes: fields[15] as int,
      isFiveOrMore: fields[16] as bool,
      isFiveOrMoreCalculatedValue: fields[17] as bool,
      isFiveOrMoreChangeReason: fields[18] as String,
      branchCode: fields[19] as String,
    );
  }

  @override
  void write(BinaryWriter writer, StoreInfo obj) {
    writer
      ..writeByte(20)
      ..writeByte(0)
      ..write(obj.storeName)
      ..writeByte(1)
      ..write(obj.ownerName)
      ..writeByte(2)
      ..write(obj.address)
      ..writeByte(3)
      ..write(obj.phone)
      ..writeByte(4)
      ..write(obj.businessNumber)
      ..writeByte(5)
      ..write(obj.businessType)
      ..writeByte(6)
      ..write(obj.accidentRate)
      ..writeByte(7)
      ..write(obj.legacyGpsRadiusUnused)
      ..writeByte(8)
      ..write(obj.useQr)
      ..writeByte(9)
      ..write(obj.payDay)
      ..writeByte(10)
      ..write(obj.payPeriodStartDay)
      ..writeByte(11)
      ..write(obj.payPeriodEndDay)
      ..writeByte(12)
      ..write(obj.isDuruNuri)
      ..writeByte(13)
      ..write(obj.duruNuriMonths)
      ..writeByte(14)
      ..write(obj.isRegistered)
      ..writeByte(15)
      ..write(obj.attendanceGracePeriodMinutes)
      ..writeByte(16)
      ..write(obj.isFiveOrMore)
      ..writeByte(17)
      ..write(obj.isFiveOrMoreCalculatedValue)
      ..writeByte(18)
      ..write(obj.isFiveOrMoreChangeReason)
      ..writeByte(19)
      ..write(obj.branchCode);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StoreInfoAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
