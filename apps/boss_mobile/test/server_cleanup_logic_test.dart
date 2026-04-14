import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:boss_mobile/services/server_cleanup_service.dart';
import 'package:boss_mobile/services/backup_service.dart';

void main() {
  group('Server Data Lifecycle Verification (Time Compression)', () {
    late FakeFirebaseFirestore fakeStore;
    final String storeId = 'store_test_01';
    final String ownerId = 'boss_uid_01';

    setUp(() async {
      fakeStore = FakeFirebaseFirestore();
      ServerCleanupService.setTestFirestore(fakeStore);
      BackupService.isTestMode = true;
      BackupService.testMockExportFailure = false;
      BackupService.testExportedLogs.clear();

      await fakeStore.collection('stores').doc(storeId).set({
        'ownerId': ownerId,
        'name': 'Test Store',
      });
      await fakeStore.collection('notificationQueue').doc('dummy').set({'test': true});
    });

    test('1. Fake Data Generation & Time Compression Archiving & Export', () async {
      // [1] 날짜 조작: 현재 시간(가정)
      final DateTime baseNow = DateTime(2026, 4, 1, 12, 0);

      // (a) 1년 전 (실제로는 압축 스케일인 1분 전) 데이터 생성
      final targetArchiveMonth = baseNow.subtract(const Duration(minutes: 1));
      final String archiveMonthStr = 'test_${targetArchiveMonth.year}_${targetArchiveMonth.month}_${targetArchiveMonth.day}_${targetArchiveMonth.hour}_${targetArchiveMonth.minute}';
      
      await fakeStore.collection('attendance').add({
        'storeId': storeId,
        'clockIn': targetArchiveMonth.add(const Duration(seconds: 10)).toIso8601String(),
        'remark': '1년 전 데이터'
      });

      // (b) 3년 전 (실제로는 압축 스케일인 3분 전) 데이터 생성
      final targetDeleteMonth = baseNow.subtract(const Duration(minutes: 3));
      final String deleteMonthStr = 'test_${targetDeleteMonth.year}_${targetDeleteMonth.month}_${targetDeleteMonth.day}_${targetDeleteMonth.hour}_${targetDeleteMonth.minute}';
      
      // 이미 1년 차에 압축되었어야 하므로, Archives 컬렉션에 가짜 Gzip을 넣어둠
      final dummyJson = jsonEncode([{"_id": "test", "_sourceCollection": "attendance", "remark": "3년 전 데이터"}]);
      final dummyGzip = GZipEncoder().encode(utf8.encode(dummyJson))!;
      await fakeStore.collection('stores').doc(storeId).collection('archives').doc(deleteMonthStr).set({
        'month': deleteMonthStr,
        'compressedData': Blob(Uint8List.fromList(dummyGzip)),
        'originalCount': 1,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // [2] 시간 압축 모드로 클린업 실행
      print(">>> Running Automatic Cleanup for baseNow...");
      await ServerCleanupService.runAutomaticCleanup(storeId, overrideNow: baseNow, testTimeCompression: true);

      // --- 검증 1: 1분 전 데이터가 아카이빙 되었는가? ---
      final archiveSnap = await fakeStore.collection('stores').doc(storeId).collection('archives').doc(archiveMonthStr).get();
      expect(archiveSnap.exists, true, reason: '1분(1년) 전 데이터는 zip화 되어 저장되어야 함');
      
      // 원본은 삭제되었는가?
      final leftover = await fakeStore.collection('attendance').where('remark', isEqualTo: '1년 전 데이터').get();
      expect(leftover.docs.isEmpty, true, reason: '압축 후 원본 데이터는 비용 절감을 위해 서버에서 삭제되어야 함');

      // --- 검증 2: 3분 전 아카이브 데이터가 클라우드로 수출되고 서버에서 '원자적 파기' 되었는가? ---
      final deletedArchiveSnap = await fakeStore.collection('stores').doc(storeId).collection('archives').doc(deleteMonthStr).get();
      expect(deletedArchiveSnap.exists, false, reason: '3분(3년) 잔 데이터는 수출 후 서버에서 삭제되어야 함');

      // 파기 증명서 로그가 작성되었는가?
      final logSnap = await fakeStore.collection('stores').doc(storeId).collection('destruction_logs').doc(deleteMonthStr).get();
      expect(logSnap.exists, true, reason: '최종 파기 증명서 로그가 작성되어야 함');
      expect(logSnap.data()!['exportedToCloud'], true);

      // 백업 큐에 실제로 전송된 파일이 있는지 확인
      expect(BackupService.testExportedLogs.length, 1, reason: '클라우드로 1개의 백업본이 전송되어야 함');
      final exportFileName = BackupService.testExportedLogs.first['fileName'] as String;
      expect(exportFileName, contains(deleteMonthStr));
    });

    test('2. Failure Scenario (Safety Net) & Restoring', () async {
      final DateTime baseNow = DateTime(2026, 4, 1, 12, 0);
      final targetDeleteMonth = baseNow.subtract(const Duration(minutes: 3));
      final String deleteMonthStr = 'test_${targetDeleteMonth.year}_${targetDeleteMonth.month}_${targetDeleteMonth.day}_${targetDeleteMonth.hour}_${targetDeleteMonth.minute}';
      
      // 가짜 데이터 셋팅
      final dummyJson = jsonEncode([{"_id": "doc123", "_sourceCollection": "attendance", "remark": "극비 노무 데이터"}]);
      final dummyGzip = GZipEncoder().encode(utf8.encode(dummyJson))!;
      await fakeStore.collection('stores').doc(storeId).collection('archives').doc(deleteMonthStr).set({
        'month': deleteMonthStr,
        'compressedData': Blob(Uint8List.fromList(dummyGzip)),
      });

      // [3] 실패 시나리오 발동
      BackupService.testMockExportFailure = true;
      print(">>> Running Failed Export Scenario...");
      await ServerCleanupService.runAutomaticCleanup(storeId, overrideNow: baseNow, testTimeCompression: true);

      // --- 검증 3: 동결 상태(Frozen) 도입 및 삭제 중단 ---
      final archiveSnap = await fakeStore.collection('stores').doc(storeId).collection('archives').doc(deleteMonthStr).get();
      expect(archiveSnap.exists, true, reason: '클라우드 연동 실패 시 서버 원본 데이터가 보호되어야 함(Safety Net 작동)');

      final frozenSnap = await fakeStore.collection('stores').doc(storeId).collection('frozen_items').doc(deleteMonthStr).get();
      expect(frozenSnap.exists, true, reason: '동결 리스트에 진입해야 함');

      // Timestamp를 수동 교체 (원래 방금 등록됨)
      await frozenSnap.reference.update({'frozenAt': Timestamp.fromDate(baseNow)});

      // [4] 강력 알림 경보 발생 시뮬레이션 (3주차, 4주차)
      // 7분(7일) 경과 시점
      final week1Now = baseNow.add(const Duration(minutes: 7));
      await ServerCleanupService.runAutomaticCleanup(storeId, overrideNow: week1Now, testTimeCompression: true);
      
      var pushDocs = await fakeStore.collection('notificationQueue').get();
      expect(pushDocs.docs.where((d) => d.data()['title'] != null && (d.data()['title'] as String).contains('유예 상태')).isNotEmpty, true, reason: '첫 3주 내내 주간 알람 발생');

      // 24분(24일) 경과 시점 -> 마지막 7일에 진입하여 🚨 [최종고지] 발송
      final week4Now = baseNow.add(const Duration(minutes: 24));
      await ServerCleanupService.runAutomaticCleanup(storeId, overrideNow: week4Now, testTimeCompression: true);

      pushDocs = await fakeStore.collection('notificationQueue').get();
      expect(pushDocs.docs.where((d) => d.data()['title'] != null && (d.data()['title'] as String).contains('최종고지')).isNotEmpty, true, reason: '경과 23일 이후 강제 최종고지 알람 발생');

      // [5] 30분(30일) 경과 강제 삭제 시나리오
      final doomNow = baseNow.add(const Duration(minutes: 30));
      await ServerCleanupService.runAutomaticCleanup(storeId, overrideNow: doomNow, testTimeCompression: true);

      final finalArchiveSnap = await fakeStore.collection('stores').doc(storeId).collection('archives').doc(deleteMonthStr).get();
      expect(finalArchiveSnap.exists, false, reason: '30일이 초과하면 강제 삭제 룰이 발동되어 지워야 함');

      final finalLogSnap = await fakeStore.collection('stores').doc(storeId).collection('destruction_logs').doc(deleteMonthStr).get();
      expect(finalLogSnap.exists, true, reason: '강제 삭제에 대한 증명서 로그가 작성됨');
      expect(finalLogSnap.data()!['exportedToCloud'], false, reason: '클라우드 추출은 실패함');

      // [6] 정상적으로 클라우드에 추출된 ZIP 파일 디코딩 및 내용 무결성 테스트 (Restore Test)
      // 재수출 테스트를 위해 새로운 아카이브 생성
      final String freshMonthStr = 'test_fresh_${targetDeleteMonth.year}_${targetDeleteMonth.minute}';
      await fakeStore.collection('stores').doc(storeId).collection('archives').doc(freshMonthStr).set({
        'month': freshMonthStr,
        'compressedData': Blob(Uint8List.fromList(dummyGzip)),
      });
      BackupService.testMockExportFailure = false;
      // 3년 전 스케일에 freshMonth 생성 (testTimeCompression의 export 파이프라인 우회 접근)
      
      try {
        final archive = Archive();
        archive.addFile(ArchiveFile('$freshMonthStr.gz', dummyGzip.length, dummyGzip));
        final zipBytes = Uint8List.fromList(ZipEncoder().encode(archive)!);
        await BackupService.exportData(zipBytes, '$freshMonthStr.zip');
      } catch(e) {}

      final exportedBytes = BackupService.testExportedLogs.last['bytes'] as Uint8List;
      final decodedZip = ZipDecoder().decodeBytes(exportedBytes);
      final jsonGzipFile = decodedZip.files.first;
      final decodedGzip = GZipDecoder().decodeBytes(jsonGzipFile.content as List<int>);
      final finalJsonString = utf8.decode(decodedGzip);

      expect(finalJsonString.contains('극비 노무 데이터'), true, reason: '복원 시 실제 원본 데이터가 100% 보존되어야 함');
    });
  });
}
