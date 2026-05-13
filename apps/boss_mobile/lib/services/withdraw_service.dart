import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart' as google_sign_in;
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:shared_logic/shared_logic.dart' show AppleAuthConfig, GoogleAuthConfig, OnboardingGuideService;

class WithdrawService {
  /// 계정과 연결된 모든 노무 데이터를 파기하고 파기 증명원(Audit Log)을 남깁니다.
  static Future<void> deleteAccountAndData(String storeId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('로그인되어 있지 않습니다.');
    
    final uid = user.uid;
    final db = FirebaseFirestore.instance;
    final errors = <String>[];

    // 1. Audit Log (파기 증명원) 보존 — 반드시 먼저
    try {
      final auditRef = db.collection('audit_logs').doc();
      await auditRef.set({
        'userId': uid,
        'storeId': storeId,
        'action': 'ACCOUNT_WITHDRAWAL',
        'reason': '사용자 자진 탈퇴 및 즉시 파기',
        'destroyedAt': FieldValue.serverTimestamp(),
        'termsAgreed': [
           '1. 백업 미진행 데이터 전량 파기 확인',
           '2. 노동 분쟁 시 증빙 자료 손실 법적 책임 동의',
           '3. 데이터의 어떠한 복구도 불가함에 동의',
        ],
        'deletedBy': 'USER_DIRECT',
      });
    } catch (e) {
      errors.add('audit_log: $e');
      // Audit 실패해도 탈퇴는 계속 진행
    }

    // 2. 매장 하위 노무 데이터 전량 삭제
    //    주의: users/{uid} 와 stores/{storeId} 본체는 맨 마지막에 삭제해야 함.
    //    isStoreMember() 규칙이 이 문서들을 참조하기 때문.
    if (storeId.isNotEmpty) {
      final storeRef = db.collection('stores').doc(storeId);
      final subcollections = [
        'attendance', 'archives', 'frozen_items', 'destruction_logs',
        'workers', 'payrolls', 'documents', 'notices', 'todos', 'expirations',
      ]; 
      
      for (final sub in subcollections) {
        try {
          final docs = await storeRef.collection(sub).get();
          for (final doc in docs.docs) {
            try {
              await doc.reference.delete();
            } catch (_) {}
          }
        } catch (e) {
          errors.add('sub/$sub: $e');
        }
      }

      // Top-level attendance 삭제
      try {
        final attendanceDocs = await db.collection('attendance')
            .where('storeId', isEqualTo: storeId)
            .get();
        for (final doc in attendanceDocs.docs) {
          try { await doc.reference.delete(); } catch (_) {}
        }
      } catch (e) {
        errors.add('top-attendance: $e');
      }

      // Top-level invites 삭제
      try {
        final inviteDocs = await db.collection('invites')
            .where('storeId', isEqualTo: storeId)
            .get();
        for (final doc in inviteDocs.docs) {
          try { await doc.reference.delete(); } catch (_) {}
        }
      } catch (e) {
        errors.add('invites: $e');
      }
      
      // 스토어 본체 삭제 (마지막)
      try {
        await storeRef.delete();
      } catch (e) {
        errors.add('store: $e');
      }
    }

    // 3. Boss(User) 정보 삭제 (스토어 삭제 후)
    try {
      final userRef = db.collection('users').doc(uid);
      await userRef.delete();
    } catch (e) {
      errors.add('user: $e');
    }

    // 4. Firebase Auth 자격 증명 파기
    //    requires-recent-login 발생 시 자동 재인증 후 재시도
    try {
      await user.delete();
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        // 사용자의 로그인 제공자 확인 후 재인증
        final reauthed = await _reauthenticateUser(user);
        if (reauthed) {
          await user.delete();
        } else {
          throw Exception('보안을 위해 다시 로그인한 직후 탈퇴를 시도해 주세요.');
        }
      } else {
        rethrow;
      }
    }

    // 탈퇴 성공 시 로컬 Google 세션도 파기
    try {
      await google_sign_in.GoogleSignIn.instance.signOut();
    } catch (_) {}

