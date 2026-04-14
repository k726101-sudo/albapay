import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

/// 모든 직원의 inviteCode 필드를 invites 컬렉션 기반으로 강제 복구하는 스크립트
Future<void> backfillInviteCodes() async {
  final firestore = FirebaseFirestore.instance;
  
  print('--- 초대 코드 자동 복구 시작 ---');
  
  try {
    final invitesSnap = await firestore.collection('invites').get();
    print('찾은 초대장 개수: ${invitesSnap.docs.length}');
    
    int successCount = 0;
    int skipCount = 0;
    
    for (var doc in invitesSnap.docs) {
      final data = doc.data();
      final inviteCode = doc.id;
      final storeId = data['storeId']?.toString();
      final workerId = data['workerId']?.toString();
      
      if (storeId == null || workerId == null) {
        print('! 스킵 (데이터 불완전): $inviteCode');
        skipCount++;
        continue;
      }
      
      final workerRef = firestore
          .collection('stores')
          .doc(storeId)
          .collection('workers')
          .doc(workerId);
          
      final workerDoc = await workerRef.get();
      if (workerDoc.exists) {
        await workerRef.set({
          'inviteCode': inviteCode,
        }, SetOptions(merge: true));
        print('✅ 복구 완료: $inviteCode (직원: ${data['staffName'] ?? workerId})');
        successCount++;
      } else {
        print('? 직원 문서 없음: $workerId (초대장: $inviteCode)');
        skipCount++;
      }
    }
    
    print('--- 복구 종료 (성공: $successCount, 스킵/실패: $skipCount) ---');
  } catch (e) {
    print('❌ 오류 발생: $e');
  }
}

void main() async {
  // 이 스크립트는 앱의 main() 등에서 일시적으로 호출하여 실행할 수 있습니다.
}
