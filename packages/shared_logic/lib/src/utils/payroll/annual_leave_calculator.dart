/// 연차 저금통 계산 엔진
///
/// [payroll_calculator.dart]에서 분리된 연차 관련 모든 모델과 계산 로직입니다.
/// - 1년 미만 월별 연차 (최대 11개)
/// - 1년 이상 정기 연차 (15개 + 추가분, 80% 출근율 검증)
/// - 단시간 근로자 비례 환산
/// - 연차 소멸 및 사용촉진 (근로기준법 제61조)
/// - 퇴사 시 잔여 연차 수당 정산
library;

import '../../models/attendance_model.dart';

class AnnualLeaveAttendanceRate {
  /// 소정 근로일 대비 실제 출근일 수
  final int workedDays;
  final int expectedDays;
  final double rate; // 0.0 ~ 1.0
  final bool passed; // >= 80%?

  const AnnualLeaveAttendanceRate({
    required this.workedDays,
    required this.expectedDays,
    required this.rate,
    required this.passed,
  });
}

/// 연차 저금통 산출 결과
class AnnualLeaveSummary {
  /// 총 발생 연차 (입사~현재까지 누적)
  final double totalGenerated;

  /// 사용한 연차
  final double used;

  /// 잔여 연차 = totalGenerated - used
  final double remaining;

  /// 퇴사 정산 연차수당 (잔여 × 일일소정근로시간 × 시급)
  final double annualLeaveAllowancePay;

  /// 1년 주기 15개 부여 시 80% 미달로 미발생한 경우의 상세 정보
  final AnnualLeaveAttendanceRate? blockedAnnualRateDetail;

  /// 사장님이 수동으로 가감한 연차 개수 (UI 표시용)
  final double manualAdjustment;

  /// 연차 산출 각 단계의 근거 문장들
  final List<String> calculationBasis;

  // ─── 1년 미만 / 1년차 이후 분리 필드 ───

  /// 1년 미만 월별 발생 연차 중 '실제 만근 기록'이 입증된 개수만 카운트
  final double preAnniversaryGenerated;

  /// 1년 미만 발생분 중 사용한 개수 (FIFO: 1년 미만분 먼저 차감)
  final double preAnniversaryUsed;

  /// 1년 미만 미사용분
  double get preAnniversaryUnused =>
      (preAnniversaryGenerated - preAnniversaryUsed).clamp(
        0.0,
        double.infinity,
      );

  /// 1년차 이후 발생 연차 총 개수 (15개 + 추가분)
  final double postAnniversaryGenerated;

  /// 1년차 이후 잔여
  double get postAnniversaryRemaining =>
      (postAnniversaryGenerated - (used - preAnniversaryUsed)).clamp(
        0.0,
        double.infinity,
      );

  /// ★ 1년 미만 미사용 수당 정산금
  final double preAnniversaryPayoutAmount;

  /// 앱 도입 이전 기초 연차 개수
  final double initialAdjustment;

  /// 기초 연차 수정 사유 로그
  final String initialAdjustmentReason;

  // ─── 연차 유효기간 소멸 관련 ───

  /// 각 연차 배치별 소멸 정보 [{grantDate, expiryDate, granted, expired, expiredPayoutAmount}]
  final List<LeaveExpirationBatch> expirationBatches;

  /// 소멸된 연차 총 일수
  final double totalExpiredDays;

  /// 소멸 연차 수당 정산금 총액
  final double totalExpiredPayoutAmount;

  // ─── 단시간 근로자 시간 환산 ───

  /// 단시간 근로자 여부 (주 40시간 미만)
  final bool isPartTimeProportional;

  /// 단시간 근로자 비례 환산 배수 (일반 8시간, 단시간은 비례 적용된 시간)
  final double hoursMultiplier;

  /// 연차를 '시간' 단위로 환산한 값 (일수 × 8시간 × 주소정/40)
  /// 통상 근로자(주40h)는 일수 × 8
  final double leaveInHours;

  /// 잔여 연차의 시간 환산
  final double remainingInHours;

  // ─── 연차 사용촉진 관련 ───

  /// 배치별 촉진 현황 목록
  final List<LeavePromotionStatus> promotionStatuses;

  /// 촉진 완료로 수당 면제되는 금액
  final double promotionExemptPayoutAmount;

  const AnnualLeaveSummary({
    required this.totalGenerated,
    required this.used,
    required this.remaining,
    this.annualLeaveAllowancePay = 0.0,
    this.blockedAnnualRateDetail,
    this.manualAdjustment = 0.0,
    this.calculationBasis = const [],
    this.preAnniversaryGenerated = 0.0,
    this.preAnniversaryUsed = 0.0,
    this.postAnniversaryGenerated = 0.0,
    this.preAnniversaryPayoutAmount = 0.0,
    this.initialAdjustment = 0.0,
    this.initialAdjustmentReason = '',
    this.expirationBatches = const [],
    this.totalExpiredDays = 0.0,
    this.totalExpiredPayoutAmount = 0.0,
    this.isPartTimeProportional = false,
    this.hoursMultiplier = 8.0,
    this.leaveInHours = 0.0,
    this.remainingInHours = 0.0,
    this.promotionStatuses = const [],
    this.promotionExemptPayoutAmount = 0.0,
  });
}

