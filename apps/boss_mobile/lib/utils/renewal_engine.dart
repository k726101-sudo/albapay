import 'package:hive/hive.dart';
import 'package:shared_logic/shared_logic.dart';
import '../models/worker.dart';

class RenewalEngine {
  /// 현재 최저임금 기준에 미달하는 모든 재직중인 직원을 추출합니다.
  static List<Worker> getPendingRenewals() {
    final box = Hive.box<Worker>('workers');
    final activeWorkers = box.values.where((w) => w.status == 'active').toList();
    
    final affected = <Worker>[];
    for (final worker in activeWorkers) {
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
