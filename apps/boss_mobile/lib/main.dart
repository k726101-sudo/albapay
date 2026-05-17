import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:app_links/app_links.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_logic/shared_logic.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/schedule_override.dart';
import 'models/store_info.dart';
import 'models/worker.dart';
import 'services/boss_logout.dart';
import 'services/store_cache_service.dart';
import 'services/push_service.dart';
import 'services/worker_service.dart';
import 'screens/login_screen.dart';
import 'screens/main_screen.dart';
import 'screens/store_info_page.dart';
import 'screens/store/store_setup_screen.dart';
import 'screens/alba/alba_main_screen.dart';
import 'theme/app_theme.dart';
import 'package:workmanager/workmanager.dart';
import 'services/server_cleanup_service.dart';
import 'firebase_options.dart';
import 'screens/web/web_invite_landing_screen.dart';
import 'screens/web/web_access_denied_screen.dart';
import 'screens/web/web_doc_view_screen.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName == 'server_cleanup') {
      try {
        final storeId = await WorkerService.resolveStoreId();
        if (storeId.isNotEmpty) {
          await ServerCleanupService.runAutomaticCleanup(storeId);
        }
        return Future.value(true);
      } catch (e) {
        return Future.value(false);
      }
    }
    return Future.value(true);
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await initializeDateFormatting('ko_KR', null);

  await Hive.initFlutter();
  Hive.registerAdapter(StoreInfoAdapter());
  Hive.registerAdapter(WorkerAdapter());
  Hive.registerAdapter(AllowanceAdapter());
  Hive.registerAdapter(LeaveUsageLogAdapter());
  Hive.registerAdapter(ScheduleOverrideAdapter());
  await Hive.openBox<StoreInfo>('store');
  await Hive.openBox<Worker>('workers');
  await Hive.openBox<ScheduleOverride>('schedule_overrides');

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // 백그라운드/종료 상태 FCM 메시지 핸들러 등록 (#6)
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  if (false && kDebugMode && !kIsWeb) { // 운영 서버 연결(옵션 1)을 위해 에뮬레이터 접속 강제 비활성화
    // 사장님의 현재 WiFi 실시간 IP (192.168.0.168)로 접속 방식을 통일합니다.
    // 안드로이드 에뮬레이터(10.0.2.2)가 불안정할 경우를 대비하여 실제 IP를 최우선으로 사용합니다.
    const host = '192.168.0.168';
    
    debugPrint('====================================================');
    debugPrint('[EMULATOR CONNECTING] Target Host: $host');
    debugPrint('[EMULATOR CONNECTING] Auth Port: 9099, Firestore Port: 8080');
    debugPrint('====================================================');

    try {
      FirebaseAuth.instance.useAuthEmulator(host, 9099);
      FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
      debugPrint('[EMULATOR SUCCESS] UseAuthEmulator & UseFirestoreEmulator Called.');
    } catch (e) {
      debugPrint('[EMULATOR FATAL ERROR] Connection Config Failed: $e');
    }
  }

  if (!kIsWeb) {
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: kDebugMode,
    );

    // 매일 새벽 3시 백업 예약
    final now = AppClock.now();
    var scheduledTime = DateTime(now.year, now.month, now.day, 3, 0);
    if (scheduledTime.isBefore(now)) {
      scheduledTime = scheduledTime.add(const Duration(days: 1));
    }
    final initialDelay = scheduledTime.difference(now);

    // 백업은 수동 파일 저장으로 대체되었으므로 자동 백업 등록을 제거합니다.

    await Workmanager().registerPeriodicTask(
      '2',
      'server_cleanup',
      frequency: const Duration(days: 7), // 서버 클린업은 주 1회면 충분함
      initialDelay: initialDelay + const Duration(hours: 1), // 백업 1시간 뒤 실행
      constraints: Constraints(
        networkType: NetworkType.unmetered,
        requiresCharging: true,
      ),
    );
  }

  // 디버그 빌드 시 앱 실행 즉시 전역 시각 동기화 시작 (공용 채널)
  if (kDebugMode) {
    AppClock.syncWithFirestore();
  }

  runApp(const BossApp());

  // 앱 첫 프레임을 먼저 띄운 뒤 백그라운드에서 동기화합니다.
  Future<void>(() async {
    await StoreCacheService.syncFirestoreToHive();
    await WorkerService.migrateStaffToWorker();
    await WorkerService.syncFromFirebase();
    await WorkerService.startRealtimeSync();
    await WorkerService.enqueueProbationEndingAlerts();
    // 기존 직원 → workerProfiles 일회성 마이그레이션 (이미 존재하면 skip)
    await WorkerService.backfillWorkerProfiles();
  });
}