/// 연차 배치별 소멸 정보
class LeaveExpirationBatch {
  /// 연차 발생일
  final DateTime grantDate;

  /// 연차 소멸일 (발생일 + 1년 - 1일)
  final DateTime expiryDate;

  /// 발생 개수
  final double granted;

  /// 소멸된 개수 (유효기간 경과 & 미사용)
  final double expired;

  /// 소멸 연차 수당 정산금
  final double expiredPayoutAmount;

  /// 소멸 여부 (정산 시점 기준)
  final bool isExpired;

  // ─── 1년 미만 vs 정기 연차 구분 (근로기준법 제61조 제2항) ───

  /// true = 1년 미만 발생분 (11개), false = 정기 연차 (15일+)
  /// 1년 미만: 1차 촉진 3개월 전 / 2차 촉진 1개월 전
  /// 정기 연차: 1차 촉진 6개월 전 / 2차 촉진 2개월 전
  final bool isPreAnniversary;

  // ─── 사용촉진제도 관련 (근로기준법 제61조) ───

  /// 1차 촉진 기한:
  ///   정기 연차 → 소멸 6개월 전
  ///   1년 미만분 → 소멸 3개월 전
  DateTime get firstNoticeDeadline => isPreAnniversary
      ? DateTime(expiryDate.year, expiryDate.month - 3, expiryDate.day)
      : DateTime(expiryDate.year, expiryDate.month - 6, expiryDate.day);

  /// 2차 촉진 기한:
  ///   정기 연차 → 소멸 2개월 전까지 지정 완료
  ///   1년 미만분 → 소멸 1개월 전까지 지정 완료
  DateTime get secondNoticeDeadline => isPreAnniversary
      ? DateTime(expiryDate.year, expiryDate.month - 1, expiryDate.day)
      : DateTime(expiryDate.year, expiryDate.month - 2, expiryDate.day);

  /// 촉진 완료 시 수당 면제 여부
  final bool isPromotionExempt;

  const LeaveExpirationBatch({
    required this.grantDate,
    required this.expiryDate,
    required this.granted,
    this.expired = 0.0,
    this.expiredPayoutAmount = 0.0,
    this.isExpired = false,
    this.isPreAnniversary = false,
    this.isPromotionExempt = false,
  });
}

/// 연차 사용촉진 현황 (근로기준법 제61조)
///
/// 절차 (정기 연차 15일 기준):
/// 1. 1차 촉진: 소멸 6개월 전까지 미사용 연차 일수 서면 통보 + 사용 시기 지정 요청
/// 2. 직원 10일 이내 사용 계획 미제출 시
/// 3. 2차 촉진: 사장님이 사용 시기 직접 지정 서면 통보 (소멸 2개월 전까지)
///
/// 1년 미만 연차 (11개 기준, 제61조 제2항):
/// 1. 1차 촉진: 소멸 3개월 전까지
/// 2. 2차 촉진: 소멸 1개월 전까지
///
/// 이행 완료 시 → 소멸 연차 수당 지급 면제
class LeavePromotionStatus {
  /// 연차 배치 발생일 (어떤 배치에 대한 촉진인지 식별)
  final DateTime batchGrantDate;

  /// 연차 소멸일
  final DateTime batchExpiryDate;

  /// 해당 배치의 미사용 연차 수
  final double unusedDays;

  /// 1년 미만 발생분 여부 (true = 3개월/1개월, false = 6개월/2개월)
  final bool isPreAnniversary;

  // ─── 1차 촉진 ───
  /// 1차 촉진 기한
  final DateTime firstNoticeDeadline;

  /// 1차 촉진 통보 완료일 (null = 미통보)
  final String? firstNoticeDate;

  /// 1차 촉진 통보 서면 PDF 문서 ID (LaborDocument 연동)
  final String? firstNoticeDocId;

  // ─── 직원 응답 ───
  /// 직원 사용 계획 제출일 (null = 미제출)
  final String? employeePlanDate;

  /// 직원이 제출한 사용 계획 내용
  final String? employeePlanContent;

  // ─── 2차 촉진 ───
  /// 2차 촉진 기한
  final DateTime secondNoticeDeadline;

  /// 2차 촉진 통보 완료일 (null = 미통보)
  final String? secondNoticeDate;

  /// 2차 촉진 통보 서면 PDF 문서 ID
  final String? secondNoticeDocId;

  /// 사장님이 지정한 사용 날짜들
  final List<String> designatedDates;

  // ─── 감사 보안 (위변조 방지) ───
  /// 촉진 기록의 무결성 해시 (SHA-256)
  /// 기록 생성 시: hash = SHA256(batchGrantDate + status + firstNoticeDate + secondNoticeDate + timestamp)
  final String? auditHash;

  /// 해시 생성 시점의 타임스탬프
  final String? auditTimestamp;

