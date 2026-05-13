import 'package:hive/hive.dart';
import 'package:shared_logic/shared_logic.dart';

part 'worker.g.dart';

@HiveType(typeId: 2)
class Worker extends HiveObject {
  Worker({
    required this.id,
    required this.name,
    required this.phone,
    required this.birthDate,
    required this.workerType,
    required this.hourlyWage,
    required this.isPaidBreak,
    required this.breakMinutes,
    required this.workDays,
    required this.checkInTime,
    required this.checkOutTime,
    required this.weeklyHours,
    required this.startDate,
    this.joinDate = '',
    this.endDate,
    required this.isProbation,
    required this.probationMonths,
    required this.allowances,
    required this.hasHealthCert,
    this.healthCertExpiry,
    this.visaType,
    this.visaExpiry,
    required this.weeklyHolidayPay,
    required this.status,
    required this.createdAt,
    this.storeId = '',
    this.firebaseId,
    this.compensationIncomeType = 'labor',
    this.deductNationalPension = true,
    this.deductHealthInsurance = true,
    this.deductEmploymentInsurance = true,
    this.trackIndustrialInsurance = false,
    this.applyWithholding33 = false,
    this.workScheduleJson = '',
    this.breakStartTime = '',
    this.breakEndTime = '',
    this.dispatchCompany,
    this.dispatchContact,
    this.dispatchStartDate,
    this.dispatchEndDate,
    this.dispatchMemo,
    this.documentsInitialized = false,
    this.weeklyHolidayDay = 0,
    this.totalStayMinutes = 0,
    this.pureLaborMinutes = 0,
    this.specialExtensionAuthorizedAt,
    this.specialExtensionReason,
    this.usedAnnualLeave = 0.0,
    this.annualLeaveManualAdjustment = 0.0,
    this.annualLeaveInitialAdjustment = 0.0,
    this.annualLeaveInitialAdjustmentReason = '',
    this.leaveUsageLogs = const [],
    this.inviteCode,
    this.previousMonthAdjustment = 0.0,
    this.manualAverageDailyWage = 0.0,
    this.employeeId,
    this.leavePromotionLogsJson = '',
    this.wageType = 'hourly',
    this.monthlyWage = 0.0,
    this.fixedOvertimeHours = 0.0,
    this.fixedOvertimePay = 0.0,
    this.mealTaxExempt = false,
    this.isPaperContract = false,
    this.wageHistoryJson = '',
  });

  @HiveField(0)
  String id;
  @HiveField(1)
  String name;
  @HiveField(2)
  String phone;
  @HiveField(3)
  String birthDate;
  @HiveField(4)
  String workerType;
  @HiveField(5)
  double hourlyWage;
  @HiveField(6)
  bool isPaidBreak;
  @HiveField(7)
  double breakMinutes;
  @HiveField(8)
  List<int> workDays;
  @HiveField(9)
  String checkInTime;
  @HiveField(10)
  String checkOutTime;
  @HiveField(11)
  double weeklyHours;
  @HiveField(12)
  String startDate;
  @HiveField(43, defaultValue: '')
  String joinDate;
  @HiveField(13)
  String? endDate;
  @HiveField(14)
  bool isProbation;
  @HiveField(15)
  int probationMonths;
  @HiveField(16)
  List<Allowance> allowances;
  @HiveField(17)
  bool hasHealthCert;
  @HiveField(18)
  String? healthCertExpiry;
  @HiveField(19)
  String? visaType;
  @HiveField(20)
  String? visaExpiry;
  @HiveField(21)
  bool weeklyHolidayPay;
  @HiveField(22)
  String status;
  @HiveField(23)
  String createdAt;

  @HiveField(24)
  String? firebaseId;

  String storeId;

  /// `labor`(근로소득) | `business_income_33`(사업소득 3.3%)
  @HiveField(25, defaultValue: 'labor')
  String compensationIncomeType;

  @HiveField(26, defaultValue: true)
  bool deductNationalPension;

  @HiveField(27, defaultValue: true)
  bool deductHealthInsurance;

  @HiveField(28, defaultValue: true)
  bool deductEmploymentInsurance;

