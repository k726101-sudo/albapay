import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_logic/shared_logic.dart';

import 'package:firebase_auth/firebase_auth.dart';

import '../models/schedule_override.dart';
import '../models/store_info.dart';
import '../models/worker.dart';
import '../services/store_cache_service.dart';
import '../services/worker_service.dart';
import '../utils/standing_calculator.dart';
import '../widgets/standing_change_alert.dart';
import '../widgets/compliance_alert_banner.dart';
import 'main_tab_contents.dart';
import 'notice_education_tab_screen.dart';
import 'notice_list_screen.dart';
import 'payroll/exception_approval_screen.dart';
import 'payroll_report_page.dart';
import 'staff/add_staff_screen.dart';
import 'health/health_certificate_alert_management_screen.dart';
import '../utils/renewal_engine.dart';
import 'documents/contract_renewal_screen.dart';
import 'alba/alba_main_screen.dart';

/// 출근 승인 시 급여 반영 기준 (pending 전용)
enum _PendingClockInApprove { payrollScheduled, actualPunch }

Map<int, ({String start, String end})> _parseWorkerSchedule(Worker worker) {
  final dayToTime = <int, ({String start, String end})>{};
  if (worker.workScheduleJson.isNotEmpty) {
    try {
      final decoded = jsonDecode(worker.workScheduleJson) as List<dynamic>;
      for (final raw in decoded) {
        final m = raw as Map<String, dynamic>;
        final start = m['start']?.toString() ?? worker.checkInTime;
        final end = m['end']?.toString() ?? worker.checkOutTime;
        final days = (m['days'] as List<dynamic>? ?? const []);
        for (final d in days) {
          final code = d is int ? d : int.tryParse(d.toString()) ?? 0;
          dayToTime[code] = (start: start, end: end);
        }
      }
    } catch (_) {}
  }
  return dayToTime;
}

/// Root shell: swipeable dashboard + schedule, bottom navigation, Speed Dial.
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  static const Color kBarBg = Color(0xFF1a1a2e);
  static const Color kBodyBg = Color(0xFFF2F2F7);

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  static const _kSwipeHintPrefsKey = 'main_screen_page_swipe_hint_v1';

  final PageController _pageController = PageController();
  DateTime? _backPressedTime;

  /// Bottom nav: 0 dashboard/pageview, 1..3 additional tabs.
  int _bottomIndex = 0;
  
  /// Sub-tab notice routing index
  int _subIndex = 0;

  /// Page inside PageView: 0 dashboard, 1 schedule.
  int _pageViewIndex = 0;

  /// 체험모드 여부 (알바 전환 버튼 표시용)
  bool _isDemo = false;
  String _demoStoreId = '';

  /// 온보딩 가이드
  final GlobalKey _fabKey = GlobalKey();
  final GlobalKey _dashboardTabKey = GlobalKey();
  final GlobalKey _staffTabKey = GlobalKey();
  final GlobalKey _docsTabKey = GlobalKey();
  final GlobalKey _settingsTabKey = GlobalKey();
  OverlayEntry? _onboardingOverlay;

  void _goToSettingsTab() {
    setState(() => _bottomIndex = 4); // Settings is now at index 4 due to Notice/Education tab
  }

  void _goToNoticeTab(int index) {
    setState(() {
      _bottomIndex = 2; // Notice/Education tab
      _subIndex = index;
    });
  }

  Future<void> _runSwipeHintIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kSwipeHintPrefsKey) == true) return;

    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    if (!_pageController.hasClients) return;

    final w = _pageController.position.viewportDimension;
    await _pageController.animateTo(
      w * 0.3,
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeInOut,
    );
    if (!mounted) return;
    await _pageController.animateTo(
      0,
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeInOut,
    );
    await prefs.setBool(_kSwipeHintPrefsKey, true);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await UserGuidePopup.showIfNeeded(context, GuideType.boss);
      
      // 로그인 직후·계정 전환 후: 매장 Hive + 직원 Firestore + 실시간 구독을 현재 uid 기준으로 맞춤.
      // (앱 최초 실행 시 main()의 백그라운드 동기화만으로는, 나중에 로그인한 계정이 반영되지 않을 수 있음.)
      await StoreCacheService.syncFirestoreToHive();
      final storeId = await WorkerService.resolveStoreId();
      if (kDebugMode || storeId.isNotEmpty) {
        // 디버그 모드라면 storeId가 비어있어도 공용 ID로 동기화 시작
        AppClock.syncWithFirestore(
          storeId.isNotEmpty ? storeId : DebugAuthConstants.debugStoreId,
        );
      }
      await WorkerService.syncFromFirebase();
      await WorkerService.startRealtimeSync();
      unawaited(WorkerService.enqueueProbationEndingAlerts());
      
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null && storeId.isNotEmpty) {
        final userSnap = await FirebaseFirestore.instance.collection('users').doc(uid).get();
        if (userSnap.data()?['isDemo'] == true) {
          final attSnap = await FirebaseFirestore.instance.collection('attendance')
              .where('storeId', isEqualTo: storeId)
              .limit(1).get();
          if (attSnap.docs.isEmpty) {
            final workersSnap = await FirebaseFirestore.instance.collection('stores')
                .doc(storeId).collection('workers').where('isDemo', isEqualTo: true).get();
            if (workersSnap.docs.isNotEmpty) {
              final dummyWorkers = workersSnap.docs.map((d) {
                final data = d.data();
                data['id'] = d.id;
                return data;
              }).toList();
              try {
                // Background seed for existing stores that lack attendance data
                await TestDataSeeder.generateVirtualWorkerAttendances(
                  storeId: storeId,
                  workersData: dummyWorkers,
                );
                debugPrint('Re-seeded demo attendance data for existing demo store.');
              } catch (_) {}
            }
          }
        }
      }

      if (!mounted) return;
      await _runSwipeHintIfNeeded();

      // 체험모드 감지
      if (uid != null && storeId.isNotEmpty) {
        final demoCheck = await FirebaseFirestore.instance.collection('users').doc(uid).get();
        if (demoCheck.data()?['isDemo'] == true && mounted) {
          setState(() {
            _isDemo = true;
            _demoStoreId = storeId;
          });
        }
      }

      // ── 온보딩 가이드 초기화 ──
      await OnboardingGuideService.instance.init();

      // MainScreen에 도달했으면 이미 로그인 완료 → login 단계 자동 완료
      if (OnboardingGuideService.instance.currentStep == OnboardingStep.login) {
        await OnboardingGuideService.instance.completeStep(OnboardingStep.login);
      }

      await OnboardingGuideService.instance.syncWithFirestore(
        uid: uid,
        storeId: storeId,
      );
      OnboardingGuideService.instance.addListener(_onOnboardingStepChanged);
      if (mounted) _showOnboardingTooltipIfNeeded();
    });
  }

  @override
  void dispose() {
    _onboardingOverlay?.remove();
    _onboardingOverlay = null;
    OnboardingGuideService.instance.removeListener(_onOnboardingStepChanged);
    _pageController.dispose();
    super.dispose();
  }

  void _onOnboardingStepChanged() {
    if (mounted) _showOnboardingTooltipIfNeeded();
  }

  void _showOnboardingTooltipIfNeeded([int retryCount = 0]) {
    final guide = OnboardingGuideService.instance;
    if (!guide.isActive) return;
    if (retryCount > 5) return; // 최대 5회 재시도

    // Step 2: 사업장 등록 안내 → 설정 탭을 가리킴
    if (guide.currentStep == OnboardingStep.storeSetup) {
      final settingsBox = _settingsTabKey.currentContext?.findRenderObject() as RenderBox?;
      if (settingsBox == null || !settingsBox.hasSize) {
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) _showOnboardingTooltipIfNeeded(retryCount + 1);
        });
        return;
      }
      _onboardingOverlay?.remove();
      Future.delayed(const Duration(milliseconds: 600), () {
        if (!mounted) return;
        _onboardingOverlay = OnboardingTooltipOverlay.show(
          context: context,
          targetKey: _settingsTabKey,
          step: OnboardingStep.storeSetup,
          isDemo: _isDemo,
          direction: TooltipDirection.above,
          targetIcon: Icons.settings_outlined,
          targetColor: const Color(0xFF607D8B),
          onDismiss: () {
            _onboardingOverlay = null;
            // 설정 탭으로 이동
            _onBottomNavTap(4);
          },
          onSkipAll: () {
            _onboardingOverlay = null;
            OnboardingGuideService.instance.dismiss();
          },
        );
      });
      return;
    }

    // Step 3: 직원 등록 안내 (대시보드 탭에서)
    if (guide.currentStep == OnboardingStep.firstStaff && _bottomIndex == 0) {
      // FAB가 렌더링될 때까지 대기
      final fabBox = _fabKey.currentContext?.findRenderObject() as RenderBox?;
      if (fabBox == null || !fabBox.hasSize) {
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) _showOnboardingTooltipIfNeeded(retryCount + 1);
        });
        return;
      }
      _onboardingOverlay?.remove();
      Future.delayed(const Duration(milliseconds: 600), () {
        if (!mounted) return;
        _onboardingOverlay = OnboardingTooltipOverlay.show(
          context: context,
          targetKey: _fabKey,
          step: OnboardingStep.firstStaff,
          isDemo: _isDemo,
          direction: TooltipDirection.above,
          targetIcon: Icons.add,
          targetColor: const Color(0xFF1a1a2e),
          onDismiss: () {
            _onboardingOverlay = null;
            OnboardingGuideService.instance.completeStep(OnboardingStep.firstStaff);
          },
          onSkipAll: () {
            _onboardingOverlay = null;
            OnboardingGuideService.instance.dismiss();
          },
        );
      });
    }

    // Step 5: 계약서 작성 안내
    if (guide.currentStep == OnboardingStep.createContract && _bottomIndex == 0) {
      _onboardingOverlay?.remove();
      Future.delayed(const Duration(milliseconds: 600), () {
        if (!mounted) return;
        _onboardingOverlay = OnboardingTooltipOverlay.show(
          context: context,
          targetKey: _docsTabKey,
          step: OnboardingStep.createContract,
          isDemo: _isDemo,
          direction: TooltipDirection.above,
          targetIcon: Icons.description_outlined,
          targetColor: const Color(0xFF1565C0),
          onDismiss: () {
            _onboardingOverlay = null;
            OnboardingGuideService.instance.completeStep(OnboardingStep.createContract);
          },
          onSkipAll: () {
            _onboardingOverlay = null;
            OnboardingGuideService.instance.dismiss();
          },
        );
      });
    }

    // Step 6: 대시보드 리포트 확인 안내 (모든 서류 완료 후)
    if (guide.currentStep == OnboardingStep.checkDashboard) {
      _onboardingOverlay?.remove();
      Future.delayed(const Duration(milliseconds: 600), () {
        if (!mounted) return;
        _onboardingOverlay = OnboardingTooltipOverlay.show(
          context: context,
          targetKey: _dashboardTabKey,
          step: OnboardingStep.checkDashboard,
          isDemo: _isDemo,
          direction: TooltipDirection.above,
          targetIcon: Icons.dashboard_outlined,
          targetColor: const Color(0xFF1a1a2e),
          onDismiss: () {
            _onboardingOverlay = null;
            OnboardingGuideService.instance.completeStep(OnboardingStep.checkDashboard);
            _onBottomNavTap(0);
          },
          onSkipAll: () {
            _onboardingOverlay = null;
            OnboardingGuideService.instance.dismiss();
          },
        );
      });
    }
  }

  void _onBottomNavTap(int i) {
    // 탭 전환 시 온보딩 오버레이 항상 제거
    _onboardingOverlay?.remove();
    _onboardingOverlay = null;
    setState(() => _bottomIndex = i);
    if (i == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pageController.hasClients) {
          _pageController.animateToPage(
            0,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOut,
          );
        }
        // 대시보드로 돌아왔을 때 온보딩 확인
        _showOnboardingTooltipIfNeeded();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // ignore: deprecated_member_use
    return WillPopScope(
      onWillPop: () async {
        if (_bottomIndex != 0) {
          setState(() {
            _bottomIndex = 0;
            if (_pageController.hasClients) {
              _pageController.animateToPage(0, duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
            }
          });
        }
        return false;
      },
      child: Scaffold(
        backgroundColor: MainScreen.kBodyBg,
        extendBody: false,
      resizeToAvoidBottomInset: false,
      body: IndexedStack(
        index: _bottomIndex,
        children: [
          DashboardPageView(
                  pageController: _pageController,
                  pageViewIndex: _pageViewIndex,
                  onPageChanged: (i) => setState(() => _pageViewIndex = i),
                  onOpenSettings: _goToSettingsTab,
                  onOpenNoticeTab: _goToNoticeTab,
                ),
                const StaffTabContent(),
                NoticeEducationTabScreen(
                  key: ValueKey(_subIndex),
                  initialIndex: _subIndex,
                ),
                const DocumentsTabContent(),
                const SettingsTabContent(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _bottomIndex,
        selectedItemColor: MainScreen.kBarBg,
        unselectedItemColor: Colors.grey,
        onTap: _onBottomNavTap,
        items: [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_outlined, key: _dashboardTabKey),
            label: '대시보드',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.people_outline),
            label: '직원',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.campaign_outlined),
            label: '공지/교육',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.description_outlined, key: _docsTabKey),
            label: '노무서류',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined, key: _settingsTabKey),
            label: '설정',
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      persistentFooterButtons: _isDemo ? [
        SizedBox(
          width: double.infinity,
          child: Material(
            color: const Color(0xFF10B981),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AlbaMainScreen(
                      storeId: _demoStoreId,
                      workerId: 'worker_a',
                    ),
                  ),
                );
              },
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.swap_horiz_rounded, color: Colors.white, size: 22),
                    SizedBox(width: 8),
                    Text(
                      '👷 알바가 보는 화면 체험하기',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ] : null,
      floatingActionButton: _bottomIndex == 0
          ? Padding(
              key: _fabKey,
              padding: const EdgeInsets.only(bottom: 16),
              child: SpeedDial(
                icon: Icons.add,
                activeIcon: Icons.close,
                backgroundColor: MainScreen.kBarBg,
                foregroundColor: Colors.white,
                overlayColor: Colors.black,
                overlayOpacity: 0.4,
                spacing: 10,
                spaceBetweenChildren: 8,
                children: [
                  SpeedDialChild(
                    child: const Icon(Icons.person_add, color: Colors.white),
                    backgroundColor: const Color(0xFF378ADD),
                    label: '직원 등록',
                    labelStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                    labelBackgroundColor: Colors.white,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const AddStaffScreen(),
                      ),
                    ),
                  ),
                  SpeedDialChild(
                    child: const Icon(Icons.check_circle_outline, color: Colors.white),
                    backgroundColor: const Color(0xFF639922),
                    label: '근무 승인',
                    labelStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                    labelBackgroundColor: Colors.white,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ExceptionApprovalScreen(),
                      ),
                    ),
                  ),
                ],
              ),
            )
          : null,
      ),
    );
  }
}