  // ─── 상태 ───
  /// 촉진 상태: pending / first_sent / awaiting_plan / second_sent / completed / expired
  final String status;

  /// 촉진 완료 여부 (1차+2차 모두 적법 이행)
  bool get isCompleted => status == 'completed';

  /// 수당 면제 여부 (촉진 완료 시 소멸분 수당 지급 의무 면제)
  bool get isExemptFromPayout => isCompleted;

  /// 연차 유형 라벨
  String get leaveTypeLabel => isPreAnniversary ? '1년 미만 발생분' : '정기 연차';

  /// 촉진 기한 라벨
  String get deadlineLabel => isPreAnniversary ? '3개월/1개월' : '6개월/2개월';

  const LeavePromotionStatus({
    required this.batchGrantDate,
    required this.batchExpiryDate,
    required this.unusedDays,
    required this.firstNoticeDeadline,
    this.isPreAnniversary = false,
    this.firstNoticeDate,
    this.firstNoticeDocId,
    this.employeePlanDate,
    this.employeePlanContent,
    required this.secondNoticeDeadline,
    this.secondNoticeDate,
    this.secondNoticeDocId,
    this.designatedDates = const [],
    this.auditHash,
    this.auditTimestamp,
    this.status = 'pending',
  });

  Map<String, dynamic> toMap() => {
    'batchGrantDate': batchGrantDate.toIso8601String(),
    'batchExpiryDate': batchExpiryDate.toIso8601String(),
    'unusedDays': unusedDays,
    'isPreAnniversary': isPreAnniversary,
    'firstNoticeDeadline': firstNoticeDeadline.toIso8601String(),
    'firstNoticeDate': firstNoticeDate,
    'firstNoticeDocId': firstNoticeDocId,
    'employeePlanDate': employeePlanDate,
    'employeePlanContent': employeePlanContent,
    'secondNoticeDeadline': secondNoticeDeadline.toIso8601String(),
    'secondNoticeDate': secondNoticeDate,
    'secondNoticeDocId': secondNoticeDocId,
    'designatedDates': designatedDates,
    'auditHash': auditHash,
    'auditTimestamp': auditTimestamp,
    'status': status,
  };

  factory LeavePromotionStatus.fromMap(
    Map<String, dynamic> map,
  ) => LeavePromotionStatus(
    batchGrantDate: DateTime.parse(map['batchGrantDate'] as String),
    batchExpiryDate: DateTime.parse(map['batchExpiryDate'] as String),
    unusedDays: (map['unusedDays'] as num?)?.toDouble() ?? 0.0,
    isPreAnniversary: map['isPreAnniversary'] as bool? ?? false,
    firstNoticeDeadline: DateTime.parse(map['firstNoticeDeadline'] as String),
    firstNoticeDate: map['firstNoticeDate']?.toString(),
    firstNoticeDocId: map['firstNoticeDocId']?.toString(),
    employeePlanDate: map['employeePlanDate']?.toString(),
    employeePlanContent: map['employeePlanContent']?.toString(),
    secondNoticeDeadline: DateTime.parse(map['secondNoticeDeadline'] as String),
    secondNoticeDate: map['secondNoticeDate']?.toString(),
    secondNoticeDocId: map['secondNoticeDocId']?.toString(),
    designatedDates:
        (map['designatedDates'] as List?)?.map((e) => e.toString()).toList() ??
        [],
    auditHash: map['auditHash']?.toString(),
    auditTimestamp: map['auditTimestamp']?.toString(),
    status: map['status']?.toString() ?? 'pending',
  );

  LeavePromotionStatus copyWith({
    String? firstNoticeDate,
    String? firstNoticeDocId,
    String? employeePlanDate,
    String? employeePlanContent,
    String? secondNoticeDate,
    String? secondNoticeDocId,
    List<String>? designatedDates,
    String? auditHash,
    String? auditTimestamp,
    String? status,
    double? unusedDays,
  }) => LeavePromotionStatus(
    batchGrantDate: batchGrantDate,
    batchExpiryDate: batchExpiryDate,
    unusedDays: unusedDays ?? this.unusedDays,
    isPreAnniversary: isPreAnniversary,
    firstNoticeDeadline: firstNoticeDeadline,
    firstNoticeDate: firstNoticeDate ?? this.firstNoticeDate,
    firstNoticeDocId: firstNoticeDocId ?? this.firstNoticeDocId,
    employeePlanDate: employeePlanDate ?? this.employeePlanDate,
    employeePlanContent: employeePlanContent ?? this.employeePlanContent,
    secondNoticeDeadline: secondNoticeDeadline,
    secondNoticeDate: secondNoticeDate ?? this.secondNoticeDate,
    secondNoticeDocId: secondNoticeDocId ?? this.secondNoticeDocId,
    designatedDates: designatedDates ?? this.designatedDates,
    auditHash: auditHash ?? this.auditHash,
    auditTimestamp: auditTimestamp ?? this.auditTimestamp,
    status: status ?? this.status,
  );
}

class AnnualLeaveCalculator {
  const AnnualLeaveCalculator();