  /// 산재는 통상 근로자 부담 없음(사업주 전액). 명세·인건비 관리용 체크
  @HiveField(29, defaultValue: false)
  bool trackIndustrialInsurance;

  @HiveField(30, defaultValue: false)
  bool applyWithholding33;

  /// 요일별 근무시간(JSON). `[{"days":[1,2,3],"start":"07:00","end":"12:00"},...]` (일=0 … 토=6)
  @HiveField(31, defaultValue: '')
  String workScheduleJson;

  @HiveField(32, defaultValue: '')
  String breakStartTime;

  @HiveField(33, defaultValue: '')
  String breakEndTime;

  @HiveField(34)
  String? dispatchCompany;

  @HiveField(35)
  String? dispatchContact;

  @HiveField(36)
  String? dispatchStartDate;

  @HiveField(37)
  String? dispatchEndDate;

  @HiveField(38)
  String? dispatchMemo;

  @HiveField(39, defaultValue: false)
  bool documentsInitialized;

  /// 주휴일 요일 (일=0 ... 토=6)
  @HiveField(40, defaultValue: 0)
  int weeklyHolidayDay;

  /// 주간 총 체류 시간(분)
  @HiveField(41, defaultValue: 0)
  int totalStayMinutes;

  /// 주간 순수 근로 시간(분) = totalStayMinutes - (휴게시간 합)
  @HiveField(42, defaultValue: 0)
  int pureLaborMinutes;

  /// 특별연장근로 승인 일자 (ISO String)
  @HiveField(44)
  String? specialExtensionAuthorizedAt;

  /// 특별연장근로 사유
  @HiveField(45)
  String? specialExtensionReason;

  /// 총 사용 연차 장부
  @HiveField(46, defaultValue: 0.0)
  double usedAnnualLeave;

  /// 연차 사용 내역 (3년 보관)
  @HiveField(47, defaultValue: [])
  List<LeaveUsageLog> leaveUsageLogs;

  /// 사장님이 수동으로 가감한 연차 개수 (Override)
  @HiveField(48, defaultValue: 0.0)
  double annualLeaveManualAdjustment;

  /// 앱 도입 이전 기초 연차 개수 (사장님 수동 입력)
  @HiveField(53, defaultValue: 0.0)
  double annualLeaveInitialAdjustment;

  /// 기초 연차 수정 사유 로그
  @HiveField(54, defaultValue: '')
  String annualLeaveInitialAdjustmentReason;

  @HiveField(49)
  String? inviteCode;

  @HiveField(50, defaultValue: 0.0)
  double previousMonthAdjustment;
  @HiveField(51, defaultValue: 0.0)
  double manualAverageDailyWage;
  @HiveField(52)
  String? employeeId;

  /// 연차 사용촉진 로그 (JSON 직렬화 저장)
  @HiveField(55, defaultValue: '')
  String leavePromotionLogsJson;

  /// 급여 형태: 'hourly' | 'monthly'
  @HiveField(56, defaultValue: 'hourly')
  String wageType;

  /// 월급 총액 (월급제일 때만 사용)
  @HiveField(57, defaultValue: 0.0)
  double monthlyWage;

  /// 포괄임금제: 고정 연장근로시간 (시간 단위)
  @HiveField(58, defaultValue: 0.0)
  double fixedOvertimeHours;

  /// 포괄임금제: 고정 연장수당 (원 단위, 시스템 자동 역산)
  @HiveField(59, defaultValue: 0.0)
  double fixedOvertimePay;

  /// 식대 비과세 적용 여부 (사장님 선택)
  @HiveField(60, defaultValue: false)
  bool mealTaxExempt;

  /// 서면 계약 완료 여부
  @HiveField(61, defaultValue: false)
  bool isPaperContract;

  /// 시급 변경 이력 (JSON 직렬화 저장). `[{"effectiveDate":"2026-01-01","hourlyWage":10320},...]`
  @HiveField(62, defaultValue: '')
  String wageHistoryJson;

