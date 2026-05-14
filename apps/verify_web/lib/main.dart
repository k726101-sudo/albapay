import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'firebase_options.dart';
import 'screens/access_gate_screen.dart';
import 'screens/verify_home_screen.dart';
import 'screens/admin/admin_screen.dart';
import 'theme/verify_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await initializeDateFormatting();
  runApp(const VerifyWebApp());
}

class VerifyWebApp extends StatelessWidget {
  const VerifyWebApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AlbaPay 급여 검증기',
      debugShowCheckedModeBanner: false,
      theme: VerifyTheme.darkTheme,
      initialRoute: '/',
      routes: {
        '/': (_) => const AccessGateScreen(),
        '/verify': (_) => const VerifyHomeScreen(),
        '/admin': (_) => const AdminScreen(),
      },
    );
  }
}