/// 전역 Navigator 키 (푸시 알림 탭 시 화면 이동용)
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class BossApp extends StatefulWidget {
  const BossApp({super.key});

  @override
  State<BossApp> createState() => _BossAppState();
}

class _BossAppState extends State<BossApp> {
  late final AppLifecycleListener _listener;

  @override
  void initState() {
    super.initState();
    _listener = AppLifecycleListener(
      // 수동 백업 전환에 따라 자동 백업 제거
    );
  }

  @override
  void dispose() {
    _listener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: '알바급여정석 - 사장님용',
      debugShowCheckedModeBanner: false,
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        dragDevices: {
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.trackpad,
        },
      ),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('ko', 'KR'),
        Locale('en', 'US'),
      ],
      theme: AppTheme.lightTheme.copyWith(
        primaryColor: const Color(0xFF1a1a2e),
        scaffoldBackgroundColor: const Color(0xFFF2F2F7),
      ),
      builder: (context, child) {
        final inner = GestureDetector(
          onTap: () {
            // 빈 공간 터치 시 키보드 숨김 처리 (주로 iOS에서 필수)
            FocusManager.instance.primaryFocus?.unfocus();
          },
          behavior: HitTestBehavior.translucent,
          child: Container(
            color: const Color(0xFFF2F2F7), // 하단 네비게이션 바와 위화감 없도록 기본 배경색 연동
            child: SafeArea(
              top: false, // 상단은 AppBar가 알아서 처리
              left: true, // 아이패드, Z폴드, 가로모드 컷아웃(노치) 보호
              right: true,
              bottom: true, // 하단 제스처/네비게이션 바 침범 방지 (글로벌 적용)
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        );

        if (kIsWeb) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: inner,
            ),
          );
        }
        return inner;
      },
      home: const _AuthGate(),
      onGenerateRoute: (settings) {
        if (!kIsWeb) return null;
        final uri = Uri.parse(settings.name ?? '');
        // 웹에서 /doc-view?id=xxx&storeId=yyy 접근 시 서류 뷰어로 라우팅
        if (uri.path == '/doc-view') {
          final id = uri.queryParameters['id'] ?? '';
          final storeId = uri.queryParameters['storeId'] ?? '';
          if (id.isNotEmpty && storeId.isNotEmpty) {
            return MaterialPageRoute(
              builder: (_) => WebDocViewScreen(docId: id, storeId: storeId),
              settings: settings,
            );
          }
        }
        return null;
      },
    );
  }
}

