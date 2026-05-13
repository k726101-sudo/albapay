import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/attendance_model.dart';
import '../utils/app_clock.dart';

/// Firestore에 테스트용 직원·근무표·출퇴근 샘플을 넣습니다. (디버그 전용에서 호출)
class TestDataSeeder {
  TestDataSeeder(this._db);

  final FirebaseFirestore _db;

  static const _workerPrefix = 'dbg_w';
  static const _inviteCodes = [
    'TST001',
    'TST002',
    'TST003',
    'TST004',
    'TST005',
  ];

  /// 직원 5명, 이번 주 rosterDays, 지난주 attendance 20건.
  Future<void> seed({required String storeId}) async {
    final now = AppClock.now();
    final today = DateTime(now.year, now.month, now.day);
    final thisMonday = today.subtract(Duration(days: today.weekday - 1));
    final lastMonday = thisMonday.subtract(const Duration(days: 7));

    final batch = _db.batch();

    for (var i = 0; i < 5; i++) {
      final id = '$_workerPrefix${i + 1}';
      final invite = _inviteCodes[i];
      final workerData = <String, dynamic>{
        'name': '테스트알바${i + 1}',
        // dbg_w1 은 알바 빠른 로그인(01000000001)과 맞춤
        'phone': i == 0
            ? '01000000001'
            : '0100000${(1000 + i).toString().padLeft(4, '0')}',
        'birthDate': '1999-01-0${i + 1}',
        'workerType': 'regular',
        'hourlyWage': 10000,
        'isPaidBreak': true,
        'breakMinutes': 60,
        'workDays': [1, 2, 3, 4, 5],
        'checkInTime': '09:00',
        'checkOutTime': '18:00',
        'weeklyHours': 40,
        'startDate': '${now.year}-01-01',
        'joinDate': '${now.year}-01-01',
        'isProbation': false,
        'probationMonths': 0,
        'allowances': <Map<String, dynamic>>[],
        'hasHealthCert': true,
        'weeklyHolidayPay': true,
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
        'storeId': storeId,
        'inviteCode': invite,
        'documentsInitialized': true,
        'weeklyHolidayDay': 0,
        'totalStayMinutes': 0,
        'pureLaborMinutes': 0,
        'compensationIncomeType': 'labor',
      };

      batch.set(
        _db.collection('stores').doc(storeId).collection('workers').doc(id),
        workerData,
        SetOptions(merge: true),
      );

      batch.set(_db.collection('invites').doc(invite), {
        'storeId': storeId,
        'workerId': id,
        'staffName': '테스트알바${i + 1}',
        'baseWage': 10000,
        'createdAt': FieldValue.serverTimestamp(),
        'usedAt': null,
      }, SetOptions(merge: true));
    }

    await batch.commit();

    // 이번 주 평일 rosterDays (월~금 × 직원, 동일 시간 명시)
    var rosterBatch = _db.batch();
    var rosterOps = 0;
    for (var w = 1; w <= 5; w++) {
      final wid = '$_workerPrefix$w';
      for (var d = 0; d < 5; d++) {
        final day = thisMonday.add(Duration(days: d));
        final ymd =
            '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
        final ref = _db
            .collection('stores')
            .doc(storeId)
            .collection('workers')
            .doc(wid)
            .collection('rosterDays')
            .doc(ymd);
        rosterBatch.set(ref, {
          'date': ymd,
          'checkIn': '09:00',
          'checkOut': '18:00',
          'updatedAt': FieldValue.serverTimestamp(),
        });
        rosterOps++;
        if (rosterOps >= 450) {
          await rosterBatch.commit();
          rosterBatch = _db.batch();
          rosterOps = 0;
        }
      }
    }
    if (rosterOps > 0) {
      await rosterBatch.commit();
    }

    // 지난주 출퇴근 20건
    final rnd = Random(42);
    final attBatch = _db.batch();
    for (var i = 0; i < 20; i++) {
      final day = lastMonday.add(Duration(days: i % 7));
      final wid = '$_workerPrefix${(i % 5) + 1}';
      final startMin = 9 * 60 + rnd.nextInt(60);
      final durMin = 420 + rnd.nextInt(120);
      final inDt = day.add(Duration(minutes: startMin));
      final outDt = inDt.add(Duration(minutes: durMin));
      final id = 'dbg_seed_att_${storeId}_$i';
      final att = Attendance(
        id: id,
        staffId: wid,
        storeId: storeId,
        clockIn: inDt,
        clockOut: outDt,
        originalClockIn: inDt,
        originalClockOut: outDt,
        isAutoApproved: true,
        type: AttendanceType.web,
        attendanceStatus: 'Normal',
        scheduledShiftStartIso: DateTime(
          day.year,
          day.month,
          day.day,
          9,
          0,
        ).toIso8601String(),
        scheduledShiftEndIso: DateTime(
          day.year,
          day.month,
          day.day,
          18,
          0,
        ).toIso8601String(),
        overtimeApproved: false,
      );
      attBatch.set(_db.collection('attendance').doc(id), att.toJson());
    }
    await attBatch.commit();
  }

