import 'package:flutter_test/flutter_test.dart';
import 'package:boss_mobile/models/worker.dart';
import 'package:boss_mobile/models/attendance.dart';
import 'package:boss_mobile/utils/renewal_engine.dart';

void main() {
  test('verify manager kim salary', () {
    final targetSalary = 2500000.0;
    final mealAllowance = 200000.0;
    final minimumWage = 10320.0;
    final standardMonthlyHours = 209.0;

    final baseSalary = (minimumWage * standardMonthlyHours).roundToDouble(); // 2156880.0
    final fixedOTPay = targetSalary - baseSalary - mealAllowance; // 143120.0
    final conservativeHourly = (baseSalary + mealAllowance) / standardMonthlyHours;
    final fixedOTHoursCalc = conservativeHourly > 0 ? fixedOTPay / (conservativeHourly * 1.5) : 0.0;

    final worker = Worker(
      id: 'worker_a',
      name: '가상 김점장',
      wageType: 'monthly',
      wage: minimumWage.round(),
      baseSalary: baseSalary.round(),
      monthlyWage: baseSalary.round(),
      mealAllowance: mealAllowance.round(),
      fixedOvertimeHours: fixedOTHoursCalc,
      fixedOvertimePay: fixedOTPay.round(),
      workDays: [1, 2, 3, 4, 5],
      weeklyHours: 40,
      checkInTime: '09:00',
      checkOutTime: '18:00',
      isPaidBreak: false,
      breakMinutes: 60,
      phone: '',
      startDate: '2026-01-01',
      createdAt: '2026-01-01T00:00:00Z',
    );

    final List<Attendance> attendances = [];
    final startDate = DateTime(2026, 5, 16);
    for (int i = 0; i < 31; i++) {
      final d = startDate.add(Duration(days: i));
      final baseDay = d.weekday == DateTime.sunday ? 0 : d.weekday;
      if (worker.workDays.contains(baseDay)) {
        final inDt = DateTime(d.year, d.month, d.day, 9, 0);
        final outDt = DateTime(d.year, d.month, d.day, 18, 0);
        attendances.add(Attendance(
          id: 'att_\$i',
          staffId: worker.id,
          storeId: 'store_1',
          clockIn: inDt,
          clockOut: outDt,
          originalClockIn: inDt,
          originalClockOut: outDt,
        ));
      }
    }

    final engine = RenewalEngine();
    final result = engine.calculateMonthly(
      worker: worker,
      attendances: attendances,
      year: 2026,
      month: 6,
      isFiveOrMore: true,
    );

    print('--- Manager Kim Salary Report ---');
    print('Target Salary: \$targetSalary');
    print('Calculated Total Salary: \${result.totalSalary}');
    print('Base Salary (기본급): \${result.baseSalary}');
    print('Meal Allowance (식비): \${result.mealAllowance}');
    print('Fixed OT Pay (고정연장수당): \${result.fixedOvertimePay}');
    print('Additional Real OT Pay (실 연장수당): \${result.overtimePay}');
    print('Deductions: \${result.totalDeductions}');
    print('Net Pay: \${result.netSalary}');
    print('Difference (Calculated - Target): \${result.totalSalary - targetSalary}');
    
    expect(result.totalSalary, targetSalary);
  });
}
