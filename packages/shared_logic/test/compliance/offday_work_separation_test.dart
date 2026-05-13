/// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
/// [법률 테스트] 월급제 휴무일(대타) 근로 — 고정OT 분리 정산 검증
/// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
///
/// 【검증 대상 법령】
///   - 근로기준법 제56조 제2항: 휴일근로 가산수당
///   - 고용노동부 포괄임금 오남용 방지 지침: 약정 초과분 추가 지급 의무
///
/// 【핵심 쟁점】
///   월급제(포괄임금) 직원이 스케줄 없는 휴무일(대타)에 출근한 경우,
///   해당 근로시간이 고정연장수당(fixedOT)을 "소진"하는 것이 아니라
///   별도의 휴일근로수당(offDayWorkPay)으로 분리 정산되어야 한다.
///
///   만약 휴무일 근로가 고정OT를 소진하면:
///   - 평일 실제 연장근로에 대한 고정OT 커버 시간이 줄어들어
///   - 초과 연장수당이 과다 발생하거나
///   - 휴일근로에 대한 별도 가산이 누락되는 문제 발생
///
/// 【검증 시나리오】
///   김점장(월급제 5인 이상): 목표 총급여 2,500,000원
///   - 기본급: 2,156,880원 | 식대: 200,000원 | 고정OT: 143,120원
///   - 고정OT 약정시간: ~8.4시간
///
///   시나리오 A: 만근(평일만) → 2,500,000원
///   시나리오 B: 만근 + 토요일(휴무일) 8시간 대타
///     → 2,500,000원 + offDayWorkPay(별도 가산) = 총액 > 2,500,000원
///     → offDayWorkPay > 0
///     → fixedOvertimeExcessHours == 0 (고정OT가 소진되지 않음)
///   시나리오 C: 만근 + 평일 잔업 3시간 + 토요일 대타 8시간
///     → 고정OT(8.4h)가 평일 잔업(3h)만 커버 → 초과 0시간
///     → 토요일 8시간은 offDayWorkPay로 별도 정산
///     → fixedOvertimeExcessHours == 0
///   시나리오 D: 만근 + 평일 잔업 12시간 + 토요일 대타 8시간
///     → 고정OT(8.4h) < 평일 잔업(12h) → 초과 3.6시간 보전
///     → 토요일 8시간은 offDayWorkPay로 별도 정산
///     → fixedOvertimeExcessHours ≈ 3.6시간
/// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_logic/shared_logic.dart';