  /// 연차 저금통 전체 누적 요약 산출
  ///
  /// - 1년 미만: 입사일 기준 1개월 단위 만근 시 +1개 (최대 11개)
  /// - 1년 이상: 해당 1년 구간의 80% 출근율 검증 후 +15개
  /// - 퇴사 시 잔여 연차 × 계약 일일소정근로시간 × 시급 = 연차수당
  static AnnualLeaveSummary calculateAnnualLeaveSummary({
    required DateTime joinDate,
    required DateTime? endDate,
    required List<Attendance> allAttendances,
    required List<int> scheduledWorkDays,
    required bool isFiveOrMore,
    required DateTime settlementPoint,
    required double usedAnnualLeave,
    required double weeklyHoursPure,
    required double hourlyRate,
    double manualAdjustment = 0.0,
    double initialAdjustment = 0.0,
    String initialAdjustmentReason = '',
    List<LeavePromotionStatus> promotionLogs = const [],
    bool isVirtual = false,
  }) {
    final basis = <String>[
      "입사일: ${joinDate.year}-${joinDate.month.toString().padLeft(2, '0')}-${joinDate.day.toString().padLeft(2, '0')} (${isFiveOrMore ? '5인이상' : '5인미만'})",
    ];
    if (!isFiveOrMore) {
      // 5인 미만 전환 시, 신규 연차 발생은 중단하되
      // 기존에 이미 사용한 연차로 인해 '마이너스 연차'가 되지 않도록
      // 최소한 사용한 만큼(usedAnnualLeave)은 발생했던 것으로 보존합니다.
      // (시스템 내 과거 5인 이상/미만 변동 이력이 없기 때문)
      double guaranteed = usedAnnualLeave;
      
      // 승급 로그(촉진 기록)에 보존된 미사용 연차 합산 (과거 확정분 보존)
      for (final log in promotionLogs) {
        guaranteed += log.unusedDays;
      }

      // 여기에 사장님이 수동으로 더해준/초기화해준 값은 그대로 보존
      guaranteed += manualAdjustment;
      guaranteed += initialAdjustment;

      return AnnualLeaveSummary(
        totalGenerated: guaranteed,
        used: usedAnnualLeave,
        remaining: guaranteed - usedAnnualLeave,
        calculationBasis: [
          "5인 미만 사업장 (설정/추정): 신규 연차 발생 대상 아님",
          "노무 참고용: 과거 사용 연차 및 수동 조정분은 이력 보존"
        ],
      );
    }

    // [수정/확인] 초단시간 근로자(주 15시간 미만) 연차 발생 제외 (근로기준법 제18조 제3항)
    if (weeklyHoursPure < 15) {
      return const AnnualLeaveSummary(
        totalGenerated: 0,
        used: 0,
        remaining: 0,
        calculationBasis: ["초단시간 근로자(주 15시간 미만): 연차 발생 대상 아님"],
      );
    }

    // 계약 일일 소정 근로시간 (계약 주간시간 / 주간 근무일수)
    final contractWorkDaysPerWeek = scheduledWorkDays.isEmpty
        ? 5.0
        : scheduledWorkDays.length.toDouble();
    final dailyContractHours = contractWorkDaysPerWeek > 0
        ? weeklyHoursPure / contractWorkDaysPerWeek
        : 8.0;

    // 단시간 근로자 비례 환산 시간 (연차 수당 지급 기준, 근로기준법)
    final isPartTime = weeklyHoursPure < 40.0 && weeklyHoursPure >= 15.0;
    final double hoursMultiplier = isPartTime
        ? (weeklyHoursPure / 40.0) * 8.0
        : 8.0;

    double totalGenerated = 0;
    double preAnnivGenerated = 0; // 1년 미만 — 실제 만근 기록이 있는 달만 카운트
    double postAnnivGenerated = 0; // 1년차 이후 발생분
    AnnualLeaveAttendanceRate? blockedDetail;

    // ─── 1단계: 입사일 기준 1개월 단위로 1년 미만 연차 계산 ───
    // 각 월 구간: _addSafeMonths(joinDate, m) ~ _addSafeMonths(joinDate, m+1) - 1일
    // 1년 미만 구간: 0 ~ 11개월차 (각 만근이면 +1)
    final oneYearPoint = DateTime(
      joinDate.year + 1,
      joinDate.month,
      joinDate.day,
    );

    // 정산 시점 기준 경과 완전 개월 수 (최대 11)
    final cutPoint = settlementPoint.isBefore(oneYearPoint)
        ? settlementPoint
        : oneYearPoint;
    final monthsElapsed = _monthsDiff(joinDate, cutPoint);
    final monthsToCheck = monthsElapsed.clamp(0, 11);

    for (int m = 0; m < monthsToCheck; m++) {
      final mStart = _addSafeMonths(joinDate, m);
      final mNext = _addSafeMonths(joinDate, m + 1);
      final mEnd = mNext.subtract(const Duration(days: 1));

      // 이 단위 구간이 정산 시점을 넘으면 최종일로 클리핑
      final mEndClipped = mEnd.isAfter(settlementPoint)
          ? settlementPoint
          : mEnd;

      final expected = _expectedWorkDays(
        mStart,
        mEndClipped,
        scheduledWorkDays,
      );
      final workedSet = _workedDaysSet(allAttendances, mStart, mEndClipped);
      final worked = workedSet.length;

      // [핵심 개편] 사장님의 가상 근무표 테스트를 위해, 입사 후 기록이 없는 구간은 '만근'으로 기본 가정함
      bool isAutoPassed = false;
      bool hasActualData = false;
      if (!isAutoPassed && expected > 0) {
        hasActualData = allAttendances.any(
          (a) =>
              a.clockIn.isAfter(mStart.subtract(const Duration(seconds: 1))) &&
              a.clockIn.isBefore(mEndClipped.add(const Duration(seconds: 1))),
        );

        // 데이터가 아예 없는 구간은 '만근 가정'으로 처리하여 연차 발생 보장
        if (!hasActualData && isVirtual) {
          isAutoPassed = true;
        }
      }

      final statusText = "($worked/$expected)";
      if (isAutoPassed || (expected > 0 && worked >= expected)) {
        totalGenerated += 1;

        // ★ preAnnivGenerated: 실제 만근 기록이 있는 달만 카운트 (수당 정산 대상)
        // 만근 가정(기록 없음)은 totalGenerated에는 포함하되, preAnnivGenerated에는 미포함
        if (hasActualData) {
          preAnnivGenerated += 1;
        }

        final passLabel = isAutoPassed ? "만근 가정 (기록 없음, +1개)" : "만근 (+1개)";
        basis.add(
          "${mStart.year}-${mStart.month.toString().padLeft(2, '0')}-${mStart.day.toString().padLeft(2, '0')} ~ ${mEnd.year}-${mEnd.month.toString().padLeft(2, '0')}-${mEnd.day.toString().padLeft(2, '0')}: $passLabel $statusText",
        );
      } else if (expected > 0) {
        basis.add(
          "${mStart.year}-${mStart.month.toString().padLeft(2, '0')}-${mStart.day.toString().padLeft(2, '0')} ~ ${mEnd.year}-${mEnd.month.toString().padLeft(2, '0')}-${mEnd.day.toString().padLeft(2, '0')}: 결근/미달 (0개) $statusText",
        );
      }
    }

    // ★ 1년 미만 발생분 배치 추적 (제61조 제2항 사용촉진 대상)
    // 발생일 = 입사일, 소멸일 = 입사 1주년 전날
    final expirationBatches = <LeaveExpirationBatch>[];
    if (preAnnivGenerated > 0) {
      final preAnnivExpiryDate = oneYearPoint.subtract(const Duration(days: 1));
      expirationBatches.add(
        LeaveExpirationBatch(
          grantDate: joinDate,
          expiryDate: preAnnivExpiryDate,
          granted: preAnnivGenerated,
          isPreAnniversary: true, // ★ 3개월/1개월 기한 적용
        ),
      );
    }

    // ─── 2단계: 1년 주기 15개 + 80% 출근율 검증 ───

    if (!settlementPoint.isBefore(oneYearPoint)) {
      final yearsPassed = _yearsDiff(joinDate, settlementPoint);
      for (int y = 1; y <= yearsPassed; y++) {
        final yearStart = DateTime(
          joinDate.year + y - 1,
          joinDate.month,
          joinDate.day,
        );
        final yearEnd = DateTime(
          joinDate.year + y,
          joinDate.month,
          joinDate.day,
        ).subtract(const Duration(days: 1));
        final yearEndClipped = yearEnd.isAfter(settlementPoint)
            ? settlementPoint
            : yearEnd;

        final expected = _expectedWorkDays(
          yearStart,
          yearEndClipped,
          scheduledWorkDays,
        );
        final workedSet = _workedDaysSet(
          allAttendances,
          yearStart,
          yearEndClipped,
        );

        // [핵심 개편] 해당 연도에 근태 기록이 아예 없는 구간은 출근율 100%로 간주함
        bool isLegacyAutoPassed = false;
        if (expected > 0) {
          final hasAnyDataInYear = allAttendances.any(
            (a) =>
                a.clockIn.isAfter(
                  yearStart.subtract(const Duration(seconds: 1)),
                ) &&
                a.clockIn.isBefore(
                  yearEndClipped.add(const Duration(seconds: 1)),
                ),
          );
          if (!hasAnyDataInYear && isVirtual) {
            isLegacyAutoPassed = true;
          }
        }
        

        final rate = expected > 0
            ? (isLegacyAutoPassed ? 1.0 : workedSet.length / expected)
            : 1.0;
        final passed = rate >= 0.8;

        if (passed) {
          final additionalDays = (y > 1) ? ((y - 1) ~/ 2) : 0;
          final grantedThisYear = (15 + additionalDays).clamp(15, 25);

          // ★ 단시간 근로자: 일관된 비례 계산 (근로기준법 시행령 별표 2 준수)
          // 기존에는 일수 자체를 (주소정/40)으로 줄여 12일로 환산하는 방식과,
          // 1일의 가치를 6.4시간으로 곱하는 방식이 혼용되어 이중 차감이 발생했습니다.
          // 이제 엔진이 'hoursMultiplier(예: 6.4)'를 적용하므로 일수는 통상 근로자와
          // 동일하게 15일을 주고, 수당을 15 * 6.4 = 96시간으로 계산하도록 통일합니다.
          final double effectiveGranted = grantedThisYear.toDouble();

          totalGenerated += effectiveGranted;
          postAnnivGenerated += effectiveGranted;

          // ★ 배치 소멸 추적: 연차 발생일 = yearEnd+1일 = 다음해 입사일 기준일
          // 소멸일 = 발생일 + 1년 - 1일
          final grantDate = DateTime(
            joinDate.year + y,
            joinDate.month,
            joinDate.day,
          );
          final expiryDate = DateTime(
            joinDate.year + y + 1,
            joinDate.month,
            joinDate.day,
          ).subtract(const Duration(days: 1));

          expirationBatches.add(
            LeaveExpirationBatch(
              grantDate: grantDate,
              expiryDate: expiryDate,
              granted: effectiveGranted,
            ),
          );

          final passLabel = isLegacyAutoPassed
              ? "만근 가정 (기록 없음) "
              : "출근율 ${(rate * 100).toStringAsFixed(1)}% ";
          final expiryLabel =
              "${grantDate.year}-${grantDate.month.toString().padLeft(2, '0')}-${grantDate.day.toString().padLeft(2, '0')}";
          final expiryEndLabel =
              "${expiryDate.year}-${expiryDate.month.toString().padLeft(2, '0')}-${expiryDate.day.toString().padLeft(2, '0')}";

          if (weeklyHoursPure < 40.0 && weeklyHoursPure >= 15.0) {
            final hoursValue = effectiveGranted * hoursMultiplier;
            basis.add(
              "$y년차(${yearStart.year}~${yearEnd.year}): $passLabel (+${effectiveGranted.toStringAsFixed(1)}일/${hoursValue.toStringAsFixed(0)}h) [유효: $expiryLabel~$expiryEndLabel]",
            );
          } else {
            basis.add(
              "$y년차(${yearStart.year}~${yearEnd.year}): $passLabel (+${effectiveGranted.toStringAsFixed(0)}개) [유효: $expiryLabel~$expiryEndLabel]",
            );
          }
        } else {
          blockedDetail = AnnualLeaveAttendanceRate(
            workedDays: workedSet.length,
            expectedDays: expected,
            rate: rate,
            passed: false,
          );
          basis.add(
            "$y년차(${yearStart.year}~${yearEnd.year}): 출근율 부족 ${(rate * 100).toStringAsFixed(1)}% (0개)",
          );
        }
      }
    }

    // ─── 기초 연차 설정 (앱 도입 이전 기간분) ───
    if (initialAdjustment != 0) {
      totalGenerated += initialAdjustment;
      final sign = initialAdjustment > 0 ? '+' : '';
      final reasonLabel = initialAdjustmentReason.isNotEmpty
          ? ' (사유: $initialAdjustmentReason)'
          : '';
      basis.add(
        "기초 연차(앱 도입 이전): $sign${initialAdjustment.toStringAsFixed(1)}개$reasonLabel",
      );
    }

    if (manualAdjustment != 0) {
      totalGenerated += manualAdjustment;
      final sign = manualAdjustment > 0 ? '+' : '';
      basis.add("관리자 수동 조정: $sign$manualAdjustment개");
    }

    final remaining = (totalGenerated - usedAnnualLeave)
        .clamp(0.0, double.infinity)
        .toDouble();

    // ─── 3단계: FIFO 사용 배분 (1년 미만분 먼저 차감) ───
    final preAnnivUsed = usedAnnualLeave.clamp(0.0, preAnnivGenerated);
    final preAnnivUnused = (preAnnivGenerated - preAnnivUsed).clamp(
      0.0,
      double.infinity,
    );

    // ★ 미사용 수당 정산금 계산 (향후 급여 명세서 '기타 수당' 연동용)
    final preAnnivPayoutAmount = preAnnivUnused * hoursMultiplier * hourlyRate;

    // ─── 4단계: 배치별 소멸 처리 ───
    // FIFO: 사용분을 먼저 오래된 배치부터 차감 → 소멸일 지난 배치의 미사용분 = 소멸
    // 1년 미만 배치는 preAnnivUsed로, 정기 연차는 postAnnivUsed로 차감
    double remainingPreUsed = preAnnivUsed;
    double postAnnivUsed = (usedAnnualLeave - preAnnivUsed).clamp(
      0.0,
      double.infinity,
    );
    double totalExpiredDays = 0.0;
    double totalExpiredPayout = 0.0;
    final processedBatches = <LeaveExpirationBatch>[];

    for (final batch in expirationBatches) {
      // 1년 미만 배치 vs 정기 배치에 따라 다른 사용 풀에서 차감
      double usedFromBatch;
      if (batch.isPreAnniversary) {
        usedFromBatch = remainingPreUsed.clamp(0.0, batch.granted);
        remainingPreUsed -= usedFromBatch;
      } else {
        usedFromBatch = postAnnivUsed.clamp(0.0, batch.granted);
        postAnnivUsed -= usedFromBatch;
      }

      final unusedInBatch = (batch.granted - usedFromBatch).clamp(
        0.0,
        double.infinity,
      );
      final isExpired = !settlementPoint.isBefore(batch.expiryDate);

      if (isExpired && unusedInBatch > 0) {
        final expiredPayout = unusedInBatch * hoursMultiplier * hourlyRate;
        totalExpiredDays += unusedInBatch;
        totalExpiredPayout += expiredPayout;

        processedBatches.add(
          LeaveExpirationBatch(
            grantDate: batch.grantDate,
            expiryDate: batch.expiryDate,
            granted: batch.granted,
            expired: unusedInBatch,
            expiredPayoutAmount: expiredPayout,
            isExpired: true,
            isPreAnniversary: batch.isPreAnniversary,
          ),
        );

        final typeLabel = batch.isPreAnniversary ? '[1년 미만] ' : '';
        basis.add(
          "⚠ $typeLabel${batch.grantDate.year}-${batch.grantDate.month.toString().padLeft(2, '0')}-${batch.grantDate.day.toString().padLeft(2, '0')} 발생분 ${unusedInBatch.toStringAsFixed(1)}개 소멸 (유효기간 만료)",
        );
      } else {
        processedBatches.add(
          LeaveExpirationBatch(
            grantDate: batch.grantDate,
            expiryDate: batch.expiryDate,
            granted: batch.granted,
            isExpired: isExpired,
            isPreAnniversary: batch.isPreAnniversary,
          ),
        );
      }
    }

    // ─── 5단계: 단시간 근로자 시간 환산 ───
    final leaveInHours = totalGenerated * hoursMultiplier;
    final remainingInHours = remaining * hoursMultiplier;

    if (isPartTime) {
      basis.add(
        "─ 단시간 근로자(주${weeklyHoursPure.toStringAsFixed(1)}h): 연차 ${totalGenerated.toStringAsFixed(1)}일 = ${leaveInHours.toStringAsFixed(1)}시간 환산",
      );
    }

    // ─── 6단계: 연차 사용촉진 현황 생성 (근로기준법 제61조) ───
    final computedPromotions = <LeavePromotionStatus>[];
    double promotionExemptPayout = 0.0;

    // FIFO 사용량 재계산 (배치별 미사용분 산출용)
    // 1년 미만 배치는 preAnnivUsed로, 정기 배치는 postAnnivUsed로 각각 차감
    double promoPreUsed = preAnnivUsed;
    double promoPostUsed = (usedAnnualLeave - preAnnivUsed).clamp(
      0.0,
      double.infinity,
    );

    for (final batch in processedBatches) {
      double usedFromBatch;
      if (batch.isPreAnniversary) {
        usedFromBatch = promoPreUsed.clamp(0.0, batch.granted);
        promoPreUsed -= usedFromBatch;
      } else {
        usedFromBatch = promoPostUsed.clamp(0.0, batch.granted);
        promoPostUsed -= usedFromBatch;
      }
      final unusedInBatch = (batch.granted - usedFromBatch).clamp(
        0.0,
        double.infinity,
      );

      // 촉진 대상: 미사용분이 있고, 아직 소멸 전이며, 1차 촉진 기한 시점에 진입한 배치
      final firstDeadline = batch.firstNoticeDeadline;
      final isInPromotionWindow =
          !settlementPoint.isBefore(firstDeadline) &&
          settlementPoint.isBefore(batch.expiryDate);

      if (unusedInBatch > 0 && (isInPromotionWindow || batch.isExpired)) {
        // 기존 촉진 로그에서 해당 배치 매칭
        final matchedLogs = promotionLogs
            .where(
              (p) =>
                  p.batchGrantDate.year == batch.grantDate.year &&
                  p.batchGrantDate.month == batch.grantDate.month &&
                  p.batchGrantDate.day == batch.grantDate.day,
            )
            .toList();
        final existingLog = matchedLogs.isNotEmpty ? matchedLogs.first : null;
        if (existingLog != null) {
          // 기존 로그 유지 (미사용분만 갱신)
          var updatedStatus = existingLog.status;
          if (batch.isExpired && updatedStatus != 'completed') {
            updatedStatus = 'expired';
          }
          final updated = existingLog.copyWith(
            unusedDays: unusedInBatch,
            status: updatedStatus,
          );
          computedPromotions.add(updated);

          // 촉진 완료된 배치의 소멸분 → 수당 면제
          if (updated.isExemptFromPayout &&
              batch.isExpired &&
              batch.expired > 0) {
            promotionExemptPayout += batch.expiredPayoutAmount;
            basis.add(
              "✅ ${batch.grantDate.year}-${batch.grantDate.month.toString().padLeft(2, '0')}-${batch.grantDate.day.toString().padLeft(2, '0')} 발생분 사용촉진 완료 → 수당 면제",
            );
          }
        } else {
          // 신규 촉진 현황 생성
          computedPromotions.add(
            LeavePromotionStatus(
              batchGrantDate: batch.grantDate,
              batchExpiryDate: batch.expiryDate,
              unusedDays: unusedInBatch,
              isPreAnniversary: batch.isPreAnniversary,
              firstNoticeDeadline: firstDeadline,
              secondNoticeDeadline: batch.secondNoticeDeadline,
              status: batch.isExpired ? 'expired' : 'pending',
            ),
          );
        }
      }
    }

    // ─── 7단계: 퇴사 정산 연차수당 ───
    double annualLeaveAllowancePay = 0;
    final isTerminated = endDate != null && !endDate.isAfter(settlementPoint);
    if (isTerminated && remaining > 0) {
      annualLeaveAllowancePay = remaining * hoursMultiplier * hourlyRate;
    }

    return AnnualLeaveSummary(
      totalGenerated: totalGenerated,
      used: usedAnnualLeave,
      remaining: remaining,
      annualLeaveAllowancePay: annualLeaveAllowancePay,
      blockedAnnualRateDetail: blockedDetail,
      manualAdjustment: manualAdjustment,
      calculationBasis: basis,
      preAnniversaryGenerated: preAnnivGenerated,
      preAnniversaryUsed: preAnnivUsed,
      postAnniversaryGenerated: postAnnivGenerated,
      preAnniversaryPayoutAmount: preAnnivPayoutAmount,
      initialAdjustment: initialAdjustment,
      initialAdjustmentReason: initialAdjustmentReason,
      expirationBatches: processedBatches,
      totalExpiredDays: totalExpiredDays,
      totalExpiredPayoutAmount: totalExpiredPayout,
      isPartTimeProportional: isPartTime,
      hoursMultiplier: hoursMultiplier,
      leaveInHours: leaveInHours,
      remainingInHours: remainingInHours,
      promotionStatuses: computedPromotions,
      promotionExemptPayoutAmount: promotionExemptPayout,
    );
  }