  Map<String, dynamic> toMap() => {
        'name': name,
        'phone': phone,
        'birthDate': birthDate,
        'workerType': workerType,
        'hourlyWage': hourlyWage,
        'isPaidBreak': isPaidBreak,
        'breakMinutes': breakMinutes,
        'workDays': workDays,
        'checkInTime': checkInTime,
        'checkOutTime': checkOutTime,
        'weeklyHours': weeklyHours,
        'startDate': startDate,
        'joinDate': joinDate,
        'endDate': endDate,
        'isProbation': isProbation,
        'probationMonths': probationMonths,
        'allowances': allowances.map((a) => a.toMap()).toList(),
        'hasHealthCert': hasHealthCert,
        'healthCertExpiry': healthCertExpiry,
        'visaType': visaType,
        'visaExpiry': visaExpiry,
        'weeklyHolidayPay': weeklyHolidayPay,
        'status': status,
        'createdAt': createdAt,
        if (storeId.isNotEmpty) 'storeId': storeId,
        'compensationIncomeType': compensationIncomeType,
        'deductNationalPension': deductNationalPension,
        'deductHealthInsurance': deductHealthInsurance,
        'deductEmploymentInsurance': deductEmploymentInsurance,
        'trackIndustrialInsurance': trackIndustrialInsurance,
        'applyWithholding33': applyWithholding33,
        'workScheduleJson': workScheduleJson,
        'breakStartTime': breakStartTime,
        'breakEndTime': breakEndTime,
        'dispatchCompany': dispatchCompany,
        'dispatchContact': dispatchContact,
        'dispatchStartDate': dispatchStartDate,
        'dispatchEndDate': dispatchEndDate,
        'dispatchMemo': dispatchMemo,
        'documentsInitialized': documentsInitialized,
        'weeklyHolidayDay': weeklyHolidayDay,
        'totalStayMinutes': totalStayMinutes,
        'pureLaborMinutes': pureLaborMinutes,
        'specialExtensionAuthorizedAt': specialExtensionAuthorizedAt,
        'specialExtensionReason': specialExtensionReason,
        'usedAnnualLeave': usedAnnualLeave,
        'annualLeaveManualAdjustment': annualLeaveManualAdjustment,
        'annualLeaveInitialAdjustment': annualLeaveInitialAdjustment,
        'annualLeaveInitialAdjustmentReason': annualLeaveInitialAdjustmentReason,
        'leaveUsageLogs': leaveUsageLogs.map((l) => l.toMap()).toList(),
        if (inviteCode != null) 'inviteCode': inviteCode,
        'previousMonthAdjustment': previousMonthAdjustment,
        'manualAverageDailyWage': manualAverageDailyWage,
        if (employeeId != null) 'employeeId': employeeId,
        'leavePromotionLogsJson': leavePromotionLogsJson,
        'wageType': wageType,
        'monthlyWage': monthlyWage,
        'fixedOvertimeHours': fixedOvertimeHours,
        'fixedOvertimePay': fixedOvertimePay,
        'mealTaxExempt': mealTaxExempt,
        'isPaperContract': isPaperContract,
        'wageHistoryJson': wageHistoryJson,
      };

