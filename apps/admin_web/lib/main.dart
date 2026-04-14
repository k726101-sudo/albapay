import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'screens/dashboard_screen.dart';
// import 'firebase_options.dart'; // 주석 처리: 사용자가 flutterfire configure 후 해제 필요

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // TODO: 터미널에서 `flutterfire configure` 실행하여 admin_web 프로젝트용 옵션 파일을 생성한 뒤,
  // 아래 주석을 해제하면 Firestore 통신이 가능해집니다.
  /*
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  */
  
  runApp(const AdminWebApp());
}

class AdminWebApp extends StatelessWidget {
  const AdminWebApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PB 관리자 - 프로모션 파서',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'NotoSansKR', // boss_mobile과 폰트 통일성 유지
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueAccent),
        useMaterial3: true,
      ),
      home: const DashboardScreen(),
    );
  }
}
