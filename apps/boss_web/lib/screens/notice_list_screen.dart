import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'notice_detail_screen.dart';

class NoticeListScreen extends StatefulWidget {
  const NoticeListScreen({
    super.key,
    required this.storeId,
    required this.workerId,
    required this.workerName,
    this.showAppBar = true,
  });

  final String storeId;
  final String workerId;
  final String workerName;
  final bool showAppBar;

  @override
  State<NoticeListScreen> createState() => _NoticeListScreenState();
}

class _NoticeListScreenState extends State<NoticeListScreen> {
  SharedPreferences? _prefs;

  @override
  void initState() {
    super.initState();
    _initPrefs();
  }

  Future<void> _initPrefs() async {
    final p = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => _prefs = p);
    }
  }

  bool _isRead(String noticeId) {
    if (_prefs == null) return false;
    return _prefs!.getString('read_notice_${widget.workerId}_$noticeId') != null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: widget.showAppBar ? AppBar(
        title: const Text('공지사항'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
      ) : null,
      body: FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
        future: FirebaseFirestore.instance
            .collection('stores')
            .doc(widget.storeId)
            .collection('notices')
            .get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting || _prefs == null) {
            return const Center(child: CircularProgressIndicator());
          }

          final allDocs = snapshot.data?.docs ?? [];

          // 기한 만료된 공지사항 파기 (비동기)
          final now = DateTime.now();
          for (final doc in allDocs) {
            final d = doc.data();
            final publishUntil = d['publishUntil'];
            if (publishUntil is Timestamp) {
              if (publishUntil.toDate().isBefore(now)) {
                FirebaseFirestore.instance
                    .collection('stores')
                    .doc(widget.storeId)
                    .collection('notices')
                    .doc(doc.id)
                    .delete()
                    .catchError((_) {});
              }
            }
          }

          // 유효한 공지만 필터링
          final activeDocs = allDocs.where((doc) {
            final d = doc.data();
            final publishUntil = d['publishUntil'];
            if (publishUntil is Timestamp) {
              return !publishUntil.toDate().isBefore(now);
            }
            return true;
          }).toList();

          if (activeDocs.isEmpty) {
            return const Center(child: Text('현재 공지가 없습니다.'));
          }

          // In-memory sort by createdAt
          final docs = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(activeDocs);
          docs.sort((a, b) {
            final ta = a.data()['createdAt'] as Timestamp?;
            final tb = b.data()['createdAt'] as Timestamp?;
            if (ta == null && tb == null) return 0;
            if (ta == null) return 1;
            if (tb == null) return -1;
            return tb.compareTo(ta);
          });

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final doc = docs[index];
              final d = doc.data();
              final title = (d['title'] ?? '') as String;
              final createdAt = d['createdAt'];

              String dateText = '';
              if (createdAt is Timestamp) {
                final dt = createdAt.toDate();
                dateText = '${dt.year}.${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')}';
              }

              final isRead = _isRead(doc.id);

              return Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontWeight: isRead ? FontWeight.w500 : FontWeight.bold,
                            color: isRead ? Colors.black54 : Colors.black87,
                          ),
                        ),
                      ),
                      if (!isRead)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'N',
                            style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                  ),
                  subtitle: Text(dateText, style: const TextStyle(fontSize: 12)),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => NoticeDetailScreen(
                          storeId: widget.storeId,
                          noticeId: doc.id,
                          workerId: widget.workerId,
                          workerName: widget.workerName,
                        ),
                      ),
                    );
                    // Refresh read status when coming back
                    if (mounted) {
                      setState(() {});
                    }
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