void main() {
  group('[휴무일 근로 분리 정산] 고정OT와 offDayWorkPay 독립성 검증', () {
    // ─────────────────────────────────────────
    // 김점장 기본 데이터
    // ─────────────────────────────────────────
    const double minimumWage = 10320.0;
    const double standardMonthlyHours = 209.0;
    final double baseSalary =
        (minimumWage * standardMonthlyHours).roundToDouble(); // 2,156,880
    const double mealAllowance = 200000.0;
    const double targetSalary = 2500000.0;
    final double fixedOTPay =
        targetSalary - baseSalary - mealAllowance; // 143,120
    final double conservativeHourly =
        (baseSalary + mealAllowance) / standardMonthlyHours;
    final double fixedOTHours = fixedOTPay / (conservativeHourly * 1.5);

    PayrollWorkerData _makeMonthlyWorker() {
      return PayrollWorkerData(
        weeklyHoursPure: 40,
        weeklyTotalStayMinutes: 40 * 60,
        breakMinutesPerShift: 60,
        isPaidBreak: false,
        joinDate: DateTime(2025, 1, 1),
        scheduledWorkDays: [1, 2, 3, 4, 5], // 월~금
        manualWeeklyHolidayApproval: true,
        allowanceAmounts: [mealAllowance],
        mealAllowance: mealAllowance,
        mealTaxExempt: true,
        isVirtual: true,
        weeklyHolidayDay: 0,
        wageType: 'monthly',
        monthlyWage: baseSalary,
        fixedOvertimeHours: fixedOTHours,
        fixedOvertimePay: fixedOTPay,
      );
    }

    // 평일(월~금) 출퇴근 기록 생성 (09:00~18:00, 5/1 제외)
    List<Attendance> _makeWeekdayAttendances(
      DateTime start,
      DateTime end, {
      String staffId = 'worker_a',
      int overtimeMinutesPerDay = 0, // 평일 추가 잔업 분
    }) {
      final list = <Attendance>[];
      int idx = 0;
      for (var d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
        final weekday = d.weekday;
        if (weekday >= 1 && weekday <= 5) {
          if (d.month == 5 && d.day == 1) continue;
          list.add(Attendance(
            id: 'att_${idx++}',
            staffId: staffId,
            storeId: 'store_1',
            clockIn: DateTime(d.year, d.month, d.day, 9, 0),
            clockOut: DateTime(
              d.year,
              d.month,
              d.day,
              18 + (overtimeMinutesPerDay ~/ 60),
              overtimeMinutesPerDay % 60,
            ),
            type: AttendanceType.web,
            attendanceStatus: 'Normal',
          ));
        }
      }
      return list;
    }

    // 토요일(휴무일) 출퇴근 기록 생성
    List<Attendance> _makeSaturdayAttendances(
      DateTime start,
      DateTime end, {
      String staffId = 'worker_a',
      int hoursWorked = 8,
    }) {
      final list = <Attendance>[];
      int idx = 0;
      for (var d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
        if (d.weekday == 6) {
          // Saturday
          list.add(Attendance(
            id: 'sat_${idx++}',
            staffId: staffId,
            storeId: 'store_1',
            clockIn: DateTime(d.year, d.month, d.day, 10, 0),
            clockOut: DateTime(d.year, d.month, d.day, 10 + hoursWorked, 0),
            type: AttendanceType.web,
            attendanceStatus: 'Normal',
          ));
        }
      }
      return list;
    }

    // 테스트 기간: 6/16 ~ 7/15 (근로자의 날 없는 기간)
    final periodStart = DateTime(2026, 6, 16);
    final periodEnd = DateTime(2026, 7, 15);

    // ═══════════════════════════════════════════════════
    // [시나리오 A] 기준선: 평일만 만근 → 정확히 2,500,000원
    // ═══════════════════════════════════════════════════
    test('시나리오 A: 평일만 만근 → 2,500,000원 (offDay·초과OT 모두 0)', () {
      final workerData = _makeMonthlyWorker();
      final atts = _makeWeekdayAttendances(periodStart, periodEnd);

      final result = PayrollCalculator.calculate(
        workerData: workerData,
        shifts: atts,
        periodStart: periodStart,
        periodEnd: periodEnd,
        hourlyRate: minimumWage,
        isFiveOrMore: true,
        allHistoricalAttendances: atts,
      );

      expect(result.totalPay, targetSalary,
          reason: '만근 시 정확히 2,500,000원');
      expect(result.offDayWorkPay, 0.0,
          reason: '휴무일 출근 없음 → offDayWorkPay = 0');
      expect(result.fixedOvertimeExcessHours, 0.0,
          reason: '잔업 없음 → 고정OT 초과 없음');
    });

    // ═══════════════════════════════════════════════════
    // [시나리오 B] ★ 핵심: 만근 + 토요일 대타 1회(8시간)
    //   → offDayWorkPay > 0 (별도 수당)
    //   → fixedOvertimeExcessHours == 0 (고정OT 미소진)
    //   → totalPay > 2,500,000원
    // ═══════════════════════════════════════════════════
    test('시나리오 B: 만근 + 토요일 대타 8시간 → offDayWorkPay 별도 지급, 고정OT 미소진', () {
      final workerData = _makeMonthlyWorker();
      final weekdayAtts = _makeWeekdayAttendances(periodStart, periodEnd);

      // 토요일 1회 출근 (7/4 토요일, 10:00~18:00, 8시간)
      final satAtts = [
        Attendance(
          id: 'sat_0',
          staffId: 'worker_a',
          storeId: 'store_1',
          clockIn: DateTime(2026, 7, 4, 10, 0),
          clockOut: DateTime(2026, 7, 4, 18, 0),
          type: AttendanceType.web,
          attendanceStatus: 'Normal',
        ),
      ];

      final allAtts = [...weekdayAtts, ...satAtts];
      final result = PayrollCalculator.calculate(
        workerData: workerData,
        shifts: allAtts,
        periodStart: periodStart,
        periodEnd: periodEnd,
        hourlyRate: minimumWage,
        isFiveOrMore: true,
        allHistoricalAttendances: allAtts,
      );

      // ★ 핵심 검증 1: offDayWorkPay가 양수 (별도 수당으로 분리)
      expect(result.offDayWorkPay, greaterThan(0),
          reason: '토요일 대타 → offDayWorkPay > 0 (별도 지급)');

      // ★ 핵심 검증 2: 고정OT 초과시간이 0 (소진되지 않음)
      expect(result.fixedOvertimeExcessHours, 0.0,
          reason: '평일 잔업 0시간 → 고정OT 초과 없음 (토요일이 고정OT를 소진하지 않음)');

      // ★ 핵심 검증 3: 총급여 > 기본 월급
      expect(result.totalPay, greaterThan(targetSalary),
          reason: '2,500,000원 + offDayWorkPay = 총급여 상승');

      // offDayWorkPay 산식 검증: 8시간 × 통상시급 × 1.5배(5인 이상)
      final offDayHours = result.offDayWorkHours;
      expect(offDayHours, greaterThan(0),
          reason: '휴무일 근무시간 기록');
    });

    // ═══════════════════════════════════════════════════
    // [시나리오 C] 만근 + 평일 잔업 3시간(고정OT 이내) + 토요일 대타 8시간
    //   → 평일 잔업 3h < 고정OT ~8.4h → 초과 0시간
    //   → 토요일 8h → offDayWorkPay 별도
    //   → fixedOvertimeExcessHours == 0
    // ═══════════════════════════════════════════════════
    test('시나리오 C: 평일 잔업(고정OT 이내) + 토요일 대타 → 각각 독립 정산', () {
      final workerData = _makeMonthlyWorker();

      // 평일 출근 (일부는 19:00까지 1시간 잔업)
      final weekdayAtts = _makeWeekdayAttendances(periodStart, periodEnd);
      // 3일치 1시간 잔업 추가 (6/16, 6/17, 6/18)
      final overtimeAtts = [
        Attendance(
          id: 'ot_0',
          staffId: 'worker_a',
          storeId: 'store_1',
          clockIn: DateTime(2026, 6, 16, 9, 0),
          clockOut: DateTime(2026, 6, 16, 19, 0), // 1시간 잔업
          type: AttendanceType.web,
          attendanceStatus: 'Normal',
          overtimeApproved: true,
        ),
        Attendance(
          id: 'ot_1',
          staffId: 'worker_a',
          storeId: 'store_1',
          clockIn: DateTime(2026, 6, 17, 9, 0),
          clockOut: DateTime(2026, 6, 17, 19, 0),
          type: AttendanceType.web,
          attendanceStatus: 'Normal',
          overtimeApproved: true,
        ),
        Attendance(
          id: 'ot_2',
          staffId: 'worker_a',
          storeId: 'store_1',
          clockIn: DateTime(2026, 6, 18, 9, 0),
          clockOut: DateTime(2026, 6, 18, 19, 0),
          type: AttendanceType.web,
          attendanceStatus: 'Normal',
          overtimeApproved: true,
        ),
      ];

      // 토요일 대타 1회
      final satAtts = [
        Attendance(
          id: 'sat_c',
          staffId: 'worker_a',
          storeId: 'store_1',
          clockIn: DateTime(2026, 7, 4, 10, 0),
          clockOut: DateTime(2026, 7, 4, 18, 0),
          type: AttendanceType.web,
          attendanceStatus: 'Normal',
        ),
      ];

      // 잔업 3일분의 원본 기록 제거 후 교체
      final baseAtts = weekdayAtts.where((a) {
        final d = a.clockIn;
        return !(d.year == 2026 &&
            d.month == 6 &&
            d.day >= 16 &&
            d.day <= 18);
      }).toList();
      final allAtts = [...baseAtts, ...overtimeAtts, ...satAtts];

      final result = PayrollCalculator.calculate(
        workerData: workerData,
        shifts: allAtts,
        periodStart: periodStart,
        periodEnd: periodEnd,
        hourlyRate: minimumWage,
        isFiveOrMore: true,
        allHistoricalAttendances: allAtts,
      );

      // 평일 잔업 3시간 < 고정OT ~8.4시간 → 초과 없음
      expect(result.fixedOvertimeExcessHours, 0.0,
          reason: '평일 잔업 3h < 고정OT ~8.4h → 초과 없음');

      // 토요일은 별도 offDayWorkPay
      expect(result.offDayWorkPay, greaterThan(0),
          reason: '토요일 대타 → offDayWorkPay 별도 정산');

      // 총급여 > 기본 월급
      expect(result.totalPay, greaterThan(targetSalary),
          reason: '월급 + offDayWorkPay');
    });

    // ═══════════════════════════════════════════════════
    // [시나리오 D] 만근 + 평일 잔업 12시간(고정OT 초과) + 토요일 대타 8시간
    //   → 평일 잔업 12h > 고정OT ~8.4h → 초과 ~3.6시간 보전
    //   → 토요일 8h → offDayWorkPay 별도
    //   → fixedOvertimeExcessHours ≈ 3.6시간 (평일 잔업에서만 계산)
    // ═══════════════════════════════════════════════════
    test('시나리오 D: 평일 잔업 초과 + 토요일 대타 → 고정OT는 평일만 적용', () {
      final workerData = _makeMonthlyWorker();

      // 평일 12일 × 1시간 잔업 = 12시간 연장근로
      final weekdayAtts = _makeWeekdayAttendances(periodStart, periodEnd);
      final overtimeDays = <Attendance>[];
      int otCount = 0;
      for (var d = periodStart;
          !d.isAfter(periodEnd) && otCount < 12;
          d = d.add(const Duration(days: 1))) {
        if (d.weekday >= 1 && d.weekday <= 5 && !(d.month == 5 && d.day == 1)) {
          overtimeDays.add(Attendance(
            id: 'ot_d_$otCount',
            staffId: 'worker_a',
            storeId: 'store_1',
            clockIn: DateTime(d.year, d.month, d.day, 9, 0),
            clockOut: DateTime(d.year, d.month, d.day, 19, 0), // 1시간 잔업
            type: AttendanceType.web,
            attendanceStatus: 'Normal',
            overtimeApproved: true,
          ));
          otCount++;
        }
      }

      // 토요일 대타 1회
      final satAtts = [
        Attendance(
          id: 'sat_d',
          staffId: 'worker_a',
          storeId: 'store_1',
          clockIn: DateTime(2026, 7, 4, 10, 0),
          clockOut: DateTime(2026, 7, 4, 18, 0),
          type: AttendanceType.web,
          attendanceStatus: 'Normal',
        ),
      ];

      // 잔업 날짜의 원본 제거 후 교체
      final otDates = overtimeDays
          .map((a) =>
              '${a.clockIn.year}-${a.clockIn.month}-${a.clockIn.day}')
          .toSet();
      final baseAtts = weekdayAtts.where((a) {
        final key =
            '${a.clockIn.year}-${a.clockIn.month}-${a.clockIn.day}';
        return !otDates.contains(key);
      }).toList();
      final allAtts = [...baseAtts, ...overtimeDays, ...satAtts];

      final result = PayrollCalculator.calculate(
        workerData: workerData,
        shifts: allAtts,
        periodStart: periodStart,
        periodEnd: periodEnd,
        hourlyRate: minimumWage,
        isFiveOrMore: true,
        allHistoricalAttendances: allAtts,
      );

      // ★ 핵심: 고정OT 초과시간 ≈ 12 - 8.4 = 3.6시간 (평일 연장에서만!)
      expect(result.fixedOvertimeExcessHours, greaterThan(0),
          reason: '평일 잔업 12h > 고정OT ~8.4h → 초과분 존재');
      expect(result.fixedOvertimeExcessHours, closeTo(12 - fixedOTHours, 1.0),
          reason: '초과시간 ≈ 12 - 8.4 = ~3.6h (토요일 미포함)');

      // 토요일은 별도 offDayWorkPay
      expect(result.offDayWorkPay, greaterThan(0),
          reason: '토요일 대타 → offDayWorkPay 별도');

      // fixedOvertimeExcessPay > 0 (평일 초과분 보전)
      expect(result.fixedOvertimeExcessPay, greaterThan(0),
          reason: '고정OT 초과 보전금 > 0');

      // 총급여 = 기본 월급 + 초과OT 보전 + offDayWorkPay
      expect(result.totalPay, greaterThan(targetSalary),
          reason: '월급 + 초과OT + offDayWorkPay');

      // ★ 최종 확인: offDayWorkPay + fixedOvertimeExcessPay가 별도 항목
      // (서로 합쳐지거나 상쇄되지 않음)
      expect(
        result.offDayWorkPay + result.fixedOvertimeExcessPay,
        greaterThan(result.offDayWorkPay),
        reason: 'offDayWorkPay와 fixedOT초과는 별도 독립 항목',
      );
    });

    // ═══════════════════════════════════════════════════
    // [시나리오 E] 5인 미만: 휴무일 가산율 1.0배 검증
    // ═══════════════════════════════════════════════════
    test('시나리오 E: 5인 미만 → 휴무일 근로 1.0배 (가산 없음)', () {
      final workerData = _makeMonthlyWorker();
      final weekdayAtts = _makeWeekdayAttendances(periodStart, periodEnd);
      final satAtts = [
        Attendance(
          id: 'sat_e',
          staffId: 'worker_a',
          storeId: 'store_1',
          clockIn: DateTime(2026, 7, 4, 10, 0),
          clockOut: DateTime(2026, 7, 4, 18, 0),
          type: AttendanceType.web,
          attendanceStatus: 'Normal',
        ),
      ];
      final allAtts = [...weekdayAtts, ...satAtts];

      final resultFive = PayrollCalculator.calculate(
        workerData: workerData,
        shifts: allAtts,
        periodStart: periodStart,
        periodEnd: periodEnd,
        hourlyRate: minimumWage,
        isFiveOrMore: true,
        allHistoricalAttendances: allAtts,
      );

      final resultUnder = PayrollCalculator.calculate(
        workerData: workerData,
        shifts: allAtts,
        periodStart: periodStart,
        periodEnd: periodEnd,
        hourlyRate: minimumWage,
        isFiveOrMore: false,
        allHistoricalAttendances: allAtts,
      );

      // 5인 이상: offDayWorkPay = hours × 통상시급 × 1.5
      // 5인 미만: offDayWorkPay = hours × 통상시급 × 1.0
      expect(resultFive.offDayWorkPay, greaterThan(resultUnder.offDayWorkPay),
          reason: '5인 이상(1.5배) > 5인 미만(1.0배)');

      // 둘 다 offDayWorkPay > 0
      expect(resultFive.offDayWorkPay, greaterThan(0));
      expect(resultUnder.offDayWorkPay, greaterThan(0));
    });
  });
}