class DashboardPageView extends StatelessWidget {
  const DashboardPageView({
    super.key,
    required this.pageController,
    required this.pageViewIndex,
    required this.onPageChanged,
    required this.onOpenSettings,
    required this.onOpenNoticeTab,
  });

  final PageController pageController;
  final int pageViewIndex;
  final ValueChanged<int> onPageChanged;
  final VoidCallback onOpenSettings;
  final ValueChanged<int> onOpenNoticeTab;

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      controller: pageController,
      itemCount: 3,
      onPageChanged: onPageChanged,
      itemBuilder: (context, index) {
        if (index == 0) {
          return DashboardPage(
            pageIndex: pageViewIndex,
            onOpenSettings: onOpenSettings,
            onOpenNoticeTab: onOpenNoticeTab,
          );
        } else if (index == 1) {
          return SchedulePage(pageIndex: pageViewIndex);
        }
        return PayrollReportPage(pageIndex: pageViewIndex);
      },
    );
  }
}

// --- Dashboard ----------------------------------------------------------------

class DashboardPage extends StatefulWidget {
  const DashboardPage({
    super.key,
    required this.pageIndex,
    required this.onOpenSettings,
    required this.onOpenNoticeTab,
  });

  final int pageIndex;
  final VoidCallback onOpenSettings;
  final ValueChanged<int> onOpenNoticeTab;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

void _showRiskWarningDialog(BuildContext context, StoreInfo? store) {
  if (store == null) return;
  
  final manualValue = store.isFiveOrMore;
  final calculatedValue = store.isFiveOrMoreCalculatedValue;
  final reason = store.isFiveOrMoreChangeReason;

  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Color(0xFFE24B4A)),
          SizedBox(width: 8),
          Text('노무 리스크 주의'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            manualValue
                ? '현재 데이터상으로는 5인 미만으로 추정되나, 5인 이상으로 설정되어 있습니다.'
                : '현재 등록된 직원이 5명 이상이나, 5인 미만으로 설정되어 있습니다.',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Text('• 시스템 추정: ${calculatedValue ? "5인 이상" : "5인 미만"}'),
          Text('• 사장님 설정: ${manualValue ? "5인 이상" : "5인 미만"}'),
          if (reason.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('• 기록된 변경 사유:', style: TextStyle(color: Color(0xFF888888))),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              margin: const EdgeInsets.only(top: 4),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(reason, style: const TextStyle(fontSize: 13)),
            ),
          ],
          const SizedBox(height: 16),
          const Text(
            '사업장 운영 형태에 따라 근로기준법상 5인 이상 사업장 규정이 적용될 수 있습니다. 설정이 실제 상황과 다를 경우 노무사 확인을 권장합니다.',
            style: TextStyle(fontSize: 12, color: Color(0xFFE24B4A)),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('확인'),
        ),
      ],
    ),
  );
}

class _DashboardPageState extends State<DashboardPage> {
  static bool _storeSnackShown = false;
  Timer? _uiTimer;

