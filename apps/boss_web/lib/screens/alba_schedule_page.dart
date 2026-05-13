import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_logic/shared_logic.dart';

class AlbaSchedulePage extends StatefulWidget {
  final String storeId;
  final String workerId;

  const AlbaSchedulePage({super.key, required this.storeId, required this.workerId});

  @override
  State<AlbaSchedulePage> createState() => _AlbaSchedulePageState();
}

class _AlbaSchedulePageState extends State<AlbaSchedulePage> with SingleTickerProviderStateMixin {
  final _db = FirebaseFirestore.instance;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      if (mounted) setState(() => _index = _tabController.index);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> _workerFuture() {
    return _db
        .collection('stores')
        .doc(widget.storeId)
        .collection('workers')
        .doc(widget.workerId)
        .get();
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _workersFuture() {
    return _db
        .collection('stores')
        .doc(widget.storeId)
        .collection('workerProfiles') // 비민감 필드만 (이름/근무시간)
        .where('status', isEqualTo: 'active')
        .get()
        .then((s) => s.docs);
  }


  // Roster days for the current month
  Future<QuerySnapshot<Map<String, dynamic>>> _rosterDaysFuture() {
    return _db
        .collection('stores')
        .doc(widget.storeId)
        .collection('workers')
        .doc(widget.workerId)
        .collection('rosterDays')
        .get();
  }

  // All workers' roster days for the weekly view
  Future<QuerySnapshot<Map<String, dynamic>>> _allWorkersRosterFuture() {
    return _db
        .collectionGroup('rosterDays')
        .where('storeId', isEqualTo: widget.storeId)
        .get();
  }

  int _plannedWeeklyPureMinutes(Map<String, dynamic> worker) {
    final wDays = (worker['workDays'] as List?)?.cast<dynamic>() ?? const [];
    final inT = (worker['checkInTime']?.toString() ?? '09:00').substring(0, 5);
    final outT = (worker['checkOutTime']?.toString() ?? '18:00').substring(0, 5);
    final breakMin = (worker['breakMinutes'] as num?)?.toInt() ?? 0;
    final shiftMin = _minutesBetweenHm(inT, outT);
    return (shiftMin - breakMin).clamp(0, 24 * 60) * wDays.length;
  }

  int _minutesBetweenHm(String start, String end) {
    final sp = start.split(':');
    final ep = end.split(':');
    if (sp.length != 2 || ep.length != 2) return 0;
    final sm = int.tryParse(sp[0])! * 60 + int.tryParse(sp[1])!;
    final em = int.tryParse(ep[0])! * 60 + int.tryParse(ep[1])!;
    return (em - sm).clamp(0, 24 * 60);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: _workerFuture(),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final worker = snap.data?.data() ?? const <String, dynamic>{};
        return Column(
          children: [
            // Page Header with Indicator
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
              color: Colors.white,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _index == 0 ? '내 근무표' : '전체 근무표',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF1565C0)),
                        ),
                        Text(
                          _index == 0 ? '나의 이번 주 일정을 확인합니다.' : '동료들과의 협업 일정을 확인합니다.',
                          style: const TextStyle(fontSize: 12, color: Colors.black45),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE3F2FD),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${_index + 1} / 2',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1565C0)),
                    ),
                  ),
                ],
              ),
            ),
            // Tab selector (Minimal style)
            Container(
              color: Colors.white,
              child: TabBar(
                controller: _tabController,
                labelColor: const Color(0xFF1565C0),
                unselectedLabelColor: Colors.black45,
                indicatorColor: const Color(0xFF1565C0),
                indicatorWeight: 3,
                onTap: (i) => setState(() => _index = i),
                tabs: const [
                  Tab(text: '나의 근무'),
                  Tab(text: '전체 근무'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _myWeeklyRosterView(worker),
                  _allRosterView(worker),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // Helper to sync tab index when swiped
  int _index = 0;

  // ─────────────────────────────────────────
  // Tab 1: 이번 주 내 근무표 (리스트)
  // ─────────────────────────────────────────
  Widget _myWeeklyRosterView(Map<String, dynamic> worker) {
    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      future: _rosterDaysFuture(),
      builder: (context, rosterSnap) {
        final rosterMap = <String, Map<String, dynamic>>{};
        for (final d in rosterSnap.data?.docs ?? []) {
          rosterMap[d.id] = d.data();
        }
        final now = AppClock.now();
        final monday = DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: now.weekday - DateTime.monday));
        const labels = ['월', '화', '수', '목', '금', '토', '일'];

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: 7,
          itemBuilder: (context, i) {
            final day = monday.add(Duration(days: i));
            final key = rosterDateKey(day);
            final shift = effectiveShiftForDate(
              worker: worker,
              date: day,
              rosterDayDoc: rosterMap[key],
            );
            final isToday = _isToday(day);

            return Column(
              children: [
                GestureDetector(
                  onTap: shift != null ? () => _showShiftActions(day, shift, worker, widget.workerId) : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                    decoration: BoxDecoration(
                      color: isToday ? const Color(0xFFF0F7FF) : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isToday ? const Color(0xFF1565C0) : const Color(0xFFEEEEEE),
                        width: isToday ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: isToday ? const Color(0xFF1565C0) : const Color(0xFFF5F5F5),
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            labels[i],
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isToday ? Colors.white : Colors.black87,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${day.month}월 ${day.day}일',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: isToday ? const Color(0xFF1565C0) : Colors.black87,
                              ),
                            ),
                            if (isToday)
                              const Text('오늘', style: TextStyle(fontSize: 10, color: Color(0xFF1565C0))),
                          ],
                        ),
                        const Spacer(),
                        if (shift == null)
                          const Text('휴무', style: TextStyle(color: Colors.black26, fontWeight: FontWeight.w500))
                        else
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${shift.checkInHm} ~ ${shift.checkOutHm}',
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                              ),
                              const Text('대근 가능', style: TextStyle(fontSize: 10, color: Colors.blue)),
                            ],
                          ),
                        const SizedBox(width: 8),
                        const Icon(Icons.chevron_right, size: 18, color: Colors.black26),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            );
          },
        );
      },
    );
  }

  // ─────────────────────────────────────────
  // Tab 2: 전체 직원 주간 근무표
  // ─────────────────────────────────────────
  Widget _allRosterView(Map<String, dynamic> myWorker) {
    return FutureBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
      future: _workersFuture(),
      builder: (context, workersSnap) {
        final workers = workersSnap.data ?? [];
        final now = AppClock.now();
        final weekStart = now.subtract(Duration(days: now.weekday % 7));

        return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
          future: _allWorkersRosterFuture(),
          builder: (context, rosterGroupSnap) {
            final rosterByWorker = <String, Map<String, Map<String, dynamic>>>{};
            for (final d in rosterGroupSnap.data?.docs ?? []) {
              final data = d.data();
              final wId = data['workerId']?.toString() ?? d.reference.parent.parent?.id ?? '';
              rosterByWorker.putIfAbsent(wId, () => {})[d.id] = data;
            }

            const dayLabels = ['일', '월', '화', '수', '목', '금', '토'];

            return SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Day columns header
                  Row(
                    children: [
                      const SizedBox(width: 72),
                      ...List.generate(7, (i) {
                        final day = weekStart.add(Duration(days: i));
                        final isToday = _isToday(day);
                        return Expanded(
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: isToday ? const Color(0xFF1565C0) : const Color(0xFFF5F5F5),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            alignment: Alignment.center,
                            child: Column(
                              children: [
                                Text(dayLabels[i], style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: isToday ? Colors.white70 : Colors.black45,
                                )),
                                Text('${day.day}', style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: isToday ? Colors.white : Colors.black87,
                                )),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Worker rows
                  ...workers.map((workerDoc) {
                    final w = workerDoc.data();
                    final wId = workerDoc.id;
                    final wName = w['name']?.toString() ?? wId;
                    final isMe = wId == widget.workerId;
                    final workerRoster = rosterByWorker[wId] ?? {};

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: isMe ? const Color(0xFFE8F0FE) : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: isMe ? Border.all(color: const Color(0xFF1565C0).withValues(alpha: 0.3)) : Border.all(color: Colors.grey.shade100),
                      ),
                      child: Row(
                        children: [
                          // Worker name label
                          SizedBox(
                            width: 72,
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (isMe)
                                    const Text('나', style: TextStyle(fontSize: 9, color: Color(0xFF1565C0), fontWeight: FontWeight.w900)),
                                  Text(wName, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                                ],
                              ),
                            ),
                          ),
                          // Shift cells
                          ...List.generate(7, (i) {
                            final date = weekStart.add(Duration(days: i));
                            final shift = effectiveShiftForDate(
                              worker: w,
                              date: date,
                              rosterDayDoc: workerRoster[rosterDateKey(date)],
                            );
                            final rosterDoc = workerRoster[rosterDateKey(date)];
                            final isSubstitution = rosterDoc?['isSubstitution'] == true;
                            final isSubstitutedOut = rosterDoc?['isOff'] == true && rosterDoc?['substitutedBy'] != null;
                            final originalWorkerName = rosterDoc?['originalWorkerName']?.toString();
                            return Expanded(
                              child: GestureDetector(
                                onTap: shift != null ? () => _showShiftActions(date, shift, w, wId) : null,
                                child: Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  decoration: BoxDecoration(
                                    color: shift != null
                                        ? (isSubstitution
                                            ? Colors.orange.shade50
                                            : isMe ? const Color(0xFF1565C0).withValues(alpha: 0.1) : Colors.green.shade50)
                                        : (isSubstitutedOut ? Colors.grey.shade50 : Colors.transparent),
                                    borderRadius: BorderRadius.circular(6),
                                    border: shift != null
                                        ? Border.all(color: isSubstitution
                                            ? Colors.orange.shade200
                                            : isMe ? const Color(0xFF1565C0).withValues(alpha: 0.2) : Colors.green.shade100)
                                        : (isSubstitutedOut ? Border.all(color: Colors.grey.shade200) : null),
                                  ),
                                  alignment: Alignment.center,
                                  child: shift != null
                                      ? Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (isSubstitution)
                                              Text('대타', style: TextStyle(fontSize: 7, fontWeight: FontWeight.w900, color: Colors.orange.shade700)),
                                            Text(
                                              shift.checkInHm,
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: isSubstitution ? Colors.orange.shade700
                                                    : isMe ? const Color(0xFF1565C0) : Colors.green.shade700,
                                              ),
                                            ),
                                            if (isSubstitution && originalWorkerName != null)
                                              Text('←$originalWorkerName', style: TextStyle(fontSize: 6, color: Colors.orange.shade400), overflow: TextOverflow.ellipsis),
                                          ],
                                        )
                                      : (isSubstitutedOut
                                          ? const Text('휴무', style: TextStyle(fontSize: 8, color: Colors.grey, fontWeight: FontWeight.w600))
                                          : const Text('-', style: TextStyle(fontSize: 10, color: Colors.black12))),
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 24),
                  // Help card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: const Color(0xFFF9FAFF), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.blue.shade50)),
                    child: const Column(
                      children: [
                        Row(
                          children: [
                            Icon(Icons.auto_awesome_rounded, size: 16, color: Color(0xFF1565C0)),
                            SizedBox(width: 8),
                            Text('자유 대근 시스템 가이드', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1565C0))),
                          ],
                        ),
                        SizedBox(height: 8),
                        Text(
                          '• 본인 근무 탭: "이 근무 대신해줄 사람?" (대근 요청)\n'
                          '• 동료 근무 탭: "이 근무 내가 할게!" (대근 지원)\n'
                          '• 법적 제한(15/52시간) 내라면 사장님 승인 없이 즉시 확정됩니다.',
                          style: TextStyle(fontSize: 11, color: Colors.black54, height: 1.6),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// 대근 신청/지원을 처리하는 중앙 로직
  /// - 법적 문제가 없으면 "즉시 승인" (Peer-to-Peer Auto Update)
  /// - 법적 경고(15h/52h) 발생 시 "사장님 승인 대기" (Notify & Request Approval)
  Future<void> _processSubstitution({
    required DateTime date,
    required dynamic shift,
    required String requesterId, // 원 근무자
    required String proposerId, // 대근 희망자 (나 또는 상대방)
  }) async {
    final now = AppClock.now();
    final subId = 'sub_${now.millisecondsSinceEpoch}';
    final dateKey = rosterDateKey(date);
    
    // 1. 참여자 정보 로드
    final workersSnap = await _workersFuture();
    final requesterSnap = workersSnap.firstWhere((d) => d.id == requesterId);
    final proposerSnap = workersSnap.firstWhere((d) => d.id == proposerId);
    
    final rName = requesterSnap.data()['name']?.toString() ?? '직원A';
    final pName = proposerSnap.data()['name']?.toString() ?? '직원B';
    
    // 2. 법적 시뮬레이션 (대근자의 주간 시간 체크)
    final pWeeklyMinutes = _plannedWeeklyPureMinutes(proposerSnap.data());
    final shiftMinutes = _minutesBetweenHm(shift.checkInHm, shift.checkOutHm) - 
                         ((proposerSnap.data()['breakMinutes'] as num?)?.toInt() ?? 0);
    final totalAfter = pWeeklyMinutes + shiftMinutes;
    
    final isWarning = totalAfter >= (15 * 60) || totalAfter >= (52 * 60);

    if (isWarning) {
      // ────────── CASE 3: 사장님 승인 요청 ──────────
      await _db.collection('substitutions').doc(subId).set({
        'id': subId,
        'storeId': widget.storeId,
        'requesterId': requesterId,
        'proposerId': proposerId,
        'date': dateKey,
        'startHm': shift.checkInHm,
        'endHm': shift.checkOutHm,
        'status': 'pending', // 사장님 승인 대기
        'over15Hours': totalAfter >= 15 * 60,
        'isAutoApproved': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
      
      await _db.collection('stores').doc(widget.storeId).collection('notifications').add({
        'type': 'substitution_approval_request',
        'title': '⚠️ 대근 승인 요청 (법적 경고 발생)',
        'message': '$rName → $pName 대근 신청이 법적 한도(15h/52h) 근접으로 인하여 사장님의 승인이 필요합니다.',
        'substitutionId': subId,
        'createdAt': FieldValue.serverTimestamp(),
      });
      
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('사장님 승인 대기'),
            content: Text('사장님께 승인 요청을 보냈습니다.\n\n대상자: $pName'),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('확인'))],
          ),
        );
      }
    } else {
      // ────────── CASE 1: 대근 요청 생성 (rosterDays는 사장님/서버가 처리) ──────────
      // 보안상 클라이언트가 다른 직원의 rosterDays를 직접 수정하지 않도록
      // substitutions 요청만 생성하고, 사장님 승인 또는 Cloud Function이 처리
      await _db.collection('substitutions').doc(subId).set({
        'id': subId,
        'storeId': widget.storeId,
        'requesterId': requesterId,
        'proposerId': proposerId,
        'requesterName': rName,
        'proposerName': pName,
        'date': dateKey,
        'startHm': shift.checkInHm,
        'endHm': shift.checkOutHm,
        'status': 'pending_auto', // 법적 문제 없음 → 사장님 자동 승인 대기
        'over15Hours': false,
        'isAutoApproved': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await _db.collection('stores').doc(widget.storeId).collection('notifications').add({
        'type': 'substitution_auto_request',
        'title': '🔄 대근 확정 요청',
        'message': '$rName → $pName 대근 신청 (법적 제한 내). 사장님 확인 후 근무표에 반영됩니다.',
        'substitutionId': subId,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('대근 요청이 접수되었습니다. 사장님 확인 후 근무표에 반영됩니다.')),
        );
      }
    }
  }

  void _showShiftActions(DateTime date, dynamic shift, Map<String, dynamic> targetWorker, String targetWorkerId) {
    final isMe = targetWorkerId == widget.workerId;
    final name = targetWorker['name']?.toString() ?? '직원';

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${date.month}월 ${date.day}일 — $name님 근무',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Row(children: [const Icon(Icons.access_time, size: 16), const SizedBox(width: 4), Text('${shift.checkInHm} ~ ${shift.checkOutHm}')]),
              const SizedBox(height: 24),
              
              if (isMe) ...[
                const Text('내 근무를 대신해줄 동료를 찾으시나요?', style: TextStyle(color: Colors.black54, fontSize: 13)),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.person_search_rounded),
                    label: const Text('특정 동료에게 대근 요청하기'),
                    onPressed: () {
                      Navigator.pop(context);
                      _pickSubstituteAndRequest(date, shift);
                    },
                  ),
                ),
              ] else ...[
                const Text('이 근무를 내가 대신 할 수 있습니다.', style: TextStyle(color: Colors.black54, fontSize: 13)),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: Colors.green),
                    icon: const Icon(Icons.volunteer_activism_rounded),
                    label: const Text('내가 대신 근무 지원하기'),
                    onPressed: () {
                      Navigator.pop(context);
                      _processSubstitution(
                        date: date,
                        shift: shift,
                        requesterId: targetWorkerId,
                        proposerId: widget.workerId,
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickSubstituteAndRequest(DateTime date, dynamic shift) async {
    final workersSnap = await _workersFuture();
    final candidates = workersSnap.where((d) => d.id != widget.workerId).toList();
    
    if (!mounted) return;
    final selected = await showDialog<QueryDocumentSnapshot<Map<String, dynamic>>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('대근 요청 대상 선택'),
        content: SizedBox(
          width: 300,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: candidates.length,
            itemBuilder: (_, i) {
              final c = candidates[i];
              return ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(c.data()['name']?.toString() ?? '직원'),
                onTap: () => Navigator.pop(ctx, c),
              );
            },
          ),
        ),
      ),
    );

    if (selected != null) {
      await _processSubstitution(
        date: date,
        shift: shift,
        requesterId: widget.workerId,
        proposerId: selected.id,
      );
    }
  }

  bool _isToday(DateTime date) {
    final now = AppClock.now();
    return date.year == now.year && date.month == now.month && date.day == now.day;
  }
}
