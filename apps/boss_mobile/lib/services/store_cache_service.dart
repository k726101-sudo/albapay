import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/schedule_override.dart';
import '../models/store_info.dart';
import '../models/worker.dart';

/// Firestore `stores/{storeId}` 문서를 Hive `StoreInfo` 캐시와 맞춥니다.
/// - 인증 게이트는 `users/{uid}.storeId`(서버)를 기준으로 합니다.
/// - 대시보드·계약서 등은 Hive를 주로 쓰므로 두 저장소를 동기화해야 합니다.
///
/// **로그아웃** 시에는 반드시 [clearAllLocalDataOnLogout]으로 기기 캐시를 비워야 합니다.
/// 그렇지 않으면 다음에 다른 계정으로 로그인해도 이전 사용자의 매장·직원 데이터가 남습니다.
class StoreCacheService {
  /// [SharedPreferences]에 마지막으로 Hive를 채운 Firebase uid. 계정이 바뀌면 Hive를 비웁니다.
  static const String _kHiveOwnerUid = 'boss_hive_owner_uid';

  /// 현재 로그인 uid와 다르면 Hive 전부 삭제 후 uid를 기록합니다.
  /// 로그아웃 없이 계정만 바뀌는 경우·앱 재시작 후 다른 계정 로그인에 대응합니다.
  static Future<void> ensureLocalCacheBelongsToCurrentUser() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final bound = prefs.getString(_kHiveOwnerUid);
    if (bound == uid) return;

    debugPrint('StoreCacheService: Hive owner changed ($bound -> $uid), clearing caches.');
    await Hive.box<StoreInfo>('store').clear();
    await Hive.box<Worker>('workers').clear();
    await Hive.box<ScheduleOverride>('schedule_overrides').clear();
    await prefs.setString(_kHiveOwnerUid, uid);
  }

  static int _asInt(dynamic v, int fallback) {
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? fallback;
  }

  static String _pickString(
    Map<String, dynamic> d,
    String key,
    String? fallback,
  ) {
    final raw = d[key];
    final s = raw?.toString().trim();
    if (s != null && s.isNotEmpty) return s;
    return fallback ?? '';
  }

  /// 로그인한 계정의 매장 문서가 있으면 Hive `store` 박스를 갱신합니다.
  static Future<void> syncFirestoreToHive() async {
    try {
      await ensureLocalCacheBelongsToCurrentUser();

      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      final userSnap =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final storeId = userSnap.data()?['storeId'];
      if (storeId is! String || storeId.trim().isEmpty) return;

      final docSnap = await FirebaseFirestore.instance
          .collection('stores')
          .doc(storeId.trim())
          .get();
      if (!docSnap.exists) return;

      final d = docSnap.data() ?? {};
      final box = Hive.box<StoreInfo>('store');
      // 같은 uid라도 서버가 갱신된 직후에는 prev에 남은 타 계정/옛 스냅샷이 없어야 함(ensure에서 이미 처리).
      final prev = box.get('current');

      final btRaw = d['businessType']?.toString().trim();
      final businessType = (btRaw != null && btRaw.isNotEmpty)
          ? btRaw
          : (prev?.businessType ?? 'food');

      final merged = StoreInfo(
        storeName: _pickString(d, 'name', prev?.storeName),
        ownerName: _pickString(d, 'representativeName', prev?.ownerName),
        address: _pickString(d, 'address', prev?.address),
        phone: _pickString(d, 'representativePhoneNumber', prev?.phone),
        businessNumber: _pickString(d, 'businessNumber', prev?.businessNumber),
        businessType: businessType,
        accidentRate: (d['accidentRate'] as num?)?.toDouble() ??
            prev?.accidentRate ??
            0.009,
        legacyGpsRadiusUnused: prev?.legacyGpsRadiusUnused ?? 0,
        useQr: d['useQr'] is bool ? d['useQr'] as bool : (prev?.useQr ?? true),
        payDay: _asInt(d['payday'], prev?.payDay ?? 10),
        payPeriodStartDay:
            _asInt(d['settlementStartDay'], prev?.payPeriodStartDay ?? 16),
        payPeriodEndDay:
            _asInt(d['settlementEndDay'], prev?.payPeriodEndDay ?? 15),
        isDuruNuri: d['isDuruNuri'] is bool
            ? d['isDuruNuri'] as bool
            : (prev?.isDuruNuri ?? false),
        duruNuriMonths:
            _asInt(d['duruNuriMonths'], prev?.duruNuriMonths ?? 36),
        isRegistered: true,
      );

      await box.put('current', merged);
    } catch (e, st) {
      debugPrint('StoreCacheService.syncFirestoreToHive failed: $e\n$st');
    }
  }

  /// 로그아웃 직후: 사업장·직원·스케줄 로컬 캐시 삭제 (계정 전환 시 필수).
  static Future<void> clearAllLocalDataOnLogout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kHiveOwnerUid);
      await Hive.box<StoreInfo>('store').clear();
      await Hive.box<Worker>('workers').clear();
      await Hive.box<ScheduleOverride>('schedule_overrides').clear();
    } catch (e, st) {
      debugPrint('StoreCacheService.clearAllLocalDataOnLogout failed: $e\n$st');
    }
  }
}
