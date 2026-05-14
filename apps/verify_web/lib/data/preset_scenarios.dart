/// 프리셋 테스트 시나리오 — docs/labor_review/06_test_scenarios.md 기반
class PresetScenarios {
  /// 시급제 프리셋
  static const Map<String, Map<String, dynamic>> hourlyPresets = {
    'A-1': {
      'label': 'A-1: 주5일 8시간 만근',
      'hourlyWage': 10320,
      'weeklyHours': 35.0, // 순수 7h × 5일 (휴게 1시간 제외)
      'breakMinutes': 60,
      'scheduledDays': [1, 2, 3, 4, 5],
      'isFiveOrMore': false,
      'totalPureHours': 150.5, // 35h × 4.3주
      'overtimeHours': 0.0,
      'nightHours': 0.0,
      'holidayHours': 0.0,
      'fullWeeks': 4,
      'absentWeeks': 0,
    },
    'A-2': {
      'label': 'A-2: 주3일 주15시간 경계',
      'hourlyWage': 12000,
      'weeklyHours': 15.0,
      'breakMinutes': 0,
      'scheduledDays': [1, 3, 5],
      'isFiveOrMore': false,
      'totalPureHours': 64.5, // 15h × 4.3주
      'overtimeHours': 0.0,
      'nightHours': 0.0,
      'holidayHours': 0.0,
      'fullWeeks': 4,
      'absentWeeks': 0,
    },
    'A-3': {
      'label': 'A-3: 야간근무 포함',
      'hourlyWage': 11000,
      'weeklyHours': 35.0, // 순수 7h × 5일
      'breakMinutes': 60,
      'scheduledDays': [2, 3, 4, 5, 6],
      'isFiveOrMore': true,
      'totalPureHours': 150.5,
      'overtimeHours': 0.0,
      'nightHours': 15.05, // 3.5h × 4.3주
      'holidayHours': 0.0,
      'fullWeeks': 4,
      'absentWeeks': 0,
    },
    'A-4': {
      'label': 'A-4: 연장근무 발생',
      'hourlyWage': 10320,
      'weeklyHours': 35.0,
      'breakMinutes': 60,
      'scheduledDays': [1, 2, 3, 4, 5],
      'isFiveOrMore': true,
      'totalPureHours': 158.5, // 기본 150.5 + 연장 8시간 분
      'overtimeHours': 8.0, // 2h연장 × 4일
      'nightHours': 0.0,
      'holidayHours': 0.0,
      'fullWeeks': 4,
      'absentWeeks': 0,
    },
    'A-5': {
      'label': 'A-5: 지각 + 유예시간',
      'hourlyWage': 10320,
      'weeklyHours': 35.0,
      'breakMinutes': 60,
      'scheduledDays': [1, 2, 3, 4, 5],
      'isFiveOrMore': false,
      'totalPureHours': 150.5,
      'overtimeHours': 0.0,
      'nightHours': 0.0,
      'holidayHours': 0.0,
      'fullWeeks': 4,
      'absentWeeks': 0,
    },
  };

  /// 월급제 프리셋
  static const Map<String, Map<String, dynamic>> monthlyPresets = {
    'B-1': {
      'label': 'B-1: 기본급215+식대20+OT14=250만',
      'baseSalary': 2150000,
      'mealPay': 200000,
      'fixedOtPay': 140000,
      'weeklyHours': 40.0,
      'isFiveOrMore': true,
      'joinDate': '2025-01-01',
      'exitDate': null,
    },
    'B-2': {
      'label': 'B-2: 중도입사 일할계산',
      'baseSalary': 2500000,
      'mealPay': 200000,
      'fixedOtPay': 0,
      'weeklyHours': 40.0,
      'isFiveOrMore': true,
      'joinDate': '2026-06-15',
      'exitDate': null,
    },
  };

  /// 퇴직금 정산 프리셋
  static const Map<String, Map<String, dynamic>> severancePresets = {
    'D-1': {
      'label': 'D-1: 시급제 2년 근무 퇴직',
      'name': '김시급',
      'joinDate': '2024-06-01',
      'exitDate': '2026-06-30',
      'weeklyHours': 40.0,
      'hourlyRate': 10320,
      'usedLeave': 5,
      'manualAdj': 0,
      'scheduledDays': [1, 2, 3, 4, 5],
      'isFiveOrMore': true,
      'wageType': 'hourly',
      'monthlySalary': 0,
      'mealPay': 0,
      'fixedOtPay': 0,
      'manualAvgWage': 0,
      'includeMealInOrdinary': true,
    },
    'D-2': {
      'label': 'D-2: 월급제 250만 1년 퇴직',
      'name': '박월급',
      'joinDate': '2025-06-01',
      'exitDate': '2026-06-30',
      'weeklyHours': 40.0,
      'hourlyRate': 0,
      'usedLeave': 3,
      'manualAdj': 0,
      'scheduledDays': [1, 2, 3, 4, 5],
      'isFiveOrMore': true,
      'wageType': 'monthly',
      'monthlySalary': 2150000,
      'mealPay': 200000,
      'fixedOtPay': 140000,
      'manualAvgWage': 0,
      'includeMealInOrdinary': true,
    },
    'D-3': {
      'label': 'D-3: 1년 미만 퇴직 (연차만)',
      'name': '이단기',
      'joinDate': '2026-01-01',
      'exitDate': '2026-06-30',
      'weeklyHours': 35.0,
      'hourlyRate': 12000,
      'usedLeave': 1,
      'manualAdj': 0,
      'scheduledDays': [1, 2, 3, 4, 5],
      'isFiveOrMore': true,
      'wageType': 'hourly',
      'monthlySalary': 0,
      'mealPay': 0,
      'fixedOtPay': 0,
      'manualAvgWage': 0,
      'includeMealInOrdinary': true,
    },
  };
}
