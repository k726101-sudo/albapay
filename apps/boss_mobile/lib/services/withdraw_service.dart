import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class WithdrawService {
  /// 계정과 연결된 모든 노무 데이터를 0바이트로 파기하고 파기 증명원(Audit Log)을 남깁니다.
  static Future<void> deleteAccountAndData(String storeId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('로그인되어 있지 않습니다.');
    
    final uid = user.uid;
    final db = FirebaseFirestore.instance;

    // 1. Audit Log (파기 증명원) 보존
    // 데이터 본체는 모두 날아가지만, '누가 언제 어떤 약관에 동의하고 파기했는지'는 3년간 서버에 남아 분쟁을 방어함.
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

    // 2. 매장 및 하위 노무 데이터(근태, 급여, 백업 파일 등) 전량 삭제
    if (storeId.isNotEmpty) {
      final storeRef = db.collection('stores').doc(storeId);
      final subcollections = ['attendance', 'archives', 'frozen_items', 'destruction_logs', 'workers', 'payrolls', 'documents']; 
      
      for (final sub in subcollections) {
        final docs = await storeRef.collection(sub).get();
        for (final doc in docs.docs) {
          // 보안 파기 목적: 삭제 전 빈 데이터로 덮어씌움 (Overwriting)
          await doc.reference.set({}, SetOptions(merge: false));
          await doc.reference.delete();
        }
      }
      
      // 스토어 본체 덮어쓰기 및 삭제
      await storeRef.set({}, SetOptions(merge: false));
      await storeRef.delete();
    }

    // 3. Boss(User) 정보 삭제
    final userRef = db.collection('users').doc(uid);
    await userRef.set({}, SetOptions(merge: false));
    await userRef.delete();

    // 4. Firebase Auth 자격 증명 파기
    // 주의: recent-login 이 필요한 경우 에러가 발생하며, 이 경우 재로그인 안내를 해야 함.
    try {
      await user.delete();
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        throw Exception('보안을 위해 다시 로그인한 직후 탈퇴를 시도해 주세요.');
      }
      rethrow;
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
