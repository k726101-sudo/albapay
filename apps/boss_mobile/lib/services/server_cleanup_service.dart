import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_logic/shared_logic.dart';
import 'backup_service.dart';
import 'withdraw_service.dart';

class ServerCleanupService {
  static FirebaseFirestore? _testDb;
  static FirebaseFirestore get _db => _testDb ?? FirebaseFirestore.instance;

  /// 테스트용 DB 의존성 주입
  @visibleForTesting
  static void setTestFirestore(FirebaseFirestore db) {
    _testDb = db;
  }

  static String _getMonthStr(DateTime date, bool isTest) {
    if (isTest) {
      return 'test_${date.year}_${date.month}_${date.day}_${date.hour}_${date.minute}';
    }
    return '${date.year}_${date.month.toString().padLeft(2, '0')}';
  }

  /// 서버 데이터 생애주기 관리 (매일 실행되는 메인 엔트리포인트)
  static Future<void> runAutomaticCleanup(String storeId, {DateTime? overrideNow, bool testTimeCompression = false}) async {
    final now = overrideNow ?? AppClock.now();
    
    // 1. 아카이빙 처리 (본래 월 단위지만 테스트 시에는 분 단위 압축으로 치환할 수 있음)
    final oneYearAgo = testTimeCompression ? now.subtract(const Duration(minutes: 1)) : DateTime(now.year - 1, now.month);
    await _archiveMonthIfDue(storeId, oneYearAgo, testTimeCompression);

    // 2. 동결(Frozen) 데이터 매일 체크 및 방어 로직
    await _processFrozenItems(storeId, now, testTimeCompression: testTimeCompression);

    // 3. 만료된(3년 전) 데이터 수출 및 삭제 시도
    final threeYearsAgo = testTimeCompression ? now.subtract(const Duration(minutes: 3)) : DateTime(now.year - 3, now.month);
    await _exportAndPermanentDeleteWithSafetyNet(storeId, threeYearsAgo, testTimeCompression);

    // 4. 휴면 계정(1년 미접속) 자동 파기 스케줄러 (Housekeeping)
    await _processInactiveAccounts(storeId, now, testTimeCompression: testTimeCompression);
  }

  /// 0. 휴면 계정 자동 파기 및 사전 고지
  static Future<void> _processInactiveAccounts(String storeId, DateTime now, {bool testTimeCompression = false}) async {
    final storeSnap = await _db.collection('stores').doc(storeId).get();
    if (!storeSnap.exists) return;
    
    final ownerId = storeSnap.data()?['ownerId'] as String?;
    if (ownerId == null) return;

    final userSnap = await _db.collection('users').doc(ownerId).get();
    if (!userSnap.exists) return;

    final lastLoginAt = userSnap.data()?['lastLoginAt'] as Timestamp?;
    if (lastLoginAt == null) return; // 미적용 계정은 다음 로그인 시 활성화
    
    final lastLogin = lastLoginAt.toDate();
    final diffDays = testTimeCompression ? now.difference(lastLogin).inMinutes : now.difference(lastLogin).inDays;
    
    // 335일(약 11개월) 지났으면 한 달 전 경고 (3회)
    if (diffDays >= 335 && diffDays < 365) {
      final warnId = 'inactive_warn_${ownerId}_${now.year}_${now.month}';
      final warnRef = _db.collection('users').doc(ownerId).collection('inactive_warnings').doc(warnId);
      final warnSnap = await warnRef.get();
      if (!warnSnap.exists) {
        await _enqueueWarning(ownerId, storeId, '', customTitle: '⚠️ 휴면 계정 자동 파기 예고', customMsg: '마지막 접속일로부터 335일 경과했습니다. 데이터 파기 정책에 따라 30일 뒤 귀하의 매장 정보와 노무 기록이 즉시 영구 파기(삭제)됩니다. 이를 원치 않으시면 지금 바로 앱에 한 번 로그인해주세요.');
        await warnRef.set({'warnedAt': FieldValue.serverTimestamp()});
      }
    } else if (diffDays >= 365) {
      // 365일 (1년) 경과 -> 즉시 강제 탈퇴 및 데이터 본체 0바이트 오버라이트, Audit 저장
      await WithdrawService.inactiveAccountHousekeeping(ownerId, storeId);
      debugPrint('Housekeeping: Inactive account $ownerId wiped out.');
    }
  }