  @override
  void initState() {
    super.initState();
    final store = Hive.box<StoreInfo>('store').get('current');
    final name = (store?.storeName ?? '').trim();
    final isRegistered = store?.isRegistered ?? false;

    if ((name.isEmpty || !isRegistered) && !_storeSnackShown) {
      _storeSnackShown = true;
      // 스낵바 제거: 이미 화면에 _buildUnregisteredBanner()로 표기되므로, 알바 로그인 시 등 잘못 팝업되는 문제 방지.
    }

    _uiTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _uiTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Box<StoreInfo>>(
      valueListenable: Hive.box<StoreInfo>('store').listenable(),
      builder: (context, box, _) {
        final store = box.get('current');
        final storeName = (store?.storeName.trim().isNotEmpty ?? false)
            ? store!.storeName.trim()
            : '매장명 미설정';
        final isRegistered = store?.isRegistered ?? false;

        return Scaffold(
          backgroundColor: MainScreen.kBodyBg,
          appBar: AppBar(
            backgroundColor: MainScreen.kBarBg,
            foregroundColor: Colors.white,
            elevation: 0,
            title: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '매장현황',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                ),
                Row(
                  children: [
                    Text(
                      storeName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                    if (store?.isFiveOrMore != store?.isFiveOrMoreCalculatedValue) ...[
                      const SizedBox(width: 6),
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: () => _showRiskWarningDialog(context, store),
                          child: const Icon(
                            Icons.warning_amber_rounded,
                            color: Color(0xFFE24B4A),
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(22),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _pageDot(active: widget.pageIndex == 0),
                    const SizedBox(width: 4),
                    _pageDot(active: widget.pageIndex == 1),
                    const SizedBox(width: 4),
                    _pageDot(active: widget.pageIndex == 2),
                    if (widget.pageIndex == 0) ...[
                      const SizedBox(width: 8),
                      const Text(
                        '옆으로 넘겨보세요 ➔',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          body: ValueListenableBuilder<Box<Worker>>(
            valueListenable: Hive.box<Worker>('workers').listenable(),
            builder: (context, box, _) {
              final activeWorkers = WorkerService.getAll();
              final dispatched = activeWorkers.where((w) => w.workerType == 'dispatch').length;
              final regular = activeWorkers.length - dispatched;
              final healthRows = _healthAlertRows(activeWorkers);
              final storeId = activeWorkers
                  .map((w) => w.storeId)
                  .firstWhere((id) => id.trim().isNotEmpty, orElse: () => '');
              
              final bool showRenewalAlert = AppClock.now().year >= PayrollConstants.minimumWageEffectiveYear && RenewalEngine.hasPendingRenewals();

              return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: storeId.isEmpty
                    ? null
                    : FirebaseFirestore.instance
                        .collection('stores')
                        .doc(storeId)
                        .snapshots(),
                builder: (context, storeSnap) {
                  final storeData = storeSnap.data?.data() ?? const {};
                  final sizeMode =
                      storeData['employeeSizeMode']?.toString() ?? 'auto';
                  double avgWorkers =
                      (storeData['averageWorkers'] as num?)?.toDouble() ?? 0.0;
                  final storedDaysWithFive =
                      (storeData['daysWithFiveOrMore'] as num?)?.toInt() ?? 0;
                  final storedTotalDays =
                      (storeData['totalBusinessDays'] as num?)?.toInt() ?? 0;
                  bool autoIsFiveOrMore =
                      (storeData['isFiveOrMore'] as bool?) ?? (avgWorkers >= 5.0);
                  // 수동 고정 모드 우선 적용
                  bool isFiveOrMore;
                  if (sizeMode == 'manual_5plus') {
                    isFiveOrMore = true;
                  } else if (sizeMode == 'manual_under5') {
                    isFiveOrMore = false;
                  } else {
                    isFiveOrMore = autoIsFiveOrMore;
                  }
                  bool isTenOrMore =
                      (storeData['isTenOrMore'] as bool?) ?? (avgWorkers >= 10.0);

                  // 초기 동기화 전에는 저장값이 비어 있을 수 있어, 0.0 대신
                  // 현재 근무표 기반 추정치를 fallback으로 사용합니다.
                  final hasStoredAverage = storeData['averageWorkers'] is num;
                  // Heavy projected calculation removed from build to prevent freezes.
                  // StandingChangeAlert will handle background calculation and Firestore update.
                  final isNearTen = avgWorkers >= 9.5 && avgWorkers < 10.0;

                  // 모드 뱃지 텍스트
                  final modeBadge = sizeMode == 'manual_5plus'
                      ? '[5인 이상 고정]'
                      : sizeMode == 'manual_under5'
                          ? '[5인 미만 고정]'
                          : '[자동]';
                  final legalText = isTenOrMore
                      ? '10인 이상 (취업규칙 신고 대상)'
                      : (isFiveOrMore ? '추정 5인 이상 $modeBadge' : '추정 5인 미만 $modeBadge');
                  final legalColor = isTenOrMore
                      ? const Color(0xFF8E44AD)
                      : (isNearTen
                          ? const Color(0xFF7A3DB8)
                          : (isFiveOrMore
                              ? const Color(0xFF1a6ebd)
                              : const Color(0xFF2D6A4F)));
                  final legalSubtitle = isNearTen
                      ? '10인 임박! 현재 ${avgWorkers.toStringAsFixed(1)}명 · 취업규칙 신고 의무 주의'
                      : sizeMode == 'auto'
                          ? (storedTotalDays > 0
                              ? '평균 ${avgWorkers.toStringAsFixed(1)}명 · 5인↑ $storedDaysWithFive/$storedTotalDays일'
                              : '상시평균 : ${avgWorkers.toStringAsFixed(1)}명')
                          : '수동 설정 (자동 추정: ${avgWorkers.toStringAsFixed(1)}명 / ${autoIsFiveOrMore ? "5인 이상" : "5인 미만"})';

                  final isMismatched = sizeMode.startsWith('manual_') && (isFiveOrMore != autoIsFiveOrMore);

                  return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (showRenewalAlert) _buildRenewalAlertBanner(context),
                    if (showRenewalAlert) const SizedBox(height: 12),
                    if (!isRegistered) _buildDashboardUnregisteredBanner(),
                    if (!isRegistered) const SizedBox(height: 12),
                    if (storeId.isNotEmpty) StandingChangeAlert(storeId: storeId),


                    Row(
                      children: [
                        Expanded(
                          child: _summaryStaffCard(
                            total: activeWorkers.length,
                            subtitle: '일반 $regular명 · 파견 $dispatched명',
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _summaryLegalCard(
                            statusText: legalText,
                            subtitle: legalSubtitle,
                            backgroundColor: legalColor,
                            showWarning: isMismatched,
                          ),
                        ),
                      ],
                    ),
                    if (storeId.isNotEmpty)
                      ComplianceAlertBanner(
                        storeId: storeId,
                        storeData: storeData,
                        fiveOrMoreReason: (sizeMode == 'auto')
                            ? storeData['fiveOrMoreDecisionReason']?.toString()
                            : null,
                        refreshKey: activeWorkers.map((w) => '${w.id}_${w.isPaperContract}_${w.documentsInitialized}').join(','),
                      ),
                    const SizedBox(height: 12),
                    _workingNowCard(
                      storeId: storeId,
                      workers: activeWorkers,
                    ),
                    const SizedBox(height: 12),
                    _exceptionPendingCard(
                      storeId: storeId,
                      workers: activeWorkers,
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => HealthCertificateAlertManagementScreen(),
                        ),
                      ),
                      borderRadius: BorderRadius.circular(16),
                      child: _healthCard(healthRows),
                    ),
                    const SizedBox(height: 12),
                    _buildNoticeSection(storeId),
                    const SizedBox(height: 12),
                    _buildExpirationSection(storeId),
                    const SizedBox(height: 12),
                    _buildTodoSection(storeId),
                  ],
                ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  Widget _summaryStaffCard({required int total, required String subtitle}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a2e),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '직원',
            style: TextStyle(fontSize: 13, color: Colors.white),
          ),
          const SizedBox(height: 4),
          Text(
            '$total',
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 11, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _summaryLegalCard({
    required String statusText,
    required String subtitle,
    required Color backgroundColor,
    bool showWarning = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Text(
                      '법적 상태',
                      style: TextStyle(fontSize: 13, color: Colors.white),
                    ),
                    if (showWarning) ...[
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.error_outline_rounded,
                        color: Colors.yellow,
                        size: 14,
                      ),
                    ],
                  ],
                ),
              ),
              InkWell(
                onTap: () => _showLegalStatusGuideDialog(),
                borderRadius: BorderRadius.circular(12),
                child: const Padding(
                  padding: EdgeInsets.all(2),
                  child: Icon(
                    Icons.help_outline_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            statusText,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 11, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Future<void> _showLegalStatusGuideDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('상시근로자 수 추정 기준 안내 (참고용)'),
        content: const SingleChildScrollView(
          child: Text(
            '상시근로자 수는 정산 기간의 근무기록·계약정보 기준 연인원/영업일수로 추정합니다.\n\n'
            '• 5인 이상: 연장·야간·휴일 가산수당(1.5배) 등 주요 규정 적용 가능\n'
            '• 10인 이상: 취업규칙 신고 의무 등 행정 의무 강화\n\n'
            '앱은 출퇴근 기록과 계약 근무요일을 바탕으로 자동 추정하며, '
            '정확한 판단은 노무사 확인을 권장합니다.',
            style: TextStyle(height: 1.35),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  Widget _workingNowCard({
    required String storeId,
    required List<Worker> workers,
  }) {
    final scheduledFallbackRows = _scheduledWorkingRows(workers);
    if (storeId.isEmpty) {
      return _buildWorkingNowCardBody(scheduledFallbackRows);
    }
    return StreamBuilder<List<Attendance>>(
      stream: DatabaseService().streamAttendance(storeId),
      builder: (context, snap) {
        final all = snap.data ?? const <Attendance>[];
        final now = AppClock.now();
        final todayYmd = rosterDateKey(now);

        // 오늘 발생한 모든 출근 기록 (완료 + 진행중)
        final todayLogs = all.where((a) => rosterDateKey(a.clockIn) == todayYmd).toList();
        final logsByStaff = <String, List<Attendance>>{};
        for (final l in todayLogs) {
          (logsByStaff[l.staffId] ??= []).add(l);
        }

        final open = all.where((a) => a.clockOut == null).toList();
        final workerById = {for (final w in workers) w.id: w};
        final rows = <_DashboardWorkRow>[];

        String format(int mins) {
          final h = mins ~/ 60;
          final m = mins % 60;
          if (h > 0) return '$h시간 ${m.toString().padLeft(2, '0')}분';
          return '$m분';
        }

        for (final a in open) {
          final w = workerById[a.staffId];
          final isOrphaned = w == null;
          final name = isOrphaned ? '(삭제된 직원)' : (w.name.isEmpty ? a.staffId : w.name);
          
          // 오늘 누적 시간 계산
          final staffLogs = logsByStaff[a.staffId] ?? [];
          int totalMins = staffLogs.fold(0, (sum, log) => sum + log.workedMinutesAt(now));
          int sessionMins = a.workedMinutesAt(now);

          final unplanned = a.attendanceStatus == 'Unplanned';
          final approved = a.attendanceStatus == 'UnplannedApproved';
          final pending = a.attendanceStatus == 'pending_approval';
          
          rows.add(
            _DashboardWorkRow(
              name: name,
              timeText: isOrphaned ? '출근 기록을 삭제하려면 누르세요' : '오늘 총 ${format(totalMins)} (현재 ${format(sessionMins)}째)',
              status: isOrphaned
                  ? '삭제 필요'
                  : (pending
                      ? '출근 승인 대기'
                      : (approved
                          ? '계획 외 승인'
                          : (unplanned ? '계획 외 근무 발생' : '정상'))),
              avatarBg: isOrphaned 
                  ? const Color(0xFFE24B4A) 
                  : (unplanned || approved || pending
                      ? const Color(0xFFEF9F27)
                      : const Color(0xFF1a6ebd)),
              attendance: a,
              needsApproval: unplanned || pending,
              isOrphaned: isOrphaned,
            ),
          );
        }
        
        // 출근 안 했지만 오늘 일한 사람들도 추가 (선택 사항인데 여기서는 '지금 근무 중' 카드이므로 일단 제외하거나 아래에 추가 가능)
        // 일단 사용자가 '각 근무자가 얼마나 일했는지' 보고 싶어 하므로, 이미 퇴근한 사람도 '오늘의 요약'에 넣으면 좋겠지만,
        // 현재 UI는 '지금 근무 중' 섹션입니다.
        // 섹션 제목을 '오늘의 근무 현황'으로 바꾸고 퇴근한 사람도 포함하는 것이 사용자 의도에 더 맞을 수 있습니다.

        final displayRows = rows.isEmpty ? scheduledFallbackRows : rows;

        return _buildWorkingNowCardBody(displayRows);
      },
    );
  }

  List<_DashboardWorkRow> _scheduledWorkingRows(List<Worker> workers) {
    final now = TimeOfDay.now();
    final nowMinutes = now.hour * 60 + now.minute;
    final weekday = AppClock.now().weekday == DateTime.sunday ? 0 : AppClock.now().weekday;
    final rows = <_DashboardWorkRow>[];
    for (final w in workers) {
      if (!w.workDays.contains(weekday)) continue;
      
      final parsedSchedule = _parseWorkerSchedule(w);
      final checkInTime = parsedSchedule[weekday]?.start ?? w.checkInTime;
      final checkOutTime = parsedSchedule[weekday]?.end ?? w.checkOutTime;

      final s = _toMinutesOrNull(checkInTime);
      final e = _toMinutesOrNull(checkOutTime);
      if (s == null || e == null) continue;
      if (nowMinutes < s || nowMinutes > e) continue;
      final lateMin = nowMinutes - s;
      final late = lateMin > 10;
      rows.add(
        _DashboardWorkRow(
          name: w.name,
          timeText: late
              ? '$checkInTime 출근 · $lateMin분 지각'
              : '$checkInTime 출근 · 정상 근무 중',
          status: late ? '미출근(지각)' : '미출근(대기)',
          avatarBg: late ? const Color(0xFFd4700a) : const Color(0xFF1a6ebd),
        ),
      );
    }
    return rows;
  }

  int? _toMinutesOrNull(String hhmm) {
    final p = hhmm.split(':');
    if (p.length != 2) return null;
    final h = int.tryParse(p[0]);
    final m = int.tryParse(p[1]);
    if (h == null || m == null) return null;
    return h * 60 + m;
  }

  Widget _buildWorkingNowCardBody(List<_DashboardWorkRow> rows) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE0E0E0), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '지금 근무 중',
                  style: TextStyle(
                    fontSize: 13,
                    color: const Color(0xFF888888),
                    letterSpacing: 0.5,
                  ),
                ),
                _buildBadge(
                  '${rows.length}명',
                  bgColor: const Color(0xFF1a6ebd),
                  textColor: Colors.white,
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 0.5, color: Color(0xFFE0E0E0)),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(14),
              child: Text('현재 근무 중인 직원이 없습니다.', style: TextStyle(color: Color(0xFF888888))),
            )
          else
            ...rows.asMap().entries.map((entry) {
              final i = entry.key;
              final row = entry.value;
              final isWarn = row.status != '정상';
              return _buildWorkerRow(
                initial: row.name.isEmpty ? '-' : row.name.substring(0, 1),
                avatarBg: row.avatarBg,
                avatarText: Colors.white,
                name: row.name,
                time: row.timeText,
                status: row.status,
                statusBg: isWarn ? const Color(0xFFFFF0DC) : const Color(0xFFEAF3DE),
                statusText: isWarn ? const Color(0xFF854F0B) : const Color(0xFF286b3a),
                isLast: i == rows.length - 1,
                onTap: row.isOrphaned && row.attendance != null
                    ? () => _deleteOrphanedAttendance(row.attendance!)
                    : (row.needsApproval && row.attendance != null
                        ? () => _approveAttendanceForBoss(row.attendance!)
                        : null),
              );
            }),
        ],
      ),
    );
  }

  String _formatHm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  Future<void> _approveAttendanceForBoss(Attendance attendance) async {
    if (!mounted) return;
    final pending = attendance.attendanceStatus == 'pending_approval';
    final isUnplanned = attendance.attendanceStatus == 'Unplanned';

    if (pending && attendance.originalClockIn != null) {
      final schedText = attendance.scheduledShiftStartIso != null
          ? _formatHm(DateTime.parse(attendance.scheduledShiftStartIso!))
          : '—';
      final choice = await showDialog<_PendingClockInApprove?>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('출근 승인'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('실제 출근(찍힌 시각): ${_formatHm(attendance.originalClockIn!)}'),
                Text('근무표 정시: $schedText'),
                const SizedBox(height: 12),
                const Text(
                  '급여에 반영할 출근 시각을 선택하세요. 사장님 지시로 일찍 출근한 경우에는 「실제 출근 시각」을 선택할 수 있습니다.',
                  style: TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(ctx).pop(_PendingClockInApprove.actualPunch),
              child: const Text('실제 출근 시각'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(ctx).pop(_PendingClockInApprove.payrollScheduled),
              child: const Text('정시 기준'),
            ),
          ],
        ),
      );
      if (choice == null || !mounted) return;

      DateTime newClockIn = attendance.clockIn;
      final orig = attendance.originalClockIn!;
      if (choice == _PendingClockInApprove.payrollScheduled) {
        if (attendance.scheduledShiftStartIso != null) {
          final sched = DateTime.parse(attendance.scheduledShiftStartIso!);
          newClockIn = orig.isAfter(sched) ? orig : sched;
        } else {
          newClockIn = attendance.clockIn;
        }
      } else {
        newClockIn = orig;
      }

      final updated = Attendance(
        id: attendance.id,
        staffId: attendance.staffId,
        storeId: attendance.storeId,
        clockIn: newClockIn,
        clockOut: attendance.clockOut,
        originalClockIn: attendance.originalClockIn,
        originalClockOut: attendance.originalClockOut,
        breakStart: attendance.breakStart,
        breakEnd: attendance.breakEnd,
        inWifiBssid: attendance.inWifiBssid,
        outWifiBssid: attendance.outWifiBssid,
        isAutoApproved: true,
        exceptionReason: attendance.exceptionReason,
        type: attendance.type,
        isAttendanceEquivalent: attendance.isAttendanceEquivalent,
        attendanceStatus: 'Normal',
        scheduledShiftStartIso: attendance.scheduledShiftStartIso,
        scheduledShiftEndIso: attendance.scheduledShiftEndIso,
        overtimeApproved: attendance.overtimeApproved,
        overtimeReason: attendance.overtimeReason,
      );
      await DatabaseService().recordAttendance(updated);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            choice == _PendingClockInApprove.actualPunch
                ? '실제 출근 시각 기준으로 승인했습니다.'
                : '정시 기준으로 승인했습니다.',
          ),
        ),
      );
      return;
    }

    final storeInfo = Hive.box<StoreInfo>('store').get('current');
    final isFiveOrMore = storeInfo?.isFiveOrMore ?? false;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(pending ? '출근 승인 (대근/추가)' : '계획 외 근무 승인'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              (pending || isUnplanned)
                  ? '근무표와 다른 출근 요청(스케줄 외 근무)을 승인하시겠습니까?'
                  : '이 출근 기록을 승인하시겠습니까?',
            ),
            if ((pending || isUnplanned) && isFiveOrMore) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFCEBEB),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Color(0xFFE24B4A), size: 18),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '사전 스케줄이 없는 대체/추가 근무입니다. 사업장 운영 형태에 따라 연장 근로에 대한 가산 수당(1.5배)이 발생할 수 있습니다.',
                        style: TextStyle(fontSize: 12, color: Color(0xFFA32D2D)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('출근 승인'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final newStatus = (pending || isUnplanned) ? 'Normal' : 'UnplannedApproved';
    var newClockIn = attendance.clockIn;
    if (pending &&
        attendance.scheduledShiftStartIso != null &&
        attendance.originalClockIn != null) {
      final sched = DateTime.parse(attendance.scheduledShiftStartIso!);
      final orig = attendance.originalClockIn!;
      newClockIn = orig.isAfter(sched) ? orig : sched;
    }
    final updated = Attendance(
      id: attendance.id,
      staffId: attendance.staffId,
      storeId: attendance.storeId,
      clockIn: newClockIn,
      clockOut: attendance.clockOut,
      originalClockIn: attendance.originalClockIn,
      originalClockOut: attendance.originalClockOut,
      breakStart: attendance.breakStart,
      breakEnd: attendance.breakEnd,
      inWifiBssid: attendance.inWifiBssid,
      outWifiBssid: attendance.outWifiBssid,
      isAutoApproved: true,
      exceptionReason: attendance.exceptionReason,
      type: attendance.type,
      isAttendanceEquivalent: attendance.isAttendanceEquivalent,
      attendanceStatus: newStatus,
      scheduledShiftStartIso: attendance.scheduledShiftStartIso,
      scheduledShiftEndIso: attendance.scheduledShiftEndIso,
      overtimeApproved: attendance.overtimeApproved,
      overtimeReason: attendance.overtimeReason,
    );
    await DatabaseService().recordAttendance(updated);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(pending ? '출근을 승인했습니다.' : '계획 외 근무를 승인했습니다.')),
    );
  }

  Future<void> _approveException(Attendance a) async {
    final isEarly = a.attendanceStatus == 'early_leave_pending';
    final updated = Attendance(
      id: a.id,
      staffId: a.staffId,
      storeId: a.storeId,
      clockIn: a.clockIn,
      clockOut: a.clockOut,
      originalClockIn: a.originalClockIn,
      originalClockOut: a.originalClockOut,
      breakStart: a.breakStart,
      breakEnd: a.breakEnd,
      inWifiBssid: a.inWifiBssid,
      outWifiBssid: a.outWifiBssid,
      isAutoApproved: true,
      exceptionReason: a.exceptionReason,
      type: a.type,
      isAttendanceEquivalent: a.isAttendanceEquivalent,
      attendanceStatus: 'Normal',
      scheduledShiftStartIso: a.scheduledShiftStartIso,
      scheduledShiftEndIso: a.scheduledShiftEndIso,
      overtimeApproved: !isEarly,
      overtimeReason: a.overtimeReason,
    );
    await DatabaseService().recordAttendance(updated);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(isEarly ? '조기 퇴근을 승인했습니다.' : '연장 근무를 승인했습니다.')),
    );
  }

