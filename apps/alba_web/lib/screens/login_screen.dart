import 'package:web/web.dart' as web;
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_logic/shared_logic.dart';

import 'alba_main_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const _sessionInviteKey = 'alba_invite_code';
  static const _sessionStoreKey = 'alba_store_id';
  static const _sessionActionKey = 'alba_pending_action';
  static const _sessionSigKey = 'alba_pending_sig';

  final _phoneController = TextEditingController();
  final _inviteController = TextEditingController();
  final _dbService = DatabaseService();
  final _consentService = ConsentService();
  bool _isLoading = false;
  String? _storeId;
  bool _inviteLockedFromUrl = false;
  bool _isConsented = false;
  String? _accessDeniedMessage;
  bool _showIosKakaoGuideOverlay = false;
  bool _showAndroidKakaoGuideOverlay = false;

  @override
  void initState() {
    super.initState();
    _handleKakaoInAppBrowser();
    _hydrateFromInviteLink();
    _persistAttendanceActionFromUrl();

    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (!mounted) return;
      if (user != null) {
        // If we're currently in the middle of login flow, navigation is handled
        // by _verifyCode after Firestore checks.
        if (_isLoading) return;
        
        // 만약 /doc-view (문서 뷰어) 등 딥링크 목적지로 진입한 상태라면 
        // 자동으로 알바용 메인화면으로 강제 이동하지 않도록 차단합니다.
        final currentUrl = web.window.location.href;
        if (currentUrl.contains('/doc-view')) {
          return;
        }

        _handleAuthedUser(user);
      }
    });
  }

  /// Kakao 인앱에서 시스템 브라우저(또는 Chrome)로 같은 URL을 엽니다. 쿼리(`code=` 등) 유지.
  static String _kakaoOpenExternalUrl(String fullPageUrl) {
    return 'kakaotalk://web/openExternal?url=${Uri.encodeComponent(fullPageUrl)}';
  }

  /// Android Chrome intent. `S.browser_fallback_url`로 인앱에서 intent 실패 시 https로 폴백합니다.
  /// URL fragment는 `#Intent`와 충돌할 수 있어 intent 경로에는 넣지 않고 폴백 URL에만 포함됩니다.
  static String _androidChromeIntentUrl(String fullPageUrl) {
    final u = Uri.parse(fullPageUrl);
    final encFallback = Uri.encodeComponent(fullPageUrl);
    final defaultPort = u.scheme == 'https' ? 443 : 80;
    final host = u.hasPort && u.port != defaultPort ? '${u.host}:${u.port}' : u.host;
    final path = u.path.isEmpty ? '/' : u.path;
    final query = u.hasQuery ? '?${u.query}' : '';
    return 'intent://$host$path$query#Intent;scheme=${u.scheme};package=com.android.chrome;'
        'S.browser_fallback_url=$encFallback;end';
  }

  void _openKakaoExternalBrowser() {
    web.window.location.href = _kakaoOpenExternalUrl(Uri.base.toString());
  }

  void _openAndroidChromeIntent() {
    web.window.location.href = _androidChromeIntentUrl(Uri.base.toString());
  }

  void _handleKakaoInAppBrowser() {
    final userAgent = web.window.navigator.userAgent.toLowerCase();
    final isKakaoInApp = userAgent.contains('kakaotalk');
    if (!isKakaoInApp) return;

    final isAndroid = userAgent.contains('android');
    final isIos =
        userAgent.contains('iphone') || userAgent.contains('ipad') || userAgent.contains('ipod');
    if (isAndroid) {
      // 1) 카카오 공식 우회: 시스템 기본 브라우저로 현재 URL 열기 (쿼리 유지)
      _openKakaoExternalBrowser();
      // 2) 전체 화면 오버레이는 자동으로 띄우지 않습니다(로그인 버튼 터치를 가로채는 문제 방지).
      //    필요 시 하단 스낵바에서만 '외부 브라우저 안내'를 열 수 있게 합니다.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 10),
            content: const Text(
              '카카오 인앱에서 로그인이 안 되면 Chrome 등 외부 브라우저에서 같은 주소를 여세요.',
            ),
            action: SnackBarAction(
              label: '열기 안내',
              onPressed: () {
                if (!mounted) return;
                setState(() => _showAndroidKakaoGuideOverlay = true);
              },
            ),
          ),
        );
      });
      return;
    }

    if (isIos) {
      // 전체 화면 오버레이는 자동 표시하지 않습니다(로그인·체크박스 터치 방해 방지).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 12),
            content: const Text(
              '홈 화면에 추가하려면 Safari에서 열어 주세요. (카카오 ⋯ 메뉴 → Safari로 열기)',
            ),
            action: SnackBarAction(
              label: 'Safari 안내',
              onPressed: () {
                if (!mounted) return;
                setState(() => _showIosKakaoGuideOverlay = true);
              },
            ),
          ),
        );
      });
    }
  }

  Future<void> _handleAuthedUser(User user) async {
    try {
      final userDoc =
          await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final storeId = userDoc.data()?['storeId']?.toString().trim();
      final workerId = userDoc.data()?['workerId']?.toString().trim();
      if (storeId == null || storeId.isEmpty || workerId == null || workerId.isEmpty) {
        await FirebaseAuth.instance.signOut();
        // 이전 세션(테스트 계정 등)이 유효하지 않으면 조용히 로그아웃 처리만 하고 사용자에게는 로그인 화면을 정상 노출합니다.
        return;
      }

      final workerDoc = await FirebaseFirestore.instance
          .collection('stores')
          .doc(storeId)
          .collection('workers')
          .doc(workerId)
          .get();

      final status = workerDoc.data()?['status']?.toString();
      if (status != 'active') {
        await FirebaseAuth.instance.signOut();
        return;
      }

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => AlbaMainScreen(storeId: storeId, workerId: workerId),
        ),
      );
    } catch (_) {
      await FirebaseAuth.instance.signOut();
    }
  }

  /// 쿼리 → URL fragment → 같은 탭 sessionStorage 순으로 초대 파라미터를 읽습니다.
  /// (iOS·인앱 브라우저 등에서 쿼리만 유실되는 경우 fragment 보조)
  ({String? invite, String? storeId}) _readInviteParamsFromBrowser() {
    final href = web.window.location.href;
    final uri = Uri.parse(href);

    String? pick(Map<String, String> q) {
      final a = q['invite_code']?.trim();
      if (a != null && a.isNotEmpty) return a.toUpperCase();
      final b = q['invite']?.trim();
      if (b != null && b.isNotEmpty) return b.toUpperCase();
      final c = q['code']?.trim();
      if (c != null && c.isNotEmpty) return c.toUpperCase();
      return null;
    }

    String? storePick(Map<String, String> q) {
      final a = q['store_id']?.trim();
      if (a != null && a.isNotEmpty) return a;
      final b = q['storeId']?.trim();
      if (b != null && b.isNotEmpty) return b;
      return null;
    }

    var invite = pick(uri.queryParameters);
    var storeIdFromUrl = storePick(uri.queryParameters);

    if (invite == null || invite.isEmpty) {
      final frag = uri.fragment.trim();
      if (frag.contains('=')) {
        var s = frag;
        if (s.startsWith('/')) s = s.substring(1);
        if (s.startsWith('?')) s = s.substring(1);
        try {
          final fq = Uri.splitQueryString(s);
          invite = pick(fq);
          storeIdFromUrl ??= storePick(fq);
        } catch (_) {}
      }
    }

    if (invite == null || invite.isEmpty) {
      final sInv = web.window.sessionStorage.getItem(_sessionInviteKey)?.trim();
      final sSt = web.window.sessionStorage.getItem(_sessionStoreKey)?.trim();
      if (sInv != null && sInv.isNotEmpty) {
        invite = sInv;
        if (storeIdFromUrl == null || storeIdFromUrl.isEmpty) {
          storeIdFromUrl = (sSt != null && sSt.isNotEmpty) ? sSt : null;
        }
      }
    }

    return (invite: invite, storeId: storeIdFromUrl);
  }

  void _persistInviteSession(String invite, String? storeId) {
    web.window.sessionStorage.setItem(_sessionInviteKey, invite);
    if (storeId != null && storeId.isNotEmpty) {
      web.window.sessionStorage.setItem(_sessionStoreKey, storeId);
    }
  }

  Future<void> _hydrateFromInviteLink() async {
    final params = _readInviteParamsFromBrowser();
    final invite = params.invite;
    final storeIdFromUrl = params.storeId;
    if (invite == null || invite.isEmpty) {
      setState(() {
        _storeId = null;
      });
      return;
    }
    _persistInviteSession(invite, storeIdFromUrl);
    _inviteController.text = invite;
    _inviteLockedFromUrl = true;

    // [핵심] 로그인 전에는 Firestore를 절대 호출하지 않습니다.
    // 모바일 Chrome에서 로그인 전에 Firestore 연결이 열리면,
    // 그 연결(gRPC 채널)이 인증 없는 상태로 고정되어
    // 로그인 후에도 DB 쓰기가 무한 대기(Hang)하는 치명적 버그가 발생합니다.
    // getInvite() 호출을 _loginWithInviteAndPhone() 내부(로그인 후)로 이동했습니다.
    if (storeIdFromUrl != null && storeIdFromUrl.isNotEmpty) {
      setState(() {
        _storeId = storeIdFromUrl;
      });
    }
  }

  void _persistAttendanceActionFromUrl() {
    final q = Uri.base.queryParameters;
    final action = q['action']?.trim();
    final storeId = (q['storeId'] ?? q['store_id'] ?? '').trim();
    final sig = q['sig']?.trim();

    if (action == 'attendance' && storeId.isNotEmpty) {
      if (kDebugMode) print('DEBUG: QR 딥링크 인식 - action=$action, storeId=$storeId');
      web.window.sessionStorage.setItem(_sessionActionKey, action!); // action is 'attendance' here
      web.window.sessionStorage.setItem(_sessionStoreKey, storeId);
      if (sig != null) {
        web.window.sessionStorage.setItem(_sessionSigKey, sig);
      }
    }
  }

  String _normalizePhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('82') && digits.length >= 11) {
      return '0${digits.substring(2)}';
    }
    return digits;
  }

  Future<void> _rollbackPartialAlbaLogin(String uid) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).delete().timeout(const Duration(seconds: 3));
    } catch (_) {}
    try {
      await FirebaseAuth.instance.signOut().timeout(const Duration(seconds: 3));
    } catch (_) {}
  }

  Future<void> _loginWithInviteAndPhone() async {
    if (!_isConsented) {
      _toast('이용약관 및 개인정보처리방침을 확인하고 동의해 주세요.');
      return;
    }
    final invite = _inviteController.text.trim().toUpperCase();
    final phone = _normalizePhone(_phoneController.text.trim());
    if (invite.isEmpty || phone.isEmpty) {
      _toast('초대코드와 전화번호를 입력해 주세요.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      // ★ Step 1: 익명 로그인을 가장 먼저 수행합니다.
      // [핵심] Firestore SDK는 첫 번째 서버 호출 시 gRPC 채널을 생성합니다.
      // 모바일 Chrome에서는 인증 없이 생성된 채널이 이후 로그인해도 갱신되지 않아
      // 모든 DB 쓰기가 무한 대기(Hang)합니다.
      // 해결: 로그인을 먼저 완료한 후에야 Firestore를 처음 사용하여,
      // 처음부터 인증된 채널이 생성되게 합니다.
      debugPrint('[LOGIN] Step 1: signInAnonymously (FIRST, before any Firestore call)');
      User? user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint('[LOGIN] Step 1: signInAnonymously executes');
        final cred = await FirebaseAuth.instance.signInAnonymously().timeout(
          const Duration(seconds: 30),
          onTimeout: () => throw FirebaseException(plugin: 'auth', code: 'timeout', message: '네트워크 상태나 브라우저 설정(쿠키 차단)을 확인해 주세요.'),
        );
        user = cred.user;
      } else {
        debugPrint('[LOGIN] Step 1: already logged in');
      }
      
      if (user != null) {
        // [핵심 방어] 신규 로그인이든, 캐시로 남아있던 기존 로그인이든 상관없이
        // 무조건 토큰을 강제 갱신합니다. (Safari ITP / 백그라운드 복귀 시 기존 토큰이 
        // 유효하지 않아 permission-denied가 발생하는 현상 방지)
        try {
          await user.getIdToken(true).timeout(const Duration(seconds: 10));
        } catch (_) {}
        await Future.delayed(const Duration(milliseconds: 300));
      }
      if (user == null) {
        _toast('로그인 토큰 발급에 실패했습니다.');
        setState(() => _isLoading = false);
        return;
      }
      debugPrint('[LOGIN] Step 1 done: uid=${user.uid}');

      // Step 2: 초대 문서 조회 (이제 Firestore 첫 호출이 인증된 상태로 실행됨)
      debugPrint('[LOGIN] Step 2: getInvite($invite)');
      final inviteData = await _dbService.getInvite(invite);
      debugPrint('[LOGIN] Step 2 done: inviteData=${inviteData != null ? 'found' : 'null'}');

      String? storeId = _storeId;
      if (storeId == null || storeId.isEmpty) {
        storeId = (inviteData?['storeId'] as String?)?.trim();
      }
      if (storeId == null || storeId.isEmpty) {
        _toast('초대 링크가 유효하지 않습니다.');
        _rollbackPartialAlbaLogin(user.uid);
        setState(() => _isLoading = false);
        return;
      }
      debugPrint('[LOGIN] storeId=$storeId');

      final workerIdHint = inviteData?['workerId']?.toString().trim();

      // Step 3: users 문서에 storeId 등록 (workers 쿼리 권한 확보)
      debugPrint('[LOGIN] Step 3: users/${user.uid} set storeId=$storeId');
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
        {
          'storeId': storeId,
          'workerId': FieldValue.delete(),
          'workerName': FieldValue.delete(),
        },
        SetOptions(merge: true),
      ).timeout(const Duration(seconds: 30), onTimeout: () => throw FirebaseException(plugin: 'firestore', code: 'timeout', message: 'Step3 타임아웃: users 문서 쓰기'));
      debugPrint('[LOGIN] Step 3 done');

      DocumentSnapshot<Map<String, dynamic>>? matched;

      // Step 4: workerIdHint로 직접 조회
      if (workerIdHint != null && workerIdHint.isNotEmpty) {
        debugPrint('[LOGIN] Step 4: direct worker lookup hint=$workerIdHint');
        final wdoc = await FirebaseFirestore.instance
            .collection('stores')
            .doc(storeId)
            .collection('workers')
            .doc(workerIdHint)
            .get()
            .timeout(const Duration(seconds: 30), onTimeout: () => throw FirebaseException(plugin: 'firestore', code: 'timeout', message: 'Step4 타임아웃: worker 문서 조회'));
        debugPrint('[LOGIN] Step 4 done: exists=${wdoc.exists}');
        if (wdoc.exists) {
          final data = wdoc.data() ?? {};
          final code = (data['inviteCode'] ?? data['invite_code'])?.toString().trim();
          if (code == invite) {
            final workerPhone = _normalizePhone(
              data['phone']?.toString() ?? data['phoneNumber']?.toString() ?? '',
            );
            if (workerPhone == phone && data['status']?.toString() == 'active') {
              matched = wdoc;
            }
          }
        }
      }

      // Step 5: inviteCode 쿼리 폴백
      if (matched == null) {
        debugPrint('[LOGIN] Step 5: query workers by inviteCode=$invite');
        QuerySnapshot<Map<String, dynamic>> snap = await FirebaseFirestore.instance
            .collection('stores')
            .doc(storeId)
            .collection('workers')
            .where('inviteCode', isEqualTo: invite)
            .where('status', isEqualTo: 'active')
            .limit(5)
            .get()
            .timeout(const Duration(seconds: 30), onTimeout: () => throw FirebaseException(plugin: 'firestore', code: 'timeout', message: 'Step5 타임아웃: inviteCode 쿼리'));
        debugPrint('[LOGIN] Step 5a done: ${snap.docs.length} docs');
        if (snap.docs.isEmpty) {
          snap = await FirebaseFirestore.instance
              .collection('stores')
              .doc(storeId)
              .collection('workers')
              .where('invite_code', isEqualTo: invite)
              .where('status', isEqualTo: 'active')
              .limit(5)
              .get()
              .timeout(const Duration(seconds: 30), onTimeout: () => throw FirebaseException(plugin: 'firestore', code: 'timeout', message: 'Step5 타임아웃: invite_code 쿼리'));
          debugPrint('[LOGIN] Step 5b done: ${snap.docs.length} docs');
        }
        if (snap.docs.isEmpty) {
          _toast('초대코드가 유효하지 않습니다.');
          _rollbackPartialAlbaLogin(user.uid); // Don't await to avoid hanging UI
          setState(() => _isLoading = false);
          return;
        }

        for (final d in snap.docs) {
          final workerPhone = _normalizePhone(
            d.data()['phone']?.toString() ?? d.data()['phoneNumber']?.toString() ?? '',
          );
          if (workerPhone == phone) {
            matched = d;
            break;
          }
        }
      }

      if (matched == null) {
        _toast('사장님이 등록하지 않은 번호입니다. 매장에 문의하세요');
        _rollbackPartialAlbaLogin(user.uid); // Don't await to avoid hanging UI
        setState(() => _isLoading = false);
        return;
      }

      final workerId = matched.id;
      debugPrint('[LOGIN] matched workerId=$workerId');

      // Step 6: worker 문서에 UID 등록
      debugPrint('[LOGIN] Step 6: set worker uid');
      await FirebaseFirestore.instance
          .collection('stores')
          .doc(storeId)
          .collection('workers')
          .doc(workerId)
          .set({'uid': user.uid}, SetOptions(merge: true))
          .timeout(const Duration(seconds: 30), onTimeout: () => throw FirebaseException(plugin: 'firestore', code: 'timeout', message: 'Step6 타임아웃: worker uid 업데이트'));
      debugPrint('[LOGIN] Step 6 done');

      // Step 7: users 문서에 workerId 저장
      final workerName = matched.data()?['name']?.toString() ?? '직원';
      debugPrint('[LOGIN] Step 7: set users workerId=$workerId');
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
        {
          'workerId': workerId,
          'workerName': workerName,
        },
        SetOptions(merge: true),
      ).timeout(const Duration(seconds: 30), onTimeout: () => throw FirebaseException(plugin: 'firestore', code: 'timeout', message: 'Step7 타임아웃: users workerId 저장'));
      debugPrint('[LOGIN] Step 7 done');

      await _consentService.ensureConsentRecorded(uid: user.uid, platform: 'alba_web');

      if (!mounted) return;
      // 키보드 강제 제거 및 브라우저 레이아웃 복구 여유 시간 부여
      FocusScope.of(context).unfocus();
      await Future.delayed(const Duration(milliseconds: 300));

      if (!mounted) return;
      debugPrint('[LOGIN] ✅ Success → navigating to AlbaMainScreen');
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => AlbaMainScreen(storeId: storeId!, workerId: workerId),
        ),
      );
    } on FirebaseAuthException catch (e) {
      debugPrint('[LOGIN] ❌ FirebaseAuthException: code=${e.code}, message=${e.message}');
      if (e.code == 'admin-restricted-operation') {
        _toast(
          '로그인이 콘솔 설정에 막혀 있습니다. Firebase에서 익명 로그인·회원가입 허용을 켜 주세요. (관리자에게 문의)',
        );
      } else if (e.code == 'operation-not-allowed') {
        _toast('이 로그인 방식은 비활성화되어 있습니다. 관리자에게 문의하세요.');
      } else if (e.code == 'too-many-requests') {
        _toast(
          '요청이 너무 많아 Firebase에서 잠시 막았습니다. 10~60분 뒤에 다시 시도하거나 다른 네트워크를 써 보세요.',
        );
      } else {
        _toast('로그인 실패(인증): ${e.message ?? e.code}');
      }
      final u = FirebaseAuth.instance.currentUser;
      if (u != null) await _rollbackPartialAlbaLogin(u.uid);
    } on FirebaseException catch (e) {
      debugPrint('[LOGIN] ❌ FirebaseException: code=${e.code}, message=${e.message}');
      if (e.code == 'permission-denied') {
        _toast('접근이 거부되었습니다. 외부 브라우저(Chrome/Safari)에서 다시 시도해 주세요.');
      } else if (e.code == 'timeout') {
        _toast('DB 응답이 느립니다. 네트워크 확인 후 다시 시도해 주세요. (${e.message})');
      } else {
        _toast('로그인 실패(DB): ${e.message ?? e.code}');
      }
      final u = FirebaseAuth.instance.currentUser;
      if (u != null) await _rollbackPartialAlbaLogin(u.uid);
    } catch (e) {
      debugPrint('[LOGIN] ❌ Unexpected: ${e.runtimeType}: $e');
      _toast('로그인 실패: $e');
      final u = FirebaseAuth.instance.currentUser;
      if (u != null) await _rollbackPartialAlbaLogin(u.uid);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _debugQuickLoginAlbaSeed() async {
    if (!kDebugMode) return;
    setState(() {
      _isConsented = true;
      _inviteController.text = DebugAuthConstants.albaInviteCode;
      _phoneController.text = DebugAuthConstants.albaPhone;
    });
    await _loginWithInviteAndPhone();
  }

  /// 앱-웹 통합 테스트용: 고정 이메일 계정으로 로그인 후 worker·스케줄 자동 등록
  Future<void> _debugLoginAsTestWorker() async {
    if (!kDebugMode) return;
    const testEmail = 'test.alba@debugstore.com';
    const testPassword = 'debug1234!';
    const storeId = 'debug_store_v30';
    setState(() => _isLoading = true);
    try {
      // 1) 로그인 시도, 없으면 계정 생성
      UserCredential cred;
      try {
        cred = await FirebaseAuth.instance
            .signInWithEmailAndPassword(email: testEmail, password: testPassword);
      } on FirebaseAuthException catch (e) {
        if (e.code == 'user-not-found' || e.code == 'invalid-credential') {
          cred = await FirebaseAuth.instance
              .createUserWithEmailAndPassword(email: testEmail, password: testPassword);
        } else {
          rethrow;
        }
      }
      final uid = cred.user!.uid;
      final db = FirebaseFirestore.instance;

      // 2) users 문서에 storeId 등록 및 workerId 고정 (앱-웹 일치화 핵심)
      await db.collection('users').doc(uid).set({
        'storeId': storeId,
        'workerId': DebugAuthConstants.testWorkerId,
        'name': '테스트 알바',
      }, SetOptions(merge: true));

      // 3) workers 문서 등록 (고정 ID 사용)
      await db
          .collection('stores')
          .doc(storeId)
          .collection('workers')
          .doc(DebugAuthConstants.testWorkerId)
          .set({
        'name': '테스트 알바',
        'status': 'active',
        'storeId': storeId,
        'phone': DebugAuthConstants.albaPhone,
        'inviteCode': DebugAuthConstants.albaInviteCode,
        'checkInTime': '09:00',
        'checkOutTime': '18:00',
        'workDays': [1, 2, 3, 4, 5, 6, 7], // 월~일 전체
        'startDate': AppClock.now().toIso8601String().substring(0, 10),
      }, SetOptions(merge: true));

      if (!mounted) return;
      
      // 테스트 로그인 시에도 키보드 해제
      FocusScope.of(context).unfocus();
      await Future.delayed(const Duration(milliseconds: 300));
      
      if (!mounted) return;
      // 4) AlbaMainScreen으로 직접 이동
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => AlbaMainScreen(
            storeId: storeId,
            workerId: DebugAuthConstants.testWorkerId,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('테스트 알바 로그인 실패: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _debugBossAppHint() {
    if (!kDebugMode) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('사장님 앱'),
        content: Text(
          '모바일 사장님 앱에서 로그인하세요.\n테스트: ${DebugAuthConstants.bossEmail}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('확인')),
        ],
      ),
    );
  }

  Future<void> _copyCurrentUrlForSafari() async {
    final url = web.window.location.href;
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    _toast('링크를 복사했습니다. Safari에서 붙여넣어 열어주세요.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          SafeArea(
            child: AutofillGroup(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 48.0),
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
              if (_accessDeniedMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.shade100),
                  ),
                  child: Text(
                    _accessDeniedMessage!,
                    style: TextStyle(
                      color: Colors.red.shade800,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              const Center(
                child: Icon(
                  Icons.work_outline,
                  size: 64,
                  color: Color(0xFF10B981),
                ),
              ),
              const SizedBox(height: 32),
              Text(
                '알바급여정석',
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      color: const Color(0xFF10B981),
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                '출퇴근 기록과 급여 내역을 실시간으로 확인하세요.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 32),
            const SizedBox(height: 12),
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
                  _isConsented ? '약관 동의 완료' : '이용약관 및 개인정보 처리방침 확인',
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
            if (!_isConsented)
              const Padding(
                padding: EdgeInsets.only(top: 8, left: 4),
                child: Text(
                  '서비스 이용을 위해 약관 동의가 필요합니다.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            const SizedBox(height: 16),
              if (_inviteLockedFromUrl)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFD0E3FF)),
                  ),
                  child: Text(
                    '초대코드 자동 입력됨: ${_inviteController.text}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF1A4C9A),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              else
                TextField(
                  controller: _inviteController,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  decoration: const InputDecoration(
                    hintText: '초대코드 (예: RW7HZN)',
                    prefixIcon: Icon(Icons.vpn_key_outlined),
                  ),
                  textCapitalization: TextCapitalization.characters,
                ),
              const SizedBox(height: 12),
              TextField(
                controller: _phoneController,
                autofillHints: const [AutofillHints.telephoneNumber],
                decoration: const InputDecoration(
                  hintText: '전화번호 (예: 01012345678)',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isLoading
                      ? null
                      : () {
                          if (_inviteController.text.trim().isEmpty || _phoneController.text.trim().isEmpty) {
                            _toast('초대코드와 전화번호를 먼저 입력해 주세요.');
                            return;
                          }
                          if (!_isConsented) {
                            _toast('이용약관 및 개인정보처리방침을 확인하고 동의해 주세요.');
                            return;
                          }
                          _loginWithInviteAndPhone();
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: (_inviteController.text.isNotEmpty && _phoneController.text.isNotEmpty) 
                      ? const Color(0xFF10B981) 
                      : Colors.grey.shade400,
                  ),
                  child: _isLoading
                      ? const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                            SizedBox(width: 8),
                            Text('DB 대기중... (최대 30초 소요 가능)', style: TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.w600)),
                          ],
                        )
                      : const Text('로그인'),
                ),
              ),
              const SizedBox(height: 16),
              if (kDebugMode) ...[
                const Divider(),
                const Text('🧪 연동 테스트용 (여기를 클릭하세요)', 
                  style: TextStyle(fontSize: 14, color: Colors.indigo, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Center(
                  child: SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton.icon(
                      onPressed: _isLoading ? null : _debugLoginAsTestWorker,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.person_pin, size: 24),
                      label: const Text('테스트 알바로 접속 (앱-웹 연동용)',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text('기타 개발자 도구', style: TextStyle(fontSize: 11, color: Colors.grey)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isLoading ? null : _debugBossAppHint,
                        child: const Text('사장님(안내)'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: _isLoading ? null : _debugQuickLoginAlbaSeed,
                        child: const Text('알바 시드'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],

              if (kDebugMode)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await FirebaseAuth.instance.signOut();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('세션이 초기화되었습니다. 다시 시작하세요.')),
                          );
                        }
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                      ),
                      icon: const Icon(Icons.cleaning_services),
                      label: const Text('디버그: 세션 강제 초기화 (로그아웃)', 
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
              // 공통 하단 문구
              const SizedBox(height: 24),
                  Center(
                    child: TextButton(
                      onPressed: () {},
                      child: const Text('회원가입은 매장 매니저를 통해 가능합니다.'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
          if (_showIosKakaoGuideOverlay)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _showIosKakaoGuideOverlay = false),
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.6),
                  child: Center(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {},
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 24),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.info_outline, color: Color(0xFF0EA5E9), size: 36),
                            const SizedBox(height: 10),
                            const Text(
                              '카카오톡 인앱브라우저에서는 기능이 제한될 수 있습니다.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              '우측 하단 점 세 개를 눌러 Safari에서 열어주세요.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 14),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Safari에서 접속해야 홈 화면에 추가 버튼이 보입니다.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12, color: Colors.black54),
                            ),
                            const SizedBox(height: 14),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: _copyCurrentUrlForSafari,
                                icon: const Icon(Icons.copy_rounded),
                                label: const Text('복사해서 Safari 열기'),
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: () => setState(() => _showIosKakaoGuideOverlay = false),
                              child: const Text('닫고 로그인하기'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (_showAndroidKakaoGuideOverlay)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _showAndroidKakaoGuideOverlay = false),
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.6),
                  child: Center(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {},
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 24),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.open_in_browser, color: Color(0xFF2563EB), size: 36),
                            const SizedBox(height: 10),
                            const Text(
                              '카카오톡 인앱에서는 로그인·저장이 막힐 수 있습니다.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              '아래에서 외부 브라우저(Chrome 등)로 같은 주소를 열어주세요. 링크의 code= 값은 그대로 유지됩니다.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 13, color: Colors.black87),
                            ),
                            const SizedBox(height: 14),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: _openKakaoExternalBrowser,
                                icon: const Icon(Icons.launch),
                                label: const Text('카카오에서 외부 브라우저로 열기'),
                              ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _openAndroidChromeIntent,
                                icon: const Icon(Icons.open_in_new),
                                label: const Text('Chrome으로 열기 (Intent)'),
                              ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: TextButton.icon(
                                onPressed: _copyCurrentUrlForSafari,
                                icon: const Icon(Icons.copy_rounded, size: 18),
                                label: const Text('현재 주소 복사'),
                              ),
                            ),
                            TextButton(
                              onPressed: () => setState(() => _showAndroidKakaoGuideOverlay = false),
                              child: const Text('닫고 로그인하기'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _inviteController.dispose();
    super.dispose();
  }
}