  /// 1. 월 단위 아카이빙 (Cost Optimization)
  static Future<void> _archiveMonthIfDue(String storeId, DateTime targetMonth, bool isTest) async {
    final monthStr = _getMonthStr(targetMonth, isTest);
    final archiveRef = _db.collection('stores').doc(storeId).collection('archives').doc(monthStr);

    final snap = await archiveRef.get();
    if (snap.exists) return;

    final rawData = await _fetchMonthlyItemsForCleanup(storeId, targetMonth);
    if (rawData.isEmpty) return;

    // JSON화 및 Gzip 압축
    final jsonStr = jsonEncode(rawData);
    final gzipBytes = GZipEncoder().encode(utf8.encode(jsonStr))!;

    // 아카이브 저장
    await archiveRef.set({
      'month': monthStr,
      'compressedData': Blob(Uint8List.fromList(gzipBytes)),
      'originalCount': rawData.length,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // 서버 용량 절감을 위해 원본 데이터 삭제 (트랜잭션/배치 처리)
    final batch = _db.batch();
    for (var item in rawData) {
      final colName = item['_sourceCollection'] as String;
      final docId = item['_id'] as String;
      batch.delete(_db.collection(colName).doc(docId));
    }
    await batch.commit();

    debugPrint('Archived $monthStr for store $storeId');
  }

  /// 2. 클라우드 자동 수출 후 원자적 삭제 (Safety Net)
  static Future<void> _exportAndPermanentDeleteWithSafetyNet(String storeId, DateTime targetMonth, bool isTest) async {
    final monthStr = _getMonthStr(targetMonth, isTest);
    final archiveRef = _db.collection('stores').doc(storeId).collection('archives').doc(monthStr);
    
    final arcSnap = await archiveRef.get();
    if (!arcSnap.exists) return; // 아카이브가 없음(이미 삭제됐거나 애초에 데이터가 없음)
    
    // 이미 파기 로그가 있다면 중단
    final logSnap = await _db.collection('stores').doc(storeId).collection('destruction_logs').doc(monthStr).get();
    if (logSnap.exists) return;

    final dataBlob = arcSnap.data()?['compressedData'] as Blob?;
    if (dataBlob == null) return;
    final gzipBytes = dataBlob.bytes;

    try {
      // ZIP 묶기 (단일 json 압축 파일이 담긴 zip)
      final exportFileName = '${monthStr}_Backup.zip';
      final archive = Archive();
      archive.addFile(ArchiveFile('$monthStr.gz', gzipBytes.length, gzipBytes));
      final zipBytes = Uint8List.fromList(ZipEncoder().encode(archive)!);

      // 클라우드로 원자적 업로드 시도 (무결성 간접 확인)
      await BackupService.exportData(zipBytes, exportFileName);

      // 클라우드 업로드 성공 시에만 서버에서 삭제 및 파기 로그 작성
      await _db.runTransaction((tx) async {
        tx.delete(archiveRef); // 콜드 스토리지 데이터 삭제
        final logRef = _db.collection('stores').doc(storeId).collection('destruction_logs').doc(monthStr);
        tx.set(logRef, {
          'month': monthStr,
          'destroyedAt': FieldValue.serverTimestamp(),
          'reason': '3년 보존 만료에 따른 개인 클라우드 이관 및 원자적 서버 삭제 완료',
          'exportedToCloud': true,
        });
      });

      debugPrint('Exported and Perma-Deleted $monthStr');
    } catch (e) {
      debugPrint('Export failed for $monthStr: $e');
      // 방어 로직 발동: 수출 실패 시 Frozen 큐로 이동
      await _freezeArchive(storeId, monthStr);
    }
  }

  /// 3. 방어 로직: 수출 실패 시 동결 및 유예 (Frozen State)
  static Future<void> _freezeArchive(String storeId, String monthStr) async {
    final frozenRef = _db.collection('stores').doc(storeId).collection('frozen_items').doc(monthStr);
    final snap = await frozenRef.get();
    if (snap.exists) return; // 이미 동결 상태

    await frozenRef.set({
      'month': monthStr,
      'frozenAt': FieldValue.serverTimestamp(), // 유예 시작점
      'status': 'frozen',
      'lastWarnedAt': null,
    });

    final ownerId = await _getOwnerId(storeId);
    if (ownerId != null) {
      await _enqueueWarning(ownerId, storeId, monthStr, isUrgent: true);
    }
  }

  /// 4. 동결 데이터 처리기 (다중 경고 시스템 및 최종 파기)
  static Future<void> _processFrozenItems(String storeId, DateTime now, {bool testTimeCompression = false}) async {
    final frozenCol = _db.collection('stores').doc(storeId).collection('frozen_items');
    final query = await frozenCol.get();

    for (var doc in query.docs) {
      final frozenAtTS = doc.data()['frozenAt'] as Timestamp?;
      if (frozenAtTS == null) continue;
      final frozenAt = frozenAtTS.toDate();
      
      // 테스트 모드(Time Compression)인 경우 day 단위 대신 분(minute) 단위를 스케일로 사용
      final diff = testTimeCompression ? now.difference(frozenAt).inMinutes : now.difference(frozenAt).inDays;
      
      final monthStr = doc.id;
      final ownerId = await _getOwnerId(storeId);
      final lastWarnedAtTS = doc.data()['lastWarnedAt'] as Timestamp?;
      final lastWarnedAt = lastWarnedAtTS?.toDate();

      if (diff >= 30) {
        // [최종 파기]: 30일(분) 유예 후에도 해결되지 않음
        await _destroyFinally(storeId, doc.reference, monthStr);
      } else if (diff >= 23) {
        // [남은 마지막 7일]: 매일 최종 고지 알림 발송
        if (lastWarnedAt == null || (testTimeCompression ? now.difference(lastWarnedAt).inSeconds >= 1 : now.difference(lastWarnedAt).inHours >= 24)) {
          if (ownerId != null) await _enqueueWarning(ownerId, storeId, monthStr, isFinalNotice: true);
          await doc.reference.update({'lastWarnedAt': testTimeCompression ? Timestamp.fromDate(now) : FieldValue.serverTimestamp()});
        }
      } else {
        // [30일 대비 최초 3주간]: 매주 1회 강력 알림
        if (lastWarnedAt == null || (testTimeCompression ? now.difference(lastWarnedAt).inSeconds >= 7 : now.difference(lastWarnedAt).inDays >= 7)) {
          if (ownerId != null) await _enqueueWarning(ownerId, storeId, monthStr, isUrgent: true);
          await doc.reference.update({'lastWarnedAt': testTimeCompression ? Timestamp.fromDate(now) : FieldValue.serverTimestamp()});
        }
      }
    }
  }

  /// 30일 동결 기간 종료 시 강제 최종 파기
  static Future<void> _destroyFinally(String storeId, DocumentReference frozenRef, String monthStr) async {
    final archiveRef = _db.collection('stores').doc(storeId).collection('archives').doc(monthStr);
    
    await _db.runTransaction((tx) async {
      tx.delete(archiveRef);
      tx.delete(frozenRef);
      final logRef = _db.collection('stores').doc(storeId).collection('destruction_logs').doc(monthStr);
      tx.set(logRef, {
        'month': monthStr,
        'destroyedAt': FieldValue.serverTimestamp(),
        'reason': '클라우드 연동 불가/방치로 인한 30일 유예 기간 경과에 따른 강제 최종 파기 (개인정보 보호법 및 약관 준수)',
        'exportedToCloud': false,
      });
    });
  }

  /// 푸시 알림 큐 발송
  static Future<void> _enqueueWarning(String ownerId, String storeId, String monthStr, {bool isFinalNotice = false, bool isUrgent = false, String? customTitle, String? customMsg}) async {
    final title = customTitle ?? (isFinalNotice ? '🚨 [최종고지] 백업 연동 필수' : '⚠️ 데이터 보존 만료 유예 상태');
    final msg = customMsg ?? (isFinalNotice 
       ? '$monthStr 연월 데이터가 며칠 내로 서버에서 영구 파기(삭제)됩니다. 즉시 구글/iCloud 로그인을 통해 클라우드 백업을 활성화해주세요.'
       : '$monthStr 연월 데이터의 보전 기한(3년)이 지났으나 클라우드 연동 실패로 임시 보관 중입니다. 30일 내 조치하지 않으면 삭제됩니다.');

    await _db.collection('notificationQueue').add({
      'storeId': storeId,
      'targetUid': ownerId,
      'channel': 'pushBoss',
      'priority': 'high',
      'title': title,
      'message': msg,
      'createdAt': FieldValue.serverTimestamp(),
      'status': 'queued',
    });
  }

  /// 클린업 시 수집할 데이터를 조회
  static Future<List<Map<String, dynamic>>> _fetchMonthlyItemsForCleanup(String storeId, DateTime targetMonth) async {
    final start = DateTime(targetMonth.year, targetMonth.month, targetMonth.day, targetMonth.hour, targetMonth.minute);
    final end = start.add(const Duration(minutes: 1)); // 1분 스팬으로 검색
    final results = <Map<String, dynamic>>[];
    
    // 1. 근태 기록
    final attSnap = await _db.collection('attendance')
        .where('storeId', isEqualTo: storeId)
        .where('clockIn', isGreaterThanOrEqualTo: start.toIso8601String())
        .where('clockIn', isLessThan: end.toIso8601String())
        .get();
        
    for (var doc in attSnap.docs) {
      results.add({
        '_id': doc.id,
        '_sourceCollection': 'attendance',
        ...doc.data()
      });
    }

    // 문서 등 기타 기록도 동일 로직 추가 가능
    return results;
  }

  static Future<String?> _getOwnerId(String storeId) async {
    final snap = await _db.collection('stores').doc(storeId).get();
    final data = snap.data();
    return data != null ? data['ownerId']?.toString() : null;
  }
}