  static int calculateAnnualLeave({
    required DateTime joinDate,
    required List<Attendance> attendances,
    required List<int> scheduledWorkDays,
    required bool isFiveOrMore,
    required DateTime settlementPoint,
  }) {
    if (!isFiveOrMore) return 0;
    final summary = calculateAnnualLeaveSummary(
      joinDate: joinDate,
      endDate: null,
      allAttendances: attendances,
      scheduledWorkDays: scheduledWorkDays,
      isFiveOrMore: isFiveOrMore,
      settlementPoint: settlementPoint,
      usedAnnualLeave: 0,
      weeklyHoursPure: 40,
      hourlyRate: 0,
    );
    return summary.totalGenerated.floor();
  }

  static int _monthsDiff(DateTime from, DateTime to) {
    int months = (to.year - from.year) * 12 + (to.month - from.month);

    // 날짜가 부족한 경우 1개월 차감
    // 단, 종료일이 해당 월의 말일이고, 시작일의 일자보다 크거나 같으면(혹은 시작일도 말일이면) 꽉 찬 것으로 봅니다.
    final lastDayOfTo = DateTime(to.year, to.month + 1, 0).day;
    bool isLastDayOfTo = to.day == lastDayOfTo;

    if (to.day < from.day && !isLastDayOfTo) {
      months--;
    }
    return months < 0 ? 0 : months;
  }

