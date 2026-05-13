// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'worker.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class WorkerAdapter extends TypeAdapter<Worker> {
  @override
  final int typeId = 2;

  @override
  Worker read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Worker(
      id: fields[0] as String,
      name: fields[1] as String,
      phone: fields[2] as String,
      birthDate: fields[3] as String,
      workerType: fields[4] as String,
      hourlyWage: fields[5] as double,
      isPaidBreak: fields[6] as bool,
      breakMinutes: fields[7] as double,
      workDays: (fields[8] as List).cast<int>(),
      checkInTime: fields[9] as String,
      checkOutTime: fields[10] as String,
      weeklyHours: fields[11] as double,
      startDate: fields[12] as String,
      joinDate: fields[43] == null ? '' : fields[43] as String,
      endDate: fields[13] as String?,
      isProbation: fields[14] as bool,
      probationMonths: fields[15] as int,
      allowances: (fields[16] as List).cast<Allowance>(),
      hasHealthCert: fields[17] as bool,
      healthCertExpiry: fields[18] as String?,
      visaType: fields[19] as String?,
      visaExpiry: fields[20] as String?,
      weeklyHolidayPay: fields[21] as bool,
      status: fields[22] as String,
      createdAt: fields[23] as String,
      firebaseId: fields[24] as String?,
      compensationIncomeType:
          fields[25] == null ? 'labor' : fields[25] as String,
      deductNationalPension: fields[26] == null ? true : fields[26] as bool,
      deductHealthInsurance: fields[27] == null ? true : fields[27] as bool,
      deductEmploymentInsurance: fields[28] == null ? true : fields[28] as bool,
      trackIndustrialInsurance: fields[29] == null ? false : fields[29] as bool,
      applyWithholding33: fields[30] == null ? false : fields[30] as bool,
      workScheduleJson: fields[31] == null ? '' : fields[31] as String,
      breakStartTime: fields[32] == null ? '' : fields[32] as String,
      breakEndTime: fields[33] == null ? '' : fields[33] as String,
      dispatchCompany: fields[34] as String?,
      dispatchContact: fields[35] as String?,
      dispatchStartDate: fields[36] as String?,
      dispatchEndDate: fields[37] as String?,
      dispatchMemo: fields[38] as String?,
      documentsInitialized: fields[39] == null ? false : fields[39] as bool,
      weeklyHolidayDay: fields[40] == null ? 0 : fields[40] as int,
      totalStayMinutes: fields[41] == null ? 0 : fields[41] as int,
      pureLaborMinutes: fields[42] == null ? 0 : fields[42] as int,
      specialExtensionAuthorizedAt: fields[44] as String?,
      specialExtensionReason: fields[45] as String?,
      usedAnnualLeave: fields[46] == null ? 0.0 : fields[46] as double,
      annualLeaveManualAdjustment:
          fields[48] == null ? 0.0 : fields[48] as double,
      annualLeaveInitialAdjustment:
          fields[53] == null ? 0.0 : fields[53] as double,
      annualLeaveInitialAdjustmentReason:
          fields[54] == null ? '' : fields[54] as String,
      leaveUsageLogs:
          fields[47] == null ? [] : (fields[47] as List).cast<LeaveUsageLog>(),
      inviteCode: fields[49] as String?,
      previousMonthAdjustment: fields[50] == null ? 0.0 : fields[50] as double,
      manualAverageDailyWage: fields[51] == null ? 0.0 : fields[51] as double,
      employeeId: fields[52] as String?,
      leavePromotionLogsJson: fields[55] == null ? '' : fields[55] as String,
      wageType: fields[56] == null ? 'hourly' : fields[56] as String,
      monthlyWage: fields[57] == null ? 0.0 : fields[57] as double,
      fixedOvertimeHours: fields[58] == null ? 0.0 : fields[58] as double,
      fixedOvertimePay: fields[59] == null ? 0.0 : fields[59] as double,
      mealTaxExempt: fields[60] == null ? false : fields[60] as bool,
      isPaperContract: fields[61] == null ? false : fields[61] as bool,
      wageHistoryJson: fields[62] == null ? '' : fields[62] as String,
      includeMealInOrdinary: fields[63] == null ? true : fields[63] as bool,
      includeAllowanceInOrdinary:
          fields[64] == null ? false : fields[64] as bool,
      includeFixedOtInAverage: fields[65] == null ? false : fields[65] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, Worker obj) {
    writer
      ..writeByte(66)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.phone)
      ..writeByte(3)
      ..write(obj.birthDate)
      ..writeByte(4)
      ..write(obj.workerType)
      ..writeByte(5)
      ..write(obj.hourlyWage)
      ..writeByte(6)
      ..write(obj.isPaidBreak)
      ..writeByte(7)
      ..write(obj.breakMinutes)
      ..writeByte(8)
      ..write(obj.workDays)
      ..writeByte(9)
      ..write(obj.checkInTime)
      ..writeByte(10)
      ..write(obj.checkOutTime)
      ..writeByte(11)
      ..write(obj.weeklyHours)
      ..writeByte(12)
      ..write(obj.startDate)
      ..writeByte(43)
      ..write(obj.joinDate)
      ..writeByte(13)
      ..write(obj.endDate)
      ..writeByte(14)
      ..write(obj.isProbation)
      ..writeByte(15)
      ..write(obj.probationMonths)
      ..writeByte(16)
      ..write(obj.allowances)
      ..writeByte(17)
      ..write(obj.hasHealthCert)
      ..writeByte(18)
      ..write(obj.healthCertExpiry)
      ..writeByte(19)
      ..write(obj.visaType)
      ..writeByte(20)
      ..write(obj.visaExpiry)
      ..writeByte(21)
      ..write(obj.weeklyHolidayPay)
      ..writeByte(22)
      ..write(obj.status)
      ..writeByte(23)
      ..write(obj.createdAt)
      ..writeByte(24)
      ..write(obj.firebaseId)
      ..writeByte(25)
      ..write(obj.compensationIncomeType)
      ..writeByte(26)
      ..write(obj.deductNationalPension)
      ..writeByte(27)
      ..write(obj.deductHealthInsurance)
      ..writeByte(28)
      ..write(obj.deductEmploymentInsurance)
      ..writeByte(29)
      ..write(obj.trackIndustrialInsurance)
      ..writeByte(30)
      ..write(obj.applyWithholding33)
      ..writeByte(31)
      ..write(obj.workScheduleJson)
      ..writeByte(32)
      ..write(obj.breakStartTime)
      ..writeByte(33)
      ..write(obj.breakEndTime)
      ..writeByte(34)
      ..write(obj.dispatchCompany)
      ..writeByte(35)
      ..write(obj.dispatchContact)
      ..writeByte(36)
      ..write(obj.dispatchStartDate)
      ..writeByte(37)
      ..write(obj.dispatchEndDate)
      ..writeByte(38)
      ..write(obj.dispatchMemo)
      ..writeByte(39)
      ..write(obj.documentsInitialized)
      ..writeByte(40)
      ..write(obj.weeklyHolidayDay)
      ..writeByte(41)
      ..write(obj.totalStayMinutes)
      ..writeByte(42)
      ..write(obj.pureLaborMinutes)
      ..writeByte(44)
      ..write(obj.specialExtensionAuthorizedAt)
      ..writeByte(45)
      ..write(obj.specialExtensionReason)
      ..writeByte(46)
      ..write(obj.usedAnnualLeave)
      ..writeByte(47)
      ..write(obj.leaveUsageLogs)
      ..writeByte(48)
      ..write(obj.annualLeaveManualAdjustment)
      ..writeByte(53)
      ..write(obj.annualLeaveInitialAdjustment)
      ..writeByte(54)
      ..write(obj.annualLeaveInitialAdjustmentReason)
      ..writeByte(49)
      ..write(obj.inviteCode)
      ..writeByte(50)
      ..write(obj.previousMonthAdjustment)
      ..writeByte(51)
      ..write(obj.manualAverageDailyWage)
      ..writeByte(52)
      ..write(obj.employeeId)
      ..writeByte(55)
      ..write(obj.leavePromotionLogsJson)
      ..writeByte(56)
      ..write(obj.wageType)
      ..writeByte(57)
      ..write(obj.monthlyWage)
      ..writeByte(58)
      ..write(obj.fixedOvertimeHours)
      ..writeByte(59)
      ..write(obj.fixedOvertimePay)
      ..writeByte(60)
      ..write(obj.mealTaxExempt)
      ..writeByte(61)
      ..write(obj.isPaperContract)
      ..writeByte(62)
      ..write(obj.wageHistoryJson)
      ..writeByte(63)
      ..write(obj.includeMealInOrdinary)
      ..writeByte(64)
      ..write(obj.includeAllowanceInOrdinary)
      ..writeByte(65)
      ..write(obj.includeFixedOtInAverage);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkerAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class AllowanceAdapter extends TypeAdapter<Allowance> {
  @override
  final int typeId = 4;

  @override
  Allowance read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Allowance(
      label: fields[0] as String,
      amount: fields[1] as double,
    );
  }

  @override
  void write(BinaryWriter writer, Allowance obj) {
    writer
      ..writeByte(2)
      ..writeByte(0)
      ..write(obj.label)
      ..writeByte(1)
      ..write(obj.amount);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AllowanceAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class LeaveUsageLogAdapter extends TypeAdapter<LeaveUsageLog> {
  @override
  final int typeId = 5;

  @override
  LeaveUsageLog read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return LeaveUsageLog(
      id: fields[0] as String,
      usedDays: fields[1] as double,
      reason: fields[2] as String,
      createdAtIso: fields[3] as String,
    );
  }

  @override
  void write(BinaryWriter writer, LeaveUsageLog obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.usedDays)
      ..writeByte(2)
      ..write(obj.reason)
      ..writeByte(3)
      ..write(obj.createdAtIso);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LeaveUsageLogAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
