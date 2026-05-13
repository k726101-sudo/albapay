import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// 백그라운드 메시지 핸들러 (main.dart 에서 등록)
/// 반드시 top-level 함수여야 함 (앱 종료 상태에서도 실행)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // 백그라운드/종료 상태에서는 OS가 알림 트레이를 자동 표시
  // 필요 시 로컬 저장 로직 추가
  debugPrint('[FCM Background] ${message.messageId} — ${message.notification?.title}');
}

class PushService {
  PushService._();
  static final PushService instance = PushService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String? _boundTopic;
  String? _boundWorkersTopic;
  bool _handlersInitialized = false;

  /// 포그라운드 메시지 수신 시 알림 표시용 콜백
  /// main.dart의 _AuthGate에서 BuildContext와 함께 설정
  void Function(RemoteMessage message)? onForegroundMessage;

  /// 알림 탭 시 화면 이동용 콜백
  void Function(Map<String, dynamic> data)? onNotificationTap;

  // ─────────────────────────────────────────────────────────
  // 포그라운드/백그라운드 메시지 수신 핸들러 초기화
  // ─────────────────────────────────────────────────────────

  void initializeHandlers({
    required GlobalKey<NavigatorState> navigatorKey,
  }) {
    if (_handlersInitialized) return;
    _handlersInitialized = true;

    // 포그라운드 메시지 (앱이 열려 있을 때)
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('[FCM Foreground] ${message.notification?.title}');
      onForegroundMessage?.call(message);
    });

    // 백그라운드에서 알림 탭하여 앱을 열었을 때
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('[FCM Tap] ${message.data}');
      _handleNotificationTap(message.data, navigatorKey);
    });

    // 앱 완전 종료 상태에서 알림 탭 → 앱 실행 시 초기 메시지 확인
    _messaging.getInitialMessage().then((RemoteMessage? message) {
      if (message != null) {
        debugPrint('[FCM Initial] ${message.data}');
        // 약간의 딜레이를 줘서 Navigator가 준비된 후 이동
        Future.delayed(const Duration(milliseconds: 800), () {
          _handleNotificationTap(message.data, navigatorKey);
        });
      }
    });
  }

  void _handleNotificationTap(
    Map<String, dynamic> data,
    GlobalKey<NavigatorState> navigatorKey,
  ) {
    onNotificationTap?.call(data);
    // Deep Link 이동 (#9)
    // route 필드가 있으면 해당 화면으로 이동
    // 현재는 콜백을 통해 main.dart에서 처리
  }

  // ─────────────────────────────────────────────────────────
  // 사전 동의 다이얼로그 (#5 알림 권한 UX)
  // iOS에서 OS 팝업 직접 띄우지 않고 먼저 설명
  // ─────────────────────────────────────────────────────────

  Future<bool> requestPermissionWithExplanation(BuildContext context) async {
    if (kIsWeb) return false;

    // 이미 권한이 있는지 확인
    final settings = await _messaging.getNotificationSettings();
    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      return true;
    }
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      return false; // 이미 거부됨 — OS 설정으로 유도 필요
    }

    // 사전 설명 다이얼로그
    if (!context.mounted) return false;
    final shouldRequest = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.notifications_active_outlined,
            size: 48, color: Color(0xFF1a1a2e)),
        title: const Text('알림을 허용하시겠어요?'),
        content: const Text(
          '알림을 허용하면 아래 정보를 빠르게 확인할 수 있어요:\n\n'
          '• 이상 근태 감지 (지각·조기퇴근·무단출근)\n'
          '• 보건증 만료 임박 알림\n'
          '• 대근 신청 도착\n'
          '• 서류 교부 완료\n'
          '• 새 공지사항 (알바생)',
          style: TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('나중에'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('허용하기'),
          ),
        ],
      ),
    );

    if (shouldRequest != true) return false;

    // OS 권한 요청
    final result = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    return result.authorizationStatus == AuthorizationStatus.authorized;
  }

  // ─────────────────────────────────────────────────────────
  // 사장님 푸시 바인딩
  // ─────────────────────────────────────────────────────────

  Future<void> bindBossPush({
    required String uid,
    required String storeId,
  }) async {
    if (kIsWeb) return; // 웹에서는 Topic 구독 및 FCM 기능 바이패스
    if (storeId.isEmpty) return;
    final topic = _topicForStore(storeId);
    if (_boundTopic != null && _boundTopic != topic) {
      await _messaging.unsubscribeFromTopic(_boundTopic!);
    }

    // 알림 권한이 아직 없으면 여기서는 조용히 넘어감
    // (권한 요청은 initializeHandlers 이후 별도 트리거)
    final settings = await _messaging.getNotificationSettings();
    if (settings.authorizationStatus != AuthorizationStatus.authorized) {
      // 권한 없어도 토큰 등록은 시도 (나중에 허용 시 즉시 수신 가능)
    }

    await _messaging.subscribeToTopic(topic);
    _boundTopic = topic;

    final token = await _messaging.getToken();
    if (token != null && token.isNotEmpty) {
      await _db.collection('users').doc(uid).set(
        {
          // storeId는 매장 등록/acceptInvite 시점에 이미 설정됨 — 중복 기록 제거
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
          'fcmTokens': FieldValue.arrayUnion([newToken]),
          'pushRole': 'boss',
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }

  // ─────────────────────────────────────────────────────────
  // 알바생 푸시 바인딩
  // ─────────────────────────────────────────────────────────

  Future<void> bindWorkerPush({
    required String uid,
    required String storeId,
    required String workerId,
  }) async {
    if (kIsWeb) return;
    if (storeId.isEmpty || workerId.isEmpty) return;
    final topic = _topicForWorker(storeId, workerId);
    if (_boundTopic != null && _boundTopic != topic) {
      await _messaging.unsubscribeFromTopic(_boundTopic!);
    }

    await _messaging.subscribeToTopic(topic);
    _boundTopic = topic;

    // 전체 알바생 Topic도 구독 (공지사항 수신용)
    final workersTopic = _topicForAllWorkers(storeId);
    if (_boundWorkersTopic != workersTopic) {
      if (_boundWorkersTopic != null) {
        await _messaging.unsubscribeFromTopic(_boundWorkersTopic!);
      }
      await _messaging.subscribeToTopic(workersTopic);
      _boundWorkersTopic = workersTopic;
    }

    final token = await _messaging.getToken();
    if (token != null && token.isNotEmpty) {
      await _db.collection('users').doc(uid).set(
        {
          'fcmTokens': FieldValue.arrayUnion([token]),
          'pushRole': 'worker',
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }

    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      await _db.collection('users').doc(uid).set(
        {
          'fcmTokens': FieldValue.arrayUnion([newToken]),
          'pushRole': 'worker',
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }

  // ─────────────────────────────────────────────────────────
  // 로그아웃/퇴사 시 푸시 해제 (#4 Topic unsubscribe)
  // ─────────────────────────────────────────────────────────

  Future<void> unbindPush({String? uid}) async {
    if (kIsWeb) return;

    // Topic 구독 해제
    if (_boundTopic != null) {
      try {
        await _messaging.unsubscribeFromTopic(_boundTopic!);
      } catch (_) {}
      _boundTopic = null;
    }
    if (_boundWorkersTopic != null) {
      try {
        await _messaging.unsubscribeFromTopic(_boundWorkersTopic!);
      } catch (_) {}
      _boundWorkersTopic = null;
    }

    // 서버에서 FCM 토큰 제거 (#3 FCM 토큰 관리)
    if (uid != null && uid.isNotEmpty) {
      try {
        final token = await _messaging.getToken();
        if (token != null && token.isNotEmpty) {
          await _db.collection('users').doc(uid).update({
            'fcmTokens': FieldValue.arrayRemove([token]),
          });
        }
      } catch (e) {
        debugPrint('[PushService] Token cleanup failed: $e');
      }
    }

    // 핸들러 상태 리셋
    _handlersInitialized = false;
    onForegroundMessage = null;
    onNotificationTap = null;
  }

  String _topicForStore(String storeId) => 'store_${storeId}_boss';
  String _topicForWorker(String storeId, String workerId) => 'store_${storeId}_worker_$workerId';
  String _topicForAllWorkers(String storeId) => 'store_${storeId}_workers';

  // ─────────────────────────────────────────────────────────
  // In-App Alert Badge (#7 장애 Fallback)
  // FCM 실패 시 Cloud Functions가 inAppAlerts 컬렉션에 저장
  // 앱에서 읽어서 뱃지/목록으로 표시
  // ─────────────────────────────────────────────────────────

  /// 읽지 않은 알림 수 스트림 (앱 뱃지 표시용)
  Stream<int> unreadAlertCount(String uid) {
    return _db
        .collection('users')
        .doc(uid)
        .collection('inAppAlerts')
        .where('read', isEqualTo: false)
        .snapshots()
        .map((snap) => snap.size);
  }

  /// 읽지 않은 알림 목록 스트림
  Stream<List<Map<String, dynamic>>> unreadAlerts(String uid) {
    return _db
        .collection('users')
        .doc(uid)
        .collection('inAppAlerts')
        .where('read', isEqualTo: false)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snap) => snap.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }

  /// 알림 읽음 처리
  Future<void> markAlertRead(String uid, String alertId) async {
    await _db
        .collection('users')
        .doc(uid)
        .collection('inAppAlerts')
        .doc(alertId)
        .update({'read': true});
  }

  /// 모든 알림 읽음 처리
  Future<void> markAllAlertsRead(String uid) async {
    final snap = await _db
        .collection('users')
        .doc(uid)
        .collection('inAppAlerts')
        .where('read', isEqualTo: false)
        .get();
    final batch = _db.batch();
    for (final doc in snap.docs) {
      batch.update(doc.reference, {'read': true});
    }
    await batch.commit();
  }
}
