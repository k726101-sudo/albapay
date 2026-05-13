import 'dart:convert';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kDebugMode, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:shared_logic/shared_logic.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart'
    show GoogleSignInException, GoogleSignInExceptionCode;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/login_brand_buttons.dart';
import 'alba/alba_login_screen.dart';

enum LoginStep { selectRole, loginManager }


class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _emailLinkController = TextEditingController();
  final _authService = AuthService();
  LoginStep _step = LoginStep.selectRole;
  bool _isLoading = false;
  DateTime? _emailLinkLastSentAt;
  static const Duration _emailLinkCooldown = Duration(seconds: 120);
  /// 디버그 「사장님 로그인」 연타로 Firebase `too-many-requests` 나는 것 방지
  DateTime? _lastDebugBossAttempt;
  static const Duration _debugBossMinInterval = Duration(seconds: 30);
  bool _showManualLinkPaste = false;
  bool _isConsented = false;

  bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;

  Future<void> _handleEmailLinkSignIn() async {
    if (_emailController.text.isEmpty) return;

    // Simple client-side cooldown to avoid Firebase rate limiting
    final now = AppClock.now();
    if (_emailLinkLastSentAt != null &&
        now.difference(_emailLinkLastSentAt!) < _emailLinkCooldown) {
      final remaining =
          _emailLinkCooldown - now.difference(_emailLinkLastSentAt!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '잠시만 기다려주세요. ${remaining.inSeconds}초 후 다시 시도할 수 있어요.',
            ),
          ),
        );
      }
      return;
    }

    setState(() => _isLoading = true);
    
    // ActionCodeSettings for Email Link
    final actionCodeSettings = ActionCodeSettings(
      // Dynamic Links 종료 대응: firebaseapp.com 도메인을 사용
      url: 'https://standard-albapay.web.app/login',
      handleCodeInApp: true,
      androidPackageName: 'com.standard.albapay',
      androidInstallApp: true,
      androidMinimumVersion: '1',
      iOSBundleId: 'com.standard.albapay',
    );

    try {
      // 링크 클릭 시 자동 로그인에 필요 (emailLink에는 email이 함께 필요)
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('emailForSignIn', _emailController.text.trim());

      await _authService.sendSignInLinkToEmail(_emailController.text, actionCodeSettings);
      _emailLinkLastSentAt = AppClock.now();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('로그인 링크가 이메일로 전송되었습니다. 이메일을 확인해주세요.')),
        );
      }
    } on FirebaseAuthException catch (e) {
      // Firebase 오류 코드는 문자열로 분기합니다.
      final String code = e.code;
      final String msg;
      if (code == 'too-many-requests') {
        msg =
            '요청이 너무 많아 잠시 차단되었습니다. 10~30분 후 다시 시도해 주세요.';
      } else if (code == 'invalid-email') {
        msg = '이메일 형식을 확인해 주세요.';
      } else {
        msg = '오류 발생: ${e.message ?? code}';
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('오류 발생: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleEmailLinkComplete() async {
    final email = _emailController.text.trim();
    final link = _emailLinkController.text.trim();
    if (email.isEmpty || link.isEmpty) return;

    if (!_authService.isSignInWithEmailLink(link)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('올바른 이메일 로그인 링크가 아닙니다. 메일에 있는 링크를 그대로 붙여넣어 주세요.')),
        );
      }
      return;
    }

    setState(() => _isLoading = true);
    final user = await _authService.signInWithEmailLink(email, link);
    _handleAuthResult(user);
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() => _isLoading = true);
    try {
      final user = await _authService.signInWithGoogle();
      _handleAuthResult(user);
    } on GoogleSignInException catch (e) {
      setState(() => _isLoading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_messageForGoogleSignInException(e)),
          duration: const Duration(seconds: 6),
        ),
      );
    } on FirebaseAuthException catch (e) {
      setState(() => _isLoading = false);
      if (!mounted) return;
      if (e.code == 'too-many-requests') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '요청이 너무 많아 Firebase에서 잠시 막았습니다. 10~60분 뒤에 다시 시도하거나 다른 네트워크를 써 보세요.',
            ),
          ),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_messageForFirebaseGoogleAuth(e)),
          duration: const Duration(seconds: 6),
        ),
      );
    } catch (e, st) {
      setState(() => _isLoading = false);
      if (!mounted) return;
      debugPrint('Google sign-in unexpected: $e\n$st');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Google 로그인 실패: $e'),
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  /// Google 플러그인 예외 — 사용자 취소·설정 오류 등 구분
  String _messageForGoogleSignInException(GoogleSignInException e) {
    final detail = (e.description != null && e.description!.trim().isNotEmpty)
        ? ' (${e.description})'
        : '';
    switch (e.code) {
      case GoogleSignInExceptionCode.canceled:
        return 'Google 로그인을 취소했습니다.';
      case GoogleSignInExceptionCode.interrupted:
        return 'Google 로그인이 중단되었습니다. 다시 시도해 주세요.$detail';
      case GoogleSignInExceptionCode.clientConfigurationError:
      case GoogleSignInExceptionCode.providerConfigurationError:
        return 'Google 로그인 앱 설정 오류입니다. Firebase 콘솔에 디버그용 SHA-1을 등록했는지, '
            '패키지명이 com.standard.albapay 인지 확인하세요.$detail';
      case GoogleSignInExceptionCode.uiUnavailable:
        return '지금은 Google 로그인 화면을 띄울 수 없습니다. 앱을 다시 켠 뒤 시도해 주세요.$detail';
      case GoogleSignInExceptionCode.userMismatch:
        return '이미 다른 Google 계정으로 로그인된 상태입니다. 기기 설정에서 계정을 확인해 주세요.$detail';
      case GoogleSignInExceptionCode.unknownError:
        return 'Google 로그인 오류(unknown).$detail';
    }
  }

  /// Firebase Auth 단계 오류 (토큰 교환 등)
  String _messageForFirebaseGoogleAuth(FirebaseAuthException e) {
    final tail = e.message != null && e.message!.trim().isNotEmpty
        ? ' — ${e.message}'
        : '';
    switch (e.code) {
      case 'invalid-credential':
        return 'Google 토큰이 Firebase에서 거부되었습니다(invalid-credential). '
            'Android: Firebase에 SHA-1 등록, Authentication에서 Google 로그인 사용, '
            '웹 클라이언트 ID(serverClientId)가 이 프로젝트와 일치하는지 확인하세요.$tail';
      case 'account-exists-with-different-credential':
        return '같은 이메일로 다른 로그인 방식으로 가입된 계정이 있습니다. '
            '기존에 쓰던 방식(이메일 링크 등)으로 로그인한 뒤 연동하거나, Firebase 콘솔에서 계정을 확인하세요.$tail';
      case 'network-request-failed':
        return '네트워크 오류로 Google 로그인에 실패했습니다.$tail';
      default:
        return 'Google 로그인 실패: ${e.code}$tail';
    }
  }

  Future<void> _handleAppleSignIn() async {
    setState(() => _isLoading = true);
    try {
      // iOS: 네이티브 / Android: CLIENT_ID·REDIRECT_URL — [AppleAuthConfig] + --dart-define
      final user = await _authService.signInWithApple();
      _handleAuthResult(user);
    } on FirebaseAuthException catch (e) {
      setState(() => _isLoading = false);
      if (!mounted) return;
      if (e.code == 'too-many-requests') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '요청이 너무 많아 Firebase에서 잠시 막았습니다. 10~60분 뒤에 다시 시도하거나 다른 네트워크를 써 보세요.',
            ),
          ),
        );
        return;
      }
      if (e.code == 'apple-android-config') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.message ??
                  'Android Apple 설정: CLIENT_ID·APPLE_ANDROID_BRIDGE_URL(Cloud Function)을 확인하세요.',
            ),
          ),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Apple 로그인 실패: ${e.code} ${e.message ?? ''}')),
      );
    } on SignInWithAppleException catch (e) {
      setState(() => _isLoading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_appleSignInUserMessage(e))),
      );
    } catch (e) {
      setState(() => _isLoading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Apple 로그인 실패: $e')),
      );
    }
  }

  /// Apple 웹 탭에서 `invalid_client` 등이 올 때 안내
  String _appleSignInUserMessage(SignInWithAppleException e) {
    final buf = StringBuffer();
    if (e is SignInWithAppleAuthorizationException) {
      buf.write(e.message);
    } else if (e is SignInWithAppleNotSupportedException) {
      buf.write(e.message);
    } else if (e is UnknownSignInWithAppleException) {
      buf.write('${e.message ?? ''} ${e.details ?? ''}');
    } else {
      buf.write(e.toString());
    }
    final t = buf.toString().toLowerCase();
    if (t.contains('invalid_client')) {
      return 'Apple invalid_client: CLIENT_ID는 반드시 Apple의 Services ID여야 합니다. '
          'iOS 번들 ID(예: com.standard.albapay)를 쓰면 안 됩니다. '
          'Apple Developer → Services ID → Return URL이 '
          'https://(프로젝트).firebaseapp.com/__/auth/handler 와 완전히 같은지 확인하세요.';
    }
    return 'Apple 로그인 실패: ${buf.toString().trim()}';
  }

  Future<void> _startExperienceMode() async {
    // 체험모드는 익명 로그인(Anonymous Auth)을 사용하며
    // 실제 개인정보를 수집하지 않으므로 약관 동의를 요구하지 않습니다.
    setState(() => _isLoading = true);
    try {
      // 1. 익명 로그인 (체험용 일회성 계정)
      final cred = await FirebaseAuth.instance.signInAnonymously();
      final uid = cred.user!.uid;
      final storeId = 'demo_$uid'; // 혼선 방지를 위해 UID를 매장 ID로 사용

      final db = FirebaseFirestore.instance;

      // 2. 가상 유저 및 매장 할당 (이전 세션의 에러 상태도 클리어)
      await db.collection('users').doc(uid).set({
        'storeId': storeId,
        'name': '체험 사장님',
        'isDemo': true,
        'isLoadingDemo': true, // 데이터 세팅 완료 전까지 렌더링 블락
        'demoError': '', // 이전 에러 클리어
      }, SetOptions(merge: true));

      await db.collection('stores').doc(storeId).set({
        'name': '알바급여정석 체험 매장',
        'ownerId': uid,
        'id': storeId,
        'isDemo': true,
        'isRegistered': true, // 사업자 정보 등록됨 표시 (UI 필터 통과용)
        'sizeMode': 'auto', 
        'settlementStartDay': 1, 
        'settlementEndDay': 31, 
        'minimumHourlyWage': 10320, 
        'createdAt': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));

      // 3. 가상의 직원 8명 생성 (교묘한 근무표로 상시평균 5인 미만이나 예외 조항으로 5인 이상 판정 유도)
      // 월,화,수,목(1,2,3,4)은 5명 근무 / 금(5),토(6),일(0)은 1명씩 근무
      // 총 23명/주 -> 평균 3.28명. 평균은 5인 미만이지만, 영업일(7일) 중 4일이 5인 이상이므로 과반수(1/2) 충족하여 5인 사업장 적용.
      final dummyWorkers = [
        {'id': 'worker_a', 'name': '가상 김점장', 'wage': 0, 'hours': 8, 'phone': '01011112222', 'isPaidBreak': false, 'workDays': [1, 2, 3, 4, 5], 'in': '09:00', 'out': '18:00', 'code': 'AAAAAA', 'wageType': 'monthly', 'targetSalary': 2500000, 'usedAnnualLeave': 0.0},  // ★ 연차 미사용 → 사용촉진 대상
        {'id': 'worker_b', 'name': '가상 이주간', 'wage': 10500, 'hours': 7, 'phone': '01033334444', 'isPaidBreak': true, 'workDays': [1, 2, 3, 4], 'in': '10:00', 'out': '18:00', 'code': 'BBBBBB', 'usedAnnualLeave': 3.0},   // 일부 사용
        {'id': 'worker_c', 'name': '가상 박오전', 'wage': 12000, 'hours': 6, 'phone': '01055556666', 'isPaidBreak': false, 'workDays': [1, 2, 3, 4], 'in': '06:00', 'out': '13:00', 'code': 'CCCCCC', 'usedAnnualLeave': 8.0},  // 절반 사용
        {'id': 'worker_d', 'name': '가상 최오후', 'wage': 10320, 'hours': 6, 'phone': '01077778888', 'isPaidBreak': false, 'workDays': [1, 2, 3, 4], 'in': '14:00', 'out': '21:00', 'code': 'DDDDDD', 'usedAnnualLeave': 2.0},
        {'id': 'worker_e', 'name': '가상 강야간', 'wage': 10320, 'hours': 7, 'phone': '01088889999', 'isPaidBreak': false, 'workDays': [1, 2, 3, 4], 'in': '22:00', 'out': '06:00', 'code': 'EEEEEE', 'usedAnnualLeave': 1.0},
        {'id': 'worker_f', 'name': '가상 정금욜', 'wage': 10320, 'hours': 8, 'phone': '01012345678', 'isPaidBreak': false, 'workDays': [5], 'in': '12:00', 'out': '21:00', 'code': 'FFFFFF', 'usedAnnualLeave': 0.0},           // ★ 미사용 → 촉진 대상
        {'id': 'worker_g', 'name': '가상 조토욜', 'wage': 11000, 'hours': 8, 'phone': '01098765432', 'isPaidBreak': false, 'workDays': [6], 'in': '12:00', 'out': '21:00', 'code': 'GGGGGG', 'usedAnnualLeave': 0.0},
        {'id': 'worker_h', 'name': '가상 윤일욜', 'wage': 10320, 'hours': 8, 'phone': '01055553333', 'isPaidBreak': false, 'workDays': [0], 'in': '12:00', 'out': '21:00', 'code': 'HHHHHH', 'usedAnnualLeave': 0.0},
      ];

      // ★ 월급제 워커: 급여 구조 자동 시뮬레이션
      // 총급여(세전) 2,500,000원 → 기본급 + 식대 + 고정OT = 2,500,000
      // ────────────────────────────────────────────────────
      //  기본급:     2,156,880원  (10,320원/h × 209h)
      //  식대:         200,000원  (비과세)
      //  고정OT:      143,120원  (나머지 전액 고정연장수당)
      //  합계:       2,500,000원
      // ────────────────────────────────────────────────────
      for (var w in dummyWorkers) {
        if (w['wageType'] == 'monthly' && w['targetSalary'] != null) {
          final totalMonthly = (w['targetSalary'] as int).toDouble();
          final mealAllowance = 200000.0;
          final minimumWage = 10320.0;
          final standardMonthlyHours = 209.0;

          // 기본급 = 최저시급 × 209h (고정)
          final baseSalary = (minimumWage * standardMonthlyHours).roundToDouble(); // 2,156,880원

          // 고정OT = 총급여 - 기본급 - 식대 (나머지 전액)
          final fixedOTPay = totalMonthly - baseSalary - mealAllowance; // 143,120원

          // 통상시급 기준 고정OT 시간 (표시용)
          final conservativeHourly = (baseSalary + mealAllowance) / standardMonthlyHours;
          final fixedOTHoursCalc = conservativeHourly > 0 ? fixedOTPay / (conservativeHourly * 1.5) : 0.0;

          w['wage'] = minimumWage.round();
          // Worker 모델의 monthlyWage는 '기본급'을 의미합니다. (UI에서 2,156,880원으로 보이게 됨)
          w['baseSalary'] = baseSalary.round();
          w['monthlyWage'] = baseSalary.round();
          w['mealAllowance'] = mealAllowance.round();
          w['fixedOTHours'] = fixedOTHoursCalc;
          w['fixedOTPay'] = fixedOTPay.round();

          debugPrint('[Demo] 김점장 급여 구성안:');
          debugPrint('  총급여(세전): ${totalMonthly.round()}원');
          debugPrint('  기본급: ${baseSalary.round()}원 (${minimumWage.round()}원/h × ${standardMonthlyHours}h)');
          debugPrint('  식대(비과세): ${mealAllowance.round()}원');
          debugPrint('  고정OT: ${fixedOTPay.round()}원 (${fixedOTHoursCalc.toStringAsFixed(1)}h)');
          debugPrint('  합계: ${(baseSalary + mealAllowance + fixedOTPay).round()}원');
        }
      }

      final now = AppClock.now();
      final oneYearAgo = now.subtract(const Duration(days: 400)).toIso8601String().substring(0, 10);
      final healthExpiry = now.add(const Duration(days: 45)).toIso8601String().substring(0, 10);

      final batch = db.batch();
      for (var w in dummyWorkers) {
        final isMonthlyWorker = w['wageType'] == 'monthly';
        batch.set(
          db.collection('stores').doc(storeId).collection('workers').doc(w['id'] as String),
          {
            'name': w['name'],
            'status': 'active',
            'storeId': storeId,
            'phone': w['phone'],
            'inviteCode': w['code'],
            'checkInTime': w['in'],
            'checkOutTime': w['out'],
            'workDays': w['workDays'], // 위에서 세팅한 교묘한 근무 요일 적용
            'hourlyWage': w['wage'],
            'weeklyHours': (w['hours'] as int) * (w['workDays'] as List).length,
            'isPaidBreak': w['isPaidBreak'],
            'breakMinutes': 60,
            'weeklyHolidayPay': true,
            'isVirtual': true, // 가상 직원 플래그 (중요: 급여 계산 시 검증 로직 통과용)
            'isDemo': true,    // 체험용 데이터 플래그
            'isAutoCalculation': true, // 상시근로자 자동 계산 모드 활성화
            'startDate': oneYearAgo, 
            'documentsInitialized': true,
            'hasHealthCert': true,
            'healthCertExpiry': healthExpiry,
            'usedAnnualLeave': (w['usedAnnualLeave'] as num?)?.toDouble() ?? 0.0, // ★ 연차 사용량 (사용촉진 시나리오용)
            // ★ 김점장: 1년 미만 연차 사용촉진 완료 로그 (수당 면제 검증용)
            if (w['id'] == 'worker_a') 'leavePromotionLogsJson': _buildPromotionLogsForKimManager(now, oneYearAgo),
            'createdAt': DateTime.now().toIso8601String(),
            // 월급제 워커 전용 필드
            if (isMonthlyWorker) 'wageType': w['wageType'],
            if (isMonthlyWorker) 'monthlyWage': w['monthlyWage'],
            if (isMonthlyWorker) 'fixedOvertimeHours': w['fixedOTHours'] ?? 0.0,
            if (isMonthlyWorker) 'fixedOvertimePay': w['fixedOTPay'] ?? 0,
            if (isMonthlyWorker) 'mealTaxExempt': true,
            if (isMonthlyWorker) 'allowances': [
              {'label': '식대', 'amount': w['mealAllowance'] ?? 200000},
            ],
          },
          SetOptions(merge: true)
        );
        
        // [추가] alba_web 로그인 연동 테스트를 위한 글로벌 초대코드 발급
        batch.set(
          db.collection('invites').doc(w['code'] as String),
          {
            'storeId': storeId,
            'workerId': w['id'],
            'createdAt': FieldValue.serverTimestamp(),
            'type': 'verification',
            'isVirtual': true,
          },
          SetOptions(merge: true),
        );
      }
      await batch.commit();

      // Firestore 색인 전파 및 규칙 반영을 위한 짧은 대기 (Atomic 전파 보장)
      // Firestore 전파를 위한 충분한 대기
      await Future.delayed(const Duration(milliseconds: 1000));

      // 4. 가상 직원의 과거 40일 치 출퇴근 기록 자동 생성 (TestDataSeeder 활용)
      await TestDataSeeder.generateVirtualWorkerAttendances(
        storeId: storeId,
        workersData: dummyWorkers,
      );

      // 5. ★ 상시 근로자 수(5인 이상 여부) 엔진 계산 → Firestore 반영
      //    출퇴근 기록 생성 후 PayrollCalculator.isFiveOrMore()를 호출하여
      //    근로기준법 시행령 제7조의2 기준으로 정확한 판정값을 매장에 저장합니다.
      try {
        final now = AppClock.now();
        final periodStart = now.subtract(const Duration(days: 30));
        final periodEnd = now;
        final attSnapshot = await db
            .collection('stores').doc(storeId)
            .collection('attendances')
            .where('clockIn', isGreaterThanOrEqualTo: periodStart.toIso8601String())
            .get();
        final attList = attSnapshot.docs.map((doc) {
          final d = doc.data();
          return Attendance(
            id: doc.id,
            staffId: d['staffId'] ?? '',
            storeId: storeId,
            clockIn: DateTime.parse(d['clockIn']),
            clockOut: d['clockOut'] != null ? DateTime.parse(d['clockOut']) : null,
            type: AttendanceType.web,
          );
        }).toList();

        final isFive = PayrollCalculator.isFiveOrMore(
          settlementAttendances: attList,
          periodStart: periodStart,
          periodEnd: periodEnd,
        );

        // ★ 대시보드 표시용 통계 계산 (main_screen이 읽는 필드)
        final totalDays = periodEnd.difference(periodStart).inDays + 1;
        final dailyStaff = <String, Set<String>>{};
        for (final att in attList) {
          final dayKey = '${att.clockIn.year}-${att.clockIn.month}-${att.clockIn.day}';
          dailyStaff.putIfAbsent(dayKey, () => <String>{}).add(att.staffId);
        }
        int operatingDays = 0;
        int daysWithFiveOrMore = 0;
        int totalPersonDays = 0;
        dailyStaff.forEach((_, staffSet) {
          operatingDays++;
          totalPersonDays += staffSet.length;
          if (staffSet.length >= 5) daysWithFiveOrMore++;
        });
        final avgWorkers = operatingDays > 0 ? totalPersonDays / operatingDays : 0.0;

        await db.collection('stores').doc(storeId).update({
          'isFiveOrMore': isFive,
          'isFiveOrMore_CalculatedValue': isFive,
          'isFiveOrMore_ChangeReason': '체험모드 자동 산정 (시행령 제7조의2)',
          'averageWorkers': avgWorkers,
          'daysWithFiveOrMore': daysWithFiveOrMore,
          'totalBusinessDays': operatingDays,
        });
        debugPrint('[LoginScreen] 5인 이상 판정: $isFive (평균 ${avgWorkers.toStringAsFixed(1)}명, 5인↑ $daysWithFiveOrMore/$operatingDays일, 출퇴근 ${attList.length}건)');
      } catch (e) {
        debugPrint('[LoginScreen] 5인 이상 판정 실패 (fallback true): $e');
        // 실패 시에도 데모 체험에 지장 없도록 5인 이상으로 강제 세팅
        await db.collection('stores').doc(storeId).update({
          'isFiveOrMore': true,
          'isFiveOrMore_CalculatedValue': true,
          'isFiveOrMore_ChangeReason': '체험모드 fallback (출퇴근 조회 실패)',
          'averageWorkers': 5.0,
        });
      }

      // StoreIdGate가 MainScreen을 자연스럽게 렌더링하도록 힌트 전달
      debugPrint('[LoginScreen] 체험 모드 데이터 세팅 완료');
      
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('체험 모드 로딩 실패: $e\n네트워크를 확인하세요.')),
        );
      }
      debugPrint('[LoginScreen] 체험 모드 에러 발생: $e');
      try {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null) {
          await FirebaseFirestore.instance.collection('users').doc(uid).update({'demoError': e.toString()});
        }
      } catch (_) {}
    } finally {
      // 에러가 났든 안 났든 무조건 렌더링 블록 해제
      try {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null) {
          await FirebaseFirestore.instance.collection('users').doc(uid).update({'isLoadingDemo': false});
        }
      } catch (_) {}
      
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 김점장의 1년 미만 연차 사용촉진 완료 로그 생성
  /// 엔진은 1년 미만 연차를 '하나의 통합 배치'로 관리합니다:
  ///   grantDate = 입사일, expiryDate = 입사 1주년 전날
  /// 이 배치에 대해 '촉진 완료' 상태를 세팅하여 수당 면제를 검증합니다.
  String _buildPromotionLogsForKimManager(DateTime now, String joinDateStr) {
    final joinDate = DateTime.parse(joinDateStr);
    final oneYearPoint = DateTime(joinDate.year + 1, joinDate.month, joinDate.day);
    final expiryDate = oneYearPoint.subtract(const Duration(days: 1));

    // 아직 소멸 전이면 빈 로그 반환 (촉진 완료 시뮬레이션 불가)
    if (now.isBefore(expiryDate)) return '[]';

    // 1년 미만: 1차 기한 = 소멸 3개월 전, 2차 기한 = 소멸 1개월 전
    final firstDeadline = DateTime(expiryDate.year, expiryDate.month - 3, expiryDate.day);
    final secondDeadline = DateTime(expiryDate.year, expiryDate.month - 1, expiryDate.day);
    // 기한 내에 이행한 것으로 세팅
    final firstNoticeDate = firstDeadline.subtract(const Duration(days: 5));
    final secondNoticeDate = secondDeadline.subtract(const Duration(days: 5));

    final log = {
      'batchGrantDate': joinDate.toIso8601String(),
      'batchExpiryDate': expiryDate.toIso8601String(),
      'unusedDays': 11.0,
      'isPreAnniversary': true,
      'firstNoticeDeadline': firstDeadline.toIso8601String(),
      'firstNoticeDate': firstNoticeDate.toIso8601String(),
      'firstNoticeDocId': 'demo-promo-1st-preanniv',
      'secondNoticeDeadline': secondDeadline.toIso8601String(),
      'secondNoticeDate': secondNoticeDate.toIso8601String(),
      'secondNoticeDocId': 'demo-promo-2nd-preanniv',
      'designatedDates': [
        expiryDate.subtract(const Duration(days: 5)).toIso8601String().substring(0, 10),
        expiryDate.subtract(const Duration(days: 4)).toIso8601String().substring(0, 10),
        expiryDate.subtract(const Duration(days: 3)).toIso8601String().substring(0, 10),
      ],
      'status': 'completed',
    };

    return jsonEncode([log]);
  }

  void _debugQuickLoginAlbaHint() {
    if (!kDebugMode) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('알바 테스트 로그인'),
        content: const Text(
          '알바용 웹 앱을 실행한 뒤, 같은 화면 하단의 「테스트: 알바 시드 로그인」을 사용하세요.\n'
          '(시드 데이터: 초대 TST001, 전화 01000000001)',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('확인')),
        ],
      ),
    );
  }

  void _showConsentRequiredSnack() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('[필수] 서비스 이용약관 및 개인정보 처리방침을 확인하고 동의해 주세요.'),
      ),
    );
  }

  void _handleAuthResult(dynamic userCredential) {
    setState(() => _isLoading = false);
    if (userCredential != null) {
      // Let _AuthGate decide next screen (StoreSetupScreen vs DashboardScreen).
      return;
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('로그인 실패. (계정/설정 문제일 수 있어요) 다시 시도해 주세요.')),
        );
      }
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _emailLinkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_step == LoginStep.selectRole) {
      return Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.account_balance, size: 80, color: Colors.blue),
                const SizedBox(height: 16),
                const Text(
                  '알바급여정석',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  '어떤 회원으로 시작하시겠어요?',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),
                FilledButton.tonal(
                  onPressed: () => setState(() => _step = LoginStep.loginManager),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.all(20),
                    alignment: Alignment.centerLeft,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade100,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.storefront, color: Colors.blue, size: 32),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('매장 관리자 (사장/점장)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
                            SizedBox(height: 4),
                            Text('매장을 등록하고 직원을 관리합니다.', style: TextStyle(fontSize: 13, color: Colors.black54)),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: Colors.black54),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.tonal(
                  onPressed: () async {
                    final prefs = await SharedPreferences.getInstance();
                    final pendingCode = prefs.getString('pending_invite_code');
                    if (pendingCode != null) {
                      await prefs.remove('pending_invite_code');
                    }
                    if (context.mounted) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => AlbaLoginScreen(initialInviteCode: pendingCode)),
                      );
                    }
                  },
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.all(20),
                    alignment: Alignment.centerLeft,
                    backgroundColor: Colors.green.shade50,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green.shade100,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.badge, color: Colors.green, size: 32),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('매장 직원 (알바생/매니저)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
                            SizedBox(height: 4),
                            Text('초대 코드를 입력하고 매장에 합류합니다.', style: TextStyle(fontSize: 13, color: Colors.black54)),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: Colors.black54),
                    ],
                  ),
                ),
                const SizedBox(height: 48),
                TextButton(
                  onPressed: _isLoading ? null : _startExperienceMode,
                  child: _isLoading
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('가상 데이터로 앱 체험해보기', style: TextStyle(color: Colors.grey, decoration: TextDecoration.underline)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // B안: 모든 기기에서 3가지 옵션 동일 제공
    final googleEnabled = true;
    final appleEnabled = true;
    final canLogin = _isConsented;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => setState(() => _step = LoginStep.selectRole),
        ),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: MediaQuery.sizeOf(context).height - kToolbarHeight - 48,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.storefront, size: 80, color: Colors.blue),
              const SizedBox(height: 16),
              const Text(
                '사장님 로그인',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text('가입하셨던 소셜 계정으로 계속합니다.'),
              const SizedBox(height: 48),

              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final agreed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => const TermsConsentPopup(),
                    );
                    if (agreed == true) {
                      setState(() {
                        _isConsented = true;
                      });
                    }
                  },
                  icon: Icon(
                    _isConsented ? Icons.check_circle : Icons.description_outlined,
                    color: _isConsented ? Colors.green : Colors.grey,
                  ),
                  label: Text(
                    _isConsented ? '약관 동의 완료' : '서비스 이용약관 및 개인정보 처리방침 확인',
                    style: TextStyle(
                      color: _isConsented ? Colors.green.shade700 : Colors.black87,
                      fontWeight: _isConsented ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: _isConsented ? Colors.green : Colors.blue.shade100),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              if (!canLogin) ...[
                const SizedBox(height: 12),
                const Text(
                  '서비스 시작 전 약관 확인 및 동의가 필요합니다.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 32),

              GoogleBrandSignInButton(
                onPressed: _isLoading || !googleEnabled
                    ? null
                    : () {
                        if (!canLogin) {
                          _showConsentRequiredSnack();
                          return;
                        }
                        _handleGoogleSignIn();
                      },
              ),
              const SizedBox(height: LoginBrandButtonMetrics.verticalGap),
              AppleBrandSignInButton(
                onPressed: _isLoading || !appleEnabled
                    ? null
                    : () {
                        if (!canLogin) {
                          _showConsentRequiredSnack();
                          return;
                        }
                        _handleAppleSignIn();
                      },
              ),
              const SizedBox(height: 18),
              if (_isAndroid)
                const Text('Android의 Apple 로그인은 “웹 기반 Apple 로그인” 설정이 필요합니다.', style: TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  void _showEmailLinkBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.only(left: 20, right: 20, top: 8, bottom: bottomInset + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('이메일 링크 로그인', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              const Text('이메일로 받은 링크를 눌러 자동으로 로그인됩니다.', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 16),
              TextField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: '이메일 주소',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: LoginBrandButtonMetrics.height,
                child: FilledButton(
                  onPressed: _isLoading ? null : _handleEmailLinkSignIn,
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(LoginBrandButtonMetrics.borderRadius),
                    ),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('이메일로 로그인 링크 받기'),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => setState(() => _showManualLinkPaste = !_showManualLinkPaste),
                child: Text(_showManualLinkPaste ? '수동 로그인 접기' : '링크가 앱에서 안 열리나요? (수동 로그인)'),
              ),
              if (_showManualLinkPaste) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _emailLinkController,
                  decoration: const InputDecoration(
                    labelText: '메일로 받은 로그인 링크 붙여넣기',
                    prefixIcon: Icon(Icons.link),
                  ),
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: LoginBrandButtonMetrics.height,
                  child: OutlinedButton(
                    onPressed: _isLoading ? null : _handleEmailLinkComplete,
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(LoginBrandButtonMetrics.borderRadius),
                      ),
                    ),
                    child: const Text('링크로 로그인 완료'),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  void _showPolicyDialog(String title, String url) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SelectableText(url),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('닫기')),
        ],
      ),
    );
  }
}