class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  final _appLinks = AppLinks();
  final _authService = AuthService();
  final _consentService = ConsentService();
  final _db = FirebaseFirestore.instance;
  String? _pushBoundForStoreId;
  bool _pushPermissionAsked = false;

  @override
  void initState() {
    super.initState();
    _listenLinks();
    _initPushHandlers();
  }

  void _initPushHandlers() {
    if (kIsWeb) return;
    PushService.instance.initializeHandlers(navigatorKey: navigatorKey);

    // 포그라운드 메시지 수신 시 SnackBar 표시
    PushService.instance.onForegroundMessage = (message) {
      final ctx = navigatorKey.currentContext;
      if (ctx == null) return;
      final title = message.notification?.title ?? '';
      final body = message.notification?.body ?? '';
      if (title.isEmpty && body.isEmpty) return;

      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title.isNotEmpty)
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              if (body.isNotEmpty)
                Text(body, style: const TextStyle(fontSize: 13)),
            ],
          ),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: '확인',
            textColor: Colors.white,
            onPressed: () {},
          ),
        ),
      );
    };
  }

  Future<void> _listenLinks() async {
    // initial link (cold start)
    final initial = await _appLinks.getInitialLink();
    if (initial != null) {
      await _handleLink(initial);
    }

    // stream links (warm)
    _appLinks.uriLinkStream.listen((uri) {
      _handleLink(uri);
    });
  }

  bool _isWebInvite = false;
  String? _webInviteCode;

  Future<void> _handleLink(Uri uri) async {
    final link = uri.toString();

    if (kIsWeb && uri.path.startsWith('/invite')) {
      final code = uri.queryParameters['code'] ?? uri.queryParameters['invite'];
      if (mounted) {
        setState(() {
          _isWebInvite = true;
          _webInviteCode = code;
        });
      }
      return;
    }

    // 1. Email Link 파싱
    if (_authService.isSignInWithEmailLink(link)) {
      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString('emailForSignIn')?.trim();
      if (email == null || email.isEmpty) return;

      final cred = await _authService.signInWithEmailLink(email, link);
      if (cred != null) {
        await prefs.remove('emailForSignIn');
      }
      return;
    }

    // 2. 초대 코드 파싱 (ex: https://.../invite?code=ABCDEF 또는 ?invite=ABCDEF)
    final inviteCode = uri.queryParameters['code'] ?? uri.queryParameters['invite'];
    if (inviteCode != null && inviteCode.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pending_invite_code', inviteCode);
    }

    // 3. 출퇴근 QR 딥링크 파싱 (ex: ?action=attendance&storeId=...)
    final action = uri.queryParameters['action'];
    final storeId = uri.queryParameters['storeId'] ?? uri.queryParameters['store_id'];
    if (action == 'attendance' && storeId != null && storeId.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pending_attendance_store_id', storeId);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isWebInvite) {
      return WebInviteLandingScreen(inviteCode: _webInviteCode);
    }

    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        final user = snap.data;
        if (user == null) return const LoginScreen();
        return FutureBuilder<void>(
          future: _consentService.ensureConsentRecorded(
            uid: user.uid,
            platform: 'boss_mobile',
          ),
          builder: (context, consentSnap) {
            if (consentSnap.connectionState != ConnectionState.done) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            if (consentSnap.hasError) {
              return Scaffold(
                body: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            '동의 정보를 저장하지 못했습니다.\n'
                            '(네트워크 또는 Firestore 규칙을 확인해 주세요.)',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          SelectableText(
                            consentSnap.error.toString(),
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          const SizedBox(height: 24),
                          FilledButton(
                            onPressed: () => performBossLogout(_authService),
                            child: const Text('로그아웃 후 다시 시도'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }

            return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: _db.collection('users').doc(user.uid).snapshots(),
              builder: (context, userDocSnap) {
                if (userDocSnap.connectionState == ConnectionState.waiting) {
                  return const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  );
                }

                final data = userDocSnap.data?.data();
                final storeId = data?['storeId'];
                final hasStore = storeId is String && storeId.trim().isNotEmpty;

                if (!hasStore) {
                  // store_onboarding_completed 플래그 확인
                  return FutureBuilder<bool>(
                    future: isStoreOnboardingCompleted(),
                    builder: (context, completedSnap) {
                      if (completedSnap.connectionState != ConnectionState.done) {
                        return const Scaffold(
                          body: Center(child: CircularProgressIndicator()),
                        );
                      }
                      final isCompleted = completedSnap.data ?? false;
                      if (isCompleted) {
                        // Firestore storeId 동기화 딜레이 케이스 → 잠시 대기
                        return const Scaffold(
                          body: Center(child: CircularProgressIndicator()),
                        );
                      }
                      return const StoreSetupScreen();
                    },
                  );
                }

                final workerId = data?['workerId'];
                final isWorker = workerId is String && workerId.trim().isNotEmpty;

                final trimmedStoreId = storeId.trim();

                if (isWorker) {
                  if (kIsWeb) {
                    return WebAccessDeniedScreen();
                  }

                  if (_pushBoundForStoreId != trimmedStoreId) {
                    _pushBoundForStoreId = trimmedStoreId;
                    AppClock.syncWithFirestore(trimmedStoreId);
                    unawaited(
                      PushService.instance.bindWorkerPush(
                        uid: user.uid,
                        storeId: trimmedStoreId,
                        workerId: workerId.trim(),
                      ),
                    );
                    // 알림 권한 사전 요청 (#5)
                    if (!_pushPermissionAsked) {
                      _pushPermissionAsked = true;
                      Future.delayed(const Duration(seconds: 2), () {
                        final ctx = navigatorKey.currentContext;
                        if (ctx != null) {
                          PushService.instance.requestPermissionWithExplanation(ctx);
                        }
                      });
                    }
                  }

                  return AlbaMainScreen(
                    storeId: trimmedStoreId,
                    workerId: workerId.trim(),
                  );
                }

                if (_pushBoundForStoreId != trimmedStoreId) {
                  _pushBoundForStoreId = trimmedStoreId;
                  AppClock.syncWithFirestore(trimmedStoreId);
                  unawaited(
                    PushService.instance.bindBossPush(
                      uid: user.uid,
                      storeId: trimmedStoreId,
                    ),
                  );
                  // 알림 권한 사전 요청 (#5)
                  if (!_pushPermissionAsked) {
                    _pushPermissionAsked = true;
                    Future.delayed(const Duration(seconds: 2), () {
                      final ctx = navigatorKey.currentContext;
                      if (ctx != null) {
                        PushService.instance.requestPermissionWithExplanation(ctx);
                      }
                    });
                  }
                }

                return const MainScreen();
              },
            );
          },
        );
      },
    );
  }
}
