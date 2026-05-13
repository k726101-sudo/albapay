import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_logic/shared_logic.dart';

import '../models/worker.dart';

class HealthCertificateAlertService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> syncAlerts({
    required String storeId,
  }) async {
    final settingRef = _db
        .collection('stores')
        .doc(storeId)
        .collection('notificationSettings')
        .doc('healthCertificate');

    final settingSnap = await settingRef.get();
    final setting = settingSnap.data() ?? {};
    final thresholds = _parseThresholds(setting['thresholdDays']);

    final channels = <String, bool>{
      'pushBoss': setting['pushBoss'] ?? true,
      'pushStaff': setting['pushStaff'] ?? true,
      'sms': setting['sms'] ?? false,
      'kakao': setting['kakao'] ?? false,
    };

    final storeSnap = await _db.collection('stores').doc(storeId).get();
    final store = storeSnap.exists ? Store.fromJson(storeSnap.data()!) : null;

    final staffSnap = await _db
        .collection('stores')
        .doc(storeId)
        .collection('workers')
        .get();
    final staffList = staffSnap.docs.map((d) => Worker.fromMap(d.id, d.data())).toList();

    final today = AppClock.now();
    final todayKey = DateTime(today.year, today.month, today.day);
    final activeIds = <String>{};

    for (final staff in staffList) {
      if (!staff.hasHealthCert) continue;
      final expiry = staff.healthCertExpiry == null ? null : DateTime.tryParse(staff.healthCertExpiry!);
      if (expiry == null) continue;

      final expKey = DateTime(expiry.year, expiry.month, expiry.day);
      final daysLeft = expKey.difference(todayKey).inDays;
      final level = _level(daysLeft, thresholds);
      if (level == null) continue;

      final alertId = '${staff.id}_$level';
      activeIds.add(alertId);

      final alertRef = _db
          .collection('stores')
          .doc(storeId)
          .collection('healthCertAlerts')
          .doc(alertId);

      await alertRef.set({
        'id': alertId,
        'storeId': storeId,
        'staffId': staff.id,
        'staffName': staff.name,
        'staffPhone': staff.phone,
        'level': level,
        'daysLeft': daysLeft,
        'expiryDate': expKey.toIso8601String(),
        'resolved': false,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await _enqueueNotifications(
        storeId: storeId,
        alertId: alertId,
        staff: staff,
        ownerUid: store?.ownerId ?? '',
        level: level,
        daysLeft: daysLeft,
        channels: channels,
      );
    }

    final currentAlerts = await _db
        .collection('stores')
        .doc(storeId)
        .collection('healthCertAlerts')
        .where('resolved', isEqualTo: false)
        .get();
    for (final doc in currentAlerts.docs) {
      if (activeIds.contains(doc.id)) continue;
      await doc.reference.set({
        'resolved': true,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  Future<void> _enqueueNotifications({
    required String storeId,
    required String alertId,
    required Worker staff,
    required String ownerUid,
    required String level,
    required int daysLeft,
    required Map<String, bool> channels,
  }) async {
    final message = daysLeft < 0
        ? '[보건증 만료] ${staff.name} (${staff.phone})'
        : '[보건증 임박-$daysLeft일] ${staff.name} (${staff.phone})';

    // notificationQueue update는 차단됨 — 이미 적재된 알림은 skip (idempotent)
    Future<void> enqueueIfAbsent(String docId, Map<String, dynamic> data) async {
      final ref = _db.collection('notificationQueue').doc(docId);
      final snap = await ref.get();
      if (!snap.exists) {
        await ref.set(data);
      }
    }

    if (channels['pushBoss'] == true && ownerUid.isNotEmpty) {
      await enqueueIfAbsent('${alertId}_pushBoss', {
        'dedupeKey': '${alertId}_pushBoss',
        'storeId': storeId,
        'alertId': alertId,
        'channel': 'pushBoss',
        'targetUid': ownerUid,
        'status': 'queued',
        'message': message,
        'level': level,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    if (channels['pushStaff'] == true) {
      await enqueueIfAbsent('${alertId}_pushStaff', {
        'dedupeKey': '${alertId}_pushStaff',
        'storeId': storeId,
        'alertId': alertId,
        'channel': 'pushStaff',
        'targetStaffId': staff.id,
        'status': 'queued',
        'message': message,
        'level': level,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    if (channels['sms'] == true) {
      await enqueueIfAbsent('${alertId}_sms', {
        'dedupeKey': '${alertId}_sms',
        'storeId': storeId,
        'alertId': alertId,
        'channel': 'sms',
        'targetPhone': staff.phone,
        'status': 'queued',
        'message': message,
        'level': level,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    if (channels['kakao'] == true) {
      await enqueueIfAbsent('${alertId}_kakao', {
        'dedupeKey': '${alertId}_kakao',
        'storeId': storeId,
        'alertId': alertId,
        'channel': 'kakao',
        'targetPhone': staff.phone,
        'status': 'queued',
        'message': message,
        'level': level,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  List<int> _parseThresholds(dynamic raw) {
    final values = (raw as List?)
            ?.map((e) => e is num ? e.toInt() : int.tryParse(e.toString()))
            .whereType<int>()
            .where((e) => e > 0)
            .toList() ??
        <int>[30, 15, 7];
    values.sort((a, b) => b.compareTo(a));
    return values.toSet().toList();
  }

  String? _level(int daysLeft, List<int> thresholds) {
    if (daysLeft < 0) return 'expired';
    for (final t in thresholds.reversed) {
      if (daysLeft <= t) return 'd$t';
    }
    return null;
  }
}