  factory Worker.fromMap(String id, Map<String, dynamic> map) => Worker(
        id: id,
        name: map['name']?.toString() ?? '',
        phone: map['phone']?.toString() ?? '',
        birthDate: map['birthDate']?.toString() ?? '',
        workerType: map['workerType']?.toString() ?? 'regular',
        hourlyWage: (map['hourlyWage'] as num?)?.toDouble() ?? 0,
        isPaidBreak: map['isPaidBreak'] == true,
        breakMinutes: (map['breakMinutes'] as num?)?.toDouble() ?? 0,
        workDays: (map['workDays'] as List?)
                ?.map((e) => e is num ? e.toInt() : int.tryParse(e.toString()) ?? 0)
                .toList() ??
            const [],
        checkInTime: map['checkInTime']?.toString() ?? '09:00',
        checkOutTime: map['checkOutTime']?.toString() ?? '18:00',
        weeklyHours: (map['weeklyHours'] as num?)?.toDouble() ?? 0,
        startDate: map['startDate']?.toString() ?? '',
        joinDate: map['joinDate']?.toString() ?? map['startDate']?.toString() ?? '',
        endDate: map['endDate']?.toString(),
        isProbation: map['isProbation'] == true,
        probationMonths: (map['probationMonths'] as num?)?.toInt() ?? 0,
        allowances: (map['allowances'] as List?)
                ?.map((e) => Allowance.fromMap((e as Map).cast<String, dynamic>()))
                .toList() ??
            const [],
        hasHealthCert: map['hasHealthCert'] == true,
        healthCertExpiry: map['healthCertExpiry']?.toString(),
        visaType: map['visaType']?.toString(),
        visaExpiry: map['visaExpiry']?.toString(),
        weeklyHolidayPay: map['weeklyHolidayPay'] != false,
        status: map['status']?.toString() ?? 'active',
        createdAt: map['createdAt']?.toString() ?? AppClock.now().toIso8601String(),
        storeId: map['storeId']?.toString() ?? '',
        firebaseId: id,
        compensationIncomeType: map['compensationIncomeType']?.toString() ?? 'labor',
        deductNationalPension: map['deductNationalPension'] != false,
        deductHealthInsurance: map['deductHealthInsurance'] != false,
        deductEmploymentInsurance: map['deductEmploymentInsurance'] != false,
        trackIndustrialInsurance: map['trackIndustrialInsurance'] == true,
        applyWithholding33: map['applyWithholding33'] == true,
        workScheduleJson: map['workScheduleJson']?.toString() ?? '',
        breakStartTime: map['breakStartTime']?.toString() ?? '',
        breakEndTime: map['breakEndTime']?.toString() ?? '',
        dispatchCompany: map['dispatchCompany']?.toString(),
        dispatchContact: map['dispatchContact']?.toString(),
        dispatchStartDate: map['dispatchStartDate']?.toString(),
        dispatchEndDate: map['dispatchEndDate']?.toString(),
        dispatchMemo: map['dispatchMemo']?.toString(),
        documentsInitialized: map['documentsInitialized'] == true,
        weeklyHolidayDay: (map['weeklyHolidayDay'] is num)
            ? (map['weeklyHolidayDay'] as num).toInt()
            : int.tryParse(map['weeklyHolidayDay']?.toString() ?? '') ?? 0,
        totalStayMinutes: (map['totalStayMinutes'] is num)
            ? (map['totalStayMinutes'] as num).toInt()
            : int.tryParse(map['totalStayMinutes']?.toString() ?? '') ?? 0,
        pureLaborMinutes: (map['pureLaborMinutes'] is num)
            ? (map['pureLaborMinutes'] as num).toInt()
            : int.tryParse(map['pureLaborMinutes']?.toString() ?? '') ?? 0,
        specialExtensionAuthorizedAt: map['specialExtensionAuthorizedAt']?.toString(),
        specialExtensionReason: map['specialExtensionReason']?.toString(),
        usedAnnualLeave: (map['usedAnnualLeave'] as num?)?.toDouble() ?? 0.0,
        annualLeaveManualAdjustment: (map['annualLeaveManualAdjustment'] as num?)?.toDouble() ?? 0.0,
        annualLeaveInitialAdjustment: (map['annualLeaveInitialAdjustment'] as num?)?.toDouble() ?? 0.0,
        annualLeaveInitialAdjustmentReason: map['annualLeaveInitialAdjustmentReason']?.toString() ?? '',
        leaveUsageLogs: (map['leaveUsageLogs'] as List?)
                ?.map((e) => LeaveUsageLog.fromMap((e as Map).cast<String, dynamic>()))
                .toList() ??
            const [],
        inviteCode: map['inviteCode']?.toString() ?? map['invite_code']?.toString(),
        previousMonthAdjustment: (map['previousMonthAdjustment'] as num?)?.toDouble() ?? 0.0,
        manualAverageDailyWage: (map['manualAverageDailyWage'] as num?)?.toDouble() ?? 0.0,
        employeeId: map['employeeId']?.toString(),
        leavePromotionLogsJson: map['leavePromotionLogsJson']?.toString() ?? '',
        wageType: map['wageType']?.toString() ?? 'hourly',
        monthlyWage: (map['monthlyWage'] as num?)?.toDouble() ?? 0.0,
        fixedOvertimeHours: (map['fixedOvertimeHours'] as num?)?.toDouble() ?? 0.0,
        fixedOvertimePay: (map['fixedOvertimePay'] as num?)?.toDouble() ?? 0.0,
        mealTaxExempt: map['mealTaxExempt'] as bool? ?? false,
        isPaperContract: map['isPaperContract'] == true,
        wageHistoryJson: map['wageHistoryJson']?.toString() ?? '',
      );

