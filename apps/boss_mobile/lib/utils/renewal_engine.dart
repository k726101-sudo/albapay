import 'package:hive/hive.dart';
import 'package:shared_logic/shared_logic.dart';
import '../models/worker.dart';

class RenewalEngine {
  /// 현재 최저임금 기준에 미달하는 시급제 재직 직원을 추출합니다.
  /// ★ 월급제(wageType == 'monthly')는 완전 제외
  /// ★ 기존 시급 ≥ 최저임금이면 대상에서 제외 (시급 인하 방지)
  static List<Worker> getPendingRenewals() {
    final box = Hive.box<Worker>('workers');
    final activeWorkers = box.values.where((w) => w.status == 'active').toList();
    
    final affected = <Worker>[];
    for (final worker in activeWorkers) {
      // ★ 월급제 완전 제외 — 월급제는 환산시급 비교가 아니라
      //   별도 컴플라이언스 엔진(compliance_engine)에서 관리
      if (worker.wageType == 'monthly') continue;

      // ── 시급제: hourlyWage 직접 비교 ──
      // ★ 기존 시급 < 최저임금인 경우만 대상 (시급 인하 방지)
      if (worker.hourlyWage < PayrollConstants.legalMinimumWage) {
        affected.add(worker);
      }
    }
    
    return affected;
  }

  /// 최저임금 갱신 필요 알림이 떠야 하는지 확인
  static bool hasPendingRenewals() {
    return getPendingRenewals().isNotEmpty;
  }
}
