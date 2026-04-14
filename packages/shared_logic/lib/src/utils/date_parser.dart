import 'package:shared_logic/shared_logic.dart';

class RobustDateParser {
  /// 다양한 날짜 형식을 시도하여 DateTime으로 변환합니다.
  /// 지원 형식: "YYYY-MM-DD", "YYYY. MM. DD.", "YY. M. D", "YYYY/MM/DD" 등
  static DateTime? parse(String? input) {
    if (input == null || input.trim().isEmpty) return null;

    final trimmed = input.trim();

    // 1. 표준 ISO 8601 시도
    final iso = DateTime.tryParse(trimmed);
    if (iso != null) return iso;

    try {
      // 2. 구분자(., /, -)를 기준으로 분리하여 수동 파싱
      // 숫자 이외의 문자를 공백으로 치환 후 split
      final clean = trimmed.replaceAll(RegExp(r'[^0-9]'), ' ').trim();
      final parts = clean.split(RegExp(r'\s+'));

      if (parts.length >= 3) {
        int year = int.parse(parts[0]);
        int month = int.parse(parts[1]);
        int day = int.parse(parts[2]);

        // "25" -> 2025 (상식적인 범위 내에서 보정)
        if (year < 100) {
          year += (year > 50) ? 1900 : 2000;
        }

        return DateTime(year, month, day);
      }
    } catch (_) {
      // 파싱 실패 시 null
    }

    return null;
  }

  /// 파싱 실패 시 기본값(보통 현재 시각)을 반환하는 헬퍼
  static DateTime parseWithFallback(String? input, {DateTime? fallback}) {
    return parse(input) ?? fallback ?? AppClock.now();
  }
}
