import 'package:shared_logic/shared_logic.dart';

import 'store_cache_service.dart';
import 'worker_service.dart';

/// Firebase·Google SDK 로그아웃 + Hive 캐시 삭제 + Firestore 실시간 구독 해제.
/// 다른 계정으로 다시 로그인할 때 이전 사업장/대시보드 데이터가 남지 않게 합니다.
Future<void> performBossLogout(AuthService auth) async {
  await WorkerService.stopRealtimeSync();
  await auth.signOut();
  await StoreCacheService.clearAllLocalDataOnLogout();
}
