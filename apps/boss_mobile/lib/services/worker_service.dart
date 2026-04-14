import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:shared_logic/shared_logic.dart';

import '../models/worker.dart';
import 'store_cache_service.dart';

class WorkerService {
  static final _hiveBox = Hive.box<Worker>('workers');
  static final _firestore = FirebaseFirestore.instance;
  static StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;

  /// 직원 초대용 6자리 코드 생성 (헷갈리기 쉬운 글자 제외)
  /// 예: `A7B2X9`
  static String _generateInviteCode() {
    const letters = 'ABCDEFGHJKLMNPRSTUVWXYZ'; // I, O 제외
    const digits = '23456789'; // 0, 1 제외
    const alphabet = '$letters$digits';

    final rnd = Random.secure();
    final buf = List<String>.generate(
      6,
      (_) => alphabet[rnd.nextInt(alphabet.length)],
      growable: false,
    );
    return buf.join();
  }

  static Future<String> _resolveStoreId() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return '';
    final snap = await _firestore.collection('users').doc(uid).get();
    final sid = snap.data()?['storeId'];
    return sid is String ? sid.trim() : '';
  }

  /// 근무표 Firestore 동기화 등에 사용
  static Future<String> resolveStoreId() => _resolveStoreId();

  static Future<void> save(Worker worker) async {
    // 주 15시간 기준 자동 판정은 "순수 근로시간(휴게 제외)"만 사용
    final pureWeeklyHours = worker.pureLaborMinutes / 60.0;
    worker.weeklyHours = pureWeeklyHours;
    worker.weeklyHolidayPay = pureWeeklyHours >= 15;

    final existing = _hiveBox.get(worker.id);
    final isNew = existing == null;

    // 중복 등록 방지: "재직(active) + 이름/연락처 동일" 직원이 있으면 신규 저장 차단
    if (isNew) {
      final normalizedName = worker.name.trim();
      final normalizedPhone = worker.phone.replaceAll(RegExp(r'[^0-9]'), '');
      final duplicated = _hiveBox.values.any((w) {
        if (w.id == worker.id || w.status != 'active') return false;
        final nameSame = w.name.trim() == normalizedName;
        final phoneSame =
            w.phone.replaceAll(RegExp(r'[^0-9]'), '') == normalizedPhone;
        return nameSame && phoneSame && normalizedName.isNotEmpty;
      });
      if (duplicated) {
        throw StateError('동일한 이름/연락처의 재직자가 이미 등록되어 있습니다.');
      }
    }

    await _hiveBox.put(worker.id, worker);

    final storeId = await _resolveStoreId();
    if (storeId.isEmpty) return;

    try {
      // 초대 코드(inviteCode) 관리: 모델에 이미 있으면 그것을 쓰고, 없으면 새로 생성
      var effectiveInviteCode = worker.inviteCode?.trim() ?? '';
      
      if (effectiveInviteCode.isEmpty) {
        // Firestore에서 한 번 더 확인 (로컬 Hive에만 없을 수도 있으므로)
        try {
          final doc = await _firestore
              .collection('stores')
              .doc(storeId)
              .collection('workers')
              .doc(worker.id)
              .get();
          final remoteCode = doc.data()?['inviteCode']?.toString().trim() ?? '';
          if (remoteCode.isNotEmpty) {
            effectiveInviteCode = remoteCode;
          }
        } catch (_) {}
      }

      if (effectiveInviteCode.isEmpty) {
        effectiveInviteCode = _generateInviteCode();
        debugPrint('[WorkerService] Generated NEW inviteCode for ${worker.name}: $effectiveInviteCode');
      }

      // 모델 업데이트 및 로컬 저장 (이후 toMap() 시 Firestore에 포함됨)
      worker.inviteCode = effectiveInviteCode;
      await _hiveBox.put(worker.id, worker);
      
      final firebaseMap = worker.toMap();
      firebaseMap['weeklyHolidayPay'] = worker.weeklyHolidayPay;

      // invites 컬렉션에 역방향 인덱스 생성/유지
      await _firestore.collection('invites').doc(effectiveInviteCode).set({
        'storeId': storeId,
        'workerId': worker.id,
        'staffName': worker.name,
        'baseWage': worker.hourlyWage,
        'createdAt': FieldValue.serverTimestamp(),
        'usedAt': null,
      }, SetOptions(merge: true));

      if (isNew) {
        firebaseMap['status'] = 'active';
        firebaseMap['createdAt'] = FieldValue.serverTimestamp();
      }

      await _firestore
          .collection('stores')
          .doc(storeId)
          .collection('workers')
          .doc(worker.id)
          .set(firebaseMap);
    } catch (e) {
      debugPrint('Firebase sync failed: $e');
    }

    // 신규 직원 또는 문서 미초기화인 경우, 노무 서류 자동 생성 (보건증 전용 인원은 제외)
    if ((isNew || worker.documentsInitialized == false) && worker.status != 'health_only') {
      try {
        await _initDocuments(worker, storeId);
      } catch (e) {
        debugPrint('[_initDocuments] failed: $e');
        rethrow;
      }
    }
  }

  static int _timeToMinutes(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length != 2) return 0;
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    return h * 60 + m;
  }

  static String _weekdayLabel(int weekday) {
    // Worker day code 기준 (0=일 ... 6=토)로도 동작하게 처리합니다.
    if (weekday == 0) return '일';
    if (weekday == DateTime.monday) return '월';
    if (weekday == DateTime.tuesday) return '화';
    if (weekday == DateTime.wednesday) return '수';
    if (weekday == DateTime.thursday) return '목';
    if (weekday == DateTime.friday) return '금';
    if (weekday == DateTime.saturday) return '토';
    if (weekday == DateTime.sunday) return '일';
    return '';
  }

  static String _workingDaysText(Worker worker) {
    if (worker.workDays.isEmpty) return '별도 협의';
    final sorted = [...worker.workDays]..sort();
    return sorted.map(_weekdayLabel).join('·');
  }

  static String _workingHoursText(Worker worker) {
    if (worker.workDays.isEmpty) return '별도 협의';

    // 요일별 출퇴근이 그룹 단위(workScheduleJson)로 저장될 수 있어서, day -> (start,end) 매핑을 풀어줍니다.
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

    final breakRange = _resolvedBreakRange(worker);
    final breakInline = breakRange != null
        ? '${breakRange.start}~${breakRange.end}'
        : '${worker.breakMinutes.toInt()}분';

    const order = [1, 2, 3, 4, 5, 6, 0]; // 월..일
    final lines = <String>[];
    for (final day in order) {
      if (!worker.workDays.contains(day)) continue;
      final t = dayToTime[day];
      final start = t?.start ?? worker.checkInTime;
      final end = t?.end ?? worker.checkOutTime;
      lines.add('${_weekdayLabel(day)} $start~$end(휴게시간 $breakInline)');
    }
    return lines.join('\n');
  }

  static String _breakTimeText(Worker worker) {
    final minutes = worker.breakMinutes.toInt();
    final paidLabel = worker.isPaidBreak ? '유급' : '무급(원칙)';

    final range = _resolvedBreakRange(worker);
    final hasRange = range != null;
    if (minutes <= 0 && !hasRange) return '없음';
    if (hasRange) {
      return '${range.start} ~ ${range.end} ($minutes분) / $paidLabel';
    }
    return '일 $minutes분 / $paidLabel';
  }

  static String _breakClauseText(Worker worker) {
    final minutes = worker.breakMinutes.toInt();
    if (minutes <= 0 &&
        (worker.breakStartTime.isEmpty || worker.breakEndTime.isEmpty)) {
      return '휴게시간 없음';
    }

    final range = _resolvedBreakRange(worker);
    final hasRange = range != null;
    if (hasRange) {
      return '${range.start}~${range.end} 중 휴게 $minutes분';
    }
    return '휴게 $minutes분';
  }

  static ({String start, String end})? _resolvedBreakRange(Worker worker) {
    final minutes = worker.breakMinutes.toInt();
    if (minutes <= 0) return null;
    if (worker.breakStartTime.isNotEmpty && worker.breakEndTime.isNotEmpty) {
      return (start: worker.breakStartTime, end: worker.breakEndTime);
    }
    final start = _autoBreakStart(worker.checkInTime, worker.checkOutTime, minutes);
    if (start == null) return null;
    return (start: start, end: _addMinutesToHm(start, minutes));
  }

  static String? _autoBreakStart(String checkIn, String checkOut, int breakMinutes) {
    final total = _durationMinutes(checkIn, checkOut);
    if (total <= 0) return null;
    final inMinutes = _timeToMinutes(checkIn);
    final offset = ((total - breakMinutes).clamp(0, total) / 2).round();
    return _minutesToHm(inMinutes + offset);
  }

  static String _minutesToHm(int minutes) {
    final normalized = ((minutes % (24 * 60)) + (24 * 60)) % (24 * 60);
    final hh = (normalized ~/ 60).toString().padLeft(2, '0');
    final mm = (normalized % 60).toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  static int _durationMinutes(String start, String end) {
    return _timeToMinutes(end) - _timeToMinutes(start);
  }

  static String _addMinutesToHm(String startHm, int deltaMinutes) {
    return _minutesToHm(_timeToMinutes(startHm) + deltaMinutes);
  }

  static String _formatOptionalDate(DateTime? date) {
    if (date == null) return '미정';
    return date.toString().length >= 10 ? date.toString().substring(0, 10) : date.toString();
  }

  static Future<void> _initDocuments(Worker worker, String storeId) async {
    final contractType = worker.weeklyHours >= 40
        ? DocumentType.contract_full
        : DocumentType.contract_part;

    List<Map<String, String>> docs = [
      {
        'type': contractType.name,
        'title': contractType == DocumentType.contract_full
            ? '표준 근로계약서'
            : '근로계약서 (단시간)',
      },
      {'type': DocumentType.checklist.name, 'title': '채용 체크리스트'},
      {'type': DocumentType.worker_record.name, 'title': '근로자 명부'},
    ];

    docs.add({
      'type': DocumentType.night_consent.name,
      'title': '휴일·야간근로 동의서',
    });

    // 파견직은 계약서/명부 제외하고 체크리스트만 생성
    if (worker.workerType == 'dispatch') {
      docs = [
        {'type': DocumentType.checklist.name, 'title': '채용 체크리스트'}
      ];
    }

    final batch = _firestore.batch();
    for (final doc in docs) {
      final docType = DocumentType.values.byName(doc['type']!);
      final docId = '${worker.id}_${docType.name}';
      final docRef = _firestore
          .collection('stores')
          .doc(storeId)
          .collection('documents')
          .doc(docId);

      final weeklyHolidayText = worker.weeklyHolidayPay
          ? '[유급] ${_weekdayLabel(worker.weeklyHolidayDay)}요일'
          : '[무급] ${_weekdayLabel(worker.weeklyHolidayDay)}요일 (초단시간 근로)';

      final dispatchCompany =
          worker.workerType == 'dispatch' ? (worker.dispatchCompany ?? '-') : '-';
      final dispatchContact =
          worker.workerType == 'dispatch' ? (worker.dispatchContact ?? '-') : '-';
      final dispatchMemo =
          worker.workerType == 'dispatch' ? (worker.dispatchMemo ?? '-') : '-';
      final dispatchPeriod = worker.workerType == 'dispatch'
          ? '${_formatOptionalDate(DateTime.tryParse(worker.dispatchStartDate ?? ''))} ~ ${_formatOptionalDate(DateTime.tryParse(worker.dispatchEndDate ?? ''))}'
          : '해당 없음';

      final now = AppClock.now();
      final todayStr = '${now.year}년 ${now.month.toString().padLeft(2, '0')}월 ${now.day.toString().padLeft(2, '0')}일';

      String content;
      switch (docType) {
        case DocumentType.contract_full:
        case DocumentType.contract_part:
          content = DocumentTemplates.getLaborContract({
            'contractDate': todayStr,
            'startDate': now.toString().substring(0, 10),
            'storeName': '본 매장',
            'jobDescription': '매장 관리 및 고객 응대',
            'workingHours': _workingHoursText(worker),
            'breakTime': _breakTimeText(worker),
            'breakClause': _breakClauseText(worker),
            'breakPaidClause': worker.isPaidBreak
                ? '\n   - 휴게시간 중 업무 수행 시 해당 시간만큼 시급을 가산하여 지급한다.'
                : '',
            'workingDays': _workingDaysText(worker),
            'weeklyHoliday': weeklyHolidayText,
            'dispatchCompany': dispatchCompany,
            'dispatchPeriod': dispatchPeriod,
            'dispatchContact': dispatchContact,
            'dispatchMemo': dispatchMemo,
            'baseWage': worker.hourlyWage.toStringAsFixed(0),
            'payday': '10',
            'ownerName': '대표자',
            'staffName': worker.name,
          });
          break;
        case DocumentType.night_consent:
          content = DocumentTemplates.getNightHolidayConsent(worker.name, consentDate: todayStr);
          break;
        case DocumentType.worker_record:
          final birth = worker.birthDate.isEmpty ? '19XX-XX-XX' : worker.birthDate;
          final hireDate = worker.startDate.isEmpty
              ? AppClock.now().toString().substring(0, 10)
              : worker.startDate.substring(0, worker.startDate.length >= 10 ? 10 : worker.startDate.length);
          final contractPeriod =
              worker.weeklyHours >= 40 ? '정규직' : '단시간';
          content = DocumentTemplates.getEmployeeRegistry({
            'name': worker.name,
            'birthDate': birth,
            'address': '별도 기재',
            'hireDate': hireDate,
            'job': '매장 스태프',
            'contractPeriod': contractPeriod,
          });
          break;
        case DocumentType.checklist:
          content = '채용 체크리스트는 앱 내 항목을 기준으로 작성하세요.';
          break;
        default:
          content = '';
      }

      final laborDoc = LaborDocument(
        id: docId,
        staffId: worker.id,
        storeId: storeId,
        type: docType,
        status: 'draft',
        title: doc['title'] ?? '',
        content: content,
        createdAt: AppClock.now(),
      );

      batch.set(docRef, laborDoc.toMap());
    }

    await batch.commit();

    worker.documentsInitialized = true;
    await _hiveBox.put(worker.id, worker);

    // 문서 초기화 상태를 Firebase worker에도 반영
    try {
      await _firestore
          .collection('stores')
          .doc(storeId)
          .collection('workers')
          .doc(worker.id)
          .set(worker.toMap(), SetOptions(merge: true)); // ← inviteCode 등 기존 필드 보존
    } catch (_) {}
  }

  static List<Worker> getAll() {
    return _hiveBox.values
        .where((w) => w.status == 'active')
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  static List<Worker> getForHealthManagement() {
    return _hiveBox.values
        .where((w) => w.status == 'active' || w.status == 'health_only')
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  static Worker? getById(String id) => _hiveBox.get(id);

  static Future<void> deactivate(String workerId, String exitDate) async {
    final worker = _hiveBox.get(workerId);
    if (worker == null) return;
    worker.status = 'inactive';
    worker.endDate = exitDate;
    await save(worker);

    // 레거시 staff 컬렉션도 종료 처리하여 앱 재시작 시 재마이그레이션을 방지합니다.
    try {
      await _firestore.collection('staff').doc(workerId).set({
        'terminatedAt': exitDate,
        'status': 'inactive',
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  static Future<void> hardDelete(String workerId) async {
    final storeId = await _resolveStoreId();
    if (storeId.isEmpty) {
      // 매장 ID를 못 찾으면 로컬이라도 먼저 지웁니다.
      await _hiveBox.delete(workerId);
      return;
    }

    // 1) Firestore 삭제
    try {
      // 초대장 있을 수 있으니 조회 후 삭제 (선택 사항이지만 깔끔한 정리를 위해)
      final worker = _hiveBox.get(workerId);
      if (worker != null) {
        // inviteCode가 있다면 invites 컬렉션에서도 삭제 시도
        // (worker 모델에 inviteCode가 들어있을 때만 가능)
      }

      await _firestore
          .collection('stores')
          .doc(storeId)
          .collection('workers')
          .doc(workerId)
          .delete();
          
      // 레거시 staff 삭제
      await _firestore.collection('staff').doc(workerId).delete();
    } catch (e) {
      debugPrint('[WorkerService] Firestore delete failed: $e');
    }

    // 2) 로컬 Hive 삭제
    await _hiveBox.delete(workerId);
  }

  static Future<void> reactivate(String workerId) async {
    final worker = _hiveBox.get(workerId);
    if (worker == null) return;
    worker.status = 'active';
    worker.endDate = null;
    await save(worker);

    // 레거시 staff 컬렉션도 active로 정리
    try {
      await _firestore.collection('staff').doc(workerId).set({
        'terminatedAt': null,
        'status': 'active',
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  static Future<void> syncFromFirebase() async {
    await StoreCacheService.ensureLocalCacheBelongsToCurrentUser();
    final storeId = await _resolveStoreId();
    if (storeId.isEmpty) return;
    try {
      final snapshot = await _firestore
          .collection('stores')
          .doc(storeId)
          .collection('workers')
          .get();
      // Firestore 스냅샷과 Hive를 1:1로 맞춤 — 이전 매장 직원 키가 남지 않게 전부 비운 뒤 채움.
      await _hiveBox.clear();
      for (final doc in snapshot.docs) {
        final worker = Worker.fromMap(doc.id, doc.data());
        await _hiveBox.put(doc.id, worker);
      }
    } catch (e) {
      debugPrint('Sync failed: $e');
    }
  }

  /// 로그아웃 시 호출 — 이전 매장 Firestore 스트림이 Hive를 덮어쓰지 않도록 합니다.
  static Future<void> stopRealtimeSync() async {
    await _sub?.cancel();
    _sub = null;
  }

  static Future<void> startRealtimeSync() async {
    await _sub?.cancel();
    await StoreCacheService.ensureLocalCacheBelongsToCurrentUser();
    final storeId = await _resolveStoreId();
    if (storeId.isEmpty) return;
    _sub = _firestore
        .collection('stores')
        .doc(storeId)
        .collection('workers')
        .snapshots()
        .listen((snapshot) async {
      final ids = snapshot.docs.map((d) => d.id).toSet();
      for (final key in _hiveBox.keys.toList()) {
        final id = key is String ? key : key.toString();
        if (!ids.contains(id)) {
          await _hiveBox.delete(id);
        }
      }
      for (final doc in snapshot.docs) {
        final worker = Worker.fromMap(doc.id, doc.data());
        await _hiveBox.put(doc.id, worker);
      }
    });
  }

  static Future<void> enqueueProbationEndingAlerts() async {
    final storeId = await _resolveStoreId();
    if (storeId.isEmpty) return;
    final ownerUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (ownerUid.isEmpty) return;

    final today = AppClock.now();
    final todayKey = DateTime(today.year, today.month, today.day);
    for (final worker in _hiveBox.values) {
      if (worker.status != 'active' || !worker.isProbation || worker.probationMonths <= 0) {
        continue;
      }
      final start = DateTime.tryParse(worker.startDate);
      if (start == null) continue;
      final probationEnd = DateTime(start.year, start.month + worker.probationMonths, start.day);
      final diffDays = DateTime(probationEnd.year, probationEnd.month, probationEnd.day)
          .difference(todayKey)
          .inDays;
      if (diffDays != 7) continue;

      final keyDate =
          '${todayKey.year}${todayKey.month.toString().padLeft(2, '0')}${todayKey.day.toString().padLeft(2, '0')}';
      final queueId = '${worker.id}_probation_end_$keyDate';
      await _firestore.collection('notificationQueue').doc(queueId).set({
        'dedupeKey': queueId,
        'storeId': storeId,
        'channel': 'pushBoss',
        'targetUid': ownerUid,
        'status': 'queued',
        'message': '${worker.name}님 수습 기간이 7일 후 종료됩니다',
        'type': 'probationEnding',
        'workerId': worker.id,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  static Future<void> migrateStaffToWorker() async {
    final storeId = await _resolveStoreId();
    if (storeId.isEmpty) return;
    try {
      final oldSnapshot = await _firestore.collection('staff').where('storeId', isEqualTo: storeId).get();
      for (final doc in oldSnapshot.docs) {
        final data = doc.data();
        final terminatedAt = data['terminatedAt']?.toString();
        if (terminatedAt != null && terminatedAt.trim().isNotEmpty) continue;

        // 이미 workers에 존재하는 직원은 마이그레이션으로 덮어쓰지 않습니다.
        // (퇴사 처리(inactive) 상태가 재기입되는 문제 방지)
        final existingHive = _hiveBox.get(doc.id);
        if (existingHive != null) continue;
        final existingRemote = await _firestore
            .collection('stores')
            .doc(storeId)
            .collection('workers')
            .doc(doc.id)
            .get();
        if (existingRemote.exists) continue;

        final worker = Worker(
          id: doc.id,
          name: data['name']?.toString() ?? '',
          phone: data['phoneNumber']?.toString() ?? '',
          birthDate: '',
          workerType: data['employeeType']?.toString() ?? 'regular',
          hourlyWage: (data['baseWage'] as num?)?.toDouble() ?? 10320,
          isPaidBreak: data['isBreakPaid'] == true,
          breakMinutes: (data['breakMinutesPerDay'] as num?)?.toDouble() ?? 0,
          workDays: (data['contractedDays'] as List?)
                  ?.map((e) => e is num ? e.toInt() : int.tryParse(e.toString()) ?? 0)
                  .toList() ??
              const [],
          checkInTime: data['workStartTime']?.toString() ?? '09:00',
          checkOutTime: data['workEndTime']?.toString() ?? '18:00',
          weeklyHours: (data['workingHoursPerDay'] as num?)?.toDouble() ?? 0,
          startDate: data['hireDate']?.toString() ?? '',
          endDate: data['terminatedAt']?.toString(),
          isProbation: data['applyProbationWage90Percent'] == true,
          probationMonths: 3,
          allowances: const [],
          hasHealthCert: data['hasHealthCertificate'] == true,
          healthCertExpiry: data['healthCertificateExpiryDate']?.toString(),
          visaType: data['visaType']?.toString(),
          visaExpiry: data['visaExpiryDate']?.toString(),
          weeklyHolidayPay: data['weeklyHolidayPayEnabled'] != false,
          status: data['terminatedAt'] == null ? 'active' : 'inactive',
          createdAt: AppClock.now().toIso8601String(),
          storeId: storeId,
          firebaseId: doc.id,
          compensationIncomeType: 'labor',
          deductNationalPension: true,
          deductHealthInsurance: true,
          deductEmploymentInsurance: true,
          trackIndustrialInsurance: false,
          applyWithholding33: false,
          workScheduleJson: '',
          breakStartTime: '',
          breakEndTime: '',
        );
        await save(worker);
      }
    } catch (e) {
      debugPrint('Migration failed: $e');
    }
  }

  /// 모든 직원의 누락된 inviteCode를 Firestore 'invites' 컬렉션 기준으로 찾아 일괄 복구합니다.
  static Future<int> backfillAllInviteCodes() async {
    final storeId = await _resolveStoreId();
    if (storeId.isEmpty) return 0;

    int fixedCount = 0;
    try {
      final invitesSnap = await _firestore
          .collection('invites')
          .where('storeId', isEqualTo: storeId)
          .get();

      for (var doc in invitesSnap.docs) {
        final data = doc.data();
        final inviteCode = doc.id;
        final workerId = data['workerId']?.toString();

        if (workerId == null) continue;

        final workerRef = _firestore
            .collection('stores')
            .doc(storeId)
            .collection('workers')
            .doc(workerId);

        final workerDoc = await workerRef.get();
        if (workerDoc.exists) {
          final existingCode = workerDoc.data()?['inviteCode']?.toString() ?? '';
          if (existingCode.isEmpty) {
            await workerRef.set({
              'inviteCode': inviteCode,
            }, SetOptions(merge: true));
            
            // 로컬 Hive도 업데이트
            final localWorker = _hiveBox.get(workerId);
            if (localWorker != null) {
              localWorker.inviteCode = inviteCode;
              await _hiveBox.put(workerId, localWorker);
            }
            fixedCount++;
            debugPrint('[WorkerService] Bulk fix applied: $workerId -> $inviteCode');
          }
        }
      }
    } catch (e) {
      debugPrint('[WorkerService] Bulk backfill failed: $e');
      rethrow;
    }
    return fixedCount;
  }
}
