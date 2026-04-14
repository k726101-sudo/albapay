import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class PushService {
  PushService._();
  static final PushService instance = PushService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String? _boundTopic;

  Future<void> bindBossPush({
    required String uid,
    required String storeId,
  }) async {
    if (storeId.isEmpty) return;
    final topic = _topicForStore(storeId);
    if (_boundTopic != null && _boundTopic != topic) {
      await _messaging.unsubscribeFromTopic(_boundTopic!);
    }

    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    await _messaging.subscribeToTopic(topic);
    _boundTopic = topic;

    final token = await _messaging.getToken();
    if (token != null && token.isNotEmpty) {
      await _db.collection('users').doc(uid).set(
        {
          'storeId': storeId,
          'fcmTokens': FieldValue.arrayUnion([token]),
          'pushRole': 'boss',
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }

    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      await _db.collection('users').doc(uid).set(
        {
          'storeId': storeId,
          'fcmTokens': FieldValue.arrayUnion([newToken]),
          'pushRole': 'boss',
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }

  String _topicForStore(String storeId) => 'store_${storeId}_boss';
}

