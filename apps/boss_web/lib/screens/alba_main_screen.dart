import 'dart:async';
import 'package:web/web.dart' as web;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_logic/shared_logic.dart';

import 'notice_education_tab_screen.dart';
import 'notice_detail_screen.dart';
import 'alba_schedule_page.dart';
import 'settings/alba_settings_screen.dart';
import 'alba_payroll_page.dart';
import 'documents/worker_documents_screen.dart';
import 'documents/document_acknowledge_dialog.dart';

class AlbaMainScreen extends StatefulWidget {
  const AlbaMainScreen({
    super.key,
    required this.storeId,
    required this.workerId,
  });

  final String storeId;
  final String workerId;

  @override
  State<AlbaMainScreen> createState() => _AlbaMainScreenState();
}

class _AlbaMainScreenState extends State<AlbaMainScreen> {
  static const _sessionActionKey = 'alba_pending_action';
  static const _sessionStoreKey = 'alba_store_id';
  
  int _index = 0;
  int _subIndex = 0;
  final _db = FirebaseFirestore.instance;
  final _dbService = DatabaseService();
  bool _autoHandled = false;
  String? _topBannerMessage;
  Timer? _uiTimer;
  bool _isProcessing = false;
  bool _isInitialLoading = true;
  Map<String, dynamic> _workerData = const {};
  Attendance? _currentOpenAttendance;
  Map<String, Map<String, dynamic>> _rosterData = {};
  List<Attendance> _weeklyData = [];
  List<Attendance> _monthlyData = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _noticesData = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _expirationsTodayData = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _incompleteTodosData = [];

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';
  String get _workerId {
    if (kDebugMode && widget.storeId == DebugAuthConstants.debugStoreId) {
      if (widget.workerId.isEmpty) return _uid;
    }
    return widget.workerId;
  }
  String get _qrStoreId =>
      (Uri.base.queryParameters['storeId'] ?? Uri.base.queryParameters['store_id'] ?? '').trim();

  /// QR 스캔 엔트리: storeId 일치 + attendance 액션 (URL 또는 세션)
  bool get _isEntryLandingLink {
    final q = Uri.base.queryParameters;
    final urlStore = (q['storeId'] ?? q['store_id'] ?? '').trim();
    final sessionAction = web.window.sessionStorage.getItem(_sessionActionKey);
    final sessionStore = web.window.sessionStorage.getItem(_sessionStoreKey);
    
    // 1. 매장 ID 확인
    final effectiveStoreId = urlStore.isNotEmpty ? urlStore : sessionStore;
    if (effectiveStoreId != null && effectiveStoreId.isNotEmpty && effectiveStoreId != widget.storeId) {
      return false;
    }
    
    // 2. 명시적인 출근(attendance) 액션 확인
    final isAttendanceAction = q['action'] == 'attendance' || sessionAction == 'attendance';
    
    if (kDebugMode && isAttendanceAction) {
      debugPrint('DEBUG: _isEntryLandingLink identified as true (Action: attendance)');
    }
    return isAttendanceAction;
  }

  Future<void> _loadDashboardData() async {
    try {
      final results = await Future.wait([
        _dbService.getWorkerRosterDays(widget.storeId, _workerId),
        _weeklyAttendanceFuture(),
        _monthlyAttendanceFuture(),
        _db.collection('stores').doc(widget.storeId).get(),
        _db.collection('stores').doc(widget.storeId).collection('notices').get(),
        _expirationsTodayFuture(),
        _incompleteTodosFuture(),
      ]);
      if (!mounted) return;
      final rosterSnap = results[0] as QuerySnapshot<Map<String, dynamic>>;
      final rMap = <String, Map<String, dynamic>>{};
      for (final d in rosterSnap.docs) { rMap[d.id] = d.data(); }
      setState(() {
        _rosterData = rMap;
        _weeklyData = results[1] as List<Attendance>;
        _monthlyData = results[2] as List<Attendance>;
        _noticesData = (results[4] as QuerySnapshot<Map<String, dynamic>>).docs;
        _expirationsTodayData = results[5] as List<QueryDocumentSnapshot<Map<String, dynamic>>>;
        _incompleteTodosData = results[6] as List<QueryDocumentSnapshot<Map<String, dynamic>>>;
      });
    } catch (e) {
      debugPrint('Dashboard data load error: $e');
    }
  }