  /// [통합 테스트용 & 체험 모드용]
  /// 가상 직원의 출퇴근 기록 40일치와 필수 노무 서류 5종을 자동으로 생성합니다.
  static Future<void> generateVirtualWorkerAttendances({
    required String storeId,
    List<Map<String, dynamic>>? workersData,
  }) async {
    final now = AppClock.now();
    final db = FirebaseFirestore.instance;

    List<Map<String, dynamic>> targetWorkers = [];

    if (workersData != null && workersData.isNotEmpty) {
      targetWorkers = workersData;
    } else {
      // 체험 매장의 모든 직원 조회 (Fallback)
      final workersSnap = await db
          .collection('stores')
          .doc(storeId)
          .collection('workers')
          .get();
      if (workersSnap.docs.isEmpty) return;
      targetWorkers = workersSnap.docs
          .map((d) => {...d.data(), 'id': d.id})
          .toList();
    }

    final startDay = now.subtract(const Duration(days: 400));
    var batch = db.batch();
    var ops = 0;

    for (var worker in targetWorkers) {
      final workerId = worker['id']?.toString() ?? '';
      if (workerId.isEmpty) continue;

      final workDays =
          (worker['workDays'] as List<dynamic>?)
              ?.map((e) => e as int)
              .toList() ??
          [];
      if (workDays.isEmpty) continue;

      final inTimeStr =
          worker['checkInTime']?.toString() ??
          worker['in']?.toString() ??
          '09:00';
      final outTimeStr =
          worker['checkOutTime']?.toString() ??
          worker['out']?.toString() ??
          '18:00';

      for (int i = 0; i <= 400; i++) {
        final d = startDay.add(Duration(days: i));

        // 오늘보다 미래의 날짜는 제외
        if (DateTime(
          d.year,
          d.month,
          d.day,
        ).isAfter(DateTime(now.year, now.month, now.day)))
          continue;

        // 요일 매칭 확인 (일=0, 월~토=1~6)
        final baseDay = d.weekday == DateTime.sunday ? 0 : d.weekday;
        if (!workDays.contains(baseDay)) continue;

        final inParts = inTimeStr.split(':');
        final outParts = outTimeStr.split(':');
        final inH = int.tryParse(inParts[0]) ?? 9;
        final inM = inParts.length > 1 ? int.tryParse(inParts[1]) ?? 0 : 0;
        final outH = int.tryParse(outParts[0]) ?? 18;
        final outM = outParts.length > 1 ? int.tryParse(outParts[1]) ?? 0 : 0;

        final inDt = DateTime(d.year, d.month, d.day, inH, inM);
        var outDt = DateTime(d.year, d.month, d.day, outH, outM);
        if (!outDt.isAfter(inDt)) outDt = outDt.add(const Duration(days: 1));

        // [개선] 현재 시간이 출퇴근 시간 사이에 있는지 체크하여 리얼한 '근무 중' 상태 구현
        final isCurrentlyWorking = now.isAfter(inDt) && now.isBefore(outDt);

        // [시나리오 주입] 가상 직원별 엣지 케이스 시나리오 (4월 정산 기준 고정 날짜)
        String status = isCurrentlyWorking ? 'Working' : 'Normal';
        final dateKey = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
        
        // 시나리오 B (worker_b, 가상 이주간): 4/14(화)~16(목) 연차 3일 연속 사용
        if (workerId == 'worker_b' && d.year == now.year &&
            (dateKey == '${now.year}-04-14' || dateKey == '${now.year}-04-15' || dateKey == '${now.year}-04-16')) {
          status = 'Leave'; // 연차 상태로 기록
        }
        
        // 시나리오 C (worker_c, 가상 박오전): 4/7(화)~8(수) 이틀 무단 결근
        if (workerId == 'worker_c' && d.year == now.year &&
            (dateKey == '${now.year}-04-07' || dateKey == '${now.year}-04-08')) {
          continue; // 출근 기록 자체를 생성하지 않아 결근(스케줄 누락)으로 처리되도록 유도
        }

        // [수정] attendance가 최상위(Root) 컬렉션이므로, 동일한 workerId를 가진 다른 체험 사용자의 기존 문서를
        // 덮어쓰려다 Permission Denied 가 발생하는 것을 방지하기 위해 ID에 storeId를 해시로 붙임
        final shortStoreId = storeId.length > 10
            ? storeId.substring(storeId.length - 8)
            : storeId;
        final attId =
            'dbg_val_${workerId}_${d.toIso8601String().substring(0, 10)}_$shortStoreId';

        final att = Attendance(
          id: attId,
          staffId: workerId,
          storeId: storeId,
          clockIn: inDt,
          clockOut: isCurrentlyWorking
              ? null
              : outDt, // 오늘이고 첫번째 직원이면 퇴근 안함 (당일 근무중 표시)
          originalClockIn: inDt,
          originalClockOut: isCurrentlyWorking ? null : outDt,
          isAutoApproved: true,
          type: AttendanceType.web,
          attendanceStatus: status, // 시나리오가 반영된 상태값 할당
          scheduledShiftStartIso: inDt.toIso8601String(),
          scheduledShiftEndIso: outDt.toIso8601String(),
          overtimeApproved: false,
        );

        final attJson = att.toJson();
        // DatabaseService queries use Strings (start.toIso8601String()),
        // so we MUST write Strings here to match the index.
        attJson['clockIn'] = inDt.toIso8601String();
        if (!isCurrentlyWorking) attJson['clockOut'] = outDt.toIso8601String();
        attJson['originalClockIn'] = inDt.toIso8601String();
        if (!isCurrentlyWorking)
          attJson['originalClockOut'] = outDt.toIso8601String();

        batch.set(
          db.collection('attendance').doc(attId),
          attJson,
          SetOptions(merge: true),
        );
        ops++;

        if (ops >= 400) {
          await batch.commit();
          batch = db.batch();
          ops = 0;
        }
      }

      // [추가] 가상 직원의 필수 노무 서류 자동 생성
      batch.set(
        db
            .collection('stores')
            .doc(storeId)
            .collection('workers')
            .doc(workerId),
        {'isVirtual': true, 'isDemo': true},
        SetOptions(merge: true),
      );

      final docTypes = [
        {'type': 'contract_full', 'title': '표준 근로계약서'},
        {'type': 'employeeRegistry', 'title': '근로자 명부'},
        {'type': 'checklist', 'title': '채용 점검 체크리스트'},
        {'type': 'night_consent', 'title': '야간/휴일근로 동의서'},
        {'type': 'wageStatement', 'title': '임금명세서 (체험용)'},
      ];

      for (var dt in docTypes) {
        final docId = 'doc_${workerId}_${dt['type']}';
        // 김점장(worker_a)만 완벽하게 서명된 상태로 테스트
        final isSigned = (workerId == 'worker_a');

        batch.set(
          db
              .collection('stores')
              .doc(storeId)
              .collection('documents')
              .doc(docId),
          {
            'id': docId,
            'staffId': workerId,
            'storeId': storeId,
            'type': dt['type'],
            'status': isSigned ? 'signed' : 'draft',
            'title': dt['title'],
            'content': '체험 모드로 자동 생성된 노무 서류입니다.',
            'createdAt': startDay.toIso8601String(),
            'signedAt': isSigned ? now.toIso8601String() : null,
            'deliveredAt': isSigned ? now.toIso8601String() : null,
            'signatureUrl': isSigned
                ? 'https://dummyimage.com/200x100/000/fff&text=Worker+Sign'
                : null,
            'bossSignatureUrl': isSigned
                ? 'https://dummyimage.com/200x100/000/fff&text=Boss+Sign'
                : null,
          },
          SetOptions(merge: true),
        );
        ops++;
      }
    }
    if (ops > 0) {
      await batch.commit();
    }

    // Debug info: write the successful execution stats to the user's document
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        await db.collection('users').doc(uid).update({
          'seederDebug':
              'Success: $ops ops. TargetWorkers: ${targetWorkers.length}. First worker: ${targetWorkers.isNotEmpty ? targetWorkers.first['id'] : "none"}',
        });
      }
    } catch (_) {}
  }
}
