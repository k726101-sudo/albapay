import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_logic/shared_logic.dart';
import '../models/worker.dart';

class NegativeAttendanceService {
  final DatabaseService _dbService = DatabaseService();
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// 급여 기간(또는 조회 기간) 내 비어있는 정상 근무 스케줄을 자동 생성(Auto-generated) 데이터로 채웁니다.
  /// 사장님이 앱을 열 때(대시보드 진입 시) On-demand로 호출됩니다.
  Future<void> generateMissingAttendances({
    required String storeId,
    required List<Worker> activeWorkers,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final now = AppClock.now();
    // 미래 일정은 자동 생성하지 않음 (오늘까지만 생성)
    final effectiveEndDate = endDate.isAfter(now) ? now : endDate;
    if (startDate.isAfter(effectiveEndDate)) return;

    // 1. 해당 기간의 기존 Attendance 전부 가져오기
    // (기간 필터링 최적화를 위해 clockIn 쿼리를 쓸 수 있으나, 편의상 상점 전체를 가져오거나 기간 쿼리 사용)
    // 여기서는 최적화를 위해 기간 쿼리를 직접 작성하거나 기존 getAttendance 활용
    final snapshot = await _db
        .collection('attendance')
        .where('storeId', isEqualTo: storeId)
        .where('clockIn', isGreaterThanOrEqualTo: startDate.toIso8601String())
        .get();

    final existingAttendances = snapshot.docs
        .map((doc) => Attendance.fromJson(doc.data(), id: doc.id))
        .toList();

    // staffId 별로 기존 attendance 분류
    final attendanceMap = <String, List<Attendance>>{};
    for (final a in existingAttendances) {
      attendanceMap.putIfAbsent(a.staffId, () => []).add(a);
    }

    final batch = _db.batch();
    int batchCount = 0;

    // 2. 워커별로 날짜 순회하며 빈 칸 채우기
    for (final worker in activeWorkers) {
      if (worker.status != 'working') continue;

      // 워커의 RosterDays 가져오기
      final rosterSnap = await _dbService.getWorkerRosterDays(
        storeId,
        worker.id,
      );
      final rosterMap = <String, Map<String, dynamic>>{};
      for (final rDoc in rosterSnap.docs) {
        rosterMap[rDoc.id] = rDoc.data();
      }

      final myAttendances = attendanceMap[worker.id] ?? [];

      DateTime current = DateTime(
        startDate.year,
        startDate.month,
        startDate.day,
      );
      final end = DateTime(
        effectiveEndDate.year,
        effectiveEndDate.month,
        effectiveEndDate.day,
      );

      while (current.compareTo(end) <= 0) {
        final dateYmd =
            "${current.year}-${current.month.toString().padLeft(2, '0')}-${current.day.toString().padLeft(2, '0')}";

        // 이미 오늘 날짜에 대한 Attendance가 있는지 확인
        final hasAttendance = myAttendances.any((a) {
          final localClockIn = a.clockIn.toLocal();
          return localClockIn.year == current.year &&
              localClockIn.month == current.month &&
              localClockIn.day == current.day;
        });

        if (!hasAttendance) {
          // 출근해야 하는 날인지 판단
          bool isWorkDay = false;
          String? checkInHm;
          String? checkOutHm;

          final roster = rosterMap[dateYmd];
          if (roster != null) {
            if (roster['isOff'] == true) {
              isWorkDay = false;
            } else {
              isWorkDay = true;
              checkInHm = roster['checkIn'];
              checkOutHm = roster['checkOut'];
            }
          } else {
            // 기본 스케줄 폴백
            if (worker.workDays.contains(current.weekday)) {
              isWorkDay = true;
              checkInHm = worker.checkInTime;
              checkOutHm = worker.checkOutTime;
            }
          }

          if (isWorkDay && checkInHm != null && checkOutHm != null) {
            // 시간 파싱 (HH:mm)
            final inParts = checkInHm.split(':');
            final outParts = checkOutHm.split(':');
            if (inParts.length == 2 && outParts.length == 2) {
              final inHour = int.tryParse(inParts[0]) ?? 0;
              final inMin = int.tryParse(inParts[1]) ?? 0;
              var outHour = int.tryParse(outParts[0]) ?? 0;
              final outMin = int.tryParse(outParts[1]) ?? 0;

              DateTime clockIn = DateTime(
                current.year,
                current.month,
                current.day,
                inHour,
                inMin,
              );
              DateTime clockOut = DateTime(
                current.year,
                current.month,
                current.day,
                outHour,
                outMin,
              );

              // 철야(자정 넘김) 처리
              if (clockOut.isBefore(clockIn) ||
                  clockOut.isAtSameMomentAs(clockIn)) {
                clockOut = clockOut.add(const Duration(days: 1));
              }

              // 미래 시간이라면 아직 생성하지 않음 (오늘 출근 전일 수 있으므로)
              if (clockIn.isBefore(now)) {
                // 휴게시간 계산 (워커 기본 설정)
                DateTime? breakStart;
                DateTime? breakEnd;
                if (worker.breakMinutes > 0) {
                  // 출근 4시간 후부터 휴게 시작으로 임의 배정 (UI에서 수정 가능하므로)
                  breakStart = clockIn.add(const Duration(hours: 4));
                  breakEnd = breakStart.add(
                    Duration(minutes: worker.breakMinutes.toInt()),
                  );
                  if (breakEnd.isAfter(clockOut)) {
                    breakStart = clockOut.subtract(
                      Duration(minutes: worker.breakMinutes.toInt()),
                    );
                    breakEnd = clockOut;
                  }
                }

                final newDocRef = _db.collection('attendance').doc();
                final newAttendance = Attendance(
                  id: newDocRef.id,
                  staffId: worker.id,
                  storeId: storeId,
                  clockIn: clockIn,
                  clockOut: clockOut,
                  type: AttendanceType.mobile,
                  attendanceStatus: 'AUTO_PENDING',
                  isAutoGenerated: true,
                  scheduledShiftStartIso: clockIn.toIso8601String(),
                  scheduledShiftEndIso: clockOut.toIso8601String(),
                  breakStart: breakStart,
                  breakEnd: breakEnd,
                  exceptionReason: '시스템 자동 생성 기록',
                );

                batch.set(newDocRef, newAttendance.toJson());
                batchCount++;

                // Firestore batch limit is 500
                if (batchCount >= 450) {
                  await batch.commit();
                  batchCount = 0;
                }
              }
            }
          }
        }
        current = current.add(const Duration(days: 1));
      }
    }

    if (batchCount > 0) {
      await batch.commit();
    }
  }
}
