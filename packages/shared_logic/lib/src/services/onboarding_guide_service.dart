import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// 온보딩 단계 정의
enum OnboardingStep {
  /// 1단계: 로그인 화면 - 역할 선택 안내
  login,

  /// 2단계: 사업장 등록 안내
  storeSetup,

  /// 3단계: 첫 직원 등록 안내
  firstStaff,

  /// 4단계: 초대 코드 발송 안내
  sendInvite,

  /// 5단계: 근로계약서 작성 안내
  createContract,

  /// 6단계: 대시보드 리포트 확인 안내
  checkDashboard,

  /// 모든 온보딩 완료
  completed,
}

/// 온보딩 가이드 상태 관리 서비스.
///
/// SharedPreferences에 현재 단계를 저장하고,
/// Firestore 데이터를 기반으로 단계 완료 여부를 자동 감지합니다.
class OnboardingGuideService extends ChangeNotifier {
  OnboardingGuideService._();
  static final OnboardingGuideService instance = OnboardingGuideService._();

  static const String _prefKey = 'onboarding_current_step';
  static const String _prefDismissedKey = 'onboarding_dismissed';

  OnboardingStep _currentStep = OnboardingStep.completed;
  bool _dismissed = false;
  bool _initialized = false;

  OnboardingStep get currentStep => _currentStep;
  bool get dismissed => _dismissed;
  bool get isActive =>
      _initialized && !_dismissed && _currentStep != OnboardingStep.completed;

  /// 초기화: SharedPreferences에서 상태 로드
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final stepIndex = prefs.getInt(_prefKey);
    _dismissed = prefs.getBool(_prefDismissedKey) ?? false;

    if (stepIndex != null && stepIndex < OnboardingStep.values.length) {
      _currentStep = OnboardingStep.values[stepIndex];
    } else {
      // 처음 실행: login 단계부터 시작
      _currentStep = OnboardingStep.login;
    }

