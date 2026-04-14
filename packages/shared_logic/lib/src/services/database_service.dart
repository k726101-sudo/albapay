import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/app_clock.dart';
import '../models/store_model.dart';
import '../models/attendance_model.dart';
import '../models/substitution_model.dart';
import '../models/document_model.dart';
import '../models/education_model.dart';
import '../models/shift_model.dart';

class DatabaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // --- Invite Operations (for staff web onboarding) ---
  //
  // Collection shape (recommended):
  // invites/{inviteId} {
  //   storeId: string,
  //   workerId: string (optional, alba_web 로그인 최적화용),
  //   staffName: string (optional),
  //   baseWage: number (optional),
  //   expiresAt: Timestamp (optional),
  //   usedAt: Timestamp (optional),
  //   usedByUid: string (optional)
  // }
  Future<Map<String, dynamic>?> getInvite(String inviteId) async {
    try {
      final doc = await _db.collection('invites').doc(inviteId).get().timeout(const Duration(seconds: 30));
      return doc.exists ? doc.data() : null;
    } catch (e) {
      // ignore – caller handles null gracefully
      return null;
    }
  }

  Future<bool> consumeInvite({
    required String inviteId,
    required String usedByUid,
  }) async {
    final ref = _db.collection('invites').doc(inviteId);
    return _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return false;
      final data = snap.data() ?? {};

      final usedAt = data['usedAt'];
      if (usedAt != null) return false;

      final expiresAt = data['expiresAt'];
      if (expiresAt is Timestamp) {
        if (expiresAt.toDate().isBefore(AppClock.now())) return false;
      }

      tx.update(ref, {
        'usedAt': FieldValue.serverTimestamp(),
        'usedByUid': usedByUid,
      });
      return true;
    });
  }

  Future<void> upsertWorker({
    required String storeId,
    required String workerId,
    required Map<String, dynamic> data,
  }) async {
    await _db
        .collection('stores')
        .doc(storeId)
        .collection('workers')
        .doc(workerId)
        .set(data, SetOptions(merge: true));
  }

  // --- Store Operations ---

  Future<void> createStore(Store store) async {
    await _db.collection('stores').doc(store.id).set(store.toJson());
  }

  /// 매장 문서 부분 갱신(Hive `StoreInfo` 확장 필드 포함). 기존 필드는 유지됩니다.
  Future<void> mergeStoreDocument(
    String storeId,
    Map<String, dynamic> data,
  ) async {
    await _db
        .collection('stores')
        .doc(storeId)
        .set(data, SetOptions(merge: true));
  }

  Future<Store?> getStore(String storeId) async {
    final doc = await _db.collection('stores').doc(storeId).get();
    return doc.exists ? Store.fromJson(doc.data()!) : null;
  }

  Stream<Store?> streamStore(String storeId) {
    return _db.collection('stores').doc(storeId).snapshots().map((doc) =>
        doc.exists ? Store.fromJson(doc.data()!) : null);
  }

  // --- Attendance Operations ---

  Future<void> recordAttendance(Attendance attendance) async {
    await _db.collection('attendance').doc(attendance.id).set(attendance.toJson(), SetOptions(merge: true));
  }

  Stream<List<Attendance>> streamAttendance(String storeId) {
    return _db
        .collection('attendance')
        .where('storeId', isEqualTo: storeId)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => Attendance.fromJson(doc.data(), id: doc.id)).toList());
  }

  Future<List<Attendance>> getAttendance(String storeId) async {
    final snapshot = await _db
        .collection('attendance')
        .where('storeId', isEqualTo: storeId)
        .get();
    return snapshot.docs.map((doc) => Attendance.fromJson(doc.data(), id: doc.id)).toList();
  }

  Stream<List<Attendance>> streamDailyAttendance(String storeId, DateTime date) {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    
    return _db
        .collection('attendance')
        .where('storeId', isEqualTo: storeId)
        .where('clockIn', isGreaterThanOrEqualTo: start.toIso8601String())
        .where('clockIn', isLessThan: end.toIso8601String())
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => Attendance.fromJson(doc.data(), id: doc.id)).toList());
  }

  /// 사장님 앱에서 저장한 일별 근무표 override → 알바 웹에서 Stream으로 반영
  Future<void> syncWorkerRosterDay({
    required String storeId,
    required String workerId,
    required String dateYmd,
    String? checkInHm,
    String? checkOutHm,
  }) async {
    final ref = _db
        .collection('stores')
        .doc(storeId)
        .collection('workers')
        .doc(workerId)
        .collection('rosterDays')
        .doc(dateYmd);
    if (checkInHm == null || checkOutHm == null) {
      await ref.delete();
    } else {
      await ref.set({
        'date': dateYmd,
        'checkIn': checkInHm,
        'checkOut': checkOutHm,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> streamWorkerRosterDays(
    String storeId,
    String workerId,
  ) {
    return _db
        .collection('stores')
        .doc(storeId)
        .collection('workers')
        .doc(workerId)
        .collection('rosterDays')
        .snapshots();
  }

  Future<QuerySnapshot<Map<String, dynamic>>> getWorkerRosterDays(
    String storeId,
    String workerId,
  ) {
    return _db
        .collection('stores')
        .doc(storeId)
        .collection('workers')
        .doc(workerId)
        .collection('rosterDays')
        .get();
  }

  /// 해당 일자(로컬 날짜 기준 clockIn 구간)에 출근 기록이 하나라도 있으면 true (진행 중·완료 모두).
  Future<bool> hasWorkerAttendanceOnDate({
    required String storeId,
    required String workerId,
    required DateTime date,
  }) async {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    final q = await _db
        .collection('attendance')
        .where('storeId', isEqualTo: storeId)
        .where('staffId', isEqualTo: workerId)
        .where('clockIn', isGreaterThanOrEqualTo: start.toIso8601String())
        .where('clockIn', isLessThan: end.toIso8601String())
        .limit(1)
        .get();
    return q.docs.isNotEmpty;
  }

  /// 연장 근무 신청 → 사장님 푸시 (notificationQueue)
  Future<void> enqueueBossOvertimeNotification({
    required String storeId,
    required String workerId,
    required String workerName,
    required String reason,
    String? attendanceId,
  }) async {
    final msg = attendanceId != null
        ? '연장 근무 신청: $workerName — $reason (기록 $attendanceId)'
        : '연장 근무 신청: $workerName — $reason';
    await enqueueBossAttendanceNotification(
      storeId: storeId,
      workerId: workerId,
      workerName: workerName,
      kind: 'overtime_request',
      message: msg,
    );
  }

  Future<void> enqueueBossAttendanceNotification({
    required String storeId,
    required String workerId,
    required String workerName,
    required String kind,
    String? message,
  }) async {
    final storeSnap = await _db.collection('stores').doc(storeId).get();
    final ownerId = storeSnap.data()?['ownerId']?.toString() ?? '';
    if (ownerId.isEmpty) return;
    final id = '${workerId}_${kind}_${AppClock.now().millisecondsSinceEpoch}';
    await _db.collection('notificationQueue').doc(id).set({
      'dedupeKey': id,
      'storeId': storeId,
      'channel': 'pushBoss',
      'targetUid': ownerId,
      'status': 'queued',
      'type': kind,
      'workerId': workerId,
      'workerName': workerName,
      'message': message ?? '출퇴근 알림',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// 알바생에게 노무 서류 관련 알림 (새 서류 도착 등)
  Future<void> enqueueWorkerDocumentNotification({
    required String storeId,
    required String workerId,
    required String docId,
    required String docTitle,
    required String kind,
  }) async {
    final id = 'worker_${workerId}_${kind}_${AppClock.now().millisecondsSinceEpoch}';
    await _db.collection('notificationQueue').doc(id).set({
      'dedupeKey': id,
      'storeId': storeId,
      'channel': 'pushWorker',
      'targetUid': workerId,
      'status': 'queued',
      'type': kind,
      'docId': docId,
      'message': '[$docTitle] 서류가 전송되었습니다. 확인 후 서명해 주세요.',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // --- Substitution Operations ---

  Future<void> requestSubstitution(Substitution sub) async {
    await _db.collection('substitutions').doc(sub.id).set(sub.toJson());
  }

  // --- Document Operations ---

  Future<void> saveDocument(LaborDocument doc) async {
    await _db
        .collection('stores')
        .doc(doc.storeId)
        .collection('documents')
        .doc(doc.id)
        .set(doc.toMap());
  }

  Stream<List<LaborDocument>> streamDocuments(String storeId) {
    return _db
        .collection('stores')
        .doc(storeId)
        .collection('documents')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => LaborDocument.fromMap(
                    doc.id,
                    doc.data(),
                  ))
              .toList(),
        );
  }

  /// 특정 알바생(staffId)에게 할당된 서류만 실시간으로 가져옵니다. (보안 규칙 준수용)
  Stream<List<LaborDocument>> streamWorkerDocuments(String storeId, String staffId) {
    return _db
        .collection('stores')
        .doc(storeId)
        .collection('documents')
        .where('staffId', isEqualTo: staffId)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => LaborDocument.fromMap(
                    doc.id,
                    doc.data(),
                  ))
              .toList(),
        );
  }

  /// 알바생이 문서를 확인하고 '교부 확인'을 눌렀을 때 실행 (법적 증거 기록)
  Future<void> acknowledgeDocument({
    required String storeId,
    required String docId,
    required String ip,
    required String userAgent,
  }) async {
    await _db
        .collection('stores')
        .doc(storeId)
        .collection('documents')
        .doc(docId)
        .update({
      'deliveryConfirmedAt': FieldValue.serverTimestamp(),
      'deliveryConfirmedIp': ip,
      'deliveryConfirmedUserAgent': userAgent,
    });
  }

  /// 알바생이 공유된 링크를 클릭하여 문서를 조회했을 때 호출 (수신 확인 트래킹)
  Future<void> setDocumentDelivered({
    required String storeId,
    required String docId,
  }) async {
    final ref = _db
        .collection('stores')
        .doc(storeId)
        .collection('documents')
        .doc(docId);
    
    final snap = await ref.get();
    if (snap.exists) {
      final data = snap.data();
      // 이미 delivered 이상인 경우(교부 확인 포함) 업데이트 건너뜀
      if (data != null && data['status'] == 'delivered' || data?['deliveryConfirmedAt'] != null) {
        return;
      }
      
      await ref.update({
        'status': 'delivered',
        'deliveredAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<List<LaborDocument>> getDocuments(String storeId) async {
    final snapshot = await _db
        .collection('stores')
        .doc(storeId)
        .collection('documents')
        .get();
    return snapshot.docs
        .map((doc) => LaborDocument.fromMap(
              doc.id,
              doc.data(),
            ))
        .toList();
  }

  Stream<List<Substitution>> streamSubstitutions(String storeId) {
    return _db
        .collection('substitutions')
        .where('storeId', isEqualTo: storeId)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => Substitution.fromJson(doc.data())).toList());
  }

  Future<List<Substitution>> getSubstitutions(String storeId) async {
    final snapshot = await _db
        .collection('substitutions')
        .where('storeId', isEqualTo: storeId)
        .get();
    return snapshot.docs.map((doc) => Substitution.fromJson(doc.data())).toList();
  }

  // --- Education Operations ---

  Future<void> saveEducationRecord(EducationRecord record) async {
    await _db.collection('educationRecords').doc(record.id).set(record.toJson());
  }

  Stream<List<EducationRecord>> streamEducationRecords(String storeId) {
    return _db
        .collection('educationRecords')
        .where('storeId', isEqualTo: storeId)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => EducationRecord.fromJson(doc.data())).toList());
  }

  Future<List<EducationRecord>> getEducationRecords(String storeId) async {
    final snapshot = await _db
        .collection('educationRecords')
        .where('storeId', isEqualTo: storeId)
        .get();
    return snapshot.docs.map((doc) => EducationRecord.fromJson(doc.data())).toList();
  }

  // --- Shift Operations ---

  Future<void> saveShift(Shift shift) async {
    await _db.collection('shifts').doc(shift.id).set(shift.toJson());
  }

  Future<List<Shift>> getShifts(String storeId) async {
    final snapshot = await _db
        .collection('shifts')
        .where('storeId', isEqualTo: storeId)
        .get();
    return snapshot.docs.map((doc) => Shift.fromJson(doc.data())).toList();
  }

  Future<Shift?> getStaffShiftForDate(String staffId, DateTime date) async {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final snapshot = await _db
        .collection('shifts')
        .where('staffId', isEqualTo: staffId)
        .where('startTime', isGreaterThanOrEqualTo: startOfDay.toIso8601String())
        .where('startTime', isLessThan: endOfDay.toIso8601String())
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) return null;
    return Shift.fromJson(snapshot.docs.first.data());
  }
}
