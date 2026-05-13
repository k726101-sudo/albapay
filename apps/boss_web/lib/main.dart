import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_logic/shared_logic.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'screens/login_screen.dart';
import 'screens/legal_screen.dart';
import 'screens/documents/document_view_screen.dart';
import 'theme/app_theme.dart';
import 'firebase_options.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

void main() async {
  usePathUrlStrategy();
  WidgetsFlutterBinding.ensureInitialized();
  
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // 1) MUST set Firestore settings BEFORE any other Firestore calls (persistenceEnabled: false for Web stability)
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: false,
  );

  // 2) persistenceEnabled: false로 오프라인 캐시가 이미 비활성화되었으므로
  // clearPersistence()는 불필요합니다. 오히려 이 호출이 Firestore SDK 내부의
  // Auth 토큰 리스너를 파괴하여, 이후 모든 Firestore 요청이 인증 없이(request.auth=null)
  // 전송되는 치명적인 부작용(permission-denied)을 유발할 수 있어 제거합니다.

  // 3) Connect to local emulators if in debug mode
  if (kDebugMode) {
    const host = '192.168.0.168'; // MacBook Local IP (Latest)
    try {
      await FirebaseAuth.instance.useAuthEmulator(host, 9099);
      FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
    } catch (e) {
      debugPrint('Emulator connection error: $e');
    }
  }

  // 4) Now safe to initialize services that use Firestore
  if (kDebugMode) {
    AppClock.syncWithFirestore();
  }

  // Keep staff web sessions persistent (avoid accidental logout).
  // 웹의 기본 persistence는 LOCAL이므로 명시적 호출이 필수적이지 않으나,
  // iOS Safari 등에서 이 호출이 무한 대기(Hang)에 빠져 앱이 하얀 화면에서 멈추는
  // 치명적 버그가 존재합니다. 이를 방지하기 위해 1초 타임아웃을 설정합니다.
  try {
    await FirebaseAuth.instance.setPersistence(Persistence.LOCAL).timeout(const Duration(seconds: 1));
  } catch (_) {
    debugPrint('setPersistence error or timeout ignored');
  }

  runApp(const AlbaApp());
}

class AlbaApp extends StatelessWidget {
  const AlbaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '알바급여정석 - 사장님 웹',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      builder: (context, child) {
        return Container(
          color: const Color(0xFFF9FAFB), // AppTheme.lightTheme scaffoldBackgroundColor default or similar
          child: SafeArea(
            top: false,
            left: true,
            right: true,
            bottom: true,
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
      onGenerateRoute: (settings) {
        final uri = Uri.parse(settings.name ?? '');
        
        // 1. 법적 고지 페이지 (로그인 불필요)
        if (uri.path == '/terms') {
          return MaterialPageRoute(
            builder: (_) => const LegalScreen(type: 'terms'),
            settings: settings,
          );
        }
        if (uri.path == '/privacy') {
          return MaterialPageRoute(
            builder: (_) => const LegalScreen(type: 'privacy'),
            settings: settings,
          );
        }

        // 2. 문서 뷰어 (로그인 상태 확인은 내부에서 처리)
        if (uri.path == '/doc-view') {
          final id = uri.queryParameters['id'] ?? '';
          final storeId = uri.queryParameters['storeId'] ?? '';
          if (id.isNotEmpty && storeId.isNotEmpty) {
            return MaterialPageRoute(
              builder: (_) => DocumentViewScreen(docId: id, storeId: storeId),
              settings: settings,
            );
          }
        }

        // 3. 기본 경로 (/) 처리: 인증 상태에 따른 분기
        if (uri.path == '/' || uri.path.startsWith('/invite') || settings.name == null) {
          return MaterialPageRoute(
            builder: (_) => StreamBuilder<User?>(
              stream: FirebaseAuth.instance.authStateChanges(),
              builder: (context, snapshot) {
                return const LoginScreen();
              },
            ),
            settings: settings,
          );
        }

        return null; // Fallback
      },

    );
  }
}