    _initialized = true;
    notifyListeners();
  }

  /// Firestore 데이터를 기반으로 현재 단계를 자동 감지하여 갱신.
  /// 이미 완료된 단계는 자동으로 건너뜁니다.
  Future<void> syncWithFirestore({
    required String? uid,
    required String? storeId,
  }) async {
    if (!_initialized || _dismissed) return;
    if (_currentStep == OnboardingStep.completed) return;

    final db = FirebaseFirestore.instance;

    // 1) 사업장 등록 여부
    if (storeId != null && storeId.isNotEmpty) {
      if (_currentStep.index <= OnboardingStep.storeSetup.index) {
        _updateStep(OnboardingStep.firstStaff);
      }

      // 2) 직원 존재 여부
      final workersSnap = await db
          .collection('stores')
          .doc(storeId)
          .collection('workers')
          .limit(1)
          .get();

      if (workersSnap.docs.isNotEmpty) {
        if (_currentStep.index <= OnboardingStep.sendInvite.index) {
          _updateStep(OnboardingStep.createContract);
        }

        // 4) 계약서 작성 여부
        final contractsSnap = await db
            .collection('stores')
            .doc(storeId)
            .collection('documents')
            .where('type', isEqualTo: 'labor_contract')
            .limit(1)
            .get();

        if (contractsSnap.docs.isNotEmpty &&
            _currentStep.index <= OnboardingStep.createContract.index) {
          _updateStep(OnboardingStep.checkDashboard);
        }
      }
    }
  }

  /// 특정 단계 완료 처리 → 다음 단계로 이동.
  /// 현재 단계가 주어진 단계보다 앞서있거나 같으면 다음 단계로 이동합니다.
  /// (예: 현재 login인데 storeSetup 완료 호출 → firstStaff로 이동)
  Future<void> completeStep(OnboardingStep step) async {
    // 이미 이 단계를 지났으면 무시
    if (_currentStep.index > step.index) return;

    final nextIndex = step.index + 1;
    if (nextIndex < OnboardingStep.values.length) {
      _updateStep(OnboardingStep.values[nextIndex]);
    }
  }

  /// 수동으로 특정 단계 설정
  Future<void> setStep(OnboardingStep step) async {
    _updateStep(step);
  }

  /// 가이드 스킵/종료
  Future<void> dismiss() async {
    _dismissed = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefDismissedKey, true);
    notifyListeners();
  }

  /// "처음부터 다시 안내받기" — 설정에서 호출
  Future<void> restart() async {
    _dismissed = false;
    _currentStep = OnboardingStep.login;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefDismissedKey, false);
    await prefs.setInt(_prefKey, OnboardingStep.login.index);
    notifyListeners();
  }

  /// 모든 가이드 상태 초기화 (로그아웃, 탈퇴 시 호출)
  Future<void> reset() async {
    _dismissed = false;
    _currentStep = OnboardingStep.login;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefDismissedKey);
    await prefs.remove(_prefKey);
    notifyListeners();
  }

  Future<void> _updateStep(OnboardingStep step) async {
    if (_currentStep == step) return;
    _currentStep = step;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefKey, step.index);
    notifyListeners();
  }

  /// 체험모드 여부에 따라 다른 메시지 반환
  static OnboardingMessage getMessage(
    OnboardingStep step, {
    bool isDemo = false,
  }) {
    if (isDemo) return _demoMessages[step] ?? _defaultMessages[step]!;
    return _defaultMessages[step]!;
  }

  static const Map<OnboardingStep, OnboardingMessage> _defaultMessages = {
    OnboardingStep.login: OnboardingMessage(
      title: '사장님이세요?',
      body: '여기를 눌러 매장을 등록하세요! 👆',
      emoji: '👋',
    ),
    OnboardingStep.storeSetup: OnboardingMessage(
      title: '매장을 등록해 볼까요?',
      body: '설정 탭에서 매장 정보를 입력하면\n직원 관리를 시작할 수 있어요! 👆',
      emoji: '🏪',
    ),
    OnboardingStep.firstStaff: OnboardingMessage(
      title: '첫 직원을 등록해볼까요?',
      body: '화면 오른쪽 아래의 동그란 버튼을 누르면\n직원 등록 화면으로 이동합니다!',
      emoji: '👤',
    ),
    OnboardingStep.sendInvite: OnboardingMessage(
      title: '직원에게 초대 코드를 보내세요!',
      body: '카카오톡으로 초대 코드를 전송하면\n직원이 앱에서 바로 접속할 수 있어요 📱',
      emoji: '💌',
    ),
    OnboardingStep.createContract: OnboardingMessage(
      title: '마지막 단계! 계약서 작성',
      body: '아래 노무서류 탭을 눌러서\n근로계약서를 작성해 주세요!',
      emoji: '📄',
    ),
    OnboardingStep.checkDashboard: OnboardingMessage(
      title: '수고하셨습니다! 🎉',
      body: '이곳 대시보드에서 매월 급여 리포트와\n직원들의 출퇴근 현황을 한눈에 확인하세요!',
      emoji: '📊',
    ),
    OnboardingStep.completed: OnboardingMessage(
      title: '설정 완료!',
      body: '모든 초기 설정이 끝났습니다 🎉',
      emoji: '🎉',
    ),
  };

  static const Map<OnboardingStep, OnboardingMessage> _demoMessages = {
    OnboardingStep.firstStaff: OnboardingMessage(
      title: '직원 목록을 확인해 보세요',
      body: '가상으로 등록된 직원 정보를\n눌러서 구경해 보세요! 👀',
      emoji: '👀',
    ),
    OnboardingStep.createContract: OnboardingMessage(
      title: '계약서를 살펴보세요',
      body: '이미 작성된 계약서를 눌러서\n어떻게 보이는지 구경해 보세요! 📋',
      emoji: '📋',
    ),
  };
}

/// 온보딩 말풍선에 표시되는 메시지 데이터
class OnboardingMessage {
  final String title;
  final String body;
  final String emoji;

  const OnboardingMessage({
    required this.title,
    required this.body,
    required this.emoji,
  });
}