  Future<void> _rejectException(Attendance a) async {
    final isEarly = a.attendanceStatus == 'early_leave_pending';
    if (!isEarly && a.scheduledShiftEndIso == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('근무표 종료 시각이 없어 반려할 수 없습니다.')),
      );
      return;
    }
    final schedEnd = a.scheduledShiftEndIso != null
        ? DateTime.parse(a.scheduledShiftEndIso!)
        : a.clockOut;
        
    final updated = Attendance(
      id: a.id,
      staffId: a.staffId,
      storeId: a.storeId,
      clockIn: a.clockIn,
      clockOut: isEarly ? a.clockOut : schedEnd,
      originalClockIn: a.originalClockIn,
      originalClockOut: a.originalClockOut ?? a.clockOut,
      breakStart: a.breakStart,
      breakEnd: a.breakEnd,
      inWifiBssid: a.inWifiBssid,
      outWifiBssid: a.outWifiBssid,
      isAutoApproved: true,
      exceptionReason: a.exceptionReason,
      type: a.type,
      isAttendanceEquivalent: a.isAttendanceEquivalent,
      attendanceStatus: 'Normal',
      scheduledShiftStartIso: a.scheduledShiftStartIso,
      scheduledShiftEndIso: a.scheduledShiftEndIso,
      overtimeApproved: false,
      overtimeReason: a.overtimeReason,
    );
    await DatabaseService().recordAttendance(updated);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(isEarly ? '조기 퇴근을 반려했습니다.' : '연장 근무를 반려했습니다. 퇴근 시각은 근무표 종료 시각으로 반영됩니다.')),
    );
  }

  Future<void> _deleteOrphanedAttendance(Attendance attendance) async {
    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('삭제된 직원 기록 정리'),
        content: const Text(
          '직원이 퇴사 또는 삭제되었으나 당시의 출근 기록(퇴근 미완료)이 남아있습니다.\n\n해당 기록을 지금 완전히 삭제하시겠습니까?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    try {
      await DatabaseService().deleteAttendance(attendance.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('기록이 정상적으로 삭제되었습니다.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('삭제 실패: $e')),
      );
    }
  }

  Widget _exceptionPendingCard({
    required String storeId,
    required List<Worker> workers,
  }) {
    if (storeId.isEmpty) {
      return _buildExceptionPendingBody(const [], workers);
    }
    return StreamBuilder<List<Attendance>>(
      stream: DatabaseService().streamAttendance(storeId),
      builder: (context, snap) {
        final all = snap.data ?? const <Attendance>[];
        final pending = all
            .where((a) =>
                (a.attendanceStatus == 'pending_approval' ||
                 a.attendanceStatus == 'Unplanned' ||
                 a.attendanceStatus == 'pending_overtime' ||
                 a.attendanceStatus == 'early_leave_pending') &&
                a.clockOut != null)
            .toList();
        return _buildExceptionPendingBody(pending, workers);
      },
    );
  }

  Widget _buildExceptionPendingBody(
    List<Attendance> pending,
    List<Worker> workers,
  ) {
    final workerById = {for (final w in workers) w.id: w};
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE0E0E0), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '예외(연장/조기) 승인 대기',
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF888888),
                    letterSpacing: 0.5,
                  ),
                ),
                _buildBadge(
                  '${pending.length}건',
                  bgColor: const Color(0xFF8E44AD),
                  textColor: Colors.white,
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 0.5, color: Color(0xFFE0E0E0)),
          if (pending.isEmpty)
            const Padding(
              padding: EdgeInsets.all(14),
              child: Text(
                '조기 퇴근 및 연장 승인 대기 건이 없습니다.',
                style: TextStyle(color: Color(0xFF888888)),
              ),
            )
          else
            ...pending.asMap().entries.map((e) {
              final i = e.key;
              final a = e.value;
              final w = workerById[a.staffId];
              final name = w?.name ?? 
                  (a.staffId.length > 8 
                      ? '정보 로딩 중... (${a.staffId.substring(0, 8)})' 
                      : a.staffId);
              final outHm = _formatHm(a.clockOut!);
              
              final isEarly = a.attendanceStatus == 'early_leave_pending';
              final isPendingClockIn = a.attendanceStatus == 'pending_approval';
              final isUnplanned = a.attendanceStatus == 'Unplanned';
              
              final label = isPendingClockIn 
                  ? '조기 출근' 
                  : (isUnplanned ? '휴무일 출근' : (isEarly ? '조기 퇴근' : '연장 근무'));
              
              final reason = (isPendingClockIn || isUnplanned)
                  ? (a.exceptionReason?.trim().isNotEmpty == true ? a.exceptionReason! : '(기록 없음)')
                  : (isEarly
                      ? (a.exceptionReason?.trim().isNotEmpty == true ? a.exceptionReason! : '(사유 없음)')
                      : (a.overtimeReason?.trim().isNotEmpty == true ? a.overtimeReason! : '(사유 없음)'));
                  
              final isLast = i == pending.length - 1;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$label: $outHm · 사유: $reason',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            if (!isPendingClockIn && !isUnplanned) ...[
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => _rejectException(a),
                                  child: const Text('반려'),
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Expanded(
                              child: FilledButton(
                                onPressed: () {
                                  if (isPendingClockIn || isUnplanned) {
                                    _approveAttendanceForBoss(a);
                                  } else {
                                    _approveException(a);
                                  }
                                },
                                child: Text((isPendingClockIn || isUnplanned) ? '출근 승인' : '승인'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (!isLast)
                    const Divider(
                      height: 1,
                      thickness: 0.5,
                      color: Color(0xFFE0E0E0),
                    ),
                ],
              );
            }),
        ],
      ),
    );
  }

  Widget _healthCard(List<_DashboardHealthRow> rows) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE0E0E0), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '보건증 만료 임박',
                  style: TextStyle(
                    fontSize: 13,
                    color: const Color(0xFF888888),
                    letterSpacing: 0.5,
                  ),
                ),
                _buildBadge(
                  '${rows.length}명',
                  bgColor: const Color(0xFFd4700a),
                  textColor: Colors.white,
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 0.5, color: Color(0xFFE0E0E0)),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(14),
              child: Text('만료 임박 보건증이 없습니다.', style: TextStyle(color: Color(0xFF888888))),
            )
          else
            ...rows.asMap().entries.map((entry) {
              final i = entry.key;
              final row = entry.value;
              return _buildHealthRow(
                name: row.name,
                date: row.date,
                dotColor: row.dotColor,
                dDay: row.dday,
                badgeBg: row.badgeBg,
                badgeText: row.badgeText,
                isLast: i == rows.length - 1,
              );
            }),
        ],
      ),
    );
  }

  List<_DashboardHealthRow> _healthAlertRows(List<Worker> workers) {
    final today = AppClock.now();
    final rows = <_DashboardHealthRow>[];
    for (final w in workers) {
      if (!w.hasHealthCert || w.healthCertExpiry == null || w.healthCertExpiry!.isEmpty) continue;
      final expiry = DateTime.tryParse(w.healthCertExpiry!);
      if (expiry == null) continue;
      final d = DateTime(expiry.year, expiry.month, expiry.day).difference(DateTime(today.year, today.month, today.day)).inDays;
      if (d > 30) continue;
      final urgent = d <= 7;
      
      String ddayText;
      if (d < 0) {
        ddayText = '만료 (D+${-d})';
      } else if (d == 0) {
        ddayText = 'D-Day';
      } else {
        ddayText = 'D-$d';
      }
      
      rows.add(
        _DashboardHealthRow(
          name: w.name,
          date: '${expiry.year}.${expiry.month.toString().padLeft(2, '0')}.${expiry.day.toString().padLeft(2, '0')}',
          dday: ddayText,
          dotColor: urgent ? const Color(0xFFE24B4A) : const Color(0xFFEF9F27),
          badgeBg: urgent ? const Color(0xFFFCEBEB) : const Color(0xFFFFF0DC),
          badgeText: urgent ? const Color(0xFFA32D2D) : const Color(0xFF854F0B),
        ),
      );
    }
    rows.sort((a, b) => _parseDDay(a.dday).compareTo(_parseDDay(b.dday)));
    return rows;
  }

  int _parseDDay(String ddayStr) {
    if (ddayStr == 'D-Day') return 0;
    if (ddayStr.startsWith('만료 (D+')) {
      final val = int.tryParse(ddayStr.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      return -val; // 만료된 것은 음수로 반환하여 최상단에 오게 함
    }
    if (ddayStr.startsWith('D-')) {
      return int.tryParse(ddayStr.substring(2)) ?? 999;
    }
    return 999;
  }

  Widget _buildWorkerRow({
    required String initial,
    required Color avatarBg,
    required Color avatarText,
    required String name,
    required String time,
    required String status,
    required Color statusBg,
    required Color statusText,
    bool isLast = false,
    VoidCallback? onTap,
  }) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: avatarBg,
                  child: Text(
                    initial,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: avatarText,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        time,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF888888),
                        ),
                      ),
                    ],
                  ),
                ),
                _buildBadge(status, bgColor: statusBg, textColor: statusText),
              ],
            ),
          ),
        ),
        if (!isLast)
          const Divider(
            height: 1,
            thickness: 0.5,
            indent: 14,
            endIndent: 14,
            color: Color(0xFFE0E0E0),
          ),
      ],
    );
  }

  Widget _buildHealthRow({
    required String name,
    required String date,
    required Color dotColor,
    required String dDay,
    required Color badgeBg,
    required Color badgeText,
    bool isLast = false,
  }) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(fontSize: 14),
                ),
              ),
              Text(
                date,
                style: const TextStyle(fontSize: 12, color: Color(0xFF888888)),
              ),
              const SizedBox(width: 8),
              _buildSmallBadge(dDay, bgColor: badgeBg, textColor: badgeText),
            ],
          ),
        ),
        if (!isLast)
          const Divider(
            height: 1,
            thickness: 0.5,
            indent: 14,
            endIndent: 14,
            color: Color(0xFFE0E0E0),
          ),
      ],
    );
  }

  Widget _buildRenewalAlertBanner(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFBE8E8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE24B4A), width: 1.5),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.gavel_rounded,
            color: Color(0xFFE24B4A),
            size: 24,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${PayrollConstants.minimumWageEffectiveYear}년 최저임금 갱신 원클릭 배포 대기 중',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFFC0392B),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  '최저임금 미달 알바생이 있습니다. 즉시 임금 변경 합의서를 일괄 전송하세요.',
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFFC0392B),
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ContractRenewalScreen()),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE24B4A),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: const Size(0, 0),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('배포하기', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardUnregisteredBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF0DC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFd4700a), width: 0.5),
      ),
      child: const Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: Color(0xFFd4700a),
            size: 20,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              '사업장 정보를 등록해주세요',
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF854F0B),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }



  Widget _buildNoticeSection(String storeId) {
    if (storeId.isEmpty) return const SizedBox.shrink();

    return FutureBuilder<QuerySnapshot>(
      future: FirebaseFirestore.instance
          .collection('stores')
          .doc(storeId)
          .collection('notices')
          .orderBy('createdAt', descending: true)
          .limit(3)
          .get(),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        
        Widget wrapCard(Widget child) {
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE0E0E0), width: 0.5),
              boxShadow: [
                 BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 2)),
              ],
            ),
            child: child,
          );
        }

        if (snap.data!.docs.isEmpty) {
          return InkWell(
            onTap: () => widget.onOpenNoticeTab(0),
            borderRadius: BorderRadius.circular(16),
            child: wrapCard(
              Row(
                children: [
                  Icon(Icons.campaign_rounded, size: 20, color: Colors.blue.shade700),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      '등록된 공지사항이 없습니다.',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, color: Colors.black54),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.campaign_rounded, size: 18, color: Colors.blue.shade700),
                    const SizedBox(width: 6),
                    const Text('최신 공지', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black54)),
                  ],
                ),
                InkWell(
                  onTap: () => widget.onOpenNoticeTab(0),
                  borderRadius: BorderRadius.circular(12),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Text('공지사항 전체보기 >', style: TextStyle(fontSize: 12, color: Colors.blue)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...snap.data!.docs.map((doc) {
              final d = doc.data() as Map<String, dynamic>;
              final title = d['title']?.toString() ?? '공지';
              final content = d['content']?.toString() ?? '';
              final imageUrl = d['imageUrl']?.toString() ?? '';
              final createdAt = d['createdAt'];

              String dateText = '';
              if (createdAt is Timestamp) {
                final dt = createdAt.toDate();
                dateText = '${dt.year}.${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')}';
              }

              return StatefulBuilder(
                builder: (context, setItemState) {
                  bool isExpanded = false;
                  return InkWell(
                    onTap: () => setItemState(() => isExpanded = !isExpanded),
                    borderRadius: BorderRadius.circular(16),
                    child: wrapCard(
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (dateText.isNotEmpty)
                                      Text(
                                        dateText,
                                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                                      ),
                                    const SizedBox(height: 2),
                                    Text(
                                      title,
                                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                                      maxLines: isExpanded ? null : 1,
                                      overflow: isExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              if (imageUrl.isNotEmpty && !isExpanded) ...[
                                const SizedBox(width: 8),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: R2Image(storeId: storeId, imagePathOrId: imageUrl, width: 36, height: 36, fit: BoxFit.cover),
                                ),
                              ],
                            ],
                          ),
                          if (isExpanded) ...[
                            const SizedBox(height: 8),
                            const Divider(height: 1),
                            const SizedBox(height: 8),
                            Text(
                              content,
                              style: const TextStyle(fontSize: 13, height: 1.4, color: Colors.black87),
                            ),
                            if (imageUrl.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: R2Image(storeId: storeId, imagePathOrId: imageUrl, fit: BoxFit.contain, width: double.infinity),
                              ),
                            ]
                          ]
                        ],
                      ),
                    ),
                  );
                }
              );
            }),
          ],
        );
      },
    );
  }

  String _expirationLine(Map<String, dynamic> d) {
    final name = d['productName']?.toString() ?? '품목';
    final qty = d['quantity']?.toString() ?? '';
    if (qty.isNotEmpty) {
      return '$name · $qty';
    }
    return name;
  }

  Widget _buildExpirationSection(String storeId) {
    if (storeId.isEmpty) return const SizedBox.shrink();

    return FutureBuilder<QuerySnapshot>(
      future: FirebaseFirestore.instance
          .collection('stores')
          .doc(storeId)
          .collection('expirations')
          .orderBy('dueDate', descending: false)
          .get(),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();

        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        
        final docs = snap.data!.docs.where((doc) {
          final ts = (doc.data() as Map<String, dynamic>)['dueDate'];
          if (ts is Timestamp) {
            final dt = ts.toDate();
            final dueDay = DateTime(dt.year, dt.month, dt.day);
            return dueDay.isAtSameMomentAs(today) || dueDay.isBefore(today);
          }
          return false;
        }).toList();

        if (docs.isEmpty) {
          return InkWell(
            onTap: () => widget.onOpenNoticeTab(2), // 2: 유통기한
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE0E0E0), width: 0.5),
              ),
              child: Row(
                children: [
                  const Icon(Icons.inventory_2_rounded, size: 20, color: Color(0xFFE67E22)),
                  const SizedBox(width: 8),
                  const Text('유통기한', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black54)),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      '오늘 마감인 품목이 없습니다.',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, color: Colors.black54),
                    ),
                  ),
                  const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
                ],
              ),
            ),
          );
        }

        return InkWell(
          onTap: () => widget.onOpenNoticeTab(2), // 2: 유통기한
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFFF6ED), Color(0xFFFFFFFF)],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFFFDAB9), width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.inventory_2_rounded, size: 18, color: Color(0xFFE67E22)),
                    const SizedBox(width: 8),
                    const Text(
                      '오늘 유통기한 마감',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFD35400),
                      ),
                    ),
                    const Spacer(),
                    _buildBadge(
                      '${docs.length}건',
                      bgColor: const Color(0xFFE67E22),
                      textColor: Colors.white,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...docs.take(3).map((doc) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        const Text('· ', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black45)),
                        Expanded(
                          child: Text(
                            _expirationLine(doc.data() as Map<String, dynamic>),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                if (docs.length > 3)
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Text('...외 추가 마감 품목 있음', style: TextStyle(fontSize: 11, color: Colors.black54)),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTodoSection(String storeId) {
    if (storeId.isEmpty) return const SizedBox.shrink();

    return FutureBuilder<QuerySnapshot>(
      future: FirebaseFirestore.instance
          .collection('stores')
          .doc(storeId)
          .collection('todos')
          .where('done', isEqualTo: false)
          .get(),
      builder: (context, snap) {
        if (snap.hasError) {
          // Fallback UI or print error
          debugPrint('Todo fetch error: ${snap.error}');
        }
        if (!snap.hasData) return const SizedBox.shrink();
        
        // Sort explicitly by createdAt descending in Dart
        final allDocs = snap.data!.docs.toList();
        allDocs.sort((a, b) {
          final ta = (a.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
          final tb = (b.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
          if (ta == null || tb == null) return 0;
          return tb.compareTo(ta); // descending
        });
        
        final docs = allDocs.take(3).toList();
        if (docs.isEmpty) {
          return InkWell(
            onTap: () => widget.onOpenNoticeTab(1), // 1: 전달사항
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE0E0E0), width: 0.5),
              ),
              child: Row(
                children: [
                  Icon(Icons.checklist_rounded, size: 20, color: Colors.green.shade700),
                  const SizedBox(width: 8),
                  const Text('전달사항', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black54)),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      '새로운 전달사항이 없습니다.',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, color: Colors.black54),
                    ),
                  ),
                  const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
                ],
              ),
            ),
          );
        }

        return InkWell(
          onTap: () => widget.onOpenNoticeTab(1), // 1: 전달사항
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE0E0E0), width: 0.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.checklist_rounded, size: 18, color: Colors.green.shade700),
                    const SizedBox(width: 8),
                    const Text(
                      '미완료 전달사항',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const Spacer(),
                    const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
                  ],
                ),
                const SizedBox(height: 8),
                ...docs.map((doc) {
                  final title = (doc.data() as Map<String, dynamic>)['title']?.toString() ?? '전달사항';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Icon(Icons.radio_button_unchecked, size: 14, color: Colors.grey.shade400),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, color: Colors.black87),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DashboardWorkRow {
  _DashboardWorkRow({
    required this.name,
    required this.timeText,
    required this.status,
    required this.avatarBg,
    this.attendance,
    this.needsApproval = false,
    this.isOrphaned = false,
  });

  final String name;
  final String timeText;
  final String status;
  final Color avatarBg;
  final Attendance? attendance;
  final bool needsApproval;
  final bool isOrphaned;
}

class _DashboardHealthRow {
  _DashboardHealthRow({
    required this.name,
    required this.date,
    required this.dday,
    required this.dotColor,
    required this.badgeBg,
    required this.badgeText,
  });

  final String name;
  final String date;
  final String dday;
  final Color dotColor;
  final Color badgeBg;
  final Color badgeText;
}

Widget _pageDot({required bool active}) {
  return Container(
    width: 6,
    height: 6,
    decoration: BoxDecoration(
      color: active
          ? Colors.white
          : Colors.white.withValues(alpha: 0.3),
      shape: BoxShape.circle,
    ),
  );
}

Widget _buildBadge(String text, {required Color bgColor, required Color textColor}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: bgColor,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: textColor,
      ),
    ),
  );
}