  Worker copyWith({
    String? id,
    String? name,
    String? phone,
    String? birthDate,
    String? workerType,
    double? hourlyWage,
    bool? isPaidBreak,
    double? breakMinutes,
    List<int>? workDays,
    String? checkInTime,
    String? checkOutTime,
    double? weeklyHours,
    String? startDate,
    String? joinDate,
    String? endDate,
    bool? isProbation,
    int? probationMonths,
    List<Allowance>? allowances,
    bool? hasHealthCert,
    String? healthCertExpiry,
    String? visaType,
    String? visaExpiry,
    bool? weeklyHolidayPay,
    String? status,
    String? createdAt,
    String? storeId,
    String? firebaseId,
    String? compensationIncomeType,
    bool? deductNationalPension,
    bool? deductHealthInsurance,
    bool? deductEmploymentInsurance,
    bool? trackIndustrialInsurance,
    bool? applyWithholding33,
    String? workScheduleJson,
    String? breakStartTime,
    String? breakEndTime,
    String? dispatchCompany,
    String? dispatchContact,
    String? dispatchStartDate,
    String? dispatchEndDate,
    String? dispatchMemo,
    bool? documentsInitialized,
    int? weeklyHolidayDay,
    int? totalStayMinutes,
    int? pureLaborMinutes,
    String? specialExtensionAuthorizedAt,
    String? specialExtensionReason,
    double? usedAnnualLeave,
    double? annualLeaveManualAdjustment,
    double? annualLeaveInitialAdjustment,
    String? annualLeaveInitialAdjustmentReason,
    List<LeaveUsageLog>? leaveUsageLogs,
    String? inviteCode,
    double? previousMonthAdjustment,
    double? manualAverageDailyWage,
    String? employeeId,
    String? leavePromotionLogsJson,
    String? wageType,
    double? monthlyWage,
    double? fixedOvertimeHours,
    double? fixedOvertimePay,
    bool? mealTaxExempt,
    bool? isPaperContract,
    String? wageHistoryJson,
  }) =>
      Worker(
        id: id ?? this.id,
        name: name ?? this.name,
        phone: phone ?? this.phone,
        birthDate: birthDate ?? this.birthDate,
        workerType: workerType ?? this.workerType,
        hourlyWage: hourlyWage ?? this.hourlyWage,
        isPaidBreak: isPaidBreak ?? this.isPaidBreak,
        breakMinutes: breakMinutes ?? this.breakMinutes,
        workDays: workDays ?? this.workDays,
        checkInTime: checkInTime ?? this.checkInTime,
        checkOutTime: checkOutTime ?? this.checkOutTime,
        weeklyHours: weeklyHours ?? this.weeklyHours,
        startDate: startDate ?? this.startDate,
        joinDate: joinDate ?? this.joinDate,
        endDate: endDate ?? this.endDate,
        isProbation: isProbation ?? this.isProbation,
        probationMonths: probationMonths ?? this.probationMonths,
        allowances: allowances ?? this.allowances,
        hasHealthCert: hasHealthCert ?? this.hasHealthCert,
        healthCertExpiry: healthCertExpiry ?? this.healthCertExpiry,
        visaType: visaType ?? this.visaType,
        visaExpiry: visaExpiry ?? this.visaExpiry,
        weeklyHolidayPay: weeklyHolidayPay ?? this.weeklyHolidayPay,
        status: status ?? this.status,
        createdAt: createdAt ?? this.createdAt,
        storeId: storeId ?? this.storeId,
        firebaseId: firebaseId ?? this.firebaseId,
        compensationIncomeType: compensationIncomeType ?? this.compensationIncomeType,
        deductNationalPension: deductNationalPension ?? this.deductNationalPension,
        deductHealthInsurance: deductHealthInsurance ?? this.deductHealthInsurance,
        deductEmploymentInsurance: deductEmploymentInsurance ?? this.deductEmploymentInsurance,
        trackIndustrialInsurance: trackIndustrialInsurance ?? this.trackIndustrialInsurance,
        applyWithholding33: applyWithholding33 ?? this.applyWithholding33,
        workScheduleJson: workScheduleJson ?? this.workScheduleJson,
        breakStartTime: breakStartTime ?? this.breakStartTime,
        breakEndTime: breakEndTime ?? this.breakEndTime,
        dispatchCompany: dispatchCompany ?? this.dispatchCompany,
        dispatchContact: dispatchContact ?? this.dispatchContact,
        dispatchStartDate: dispatchStartDate ?? this.dispatchStartDate,
        dispatchEndDate: dispatchEndDate ?? this.dispatchEndDate,
        dispatchMemo: dispatchMemo ?? this.dispatchMemo,
        documentsInitialized: documentsInitialized ?? this.documentsInitialized,
        weeklyHolidayDay: weeklyHolidayDay ?? this.weeklyHolidayDay,
        totalStayMinutes: totalStayMinutes ?? this.totalStayMinutes,
        pureLaborMinutes: pureLaborMinutes ?? this.pureLaborMinutes,
        specialExtensionAuthorizedAt: specialExtensionAuthorizedAt ?? this.specialExtensionAuthorizedAt,
        specialExtensionReason: specialExtensionReason ?? this.specialExtensionReason,
        usedAnnualLeave: usedAnnualLeave ?? this.usedAnnualLeave,
        annualLeaveManualAdjustment: annualLeaveManualAdjustment ?? this.annualLeaveManualAdjustment,
        annualLeaveInitialAdjustment: annualLeaveInitialAdjustment ?? this.annualLeaveInitialAdjustment,
        annualLeaveInitialAdjustmentReason: annualLeaveInitialAdjustmentReason ?? this.annualLeaveInitialAdjustmentReason,
        leaveUsageLogs: leaveUsageLogs ?? this.leaveUsageLogs,
        inviteCode: inviteCode ?? this.inviteCode,
        previousMonthAdjustment: previousMonthAdjustment ?? this.previousMonthAdjustment,
        manualAverageDailyWage: manualAverageDailyWage ?? this.manualAverageDailyWage,
        employeeId: employeeId ?? this.employeeId,
        leavePromotionLogsJson: leavePromotionLogsJson ?? this.leavePromotionLogsJson,
        wageType: wageType ?? this.wageType,
        monthlyWage: monthlyWage ?? this.monthlyWage,
        fixedOvertimeHours: fixedOvertimeHours ?? this.fixedOvertimeHours,
        fixedOvertimePay: fixedOvertimePay ?? this.fixedOvertimePay,
        mealTaxExempt: mealTaxExempt ?? this.mealTaxExempt,
        isPaperContract: isPaperContract ?? this.isPaperContract,
        wageHistoryJson: wageHistoryJson ?? this.wageHistoryJson,
      );
}

