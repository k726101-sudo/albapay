import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_logic/shared_logic.dart';

import '../alba_main_screen.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({
    super.key,
    this.title = '근무표',
    this.storeId,
    this.debugWorkerId,
  });

  final String title;
  final String? storeId;
  /// 디버그 모드에서 출근 중인 알바 ID가 발견된 경우 전달됨.
  /// 설정되면 즉시 AlbaMainScreen으로 이동.
  final String? debugWorkerId;

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.storeId != null) {
      AppClock.syncWithFirestore(widget.storeId!);
    }
    // 디버그 모드에서 출근 중인 알바 ID가 있으면 즉시 해당 알바로 접속
    if (kDebugMode && widget.storeId != null) {
      final effectiveWorkerId = (widget.debugWorkerId?.isNotEmpty == true)
          ? widget.debugWorkerId!
          : FirebaseAuth.instance.currentUser?.uid ?? '';
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => AlbaMainScreen(
              storeId: widget.storeId!,
              workerId: effectiveWorkerId,
            ),
          ),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 디버그 모드에서는 initState에서 바로 이동하므로 로딩 표시만.
    if (kDebugMode && widget.storeId != null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: const Center(
        child: Text('데모 화면입니다. 실제 출퇴근은 홈 탭에서 처리됩니다.'),
      ),
    );
  }
}