Widget _buildSmallBadge(String text, {required Color bgColor, required Color textColor}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: bgColor,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w500,
        color: textColor,
      ),
    ),
  );
}

// --- Schedule -----------------------------------------------------------------

class SchedulePage extends StatefulWidget {
  const SchedulePage({super.key, required this.pageIndex});

  final int pageIndex;

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  DateTime _currentWeekStart = _getMonday(AppClock.now());

  @override
  void initState() {
    super.initState();
  }

  static DateTime _getMonday(DateTime d) => d.subtract(Duration(days: d.weekday - 1));
  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
  static String _toYmd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  void _previousWeek() => setState(() => _currentWeekStart = _currentWeekStart.subtract(const Duration(days: 7)));
  void _nextWeek() => setState(() => _currentWeekStart = _currentWeekStart.add(const Duration(days: 7)));

  Future<void> _onCellTap(Worker worker, int dayIndex) async {
    final target = _currentWeekStart.add(Duration(days: dayIndex));
    final ymd = _toYmd(target);
    final key = '${worker.id}_$ymd';
    final overrideBox = Hive.box<ScheduleOverride>('schedule_overrides');
    final current = overrideBox.get(key);

    final initialIn = current?.checkIn ?? worker.checkInTime;
    final initialOut = current?.checkOut ?? worker.checkOutTime;
    final hasShift = _hasEffectiveShift(worker, target, overrideBox.toMap());
    final isSubstituteShift = current != null && current.checkIn != null;
    final isAnnualLeave = current?.isAnnualLeave ?? false;
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.edit_calendar_outlined),
                title: const Text('근무시간 수정'),
                onTap: () => Navigator.of(context).pop('edit'),
              ),
              ListTile(
                leading: const Icon(Icons.swap_horiz_rounded),
                title: const Text('대타 / 교대 지정'),
                enabled: hasShift,
                onTap: hasShift ? () => Navigator.of(context).pop('substitute') : null,
              ),
              if (!isAnnualLeave)
                ListTile(
                  leading: const Icon(Icons.beach_access_rounded, color: Color(0xFF1565C0)),
                  title: const Text('연차 처리', style: TextStyle(color: Color(0xFF1565C0), fontWeight: FontWeight.w600)),
                  onTap: () => Navigator.of(context).pop('annual_leave'),
                ),
              if (current != null)
                ListTile(
                  leading: const Icon(Icons.restart_alt_rounded, color: Color(0xFFE24B4A)),
                  title: Text(
                    isAnnualLeave ? '연차 취소' : isSubstituteShift ? '대근 지정 취소' : '기본 근무로 초기화',
                    style: const TextStyle(color: Color(0xFFE24B4A), fontWeight: FontWeight.w600),
                  ),
                  onTap: () => Navigator.of(context).pop('reset'),
                ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;

    if (action == 'reset') {
      await _resetOverride(worker, target, overrideBox);
      return;
    }

    if (action == 'annual_leave') {
      await _handleAnnualLeave(worker, target, overrideBox);
      return;
    }

    if (action == 'substitute') {
      await _assignSubstitution(
        originalWorker: worker,
        targetDate: target,
        ymd: ymd,
        overrideBox: overrideBox,
      );
      return;
    }

    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ScheduleEditSheet(
        workerName: worker.name,
        dayLabel: const ['월', '화', '수', '목', '금', '토', '일'][dayIndex],
        initialCheckIn: initialIn,
        initialCheckOut: initialOut,
        onSave: (checkIn, checkOut) async {
          await _saveOverrideWithCleanup(
            worker: worker,
            date: target,
            checkIn: checkIn,
            checkOut: checkOut,
            overrideBox: overrideBox,
          );
          await _checkStandingFlipRiskAfterScheduleChange();
        },
        onDelete: () async {
          await _saveOverrideWithCleanup(
            worker: worker,
            date: target,
            checkIn: null,
            checkOut: null,
            overrideBox: overrideBox,
          );
          await _checkStandingFlipRiskAfterScheduleChange();
        },
      ),
    );
  }

  bool _hasEffectiveShift(
    Worker worker,
    DateTime date,
    Map<dynamic, ScheduleOverride> overrides,
  ) {
    final key = '${worker.id}_${_toYmd(date)}';
    final o = overrides[key];
    final baseDay = date.weekday == DateTime.sunday ? 0 : date.weekday;
    final hasBaseShift = worker.workDays.contains(baseDay);
    final checkIn = (o != null) ? o.checkIn : (hasBaseShift ? worker.checkInTime : null);
    final checkOut = (o != null) ? o.checkOut : (hasBaseShift ? worker.checkOutTime : null);
    return checkIn != null && checkOut != null;
  }

  ({String checkIn, String checkOut})? _effectiveShiftRange(
    Worker worker,
    DateTime date,
    Map<dynamic, ScheduleOverride> overrides,
  ) {
    final key = '${worker.id}_${_toYmd(date)}';
    final o = overrides[key];
    final baseDay = date.weekday == DateTime.sunday ? 0 : date.weekday;
    final hasBaseShift = worker.workDays.contains(baseDay);
    final checkIn = (o != null) ? o.checkIn : (hasBaseShift ? worker.checkInTime : null);
    final checkOut = (o != null) ? o.checkOut : (hasBaseShift ? worker.checkOutTime : null);
    if (checkIn == null || checkOut == null) return null;
    return (checkIn: checkIn, checkOut: checkOut);
  }

  int _minutesFromHm(String hm) {
    final p = hm.split(':');
    if (p.length != 2) return 0;
    return (int.tryParse(p[0]) ?? 0) * 60 + (int.tryParse(p[1]) ?? 0);
  }

  bool _isOverlapping(String aIn, String aOut, String bIn, String bOut) {
    final aStart = _minutesFromHm(aIn);
    var aEnd = _minutesFromHm(aOut);
    final bStart = _minutesFromHm(bIn);
    var bEnd = _minutesFromHm(bOut);
    if (aEnd <= aStart) aEnd += 24 * 60;
    if (bEnd <= bStart) bEnd += 24 * 60;
    return aStart < bEnd && bStart < aEnd;
  }

  String? _normalizeHm(String? hm) {
    if (hm == null) return null;
    final p = hm.split(':');
    if (p.length < 2) return null;
    final h = p[0].padLeft(2, '0');
    final m = p[1].padLeft(2, '0');
    return '$h:$m';
  }

  /// 연차 처리: ScheduleOverride + Attendance(isAttendanceEquivalent) + usedAnnualLeave 차감
  Future<void> _handleAnnualLeave(Worker worker, DateTime date, Box<ScheduleOverride> overrideBox) async {
    final ymd = _toYmd(date);
    final key = '${worker.id}_$ymd';

    // 이미 연차 처리된 날인지 확인
    final existing = overrideBox.get(key);
    if (existing?.isAnnualLeave ?? false) return;

    // 확인 다이얼로그
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('연차 처리'),
        content: Text(
          '${worker.name}의 ${date.month}/${date.day} 근무를 연차로 처리합니다.\n'
          '연차 1일이 차감되며, 해당 일은 출근한 것으로 간주되어 주휴수당에 영향을 주지 않습니다.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('연차 처리')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // 1. ScheduleOverride 저장 (연차 타입)
    await overrideBox.put(
      key,
      ScheduleOverride(
        workerId: worker.id,
        date: ymd,
        checkIn: null,
        checkOut: null,
        leaveType: 'annual_leave',
      ),
    );

    // 2. Attendance 레코드 생성 (isAttendanceEquivalent = true)
    final sid = await WorkerService.resolveStoreId();
    if (sid.isNotEmpty) {
      final leaveAttendanceId = 'leave_${worker.id}_$ymd';
      final leaveDate = DateTime(date.year, date.month, date.day, 9, 0);
      final leaveAttendance = Attendance(
        id: leaveAttendanceId,
        staffId: worker.id,
        storeId: sid,
        clockIn: leaveDate,
        clockOut: leaveDate,
        type: AttendanceType.mobile,
        isAttendanceEquivalent: true,
        attendanceStatus: 'annual_leave',
        isEditedByBoss: true,
        editedByBossAt: AppClock.now(),
      );
      await DatabaseService().recordAttendance(leaveAttendance);

      // 3. usedAnnualLeave 1.0 증가
      worker.usedAnnualLeave += 1.0;
      await WorkerService.save(worker);

      // 4. Firestore rosterDay 동기화
      await _syncRosterDayToFirestore(worker.id, ymd, null, null, isOff: true);
    }

    if (mounted) setState(() {});
  }

  Future<void> _resetOverride(Worker worker, DateTime date, Box<ScheduleOverride> overrideBox) async {
    final ymd = _toYmd(date);
    final key = '${worker.id}_$ymd';
    final hasOverride = overrideBox.containsKey(key);
    if (!hasOverride) return;

    final o = overrideBox.get(key);

    // 연차 취소 처리
    if (o?.isAnnualLeave ?? false) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('연차 취소'),
          content: Text('${worker.name}의 ${date.month}/${date.day} 연차를 취소합니다.\n차감된 연차 1일이 복원됩니다.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('아니오')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE24B4A)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('연차 취소'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;

      await overrideBox.delete(key);
      await _syncRosterDayToFirestore(worker.id, ymd, null, null);

      // Attendance 삭제
      final leaveAttendanceId = 'leave_${worker.id}_$ymd';
      await DatabaseService().deleteAttendance(leaveAttendanceId);

      // usedAnnualLeave 복원
      worker.usedAnnualLeave = (worker.usedAnnualLeave - 1.0).clamp(0.0, double.infinity);
      await WorkerService.save(worker);

      if (mounted) setState(() {});
      return;
    }

    final isSubShift = o != null && o.checkIn != null; // Substitute worker (currently working)
    final isInOffState = o != null && o.checkIn == null; // Original worker (currently off)

    // Reset this worker
    await overrideBox.delete(key);
    await _syncRosterDayToFirestore(worker.id, ymd, null, null);

    // Smart Cancellation: If we reset a substitute, try to find the original person and restore them too.
    if (isSubShift) {
      final workers = WorkerService.getAll();
      final currentOverrides = overrideBox.toMap();
      final baseDay = date.weekday == DateTime.sunday ? 0 : date.weekday;
      
      final subIn = _normalizeHm(o.checkIn);
      final subOut = _normalizeHm(o.checkOut);

      for (final w in workers) {
        if (w.id == worker.id) continue;
        
        final wKey = '${w.id}_$ymd';
        final wOverride = currentOverrides[wKey];
        final wHasBaseShift = w.workDays.contains(baseDay);
        
        // If they had a base shift that matches what the sub was doing, BUT they are currently OFF by override...
        if (wHasBaseShift && 
            wOverride != null && wOverride.checkIn == null && 
            _normalizeHm(w.checkInTime) == subIn && 
            _normalizeHm(w.checkOutTime) == subOut) {
          
          await overrideBox.delete(wKey);
          await _syncRosterDayToFirestore(w.id, ymd, null, null);
          break; // We found the pair
        }
      }
    }
    // Smart Cancellation: If we reset an OFF person, try to find who took their shift and remove it.
    else if (isInOffState) {
        final workers = WorkerService.getAll();
        final currentOverrides = overrideBox.toMap();
        final baseDay = date.weekday == DateTime.sunday ? 0 : date.weekday;
        
        final originalIn = _normalizeHm(worker.checkInTime);
        final originalOut = _normalizeHm(worker.checkOutTime);

        for (final w in workers) {
            if (w.id == worker.id) continue;
            final wKey = '${w.id}_$ymd';
            final wOverride = currentOverrides[wKey];
            if (wOverride != null && _normalizeHm(wOverride.checkIn) == originalIn && _normalizeHm(wOverride.checkOut) == originalOut) {
                await overrideBox.delete(wKey);
                await _syncRosterDayToFirestore(w.id, ymd, null, null);
                break;
            }
        }
    }
  }

  Future<void> _syncRosterDayToFirestore(
    String workerId,
    String ymd,
    String? inHm,
    String? outHm, {
    bool isOff = false,
  }) async {
    final sid = await WorkerService.resolveStoreId();
    if (sid.isEmpty) return;
    await DatabaseService().syncWorkerRosterDay(
      storeId: sid,
      workerId: workerId,
      dateYmd: ymd,
      checkInHm: inHm,
      checkOutHm: outHm,
      isOff: isOff,
    );
  }

  /// rosterDays 문서 삭제 전: 해당 날짜 출근 기록이 있으면 차단
  Future<bool> _canRosterDayDeleteOrWarn({
    required Worker worker,
    required DateTime date,
  }) async {
    final sid = await WorkerService.resolveStoreId();
    if (sid.isEmpty) return true;
    final has = await DatabaseService().hasWorkerAttendanceOnDate(
      storeId: sid,
      workerId: worker.id,
      date: date,
    );
    if (!has) return true;
    if (!mounted) return false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('근무표 삭제 불가'),
        content: const Text(
          '해당 날짜에 이미 출근 기록(진행 중 또는 완료)이 있어 이 날짜의 근무표 일정을 삭제·되돌릴 수 없습니다.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('확인'),
          ),
        ],
      ),
    );
    return false;
  }

  Future<void> _saveOverrideWithCleanup({
    required Worker worker,
    required DateTime date,
    required String? checkIn,
    required String? checkOut,
    required Box<ScheduleOverride> overrideBox,
  }) async {
    final ymd = _toYmd(date);
    final key = '${worker.id}_$ymd';
    final baseDay = date.weekday == DateTime.sunday ? 0 : date.weekday;
    final hasBaseShift = worker.workDays.contains(baseDay);

    final normalizedIn = _normalizeHm(checkIn);
    final normalizedOut = _normalizeHm(checkOut);
    final baseIn = _normalizeHm(worker.checkInTime);
    final baseOut = _normalizeHm(worker.checkOutTime);

    final isSameAsBase =
        hasBaseShift && normalizedIn == baseIn && normalizedOut == baseOut;
    final isNoShift = normalizedIn == null || normalizedOut == null;

    if (isNoShift && !hasBaseShift) {
      if (!await _canRosterDayDeleteOrWarn(worker: worker, date: date)) {
        return;
      }
      await overrideBox.delete(key);
      await _syncRosterDayToFirestore(worker.id, ymd, null, null);
      return;
    }
    if (isSameAsBase) {
      if (!await _canRosterDayDeleteOrWarn(worker: worker, date: date)) {
        return;
      }
      await overrideBox.delete(key);
      await _syncRosterDayToFirestore(worker.id, ymd, null, null);
      return;
    }
    await overrideBox.put(
      key,
      ScheduleOverride(
        workerId: worker.id,
        date: ymd,
        checkIn: normalizedIn,
        checkOut: normalizedOut,
      ),
    );
    final forceOff = isNoShift && hasBaseShift;
    await _syncRosterDayToFirestore(worker.id, ymd, normalizedIn, normalizedOut, isOff: forceOff);
  }

  Future<void> _assignSubstitution({
    required Worker originalWorker,
    required DateTime targetDate,
    required String ymd,
    required Box<ScheduleOverride> overrideBox,
  }) async {
    final workers = WorkerService.getAll();
    final overrides = overrideBox.toMap();
    final sourceShift = _effectiveShiftRange(originalWorker, targetDate, overrides);
    if (sourceShift == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('해당 날짜에 넘길 근무가 없습니다.')),
      );
      return;
    }

    final available = workers.where((w) => w.id != originalWorker.id).toList();

    if (!mounted) return;
    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('교대 또는 대타 가능한 직원이 없습니다.')),
      );
      return;
    }

    final selected = await showModalBottomSheet<Worker>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                title: Text('대타 / 교대 지정', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('근무가 없는 직원은 대타, 근무가 있는 직원은 맞교대 처리됩니다.'),
              ),
              ...available.map(
                (w) => ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(w.name),
                  onTap: () => Navigator.of(context).pop(w),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected == null) return;

    final selectedShift = _effectiveShiftRange(selected, targetDate, overrides);
    final isSwap = selectedShift != null;

    final beforeBMinutes = _workerWeeklyPureMinutes(selected, overrides, _currentWeekStart);

    if (isSwap) {
      await _saveOverrideWithCleanup(
        worker: originalWorker,
        date: targetDate,
        checkIn: selectedShift.checkIn,
        checkOut: selectedShift.checkOut,
        overrideBox: overrideBox,
      );
      await _saveOverrideWithCleanup(
        worker: selected,
        date: targetDate,
        checkIn: sourceShift.checkIn,
        checkOut: sourceShift.checkOut,
        overrideBox: overrideBox,
      );
    } else {
      await _saveOverrideWithCleanup(
        worker: originalWorker,
        date: targetDate,
        checkIn: null,
        checkOut: null,
        overrideBox: overrideBox,
      );
      await _saveOverrideWithCleanup(
        worker: selected,
        date: targetDate,
        checkIn: sourceShift.checkIn,
        checkOut: sourceShift.checkOut,
        overrideBox: overrideBox,
      );
    }

    await _checkStandingFlipRiskAfterScheduleChange();
    if (!mounted) return;

    final afterOverrides = overrideBox.toMap();
    final afterBMinutes =
        _workerWeeklyPureMinutes(selected, afterOverrides, _currentWeekStart);
    final crossedRisk = beforeBMinutes < 15 * 60 && afterBMinutes >= 15 * 60;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isSwap
              ? '${originalWorker.name} 님과 ${selected.name} 님의 근무를 맞교대했습니다.'
              : '${originalWorker.name} 님의 근무를 ${selected.name} 님에게 대타 배정했습니다.',
        ),
      ),
    );
    if (crossedRisk) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.orange.shade700,
          content: Text(
            '주휴수당 발생 주의: ${selected.name}의 이번 주 순수 근로가 ${PayrollCalculator.formatHoursAsKorean(afterBMinutes / 60.0)}입니다.',
          ),
        ),
      );
    }
  }

  Future<void> _checkStandingFlipRiskAfterScheduleChange() async {
    final workers = WorkerService.getAll()
        .where((w) => w.workerType != 'dispatch')
        .toList();
    if (workers.isEmpty) return;

    final storeId = workers
        .map((w) => w.storeId)
        .firstWhere((id) => id.trim().isNotEmpty, orElse: () => '');
    if (storeId.isEmpty) return;

    final storeSnap =
        await FirebaseFirestore.instance.collection('stores').doc(storeId).get();
    if (!storeSnap.exists) return;
    final storeData = storeSnap.data() ?? {};

    final settlementStartDay =
        (storeData['settlementStartDay'] as num?)?.toInt() ?? 1;
    final settlementEndDay =
        (storeData['settlementEndDay'] as num?)?.toInt() ?? 31;
    final storedIsFive = storeData['isFiveOrMore'] == true;

    final period = computeSettlementPeriod(
      now: AppClock.now(),
      settlementStartDay: settlementStartDay,
      settlementEndDay: settlementEndDay,
    );

    final overrides = Hive.box<ScheduleOverride>('schedule_overrides').toMap();
    final projectedAttendance = _projectedAttendanceFromSchedule(
      workers: workers,
      overrides: overrides,
      periodStart: period.start,
      periodEnd: period.end,
      storeId: storeId,
    );
    final projectedStanding = calculateStandingFromAttendances(
      attendances: projectedAttendance,
      periodStart: period.start,
      periodEnd: period.end,
      staffList: workers,
    );

    if (projectedStanding.isFiveOrMore == storedIsFive || !mounted) return;

    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('5인 이상 판정 변경 가능성'),
        content: Text(
          projectedStanding.isFiveOrMore
              ? '이번 근무표 수정으로 5인 미만 -> 5인 이상 판정으로 바뀔 가능성이 있습니다.\n가산수당/법정 기준을 확인하세요.'
              : '이번 근무표 수정으로 5인 이상 -> 5인 미만 판정으로 바뀔 가능성이 있습니다.\n급여 기준 반영 전 최종 판정을 확인하세요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  List<Attendance> _projectedAttendanceFromSchedule({
    required List<Worker> workers,
    required Map<dynamic, ScheduleOverride> overrides,
    required DateTime periodStart,
    required DateTime periodEnd,
    required String storeId,
  }) {
    final list = <Attendance>[];
    for (final worker in workers) {
      if (worker.workerType == 'dispatch') continue;
      final dayToTime = _parseWorkerSchedule(worker);
      for (var d = periodStart;
          !d.isAfter(periodEnd);
          d = d.add(const Duration(days: 1))) {
        final ymd = _toYmd(d);
        final key = '${worker.id}_$ymd';
        final o = overrides[key];
        final baseDay = d.weekday == DateTime.sunday ? 0 : d.weekday;
        final hasBaseShift = worker.workDays.contains(baseDay);
        final defaultIn = dayToTime[baseDay]?.start ?? worker.checkInTime;
        final defaultOut = dayToTime[baseDay]?.end ?? worker.checkOutTime;
        final checkIn = (o != null) ? o.checkIn : (hasBaseShift ? defaultIn : null);
        final checkOut = (o != null) ? o.checkOut : (hasBaseShift ? defaultOut : null);
        if (checkIn == null || checkOut == null) continue;

        final inDt = _ymdWithHm(d, checkIn);
        var outDt = _ymdWithHm(d, checkOut);
        if (!outDt.isAfter(inDt)) {
          outDt = outDt.add(const Duration(days: 1));
        }
        list.add(
          Attendance(
            id: 'proj_${worker.id}_$ymd',
            staffId: worker.id,
            storeId: storeId,
            clockIn: inDt,
            clockOut: outDt,
            type: AttendanceType.web,
          ),
        );
      }
    }
    return list;
  }

  DateTime _ymdWithHm(DateTime day, String hm) {
    final p = hm.split(':');
    final h = int.tryParse(p.first) ?? 0;
    final m = p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0;
    return DateTime(day.year, day.month, day.day, h, m);
  }

  int _weeklyCost(List<Worker> workers, Map<dynamic, ScheduleOverride> overrides) {
    var total = 0.0;
    for (final worker in workers) {
      if (worker.workerType == 'dispatch') continue;
      final dayToTime = _parseWorkerSchedule(worker);
      for (var i = 0; i < 7; i++) {
        final date = _currentWeekStart.add(Duration(days: i));
        final key = '${worker.id}_${_toYmd(date)}';
        final o = overrides[key];
        final baseDay = (i == 6) ? 0 : i + 1;
        final hasBaseShift = worker.workDays.contains(baseDay);
        final defaultIn = dayToTime[baseDay]?.start ?? worker.checkInTime;
        final defaultOut = dayToTime[baseDay]?.end ?? worker.checkOutTime;
        final checkIn = (o != null) ? o.checkIn : (hasBaseShift ? defaultIn : null);
        final checkOut = (o != null) ? o.checkOut : (hasBaseShift ? defaultOut : null);
        if (checkIn == null || checkOut == null) continue;
        final minutes = _minutesBetween(checkIn, checkOut);
        if (minutes <= 0) continue;
        final paidMinutes = worker.isPaidBreak ? minutes : (minutes - worker.breakMinutes).clamp(0, minutes.toDouble());
        total += (paidMinutes / 60.0) * worker.hourlyWage;
      }
    }
    return total.round();
  }

  int _weeklyPureMinutes(
    List<Worker> workers,
    Map<dynamic, ScheduleOverride> overrides,
    DateTime weekStart,
  ) {
    var total = 0;
    for (final worker in workers) {
      if (worker.workerType == 'dispatch') continue;
      final dayToTime = _parseWorkerSchedule(worker);
      for (var i = 0; i < 7; i++) {
        final date = weekStart.add(Duration(days: i));
        final key = '${worker.id}_${_toYmd(date)}';
        final o = overrides[key];
        final baseDay = (i == 6) ? 0 : i + 1;
        final hasBaseShift = worker.workDays.contains(baseDay);
        final defaultIn = dayToTime[baseDay]?.start ?? worker.checkInTime;
        final defaultOut = dayToTime[baseDay]?.end ?? worker.checkOutTime;
        final checkIn = (o != null) ? o.checkIn : (hasBaseShift ? defaultIn : null);
        final checkOut = (o != null) ? o.checkOut : (hasBaseShift ? defaultOut : null);
        if (checkIn == null || checkOut == null) continue;
        final minutes = _minutesBetween(checkIn, checkOut);
        if (minutes <= 0) continue;
        total += (minutes - worker.breakMinutes.toInt()).clamp(0, minutes);
      }
    }
    return total;
  }

  int _workerWeeklyPureMinutes(
    Worker worker,
    Map<dynamic, ScheduleOverride> overrides,
    DateTime weekStart,
  ) {
    var total = 0;
    final dayToTime = _parseWorkerSchedule(worker);
    for (var i = 0; i < 7; i++) {
      final date = weekStart.add(Duration(days: i));
      final key = '${worker.id}_${_toYmd(date)}';
      final o = overrides[key];
      final baseDay = (i == 6) ? 0 : i + 1;
      final hasBaseShift = worker.workDays.contains(baseDay);
      final defaultIn = dayToTime[baseDay]?.start ?? worker.checkInTime;
      final defaultOut = dayToTime[baseDay]?.end ?? worker.checkOutTime;
      final checkIn = (o != null) ? o.checkIn : (hasBaseShift ? defaultIn : null);
      final checkOut = (o != null) ? o.checkOut : (hasBaseShift ? defaultOut : null);
      if (checkIn == null || checkOut == null) continue;
      final minutes = _minutesBetween(checkIn, checkOut);
      if (minutes <= 0) continue;
      total += (minutes - worker.breakMinutes.toInt()).clamp(0, minutes);
    }
    return total;
  }

  ({double currentAvgHours, double baseAvgHours}) _fourWeekPureAverageHours(
    List<Worker> workers,
    Map<dynamic, ScheduleOverride> overrides,
  ) {
    var currentTotal = 0;
    var baseTotal = 0;
    for (var week = 0; week < 4; week++) {
      final start = _currentWeekStart.subtract(Duration(days: 7 * week));
      currentTotal += _weeklyPureMinutes(workers, overrides, start);
      baseTotal += _weeklyPureMinutes(workers, const {}, start);
    }
    return (
      currentAvgHours: (currentTotal / 4) / 60.0,
      baseAvgHours: (baseTotal / 4) / 60.0,
    );
  }

  int _minutesBetween(String s, String e) {
    final sp = s.split(':');
    final ep = e.split(':');
    if (sp.length != 2 || ep.length != 2) return 0;
    final sm = (int.tryParse(sp[0]) ?? 0) * 60 + (int.tryParse(sp[1]) ?? 0);
    final em = (int.tryParse(ep[0]) ?? 0) * 60 + (int.tryParse(ep[1]) ?? 0);
    return em - sm;
  }

  bool _hasNightWorkAfter22(String checkIn, String checkOut) {
    final sp = checkIn.split(':');
    final ep = checkOut.split(':');
    if (sp.length != 2 || ep.length != 2) return false;
    var start = (int.tryParse(sp[0]) ?? 0) * 60 + (int.tryParse(sp[1]) ?? 0);
    var end = (int.tryParse(ep[0]) ?? 0) * 60 + (int.tryParse(ep[1]) ?? 0);
    if (end <= start) end += 24 * 60; // overnight
    const nightStart = 22 * 60;
    const dayEnd = 24 * 60;
    return start < dayEnd && end > nightStart;
  }

  String _money(int value) =>
      value.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');

  @override
  Widget build(BuildContext context) {
    final overrideBox = Hive.box<ScheduleOverride>('schedule_overrides');
    return ValueListenableBuilder<Box<Worker>>(
      valueListenable: Hive.box<Worker>('workers').listenable(),
      builder: (context, workersBox, _) {
        return ValueListenableBuilder<Box<ScheduleOverride>>(
          valueListenable: overrideBox.listenable(),
          builder: (context, overridesBox, nestedChild) {
            final workers = WorkerService.getAll().where((w) => w.workerType != 'dispatch').toList();
            final overrides = overrideBox.toMap();
            final storeId = workers
                .map((w) => w.storeId)
                .firstWhere((id) => id.trim().isNotEmpty, orElse: () => '');
            final weeklyCost = _weeklyCost(workers, overrides);
            final avg4w = _fourWeekPureAverageHours(workers, overrides);
            final avgDelta = avg4w.currentAvgHours - avg4w.baseAvgHours;
            final workerWeeklyPureHours = <String, double>{
              for (final w in workers)
                w.id: _workerWeeklyPureMinutes(w, overrides, _currentWeekStart) / 60.0,
            };
            final workerNightRiskByDay = <String, Set<int>>{};
            for (final w in workers) {
              final nightRiskDays = <int>{};
              final dayToTime = _parseWorkerSchedule(w);
              for (var i = 0; i < 7; i++) {
                final date = _currentWeekStart.add(Duration(days: i));
                final key = '${w.id}_${_toYmd(date)}';
                final o = overrides[key];
                final baseDay = (i == 6) ? 0 : i + 1;
                final hasBaseShift = w.workDays.contains(baseDay);
                final defaultIn = dayToTime[baseDay]?.start ?? w.checkInTime;
                final defaultOut = dayToTime[baseDay]?.end ?? w.checkOutTime;
                final checkIn = (o != null) ? o.checkIn : (hasBaseShift ? defaultIn : null);
                final checkOut = (o != null) ? o.checkOut : (hasBaseShift ? defaultOut : null);
                final hasShift = checkIn != null && checkOut != null;
                if (hasShift && _hasNightWorkAfter22(checkIn, checkOut)) {
                  nightRiskDays.add(i);
                }
              }
              workerNightRiskByDay[w.id] = nightRiskDays;
            }

            return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: storeId.isEmpty
                  ? null
                  : FirebaseFirestore.instance
                      .collection('stores')
                      .doc(storeId)
                      .snapshots(),
              builder: (context, storeSnap) {
                final storeData = storeSnap.data?.data() ?? const {};
                final isFiveOrMoreStore =
                    (storeData['isFiveOrMore'] as bool?) ?? false;
                return Scaffold(
          backgroundColor: const Color(0xFFF2F2F7),
          appBar: AppBar(
            backgroundColor: const Color(0xFF1a1a2e),
            title: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '근무시간표',
                  style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.6)),
                ),
                Text(
                  _isSameDay(_currentWeekStart, _getMonday(AppClock.now()))
                      ? '이번 주'
                      : '${_currentWeekStart.month}/${_currentWeekStart.day} ~ ${_currentWeekStart.add(const Duration(days: 6)).month}/${_currentWeekStart.add(const Duration(days: 6)).day}',
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w500),
                ),
              ],
            ),
            actions: [
              IconButton(icon: const Icon(Icons.chevron_left, color: Colors.white), onPressed: _previousWeek),
              IconButton(icon: const Icon(Icons.chevron_right, color: Colors.white), onPressed: _nextWeek),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(22),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _pageDot(active: widget.pageIndex == 0),
                    const SizedBox(width: 4),
                    _pageDot(active: widget.pageIndex == 1),
                    const SizedBox(width: 4),
                    _pageDot(active: widget.pageIndex == 2),
                  ],
                ),
              ),
            ),
          ),
          body: Column(
            children: [
              Container(
                width: double.infinity,
                color: const Color(0xFF1a1a2e),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Text(
                  '이번 주 예상 인건비 ${_money(weeklyCost)}원',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                ),
              ),
              Container(
                width: double.infinity,
                color: const Color(0xFFEAF2FF),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Text(
                  '4주 평균 순수근로시간: ${PayrollCalculator.formatHoursAsKorean(avg4w.currentAvgHours)} '
                  '(기준 대비 ${avgDelta >= 0 ? '+' : ''}${PayrollCalculator.formatHoursAsKorean(avgDelta)})',
                  style: const TextStyle(
                    color: Color(0xFF1A4C9A),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                color: const Color(0xFF1a1a2e),
                child: Row(
                  children: [
                    Container(
                      width: 70,
                      padding: const EdgeInsets.all(10),
                      child: const Text('직원', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    ),
                    ...List.generate(7, (i) {
                      final day = _currentWeekStart.add(Duration(days: i));
                      final isToday = _isSameDay(day, AppClock.now());
                      return Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: isToday ? const Color(0xFF1a6ebd) : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            children: [
                              Text(const ['월', '화', '수', '목', '금', '토', '일'][i],
                                  style: const TextStyle(color: Colors.white, fontSize: 12)),
                              Text('${day.day}',
                                  style: TextStyle(
                                    color: isToday ? Colors.white : Colors.white70,
                                    fontSize: 11,
                                  )),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: workers.length,
                  itemBuilder: (context, idx) {
                    final worker = workers[idx];
                    final pureHours = workerWeeklyPureHours[worker.id] ?? 0.0;
                    final isRisk = pureHours >= 15.0;
                    final parsedSchedule = _parseWorkerSchedule(worker);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 2),
                      color: Colors.white,
                      child: Row(
                        children: [
                          Container(
                            width: 70,
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(worker.name,
                                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                                    ),
                                    Icon(
                                      isRisk
                                          ? Icons.warning_amber_rounded
                                          : Icons.check_circle,
                                      size: 14,
                                      color: isRisk
                                          ? Colors.redAccent
                                          : Colors.green,
                                    ),
                                  ],
                                ),
                                Text(
                                  '순수 ${PayrollCalculator.formatHoursAsKorean(pureHours)}',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: isRisk
                                        ? Colors.redAccent
                                        : Colors.green.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ...List.generate(7, (i) {
                            final date = _currentWeekStart.add(Duration(days: i));
                            final key = '${worker.id}_${_toYmd(date)}';
                            final override = overrides[key];
                            final baseDay = (i == 6) ? 0 : i + 1;
                            final hasBaseShift = worker.workDays.contains(baseDay);
                            
                            final defaultIn = parsedSchedule[baseDay]?.start ?? worker.checkInTime;
                            final defaultOut = parsedSchedule[baseDay]?.end ?? worker.checkOutTime;

                            final isOverrideChanged = override != null &&
                                ((override.checkIn == null && override.checkOut == null && hasBaseShift) ||
                                    (override.checkIn != null &&
                                        override.checkOut != null &&
                                        (!hasBaseShift ||
                                            override.checkIn!.substring(0, 5) !=
                                                defaultIn.substring(0, 5) ||
                                            override.checkOut!.substring(0, 5) !=
                                                defaultOut.substring(0, 5))));
                            final isOverriddenShift = isOverrideChanged;
                            final hasShift = override != null
                                ? (override.checkIn != null && override.checkOut != null)
                                : hasBaseShift;
                            final displayIn = override?.checkIn ?? defaultIn;
                            final displayOut = override?.checkOut ?? defaultOut;
                            final isContractShift = hasShift &&
                                ((override == null && hasBaseShift) ||
                                    (override != null &&
                                        hasBaseShift &&
                                        override.checkIn != null &&
                                        override.checkOut != null &&
                                        override.checkIn!.substring(0, 5) ==
                                            defaultIn.substring(0, 5) &&
                                        override.checkOut!.substring(0, 5) ==
                                            defaultOut.substring(0, 5)));
                            final isExtraOrSubstituteShift =
                                hasShift && !isContractShift;
                            final hasNightRisk = isFiveOrMoreStore &&
                                (workerNightRiskByDay[worker.id]?.contains(i) ??
                                    false);
                            final weekend = i >= 5;
                            final isToday = _isSameDay(date, AppClock.now());
                            final isAnnualLeaveCell = override?.isAnnualLeave ?? false;
                            return Expanded(
                              child: GestureDetector(
                                onTap: () => _onCellTap(worker, i),
                                child: Container(
                                  height: 52,
                                  margin: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(
                                    color: isAnnualLeaveCell
                                        ? const Color(0xFFE3F2FD)
                                        : hasShift
                                        ? (isOverriddenShift
                                            ? const Color(0xFF5E35B1)
                                            : (hasNightRisk
                                                ? const Color(0xFFB71C1C)
                                                : isExtraOrSubstituteShift
                                                    ? const Color(0xFFFFF3E0)
                                                    : const Color(0xFFE8F5E9)))
                                        : (weekend ? const Color(0xFFFAFAFA) : const Color(0xFFF8F8F8)),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: isToday
                                          ? const Color(0xFF1a6ebd)
                                          : isAnnualLeaveCell
                                              ? const Color(0xFF1565C0)
                                          : hasShift
                                              ? (isOverriddenShift
                                                  ? const Color(0xFF4527A0)
                                                  : (hasNightRisk
                                                      ? const Color(0xFF7F0000)
                                                      : isExtraOrSubstituteShift
                                                          ? const Color(0xFFEF6C00)
                                                          : const Color(0xFF2E7D32)))
                                              : const Color(0xFFEEEEEE),
                                      width: isToday ? 1.2 : 0.5,
                                    ),
                                  ),
                                  child: isAnnualLeaveCell
                                      ? Center(
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              const Icon(Icons.beach_access_rounded, size: 16, color: Color(0xFF1565C0)),
                                              const Text('연차', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFF1565C0))),
                                            ],
                                          ),
                                        )
                                      : hasShift
                                      ? Stack(
                                          children: [
                                            Container(
                                              alignment: Alignment.center,
                                              child: Column(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  FittedBox(
                                                    fit: BoxFit.scaleDown,
                                                    child: Text(displayIn.substring(0, 5),
                                                        maxLines: 1,
                                                        softWrap: false,
                                                        style: TextStyle(
                                                            fontSize: 10,
                                                            color: isOverriddenShift
                                                                ? Colors.white
                                                                : hasNightRisk
                                                                ? Colors.white
                                                                    : isExtraOrSubstituteShift
                                                                        ? const Color(0xFFEF6C00)
                                                                        : const Color(0xFF2E7D32),
                                                            fontWeight: FontWeight.w500)),
                                                  ),
                                                  FittedBox(
                                                    fit: BoxFit.scaleDown,
                                                    child: Text(displayOut.substring(0, 5),
                                                        maxLines: 1,
                                                        softWrap: false,
                                                        style: TextStyle(
                                                          fontSize: 10,
                                                          color: isOverriddenShift
                                                              ? Colors.white
                                                              : hasNightRisk
                                                              ? Colors.white
                                                                  : isExtraOrSubstituteShift
                                                                      ? const Color(0xFFEF6C00)
                                                                      : const Color(0xFF2E7D32),
                                                        )),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            if (hasNightRisk)
                                              const Positioned(
                                                left: 3,
                                                top: 2,
                                                child: Icon(
                                                  Icons.nights_stay_rounded,
                                                  size: 10,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            if (override != null)
                                              Positioned(
                                                right: 3,
                                                top: 2,
                                                child: Text('●',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      color: isOverriddenShift
                                                          ? Colors.white
                                                          : hasNightRisk
                                                          ? Colors.white
                                                              : isExtraOrSubstituteShift
                                                                  ? const Color(0xFFEF6C00)
                                                                  : const Color(0xFF2E7D32),
                                                    )),
                                              ),
                                            if (isOverriddenShift && hasShift)
                                              Positioned(
                                                right: 3,
                                                bottom: 2,
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(
                                                      horizontal: 3, vertical: 1),
                                                  decoration: BoxDecoration(
                                                    color: Colors.white.withValues(alpha: 0.18),
                                                    borderRadius: BorderRadius.circular(3),
                                                  ),
                                                  child: const Text(
                                                    '대체',
                                                    style: TextStyle(
                                                      fontSize: 8,
                                                      color: Colors.white,
                                                      fontWeight: FontWeight.w700,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                          ],
                                        )
                                      : const Icon(Icons.add, size: 14, color: Color(0xFFDDDDDD)),
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          );
              },
            );
          },
        );
      },
    );
  }
}

class _ScheduleEditSheet extends StatefulWidget {
  const _ScheduleEditSheet({
    required this.workerName,
    required this.dayLabel,
    required this.initialCheckIn,
    required this.initialCheckOut,
    required this.onSave,
    required this.onDelete,
  });

  final String workerName;
  final String dayLabel;
  final String initialCheckIn;
  final String initialCheckOut;
  final Future<void> Function(String checkIn, String checkOut) onSave;
  final Future<void> Function() onDelete;

  @override
  State<_ScheduleEditSheet> createState() => _ScheduleEditSheetState();
}

class _ScheduleEditSheetState extends State<_ScheduleEditSheet> {
  late TimeOfDay _checkIn;
  late TimeOfDay _checkOut;

  @override
  void initState() {
    super.initState();
    _checkIn = _parseTime(widget.initialCheckIn);
    _checkOut = _parseTime(widget.initialCheckOut);
  }

  TimeOfDay _parseTime(String hhmm) {
    final p = hhmm.split(':');
    return TimeOfDay(hour: int.tryParse(p.first) ?? 9, minute: int.tryParse(p.last) ?? 0);
  }

  String _fmt(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Widget _buildTimePicker(String label, TimeOfDay time, ValueChanged<TimeOfDay> onChanged) {
    return Row(
      children: [
        const SizedBox(width: 16),
        SizedBox(
          width: 40,
          child: Text(label, style: const TextStyle(fontSize: 14, color: Color(0xFF888888))),
        ),
        Expanded(
          child: GestureDetector(
            onTap: () async {
              final picked = await showTimePicker(context: context, initialTime: time);
              if (picked != null) onChanged(picked);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.access_time, color: Color(0xFF1a6ebd), size: 18),
                  const SizedBox(width: 8),
                  Text(
                    _fmt(time),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Color(0xFF1a1a2e)),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFDDDDDD),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Text(
            '${widget.workerName} · ${widget.dayLabel}요일',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 20),
          _buildTimePicker('출근', _checkIn, (t) => setState(() => _checkIn = t)),
          const SizedBox(height: 16),
          _buildTimePicker('퇴근', _checkOut, (t) => setState(() => _checkOut = t)),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      await widget.onDelete();
                      if (context.mounted) Navigator.pop(context);
                    },
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFE24B4A)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('근무 없음', style: TextStyle(color: Color(0xFFE24B4A), fontSize: 14)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: () async {
                      await widget.onSave(_fmt(_checkIn), _fmt(_checkOut));
                      if (context.mounted) Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1a1a2e),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 0,
                    ),
                    child: const Text(
                      '저장',
                      style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
