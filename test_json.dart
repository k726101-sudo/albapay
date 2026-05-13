import 'dart:convert';
void main() {
  String dataJson = '{"periodStart":"2026-03-01T00:00:00.000","periodEnd":"2026-03-31T00:00:00.000","basePay":154000.0,"premiumPay":0.0,"weeklyHolidayPay":0.0,"breakPay":0.0,"otherAllowancePay":0.0,"totalPay":154000.0,"pureLaborHours":15.0,"hourlyRate":10000.0}';
  try {
    final data = jsonDecode(dataJson) as Map<String, dynamic>;
    final base = (data['basePay'] as num?)?.toInt() ?? 0;
    print("Base: $base");
  } catch (e) {
    print("Error 1: $e");
  }

  // what if dataJson is NOT JSON format but just a string representation of a Dart Map?
  String dartMapString = '{periodStart: 2026-03-01T00:00:00.000, basePay: 154000.0}';
  try {
     jsonDecode(dartMapString);
  } catch (e) {
     print("Error 2: $e");
  }
}