@HiveType(typeId: 4)
class Allowance {
  const Allowance({
    required this.label,
    required this.amount,
  });

  @HiveField(0)
  final String label;
  @HiveField(1)
  final double amount;

  Map<String, dynamic> toMap() => {
        'label': label,
        'amount': amount,
      };

  factory Allowance.fromMap(Map<String, dynamic> map) => Allowance(
        label: map['label']?.toString() ?? '',
        amount: (map['amount'] as num?)?.toDouble() ?? 0,
      );
}

@HiveType(typeId: 5)
class LeaveUsageLog {
  const LeaveUsageLog({
    required this.id,
    required this.usedDays,
    required this.reason,
    required this.createdAtIso,
  });

  @HiveField(0)
  final String id;
  @HiveField(1)
  final double usedDays;
  @HiveField(2)
  final String reason;
  @HiveField(3)
  final String createdAtIso;

  Map<String, dynamic> toMap() => {
        'id': id,
        'usedDays': usedDays,
        'reason': reason,
        'createdAtIso': createdAtIso,
      };

  factory LeaveUsageLog.fromMap(Map<String, dynamic> map) => LeaveUsageLog(
        id: map['id']?.toString() ?? '',
        usedDays: (map['usedDays'] as num?)?.toDouble() ?? 0.0,
        reason: map['reason']?.toString() ?? '',
        createdAtIso: map['createdAtIso']?.toString() ?? '',
      );
}
