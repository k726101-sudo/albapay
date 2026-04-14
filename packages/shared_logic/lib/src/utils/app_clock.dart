import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';

/// 디버그 빌드에서만 가상 시각을 쓸 수 있습니다. 릴리스에서는 항상 실제 시각과 동일합니다.
class AppClock extends ChangeNotifier {
  AppClock._();
  static final AppClock instance = AppClock._();

  DateTime? _debugOverride;
  String? _syncedStoreId;
  StreamSubscription? _syncSub;

  /// 앱 전체에서 `DateTime.now()` 대신 사용합니다.
  static DateTime now() {
    if (kDebugMode && instance._debugOverride != null) {
      return instance._debugOverride!;
    }
    return DateTime.now();
  }

  /// [simulated] 가 null이면 실제 시간을 사용하도록 초기화합니다.
  /// [pushToFirestore] 가 true이면 파이어베이스 전역 채널('invites/global_debug_time_sync')에도 기록합니다.
  static void setDebugOverride(DateTime? simulated, {bool pushToFirestore = true}) {
    if (!kDebugMode) return;
    debugPrint('[AppClock] setDebugOverride: $simulated (pushToFirestore: $pushToFirestore)');
    instance._debugOverride = simulated;
    instance.notifyListeners();

    if (pushToFirestore) {
      FirebaseFirestore.instance
          .collection('debug')
          .doc('global_time_sync')
          .set({
        'timeOverride': simulated != null ? Timestamp.fromDate(simulated) : null,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  /// 전역 디버그 시각 설정을 실시간으로 감시하여 동기화합니다.
  static void syncWithFirestore([String? unusedStoreId]) {
    if (!kDebugMode) return;
    if (instance._syncSub != null) return;

    debugPrint('[AppClock] Starting global debug time sync (Real-time stream)...');
    instance._syncSub = FirebaseFirestore.instance
        .collection('debug')
        .doc('global_time_sync')
        .snapshots()
        .listen((snap) {
      if (!snap.exists) return;
      final data = snap.data();
      if (data == null) return;

      final remoteTime = data['timeOverride'] as Timestamp?;
      final newTime = remoteTime?.toDate();

      if (instance._debugOverride?.millisecondsSinceEpoch !=
          newTime?.millisecondsSinceEpoch) {
        debugPrint('[AppClock] Global time synced: $newTime');
        setDebugOverride(newTime, pushToFirestore: false);
      }
    }, onError: (e) {
      debugPrint('[AppClock] Global time sync failed: $e');
    });
  }

  static bool get isDebugOverrideActive =>
      kDebugMode && instance._debugOverride != null;

  @override
  void dispose() {
    _syncSub?.cancel();
    super.dispose();
  }
}