  Future<void> _loadWorkerData() async {
    try {
      final snap = await _workerFuture();
      if (mounted) {
        setState(() {
          _workerData = snap.data() ?? const {};
          _isInitialLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Worker data load error: $e');
      if (mounted) setState(() => _isInitialLoading = false);
    }
  }

  Future<void> _loadOpenAttendance() async {
    try {
      final result = await _openAttendanceFuture();
      if (mounted) {
        setState(() {
          _currentOpenAttendance = result;
        });
      }
    } catch (e) {
      debugPrint('Open attendance load error: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
    _loadWorkerData();
    _loadOpenAttendance();
    AppClock.syncWithFirestore(widget.storeId);
    _uiTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      UserGuidePopup.showIfNeeded(context, GuideType.alba).then((_) {});
      _runEntryLandingAttendance();
      _checkPendingDocuments();
    });
  }

  @override
  void dispose() {
    _uiTimer?.cancel();
    super.dispose();
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> _workerFuture() {
    return _db
        .collection('stores')
        .doc(widget.storeId)
        .collection('workers')
        .doc(_workerId)
        .get();
  }



  Future<List<Attendance>> _monthlyAttendanceFuture() async {
    final s = await _db
        .collection('attendance')
        .where('storeId', isEqualTo: widget.storeId)
        .where('staffId', isEqualTo: _workerId)
        .get();

    final now = AppClock.now();
    final start = DateTime(now.year, now.month, 1);
    final end = DateTime(now.year, now.month + 1, 1);
    final startIso = start.toIso8601String();
    final endIso = end.toIso8601String();

    return s.docs.map((d) => Attendance.fromJson(d.data(), id: d.id)).where((a) {
      final ci = a.clockIn.toIso8601String();
      return ci.compareTo(startIso) >= 0 && ci.compareTo(endIso) < 0;
    }).toList();
  }

  Future<List<Attendance>> _weeklyAttendanceFuture() async {
    final now = AppClock.now();
    final start = ComplianceEngine.getWeeklyStart(now);
    final s = await _db
        .collection('attendance')
        .where('storeId', isEqualTo: widget.storeId)
        .where('staffId', isEqualTo: _workerId)
        .where('clockIn', isGreaterThanOrEqualTo: start.toIso8601String())
        .get();

    return s.docs.map((d) => Attendance.fromJson(d.data(), id: d.id)).toList();
  }

  Future<Attendance?> _openAttendanceFuture() async {
    final s = await _db
        .collection('attendance')
        .where('storeId', isEqualTo: widget.storeId)
        .where('staffId', isEqualTo: _workerId)
        .where('clockOut', isNull: true)
        .limit(1)
        .get();

    if (s.docs.isEmpty) return null;
    return Attendance.fromJson(s.docs.first.data(), id: s.docs.first.id);
  }

  /// 엔트리 URL 접속 시: 출근/퇴근 여부를 묻고 처리합니다.
  Future<void> _runEntryLandingAttendance() async {
    if (_autoHandled || !mounted) return;
    if (!_isEntryLandingLink) return;
    final uid = _uid;
    if (uid.isEmpty || _workerId.isEmpty) return;
    final qrStoreId = _qrStoreId;
    if (qrStoreId.isNotEmpty && qrStoreId != widget.storeId) {
      if (kDebugMode) debugPrint('DEBUG: StoreId mismatch: URL($qrStoreId) vs Widget(${widget.storeId})');
      return;
    }
    _autoHandled = true;
    
    // Clear session once handled
    web.window.sessionStorage.removeItem(_sessionActionKey);
    web.window.sessionStorage.removeItem(_sessionStoreKey);
    web.window.sessionStorage.removeItem('alba_pending_sig');

    if (kDebugMode) debugPrint('DEBUG: _runEntryLandingAttendance logic starting...');

    final workerSnap = await _db
        .collection('stores')
        .doc(widget.storeId)
        .collection('workers')
        .doc(_workerId)
        .get();
    final worker = workerSnap.data() ?? const <String, dynamic>{};

    final openAttendance = await _openAttendanceFuture();
    final q = Uri.base.queryParameters;
    final sessionAction = web.window.sessionStorage.getItem(_sessionActionKey);
    final isAttendanceAction = q['action'] == 'attendance' || sessionAction == 'attendance';
    
    if (kDebugMode) debugPrint('DEBUG: state - openAttendance=${openAttendance?.id}, action=$isAttendanceAction');

    if (isAttendanceAction) {
      if (openAttendance == null) {
        // --- 출근 로직 ---
        if (!mounted) return;
        final name = worker['name']?.toString() ?? '알바';
        final confirm = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('출근 확인'),
            content: Text('$name님, 매장 QR을 통해 접속하셨습니다.\n지금 바로 출근 처리를 진행할까요?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('출근 및 공지 확인')),
            ],
          ),
        );
        if (confirm == true && mounted) {
          await _clockIn(worker, isSilent: true);
          if (mounted) {
            setState(() {
              _index = 3; // 공지/교육 탭
            });
          }
        }
      } else {
        // --- 퇴근 로직 (이미 출근 중인 경우) ---
        if (!mounted) return;
        final name = worker['name']?.toString() ?? '알바';
        final confirm = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('퇴근 확인'),
            content: Text('$name님, 현재 출근 상태입니다.\n지금 퇴근 처리를 진행할까요?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC62828)),
                child: const Text('퇴근하기'),
              ),
            ],
          ),
        );
        
        if (confirm == true && mounted) {
          await _clockOut(openAttendance);
        }
      }
    }
  }

  /// 미교부된(서명은 완료되었으나 알바생이 확인하지 않은) 서류가 있는지 확인하고 팝업을 띄웁니다.
  Future<void> _checkPendingDocuments() async {
    if (!mounted) return;
    try {
      final docs = await _dbService.getDocuments(widget.storeId);
      final myPendingDocs = docs.where((d) => 
        d.staffId == _workerId && 
        d.status == 'sent' && 
        d.deliveryConfirmedAt == null
      ).toList();

      if (myPendingDocs.isNotEmpty && mounted) {
        // 가장 오래된 미교부 서류부터 순차적으로 노출
        final doc = myPendingDocs.first;
        await showDialog(
          context: context,
          barrierDismissible: false, // 반드시 확인해야 함
          builder: (ctx) => DocumentAcknowledgeDialog(
            storeId: widget.storeId,
            document: doc,
            onAcknowledged: () {
              // 확인 후 배너 표시
              _showTopBanner('서류 교부 확인이 완료되었습니다.');
              // 다음 문서가 있을 수 있으므로 재귀 호출
              Future.delayed(const Duration(milliseconds: 500), _checkPendingDocuments);
            },
          ),
        );
      }
    } catch (e) {
      debugPrint('Error checking pending documents: $e');
    }
  }

  void _showTopBanner(String message, {VoidCallback? alsoRun}) {
    setState(() {
      _topBannerMessage = message;
      alsoRun?.call();
    });
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_topBannerMessage == message) {
          setState(() => _topBannerMessage = null);
        }
      });
    });
  }

  String _todayContractLabel(Map<String, dynamic> worker) {
    final workDays = (worker['workDays'] as List?)?.cast<dynamic>() ?? const [];
    final weekday = AppClock.now().weekday == DateTime.sunday ? 0 : AppClock.now().weekday;
    final hasShift = workDays.contains(weekday);
    if (!hasShift) return '오늘 계약 근무: 휴무';
    final inTime = (worker['checkInTime']?.toString() ?? '09:00').substring(0, 5);
    final outTime = (worker['checkOutTime']?.toString() ?? '18:00').substring(0, 5);
    return '오늘 계약 근무: $inTime ~ $outTime';
  }

  Future<bool> _hasUnreadNotices() async {
    if (widget.storeId.isEmpty || _workerId.isEmpty) return false;
    try {
      final notices = await _db
          .collection('stores')
          .doc(widget.storeId)
          .collection('notices')
          .get();

      if (notices.docs.isEmpty) return false;

      final now = DateTime.now();
      final activeDocs = notices.docs.where((doc) {
        final d = doc.data();
        final publishUntil = d['publishUntil'];
        if (publishUntil is Timestamp) {
          return !publishUntil.toDate().isBefore(now);
        }
        return true;
      }).toList();

      if (activeDocs.isEmpty) return false;

      // In-memory sort for stability on Web
      final sortedDocs = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(activeDocs);
      sortedDocs.sort((a, b) {
        final ta = a.data()['createdAt'] as Timestamp?;
        final tb = b.data()['createdAt'] as Timestamp?;
        if (ta == null && tb == null) return 0;
        if (ta == null) return 1;
        if (tb == null) return -1;
        return tb.compareTo(ta);
      });

      final checkRange = sortedDocs.take(3);
      for (final doc in checkRange) {
        final readSnap = await _db
            .collection('stores')
            .doc(widget.storeId)
            .collection('notices')
            .doc(doc.id)
            .collection('reads')
            .doc(_workerId)
            .get();
        if (!readSnap.exists) return true;
      }
    } catch (e) {
      debugPrint('Error checking unread notices: $e');
    }
    return false;
  }

  /// 오늘 날짜 due인 expirations 문서만 클라이언트에서 필터 (백그라운드로 만료 기한 지난 항목 자동 삭제 수행)
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _expirationsTodayFuture() async {
    final snap = await _db
        .collection('stores')
        .doc(widget.storeId)
        .collection('expirations')
        .limit(100)
        .get();
    
    final now = AppClock.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final yesterdayStart = todayStart.subtract(const Duration(days: 1));

    // 백그라운드 자동 삭제 로직 (유예 1일: 유통기한이 '어제'보다 이전이면 파기)
    // 예: 4/9일 유통기한 -> 4/10일까지 유지, 4/11일에 어제(4/10)보다 전이므로 삭제됨.
    for (final doc in snap.docs) {
      final ts = doc.data()['dueDate'];
      if (ts is Timestamp) {
        final dt = ts.toDate();
        final dueDay = DateTime(dt.year, dt.month, dt.day);
        if (dueDay.isBefore(yesterdayStart)) {
          // 비동기로 안전하게 삭제
          _db.collection('stores').doc(widget.storeId).collection('expirations').doc(doc.id).delete().catchError((_) {});
        }
      }
    }

    return snap.docs.where((doc) => _isExpirationDueToday(doc.data(), now)).toList();
  }

  bool _isExpirationDueToday(Map<String, dynamic> d, DateTime now) {
    final ts = d['dueDate'];
    if (ts is Timestamp) {
      final dt = ts.toDate();
      // 대시보드에서는 오늘과 어제 남은 유예 항목을 같이 보여줄 지 결정
      // 유예 항목(어제)도 홈 화면에 띄웁니다.
      final dueDay = DateTime(dt.year, dt.month, dt.day);
      final todayStr = DateTime(now.year, now.month, now.day);
      final yesterdayStr = todayStr.subtract(const Duration(days: 1));
      return dueDay.isAtSameMomentAs(todayStr) || dueDay.isAtSameMomentAs(yesterdayStr);
    }
    final s = d['dueDateString']?.toString();
    if (s != null && s.length >= 10) {
      final parts = s.substring(0, 10).split('-');
      if (parts.length == 3) {
        final y = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        final day = int.tryParse(parts[2]);
        if (y != null && m != null && day != null) {
          final dueDay = DateTime(y, m, day);
          final todayStr = DateTime(now.year, now.month, now.day);
          final yesterdayStr = todayStr.subtract(const Duration(days: 1));
          return dueDay.isAtSameMomentAs(todayStr) || dueDay.isAtSameMomentAs(yesterdayStr);
        }
      }
    }
    return false;
  }

  String _expirationLine(Map<String, dynamic> d) {
    final name = d['productName']?.toString() ?? d['title']?.toString() ?? '품목';
    final qty = d['quantity']?.toString();
    if (qty != null && qty.isNotEmpty) return '$name · $qty';
    return name;
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _incompleteTodosFuture() {
    return _db
        .collection('stores')
        .doc(widget.storeId)
        .collection('todos')
        .where('done', isEqualTo: false)
        .limit(30)
        .get()
        .then((snap) {
      final docs = [...snap.docs];
      docs.sort((a, b) {
        final ta = a.data()['createdAt'];
        final tb = b.data()['createdAt'];
        if (ta is Timestamp && tb is Timestamp) return tb.compareTo(ta); // 최신순 정렬 (내림차순)
        return 0;
      });
      return docs.take(6).toList();
    });
  }

  Future<void> _markTodoDone(String docId) async {
    try {
      await _db
          .collection('stores')
          .doc(widget.storeId)
          .collection('todos')
          .doc(docId)
          .update({
        'done': true,
        'completedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('처리 실패: $e')),
      );
    }
  }

  void _showAddMessageDialog(Map<String, dynamic> worker) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('전달사항 작성'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: '사장님이나 다른 알바생에게 남길 메모를 입력하세요.',
            border: OutlineInputBorder(),
          ),
          maxLines: 2,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () async {
              final title = controller.text.trim();
              if (title.isNotEmpty) {
                final name = worker['name']?.toString() ?? '알바생';
                await _db.collection('stores').doc(widget.storeId).collection('todos').add({
                  'title': title,
                  'done': false,
                  'createdAt': FieldValue.serverTimestamp(),
                  'authorName': name,
                  'isBoss': false,
                  'order': DateTime.now().millisecondsSinceEpoch,
                });
                if (context.mounted) Navigator.pop(ctx);
              }
            },
            child: const Text('작성'),
          ),
        ],
      ),
    );
  }

  static const Color _pageBg = Color(0xFFF5F5F5);

  Widget _dashCard({required Widget child, EdgeInsetsGeometry? margin}) {
    return Container(
      margin: margin ?? const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: child,
      ),
    );
  }

  Future<void> _clockIn(Map<String, dynamic> worker, {bool isSilent = false}) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      // ★ 병렬 읽기: 서로 의존성 없는 Firestore 요청을 동시 실행
      final now = AppClock.now();
      final ymd = rosterDateKey(now);

      final results = await Future.wait([
        _weeklyAttendanceFuture(),                                          // [0] 주간 출근기록
        _db.collection('stores').doc(widget.storeId).get(),                 // [1] 매장 정보
        if (!isSilent) _hasUnreadNotices() else Future.value(false),        // [2] 미확인 공지
        _db.collection('stores').doc(widget.storeId)                        // [3] 근무표
            .collection('workers').doc(_workerId)
            .collection('rosterDays').doc(ymd).get(),
      ]);

      final weekly = results[0] as List<Attendance>;
      final storeSnap = results[1] as DocumentSnapshot<Map<String, dynamic>>;
      final hasUnread = results[2] as bool;
      final rosterSnap = results[3] as DocumentSnapshot<Map<String, dynamic>>;

      // 1. Compliance check (52시간 차단)
      try {
        final store = Store.fromJson(storeSnap.data() ?? {});
        if (store.isFiveOrMore) {
          final compliance = ComplianceEngine.checkWeeklyCompliance(
            store: store,
            currentWeeklyAttendances: weekly,
            newShiftMinutes: 60,
          );

          if (compliance.status == ComplianceStatus.blocked52) {
            final today = now.toIso8601String().substring(0, 10);
            final isAuthorized = worker['specialExtensionAuthorizedAt'] == today;
            
            if (!isAuthorized) {
              if (mounted) {
                await showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, color: Colors.red),
                        SizedBox(width: 8),
                        Text('출근 불가 (52시간 도달)'),
                      ],
                    ),
                    content: const Text(
                      '이번 주 총 근로시간이 52시간에 도달했습니다.\n근로기준법 준수를 위해 추가 출근이 차단됩니다.\n\n※ 연장이 불가피한 경우 사장님의 특별 승인이 필요합니다.',
                      style: TextStyle(height: 1.5),
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('닫기')),
                    ],
                  ),
                );
              }
              return;
            }
          }
        }
      } catch (e) {
        debugPrint('Compliance check non-fatal error: $e');
      }

      // 2. Unread notices check
      if (!isSilent && hasUnread && mounted) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('신규 공지 확인'),
            content: const Text('아직 읽지 않은 공지사항이 있습니다.\n확인 후 출근하시겠습니까?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('공지 확인하기'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('그냥 출근하기', style: TextStyle(color: Colors.grey.shade600)),
              ),
            ],
          ),
        );

        if (proceed == false && mounted) {
          setState(() {
            _index = 3; // 공지/교육 탭
          });
          return;
        }
      }

      final todayStr = now.toIso8601String().substring(0, 10);
      final isAuthorized = worker['specialExtensionAuthorizedAt'] == todayStr;
      final authReason = isAuthorized ? (worker['specialExtensionReason']?.toString() ?? '사장님 승인') : null;

      final shift = effectiveShiftForDate(
        worker: worker,
        date: now,
        rosterDayDoc: rosterSnap.data(),
      );

      String? schedStartIso;
      String? schedEndIso;
      late final DateTime recordedClockIn;
      late final String status;
      late final bool autoApprove;

      if (shift == null) {
        if (!isSilent) {
          if (!mounted) return;
          final shouldProceed = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              title: const Text('휴무일 출근 확인'),
              content: const Text(
                '오늘은 근무일이 아닙니다.\n그래도 출근하시겠습니까?\n\n※ 사장님의 승인이 있어야 급여에 정산됩니다.',
                style: TextStyle(height: 1.4),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('취소'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('출근하기'),
                ),
              ],
            ),
          );
          if (shouldProceed != true) return;
        }
        
        recordedClockIn = now;
        status = 'Unplanned';
        autoApprove = false;
      } else {
        schedStartIso = shift.scheduledStart.toIso8601String();
        schedEndIso = shift.scheduledEnd.toIso8601String();
        autoApprove = shouldAutoApproveClockIn(now: now, shift: shift);
        recordedClockIn = now;
        status = autoApprove ? 'Normal' : 'pending_approval';
      }

      final attendance = Attendance(
        id: '${_workerId}_${now.millisecondsSinceEpoch}',
        staffId: _workerId,
        storeId: widget.storeId,
        clockIn: recordedClockIn,
        originalClockIn: now,
        isAutoApproved: autoApprove,
        type: AttendanceType.web,
        attendanceStatus: status,
        scheduledShiftStartIso: schedStartIso,
        scheduledShiftEndIso: schedEndIso,
        isSpecialOvertime: isAuthorized,
        specialOvertimeReason: authReason,
        specialOvertimeAuthorizedAt: isAuthorized ? AppClock.now() : null,
      );
      await _dbService.recordAttendance(attendance);

      String bannerMessage = '';
      if (shift != null) {
        final late = lateMinutes(
          actualClockIn: now,
          scheduledStart: shift.scheduledStart,
        );
        if (late > 0) {
          bannerMessage = '오늘 $late분 지각하셨습니다';
        } else if (now.isBefore(shift.scheduledStart)) {
          final h = shift.scheduledStart.hour;
          bannerMessage = '일찍 오셨네요! 출근 기록은 완료되었으며, 근무시간은 $h시부터 입니다.';
        } else {
          bannerMessage = '출근 처리되었습니다';
        }
      } else {
        bannerMessage = '근무표에 없는 출근입니다. 사장님 승인을 기다려 주세요.';
      }

      if (status == 'pending_approval' || status == 'Unplanned') {
        final name = worker['name']?.toString() ?? '직원';
        // ★ 알림은 출근 완료 후 비동기 fire-and-forget (UI 차단 안 함)
        _dbService.enqueueBossAttendanceNotification(
          storeId: widget.storeId,
          workerId: _workerId,
          workerName: name,
          kind: 'clock_in_pending',
          message: shift == null
              ? '근무표에 없는 날 출근 요청: $name님'
              : '근무표와 다른 시간대 출근 요청: $name님',
        );
      }
      
      _finishClockIn(attendance, bannerMessage);
    } catch (e) {
      debugPrint('Clock-in fatal error: $e');
      String msg = '출근 처리 중 오류가 발생했습니다.';
      if (e is FirebaseException) {
        msg += ' (${e.code}: ${e.message})';
        if (e.code == 'permission-denied') {
          msg += '\n보안 권한 거부: 로그아웃 후 다시 시도해 보세요.';
        }
      } else {
        msg += ' ($e)';
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            duration: const Duration(seconds: 5),
            backgroundColor: Colors.red.shade800,
            action: SnackBarAction(label: '확인', textColor: Colors.white, onPressed: () {}),
          ),
        );
      }
    } finally {
      // 다이얼로그/오버레이 정리가 끝난 후 안전하게 setState
      if (mounted && _isProcessing) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _isProcessing) {
            setState(() => _isProcessing = false);
            Future.delayed(const Duration(milliseconds: 2000), () {
              if (mounted) {
                _loadOpenAttendance();
                _loadWorkerData();
                _loadDashboardData();
              }
            });
          }
        });
      }
    }
  }

  Future<DateTime?> _scheduledEndForOpen(
    Attendance open,
    Map<String, dynamic> worker,
  ) async {
    if (open.scheduledShiftEndIso != null) {
      return DateTime.parse(open.scheduledShiftEndIso!);
    }
    final day = DateTime(open.clockIn.year, open.clockIn.month, open.clockIn.day);
    final ymd = rosterDateKey(day);
    final rosterSnap = await _db
        .collection('stores')
        .doc(widget.storeId)
        .collection('workers')
        .doc(_workerId)
        .collection('rosterDays')
        .doc(ymd)
        .get();
    final shift = effectiveShiftForDate(
      worker: worker,
      date: day,
      rosterDayDoc: rosterSnap.data(),
    );
    return shift?.scheduledEnd;
  }

  /// 퇴근 성공 시 원자적으로 상태를 업데이트하는 헬퍼.

  void _finishClockIn(Attendance attendance, String bannerMessage) {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _topBannerMessage = bannerMessage;
        _currentOpenAttendance = attendance;
        _isProcessing = false;
      });
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (!mounted) return;
        if (_topBannerMessage == bannerMessage) {
          setState(() => _topBannerMessage = null);
        }
      });
      Future.delayed(const Duration(milliseconds: 2000), () {
        if (mounted) {
          _loadOpenAttendance();
          _loadWorkerData();
          _loadDashboardData();
        }
      });
    });
  }

  void _finishClockOut(String bannerMessage) {
    if (!mounted) return;
    // 현재 프레임 완료 후 원자적으로 상태 변경 (다이얼로그 오버레이 정리 대기)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _topBannerMessage = bannerMessage;
        _currentOpenAttendance = null;
        _isProcessing = false;
      });
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (!mounted) return;
        if (_topBannerMessage == bannerMessage) {
          setState(() => _topBannerMessage = null);
        }
      });
      Future.delayed(const Duration(milliseconds: 2000), () {
        if (mounted) {
          _loadOpenAttendance();
          _loadWorkerData();
          _loadDashboardData();
        }
      });
    });
  }

  Future<void> _clockOut(Attendance open) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      final workerSnap = await _db
          .collection('stores')
          .doc(widget.storeId)
          .collection('workers')
          .doc(_workerId)
          .get();
      final worker = workerSnap.data() ?? const <String, dynamic>{};
      if (!mounted) return;

      final storeSnapGlobal = await _db.collection('stores').doc(widget.storeId).get();
      final storeData = storeSnapGlobal.data() ?? const <String, dynamic>{};
      final graceMinutes = (storeData['attendanceGracePeriodMinutes'] as num?)?.toInt() ?? 5;

      final now = AppClock.now();

      final schedEnd = await _scheduledEndForOpen(open, worker);
      if (!mounted) return;

      if (schedEnd != null &&
          isEarlyClockOut(
            actualClockOut: now,
            scheduledEnd: schedEnd,
            graceMinutes: graceMinutes,
          )) {
        final hm =
            '${schedEnd.hour.toString().padLeft(2, '0')}:${schedEnd.minute.toString().padLeft(2, '0')}';
        
        final reason = await _showEarlyClockOutReasonDialog(hm);
        if (reason == null) return;

        final name = worker['name']?.toString() ?? '직원';
        
        final earlyUpdated = Attendance(
          id: open.id,
          staffId: open.staffId,
          storeId: open.storeId,
          clockIn: open.clockIn,
          clockOut: now,
          originalClockIn: open.originalClockIn ?? open.clockIn,
          originalClockOut: now,
          breakStart: open.breakStart,
          breakEnd: open.breakEnd,
          inWifiBssid: open.inWifiBssid,
          outWifiBssid: open.outWifiBssid,
          isAutoApproved: open.isAutoApproved,
          exceptionReason: reason,
          type: open.type,
          isAttendanceEquivalent: open.isAttendanceEquivalent,
          attendanceStatus: 'early_leave_pending',
          scheduledShiftStartIso: open.scheduledShiftStartIso,
          scheduledShiftEndIso: open.scheduledShiftEndIso ?? schedEnd.toIso8601String(),
          overtimeApproved: false,
          overtimeReason: open.overtimeReason,
        );
        await _dbService.recordAttendance(earlyUpdated);
        await _dbService.enqueueBossAttendanceNotification(
          storeId: widget.storeId,
          workerId: _workerId,
          workerName: name,
          kind: 'early_clock_out_pending',
          message: '조기 퇴근 요청: $name님 (사유: $reason)',
        );
        _finishClockOut('조기 퇴근 승인 요청이 접수되었습니다.');
        return;
      }

      final lateMinOvertime = schedEnd != null && !now.isBefore(schedEnd)
          ? now.difference(schedEnd).inMinutes
          : 0;
      
      final overtimeThreshold = graceMinutes > 0 ? graceMinutes : 0;
      if (schedEnd != null && lateMinOvertime > overtimeThreshold) {
        final choice = await _showOvertimeChoiceDialog();
        if (choice == null) return;

        if (choice == 'overtime') {
          final reason = await _showOvertimeRequestDialog();
          if (!mounted) return;
          if (reason == null) return;

          final wname = worker['name']?.toString() ?? '직원';
          final overtimeUpdated = Attendance(
            id: open.id,
            staffId: open.staffId,
            storeId: open.storeId,
            clockIn: open.clockIn,
            clockOut: now,
            originalClockIn: open.originalClockIn ?? open.clockIn,
            originalClockOut: now,
            breakStart: open.breakStart,
            breakEnd: open.breakEnd,
            inWifiBssid: open.inWifiBssid,
            outWifiBssid: open.outWifiBssid,
            isAutoApproved: open.isAutoApproved,
            exceptionReason: open.exceptionReason,
            type: open.type,
            isAttendanceEquivalent: open.isAttendanceEquivalent,
            attendanceStatus: 'pending_overtime',
            scheduledShiftStartIso: open.scheduledShiftStartIso,
            scheduledShiftEndIso: open.scheduledShiftEndIso ?? schedEnd.toIso8601String(),
            overtimeApproved: false,
            overtimeReason: reason,
          );
          await _dbService.recordAttendance(overtimeUpdated);
          await _dbService.enqueueBossOvertimeNotification(
            storeId: widget.storeId,
            workerId: _workerId,
            workerName: wname,
            reason: reason,
            attendanceId: open.id,
          );
          _finishClockOut('연장 근무 신청이 접수되었습니다.');
          return;
        } else {
          // 'personal' (개인 사유로 정시 퇴근 선택)
          final updated = Attendance(
            id: open.id,
            staffId: open.staffId,
            storeId: open.storeId,
            clockIn: open.clockIn,
            clockOut: now,
            originalClockIn: open.originalClockIn ?? open.clockIn,
            originalClockOut: now,
            breakStart: open.breakStart,
            breakEnd: open.breakEnd,
            inWifiBssid: open.inWifiBssid,
            outWifiBssid: open.outWifiBssid,
            isAutoApproved: open.isAutoApproved,
            exceptionReason: open.exceptionReason,
            type: open.type,
            isAttendanceEquivalent: open.isAttendanceEquivalent,
            attendanceStatus: open.attendanceStatus,
            scheduledShiftStartIso: open.scheduledShiftStartIso,
            scheduledShiftEndIso: open.scheduledShiftEndIso ?? schedEnd.toIso8601String(),
            overtimeApproved: false,
            voluntaryWaiverNote: '사용자가 자발적으로 연장 수당 미신청을 선택함 (개인 사유)',
            voluntaryWaiverLogAt: now,
          );
          await _dbService.recordAttendance(updated);
          _finishClockOut('정시 퇴근(개인 사유 지연)으로 처리되었습니다.');
          return;
        }
      }

      final updated = Attendance(
        id: open.id,
        staffId: open.staffId,
        storeId: open.storeId,
        clockIn: open.clockIn,
        clockOut: now,
        originalClockIn: open.originalClockIn ?? open.clockIn,
        originalClockOut: now,
        breakStart: open.breakStart,
        breakEnd: open.breakEnd,
        inWifiBssid: open.inWifiBssid,
        outWifiBssid: open.outWifiBssid,
        isAutoApproved: open.isAutoApproved,
        exceptionReason: open.exceptionReason,
        type: open.type,
        isAttendanceEquivalent: open.isAttendanceEquivalent,
        attendanceStatus: open.attendanceStatus,
        scheduledShiftStartIso: open.scheduledShiftStartIso,
        scheduledShiftEndIso: open.scheduledShiftEndIso ?? schedEnd?.toIso8601String(),
        overtimeApproved: open.overtimeApproved,
        overtimeReason: open.overtimeReason,
      );
      await _dbService.recordAttendance(updated);
      _finishClockOut('퇴근 처리되었습니다');
    } catch (e) {
      debugPrint('Clock-out fatal error: $e');
      String msg = '퇴근 처리 중 오류가 발생했습니다.';
      if (e is FirebaseException) {
        msg += ' (${e.code}: ${e.message})';
      } else {
        msg += ' ($e)';
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            duration: const Duration(seconds: 5),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
    } finally {
      // 다이얼로그 오버레이 정리가 끝난 후 안전하게 setState
      if (mounted && _isProcessing) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _isProcessing) {
            setState(() => _isProcessing = false);
          }
        });
      }
    }
  }

  Future<String?> _showEarlyClockOutReasonDialog(String hm) async {
    final controller = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('조기 퇴근 사유 입력'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('근무 종료 예정($hm)보다 이릅니다. 조기 퇴근 사유를 반드시 입력해주세요.',
                    style: const TextStyle(fontSize: 14)),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    hintText: '예: 학교 보충수업, 병원 방문 등',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () {
                final text = controller.text.trim();
                if (text.isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('사유를 입력해주세요.')),
                  );
                  return;
                }
                Navigator.of(ctx).pop(text);
              },
              child: const Text('퇴근 승인 요청'),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<String?> _showOvertimeChoiceDialog() async {
    return await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('퇴근 확인'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('근무 종료 예정 시간보다 15분이 지났습니다.', style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 12),
            Text('실제로 추가 업무를 수행하셨나요, 아니면 단순히 늦게 퇴근 버튼을 누르셨나요?'),
          ],
        ),
        actions: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(null),
                child: const Text('취소'),
              ),
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop('personal'),
                    child: const Text('개인 사유 (정시 퇴근)'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.of(ctx).pop('overtime'),
                    child: const Text('연장 근무 신청'),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<String?> _showOvertimeRequestDialog() async {
    String? selectedType; // 'personal', 'boss', 'other'
    int overtimeMinutes = 30; // 기본 30분
    final controller = TextEditingController();

    try {
      return await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Text('연장 근무 신청'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                   const Text('연장 근무 시간을 설정하고 사유를 선택해 주세요.', style: TextStyle(fontSize: 13, color: Colors.grey)),
                   const SizedBox(height: 16),
                   
                   // 30분 단위 스테퍼
                   Container(
                     padding: const EdgeInsets.symmetric(vertical: 8),
                     decoration: BoxDecoration(
                       color: Colors.grey.shade50,
                       borderRadius: BorderRadius.circular(12),
                       border: Border.all(color: Colors.grey.shade200),
                     ),
                     child: Row(
                       mainAxisAlignment: MainAxisAlignment.center,
                       children: [
                         IconButton(
                           onPressed: overtimeMinutes <= 0 ? null : () => setState(() => overtimeMinutes -= 30),
                           icon: const Icon(Icons.remove_circle_outline, color: Color(0xFF1565C0)),
                         ),
                         Padding(
                           padding: const EdgeInsets.symmetric(horizontal: 16),
                           child: Column(
                             children: [
                               const Text('신청 시간', style: TextStyle(fontSize: 10, color: Colors.grey)),
                               Text(
                                 '${overtimeMinutes ~/ 60 > 0 ? '${overtimeMinutes ~/ 60}시간 ' : ''}${overtimeMinutes % 60}분',
                                 style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1565C0)),
                               ),
                             ],
                           ),
                         ),
                         IconButton(
                           onPressed: overtimeMinutes >= 240 ? null : () => setState(() => overtimeMinutes += 30),
                           icon: const Icon(Icons.add_circle_outline, color: Color(0xFF1565C0)),
                         ),
                       ],
                     ),
                   ),
                   const SizedBox(height: 20),
                   
                   const Text('신청 사유', style: TextStyle(fontSize: 13, color: Colors.grey)),
                   const SizedBox(height: 8),
                   _reasonOptionButton(
                     label: '💁‍♂️ 개인사유 (업무 미숙, 개인 정비 등)',
                     isSelected: selectedType == 'personal',
                     onTap: () => setState(() => selectedType = 'personal'),
                   ),
                   const SizedBox(height: 8),
                   _reasonOptionButton(
                     label: '📢 사장님 요청 (추가 지시, 손님 응대)',
                     isSelected: selectedType == 'boss',
                     onTap: () => setState(() => selectedType = 'boss'),
                   ),
                   const SizedBox(height: 8),
                   _reasonOptionButton(
                     label: '✏️ 기타 (직접 입력)',
                     isSelected: selectedType == 'other',
                     onTap: () => setState(() => selectedType = 'other'),
                   ),

                   if (selectedType == 'other') ...[
                     const SizedBox(height: 12),
                     TextField(
                       controller: controller,
                       maxLines: 2,
                       decoration: const InputDecoration(
                         hintText: '상세 사유를 입력하세요.',
                         border: OutlineInputBorder(),
                         isDense: true,
                       ),
                     ),
                   ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(null),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () {
                  if (overtimeMinutes <= 0) {
                    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('연장 시간을 설정해 주세요.')));
                    return;
                  }
                  if (selectedType == null) {
                    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('사유를 선택해 주세요.')));
                    return;
                  }
                  
                  final durationStr = '${overtimeMinutes ~/ 60 > 0 ? '${overtimeMinutes ~/ 60}시간 ' : ''}${overtimeMinutes % 60}분';
                  String finalReason = '';
                  if (selectedType == 'personal') {
                    finalReason = '[$durationStr 신청] 개인사유';
                  } else if (selectedType == 'boss') {
                    finalReason = '[$durationStr 신청] 사장님 요청';
                  } else {
                    final t = controller.text.trim();
                    if (t.isEmpty) {
                      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('상세 사유를 입력해 주세요.')));
                      return;
                    }
                    finalReason = '[$durationStr 신청] $t';
                  }
                  Navigator.of(ctx).pop(finalReason);
                },
                child: const Text('신청'),
              ),
            ],
          ),
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Widget _reasonOptionButton({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFE3F2FD) : Colors.white,
          border: Border.all(
            color: isSelected ? const Color(0xFF1565C0) : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? const Color(0xFF1565C0) : Colors.black87,
          ),
        ),
      ),
    );
  }





  Widget _homeDashboard(Map<String, dynamic> worker) {
    final name = worker['name']?.toString().trim().isNotEmpty == true
        ? worker['name'].toString().trim()
        : '알바';

    final open = _currentOpenAttendance;
    final isClockedIn = open != null;

    // 로스터 데이터
    final today = AppClock.now();
    final shiftToday = effectiveShiftForDate(
      worker: worker,
      date: today,
      rosterDayDoc: _rosterData[rosterDateKey(today)],
    );
    final hasShiftToday = shiftToday != null;
    final scheduleLine = shiftToday == null
        ? '오늘은 계약상 휴무입니다. (출근 기록은 가능)'
        : '오늘 스케줄 · ${shiftToday.checkInHm} ~ ${shiftToday.checkOutHm}';
    final contractSub = shiftToday == null
        ? _todayContractLabel(worker)
        : '오늘 계약 근무: ${shiftToday.checkInHm} ~ ${shiftToday.checkOutHm}';

    // 금주 근무시간
    final weekly = _weeklyData;
    final hours = ComplianceEngine.calculateWeeklyHours(weekly);
    final progress = (hours / 52.0).clamp(0.0, 1.0);
    Color progressColor = const Color(0xFF1565C0);
    String statusText = '정상 준수 중';
    if (hours >= 51.5) {
      progressColor = Colors.red;
      statusText = '한도 도달 (차단)';
    } else if (hours >= 48) {
      progressColor = Colors.orange;
      statusText = '한도 임박 (주의)';
    } else if (hours > 40) {
      progressColor = Colors.blue;
      statusText = '연장 수당 발생';
    }

    // 실시간 근무 시간
    final mList = _monthlyData;
    final now = AppClock.now();
    final todayYmd = rosterDateKey(now);
    final todayFinished = mList.where((a) {
      if (a.clockOut == null) return false;
      return rosterDateKey(a.clockIn) == todayYmd;
    });
    int finishedMinutes = todayFinished.fold(0, (total, a) => total + a.workedMinutes);
    int currentSessionMinutes = isClockedIn ? (open.workedMinutesAt(now)) : 0;
    int totalTodayMinutes = finishedMinutes + currentSessionMinutes;

    String formatMin(int total) {
      final h = total ~/ 60;
      final m = total % 60;
      return '$h시간 ${m.toString().padLeft(2, '0')}분';
    }

    // 공지사항 정렬
    final allNotices = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(_noticesData);
    allNotices.sort((a, b) {
      final ta = a.data()['createdAt'] as Timestamp?;
      final tb = b.data()['createdAt'] as Timestamp?;
      if (ta == null && tb == null) return 0;
      if (ta == null) return 1;
      if (tb == null) return -1;
      return tb.compareTo(ta);
    });
    final previewNotices = allNotices.take(3).toList();

    // 유통기한
    final expirationDocs = _expirationsTodayData;

    // 전달사항
    final tdocs = _incompleteTodosData;
    final todoListHeight = tdocs.isEmpty
        ? 44.0
        : (tdocs.length * 34.0 + 8).clamp(48.0, 220.0);

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('반가워요, $name님!', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF1B1B1B))),
                  IconButton(
                    onPressed: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const AlbaSettingsScreen()));
                    },
                    icon: const Icon(Icons.settings_outlined, color: Colors.black87),
                  ),
                ],
              ),
              const Text('오늘도 화이팅하세요.', style: TextStyle(fontSize: 13, color: Colors.black54)),
              const SizedBox(height: 16),

              // 금주 근로 시간 현황
              _dashCard(
                margin: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('금주 누적 근로시간', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: progressColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                          child: Text(statusText, style: TextStyle(fontSize: 10, color: progressColor, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(value: progress, backgroundColor: Colors.grey.shade100, color: progressColor, minHeight: 6),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(PayrollCalculator.formatHoursAsKorean(hours), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                        const Text('한도 52.0h', style: TextStyle(fontSize: 11, color: Colors.grey)),
                      ],
                    ),
                  ],
                ),
              ),

              // 1) 근무
              _dashCard(
                margin: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(Icons.schedule_rounded, color: hasShiftToday ? const Color(0xFF1565C0) : Colors.black45, size: 20),
                      const SizedBox(width: 6),
                      const Text('근무', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                    ]),
                    const SizedBox(height: 8),
                    Text(scheduleLine, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: hasShiftToday ? Colors.black87 : Colors.black54)),
                    Text(contractSub, style: const TextStyle(fontSize: 11, color: Colors.black54)),
                    const SizedBox(height: 14),

                    // 실시간 근무 시간 표시
                    Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F7FA),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('실제 근무 시간', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.black54)),
                              if (isClockedIn)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(4)),
                                  child: const Text('기록 중', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF2E7D32))),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          if (isClockedIn) ...[
                            Text('현재 ${formatMin(currentSessionMinutes)}째 근무 중', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF1565C0))),
                            const SizedBox(height: 2),
                            Text('오늘 총 ${formatMin(totalTodayMinutes)}', style: const TextStyle(fontSize: 12, color: Colors.black87)),
                          ] else ...[
                            Text(
                              totalTodayMinutes > 0 ? '오늘 총 ${formatMin(totalTodayMinutes)} 근무함' : '오늘 근무 기록이 없습니다.',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: totalTodayMinutes > 0 ? Colors.black87 : Colors.black45),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // --- 중앙 출퇴근 버튼 ---
              Center(
                key: ValueKey<bool>(isClockedIn),
                child: isClockedIn
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 220, height: 80,
                            child: FilledButton.icon(
                              onPressed: _isProcessing ? null : () async => _clockOut(open),
                              style: FilledButton.styleFrom(
                                backgroundColor: _isProcessing ? Colors.grey.shade400 : const Color(0xFFC62828), foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40)),
                                elevation: _isProcessing ? 0 : 8, shadowColor: const Color(0xFFC62828).withValues(alpha: 0.4),
                              ),
                              icon: _isProcessing
                                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                                  : const Icon(Icons.stop_circle_outlined, size: 28),
                              label: Text(_isProcessing ? '처리 중...' : '지금 퇴근하기', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text('퇴근 시각이 즉시 기록됩니다.', style: TextStyle(fontSize: 13, color: Colors.black54)),
                        ],
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_isEntryLandingLink)
                            const Padding(
                              padding: EdgeInsets.only(bottom: 12),
                              child: Text('출근 링크 접속 시 자동 출근됩니다. (수동 출근 가능)', style: TextStyle(fontSize: 13, color: Colors.black54), textAlign: TextAlign.center),
                            ),
                          SizedBox(
                            width: 220, height: 80,
                            child: FilledButton.icon(
                              onPressed: _isProcessing ? null : () async => _clockIn(worker),
                              style: FilledButton.styleFrom(
                                backgroundColor: _isProcessing ? Colors.grey.shade400 : const Color(0xFF1565C0), foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40)),
                                elevation: _isProcessing ? 0 : 8, shadowColor: const Color(0xFF1565C0).withValues(alpha: 0.4),
                              ),
                              icon: _isProcessing
                                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                                  : const Icon(Icons.play_circle_fill, size: 28),
                              label: Text(_isProcessing ? '처리 중...' : '출근하기', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(_isProcessing ? '잠시만 기다려주세요...' : '출근 시각이 즉시 기록됩니다.', style: const TextStyle(fontSize: 13, color: Colors.black54)),
                        ],
                      ),
              ),
              const SizedBox(height: 16),

              // 2) 공지사항
              if (allNotices.isEmpty)
                _dashCard(
                  margin: EdgeInsets.zero,
                  child: const Row(children: [
                    Icon(Icons.campaign_outlined, size: 18, color: Colors.black45),
                    SizedBox(width: 6),
                    Expanded(child: Text('등록된 공지가 없습니다.', style: TextStyle(fontSize: 13, color: Colors.black54))),
                  ]),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ...previewNotices.map((doc) {
                      final d = doc.data();
                      final title = d['title']?.toString() ?? '공지';
                      final content = d['content']?.toString() ?? '';
                      final imageUrl = d['imageUrl']?.toString() ?? '';
                      final createdAt = d['createdAt'];
                      String dateText = '';
                      if (createdAt is Timestamp) {
                        final dt = createdAt.toDate();
                        dateText = '${dt.year}.${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')}';
                      }
                      return FutureBuilder<DocumentSnapshot>(
                        future: _db.collection('stores').doc(widget.storeId).collection('notices').doc(doc.id).collection('reads').doc(_workerId).get(),
                        builder: (context, rSnap) {
                          final isRead = rSnap.hasData && rSnap.data!.exists;
                          bool isExpanded = false;
                          return StatefulBuilder(
                            builder: (context, setItemState) {
                              return Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                decoration: BoxDecoration(
                                  color: Colors.white, borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.grey.shade200),
                                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))],
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: InkWell(
                                  onTap: () async {
                                    if (!isRead) {
                                      await _db.collection('stores').doc(widget.storeId).collection('notices').doc(doc.id).collection('reads').doc(_workerId).set({'readAt': FieldValue.serverTimestamp()});
                                      if (mounted) setState((){});
                                    }
                                    setItemState(() => isExpanded = !isExpanded);
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                            Row(children: [
                                              Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(4)), child: Text('공지', style: TextStyle(color: Colors.blue.shade700, fontSize: 11, fontWeight: FontWeight.bold))),
                                              if (!isRead) Container(margin: const EdgeInsets.only(left: 6), padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(4)), child: const Text('N', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))),
                                            ]),
                                            const SizedBox(height: 8),
                                            Text(title, style: TextStyle(fontWeight: isRead ? FontWeight.w500 : FontWeight.w800, fontSize: 15, color: Colors.black87), maxLines: isExpanded ? null : 2, overflow: isExpanded ? TextOverflow.visible : TextOverflow.ellipsis),
                                            const SizedBox(height: 8),
                                            Text(dateText, style: const TextStyle(fontSize: 12, color: Colors.black45)),
                                          ])),
                                          if (imageUrl.isNotEmpty) ...[
                                            const SizedBox(width: 16),
                                            ClipRRect(borderRadius: BorderRadius.circular(8), child: R2Image(storeId: widget.storeId, imagePathOrId: imageUrl, width: 60, height: 60, fit: BoxFit.cover)),
                                          ]
                                        ]),
                                        if (isExpanded) ...[
                                          const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1)),
                                          Text(content, style: const TextStyle(fontSize: 14, height: 1.5, color: Colors.black87)),
                                          if (imageUrl.isNotEmpty) ...[
                                            const SizedBox(height: 12),
                                            ClipRRect(borderRadius: BorderRadius.circular(8), child: R2Image(storeId: widget.storeId, imagePathOrId: imageUrl, fit: BoxFit.contain, width: double.infinity)),
                                          ],
                                          const SizedBox(height: 8),
                                          Align(alignment: Alignment.centerRight, child: TextButton(
                                            onPressed: () async {
                                              await Navigator.push(context, MaterialPageRoute(builder: (_) => NoticeDetailScreen(storeId: widget.storeId, noticeId: doc.id, workerId: _workerId, workerName: worker['name'] ?? '알바')));
                                              if (mounted) setState((){});
                                            },
                                            style: TextButton.styleFrom(foregroundColor: Colors.blue.shade700, textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                            child: const Text('전체화면에서 보기 >'),
                                          ))
                                        ]
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }
                          );
                        }
                      );
                    }),
                    const SizedBox(height: 4),
                    InkWell(
                      onTap: () => setState(() { _index = 3; _subIndex = 0; }),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300)),
                        alignment: Alignment.center,
                        child: const Text('공지사항 전체보기  >', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87)),
                      ),
                    ),
                  ]
                ),
              const SizedBox(height: 6),

              // 3) 유통기한 알림
              InkWell(
                onTap: () => setState(() { _index = 3; _subIndex = 2; }),
                borderRadius: BorderRadius.circular(15),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(15),
                    gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFFF3E0), Color(0xFFFFFFFF)]),
                    border: Border.all(color: const Color(0xFFE65100), width: 2),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 10, offset: const Offset(0, 2))],
                  ),
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Container(padding: const EdgeInsets.all(5), decoration: BoxDecoration(color: const Color(0xFFFFE0B2), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.warning_amber_rounded, color: Color(0xFFF9A825), size: 18)),
                        const SizedBox(width: 8),
                        const Expanded(child: Text('유통기한 알림', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xFFBF360C)))),
                      ]),
                      const SizedBox(height: 6),
                      expirationDocs.isEmpty
                          ? const Text('오늘 마감 품목이 없습니다.', style: TextStyle(fontSize: 12, color: Colors.black54))
                          : ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: expirationDocs.length.clamp(0, 5),
                              itemBuilder: (_, i) {
                                final line = _expirationLine(expirationDocs[i].data());
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 3),
                                  child: Text('· $line', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                );
                              },
                            ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),

              // 4) 전달사항
              InkWell(
                onTap: () => setState(() { _index = 3; _subIndex = 1; }),
                borderRadius: BorderRadius.circular(15),
                child: _dashCard(
                  margin: EdgeInsets.zero,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(Icons.checklist_rounded, size: 18, color: Colors.green.shade800),
                        const SizedBox(width: 6),
                        const Text('전달사항', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                        const Spacer(),
                        TextButton(
                          onPressed: () => _showAddMessageDialog(worker),
                          style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(60, 30), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                          child: const Text('+ 남기기', style: TextStyle(fontSize: 12)),
                        ),
                      ]),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: todoListHeight,
                        width: double.infinity,
                        child: tdocs.isEmpty
                            ? const Align(alignment: Alignment.centerLeft, child: Text('등록된 전달사항이 없습니다.', style: TextStyle(fontSize: 12, color: Colors.black54)))
                            : ListView.builder(
                                physics: const ClampingScrollPhysics(),
                                itemCount: tdocs.length,
                                itemBuilder: (_, i) {
                                  final doc = tdocs[i];
                                  final title = doc.data()['title']?.toString() ?? '할 일';
                                  return InkWell(
                                    onTap: () => _markTodoDone(doc.id),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 2),
                                      child: Row(children: [
                                        Icon(Icons.radio_button_unchecked, size: 16, color: Colors.grey.shade600),
                                        const SizedBox(width: 6),
                                        Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))),
                                      ]),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }




  @override
  Widget build(BuildContext context) {
    if (_uid.isEmpty) {
      return const Scaffold(body: Center(child: Text('로그인이 필요합니다.')));
    }

    if (_isInitialLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final worker = _workerData;

    Widget currentPage;
    switch (_index) {
      case 0:
        currentPage = _homeDashboard(worker);
        break;
      case 1:
        currentPage = AlbaSchedulePage(storeId: widget.storeId, workerId: _workerId);
        break;
      case 2:
        currentPage = AlbaPayrollPage(storeId: widget.storeId, workerId: _workerId, worker: worker);
        break;
      case 3:
        currentPage = NoticeEducationTabScreen(
          key: ValueKey(_subIndex),
          storeId: widget.storeId,
          workerId: _workerId,
          workerName: worker['name'] ?? '알바생',
          initialIndex: _subIndex,
        );
        break;
      case 4:
        currentPage = WorkerDocumentsScreen(storeId: widget.storeId, workerId: _workerId);
        break;
      default:
        currentPage = _homeDashboard(worker);
    }

    String getTitle() {
      if (_index == 1) return '근무표';
      if (_index == 2) return '내 급여';
      if (_index == 3) return '공지/업무';
      if (_index == 4) return '노무서류';
      return '';
    }

    return Scaffold(
          backgroundColor: _pageBg,
          resizeToAvoidBottomInset: false,
          appBar: _index == 0
              ? null
              : AppBar(
                  title: Text(getTitle()),
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black87,
                  elevation: 0.5,
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.settings_outlined),
                      onPressed: () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const AlbaSettingsScreen()));
                      },
                    ),
                  ],
                ),
          body: Stack(
            children: [
              Positioned.fill(
                child: currentPage,
              ),
              if (_topBannerMessage != null)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    bottom: false,
                    child: Center(
                      child: Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x33000000),
                              blurRadius: 8,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Text(
                          _topBannerMessage!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          bottomNavigationBar: Column(
            mainAxisSize: MainAxisSize.min,
            children: [

              BottomNavigationBar(
                currentIndex: _index,
                onTap: (i) => setState(() {
                  _index = i;
                  if (i == 3) _subIndex = 0; // 공지/업무 탭 진입 시 공지사항이 디폴트
                }),
                backgroundColor: Colors.white,
                elevation: 12,
                type: BottomNavigationBarType.fixed,
                selectedItemColor: const Color(0xFF2E7D32),
                unselectedItemColor: Colors.black45,
                items: const [
                  BottomNavigationBarItem(
                    icon: Icon(Icons.home_rounded),
                    activeIcon: Icon(Icons.home),
                    label: '홈',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.calendar_month_rounded),
                    activeIcon: Icon(Icons.calendar_month),
                    label: '근무표',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.account_balance_wallet_outlined),
                    activeIcon: Icon(Icons.account_balance_wallet_rounded),
                    label: '내 급여',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.campaign_outlined),
                    activeIcon: Icon(Icons.campaign),
                    label: '공지/업무',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.description_outlined),
                    activeIcon: Icon(Icons.description_rounded),
                    label: '서류',
                  ),
                ],
              ),
            ],
          ),
    );
  }
} // End of class _AlbaMainScreenState