    // 5. 온보딩 가이드 상태 초기화
    try {
      await OnboardingGuideService.instance.reset();
    } catch (_) {}
  }

  /// 사용자 재인증 (Google / Apple)
  static Future<bool> _reauthenticateUser(User user) async {
    final providers = user.providerData.map((p) => p.providerId).toList();

    try {
      if (providers.contains('google.com')) {
        return await _reauthWithGoogle(user);
      } else if (providers.contains('apple.com')) {
        return await _reauthWithApple(user);
      }
    } catch (e) {
      // 재인증 실패
    }
    return false;
  }

  static Future<bool> _reauthWithGoogle(User user) async {
    try {
      final googleSignIn = google_sign_in.GoogleSignIn.instance;

      // GoogleSignIn 초기화
      try {
        await googleSignIn.initialize(
          serverClientId: GoogleAuthConfig.serverClientId,
        );
      } catch (_) {
        // 이미 초기화된 경우 무시
      }

      final googleUser = await googleSignIn.authenticate();
      final googleAuth = googleUser.authentication;
      final authz = await googleUser.authorizationClient.authorizationForScopes(
        const ['email', 'profile'],
      );

      final credential = GoogleAuthProvider.credential(
        accessToken: authz?.accessToken,
        idToken: googleAuth.idToken,
      );

      await user.reauthenticateWithCredential(credential);
      return true;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> _reauthWithApple(User user) async {
    try {
      final cid = AppleAuthConfig.clientId.trim();
      final bridgeUri = Uri.parse(AppleAuthConfig.androidOAuthReturnUrl);

      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        webAuthenticationOptions: AppleAuthConfig.useNativeAppleSignIn
            ? null
            : WebAuthenticationOptions(
                clientId: cid,
                redirectUri: bridgeUri,
              ),
      );

      final oAuth = OAuthProvider('apple.com');
      final credential = oAuth.credential(
        idToken: appleCredential.identityToken,
        accessToken: appleCredential.authorizationCode,
      );

      await user.reauthenticateWithCredential(credential);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// 1년(365일) 이상 묵은 휴면 계정용 자동 파기 파이프라인
  static Future<void> inactiveAccountHousekeeping(String uid, String storeId) async {
    final db = FirebaseFirestore.instance;

    // 1. Audit Log 보존 (휴면 파기용)
    final auditRef = db.collection('audit_logs').doc();
    await auditRef.set({
      'userId': uid,
      'storeId': storeId,
      'action': 'INACTIVE_ACCOUNT_DESTRUCTION',
      'reason': '1년 이상 미접속으로 인한 개인정보보호법에 따른 휴면 파기',
      'destroyedAt': FieldValue.serverTimestamp(),
      'termsAgreed': [
         '1. 가입 시 동의한 휴면 계정 영구 파기 철칙 발동',
      ],
      'deletedBy': 'SYSTEM_HOUSEKEEPING',
    });

    // 2. 매장 데이터 전량 덮어쓰기 및 삭제
    if (storeId.isNotEmpty) {
      final storeRef = db.collection('stores').doc(storeId);
      
      final subcollections = ['attendance', 'archives', 'frozen_items', 'destruction_logs', 'workers', 'payrolls', 'documents']; 
      
      for (final sub in subcollections) {
        final docs = await storeRef.collection(sub).get();
        for (final doc in docs.docs) {
          await doc.reference.set({}, SetOptions(merge: false));
          await doc.reference.delete();
        }
      }
      await storeRef.set({}, SetOptions(merge: false));
      await storeRef.delete();
    }

    // 3. User 데이터 삭제
    final userRef = db.collection('users').doc(uid);
    await userRef.set({}, SetOptions(merge: false));
    await userRef.delete();

    // (참고: Cloud Functions나 Admin SDK가 없으면 Firebase Auth 삭제는 서버리스로 완벽 처리 불가)
    // 방어 로직: uid에 해당하는 users/store가 없으므로 재접속 시 어차피 새로 가입하는 형태로 작동.
  }
}