  /// 31일 입사자가 말일(2월 등)을 지날 때 날짜가 튀는 현상을 방지하는 안전한 월 덧셈
  static DateTime _addSafeMonths(DateTime from, int months) {
    int nextYear = from.year + ((from.month + months - 1) ~/ 12);
    int nextMonth = (from.month + months - 1) % 12 + 1;
    // 해당 월의 실제 최대 일수 확인
    int lastDay = DateTime(nextYear, nextMonth + 1, 0).day;
    int nextDay = from.day > lastDay ? lastDay : from.day;
    return DateTime(nextYear, nextMonth, nextDay);
  }

  static int _yearsDiff(DateTime from, DateTime to) {
    int years = to.year - from.year;
    if (to.month < from.month ||
        (to.month == from.month && to.day < from.day)) {
      years--;
    }
    return years < 0 ? 0 : years;
  }

  static int _expectedWorkDays(
    DateTime from,
    DateTime to,
    List<int> scheduledWorkDays,
  ) {
    int count = 0;
    for (
      DateTime d = from;
      !d.isAfter(to);
      d = d.add(const Duration(days: 1))
    ) {
      final code = d.weekday == DateTime.sunday ? 0 : d.weekday;
      if (scheduledWorkDays.contains(code)) count++;
    }
    return count;
  }

  static Set<String> _workedDaysSet(
    List<Attendance> attendances,
    DateTime from,
    DateTime to,
  ) {
    final set = <String>{};
    for (final att in attendances) {
      final d = DateTime(att.clockIn.year, att.clockIn.month, att.clockIn.day);
      if (d.isBefore(from) || d.isAfter(to)) continue;
      set.add('${d.year}-${d.month}-${d.day}');
    }
    return set;
  }
}
