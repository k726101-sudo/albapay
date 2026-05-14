import 'package:flutter/material.dart';
import '../theme/verify_theme.dart';
import '../widgets/verify_meta_header.dart';
import 'hourly_verify_screen.dart';
import 'monthly_verify_screen.dart';
import 'severance_verify_screen.dart';
import 'detailed_verify_screen.dart';

/// 검증기 메인 화면 — 시급제/월급제 탭으로 구성
class VerifyHomeScreen extends StatefulWidget {
  const VerifyHomeScreen({super.key});

  @override
  State<VerifyHomeScreen> createState() => _VerifyHomeScreenState();
}

class _VerifyHomeScreenState extends State<VerifyHomeScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [VerifyTheme.accentPrimary, VerifyTheme.accentSecondary],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.verified_outlined, size: 20, color: Colors.white),
            ),
            const SizedBox(width: 12),
            const Text('AlbaPay 급여 검증기', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.access_time), text: '시급제'),
            Tab(icon: Icon(Icons.calendar_month), text: '월급제'),
            Tab(icon: Icon(Icons.account_balance), text: '퇴직금'),
            Tab(icon: Icon(Icons.table_chart), text: '상세검증'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, size: 20),
            tooltip: '나가기',
            onPressed: () => Navigator.pushReplacementNamed(context, '/'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          const VerifyMetaHeader(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [
                HourlyVerifyScreen(),
                MonthlyVerifyScreen(),
                SeveranceVerifyScreen(),
                DetailedVerifyScreen(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
