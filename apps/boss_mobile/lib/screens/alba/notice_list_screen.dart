import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_logic/shared_logic.dart';
import 'notice_detail_screen.dart';
import '../../widgets/full_screen_image_viewer.dart';

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
              final content = (d['content'] ?? '') as String;
              final imageUrl = (d['imageUrl'] ?? '') as String;
              final createdAt = d['createdAt'];

              String dateText = '';
              if (createdAt is Timestamp) {
                final dt = createdAt.toDate();
                dateText = '${dt.year}.${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')}';
              }

              final isRead = _isRead(doc.id);
              bool isExpanded = false;

              return StatefulBuilder(
                builder: (context, setItemState) {

                  return Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () async {
                        // Mark as read
                        if (!isRead) {
                           await _prefs!.setString('read_notice_${widget.workerId}_${doc.id}', DateTime.now().toIso8601String());
                           if (mounted) setState(() {});
                        }

                        // 펼치거나 전체화면 (내용이 길어도 일단 펼쳐지게 하고 상세보기 버튼을 제공)
                        setItemState(() {
                          isExpanded = !isExpanded;
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.blue.shade50,
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              '공지',
                                              style: TextStyle(
                                                color: Colors.blue.shade700,
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          if (!isRead)
                                            Container(
                                              margin: const EdgeInsets.only(left: 6),
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.red,
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: const Text('N', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        title,
                                        style: TextStyle(
                                          fontWeight: isRead ? FontWeight.w500 : FontWeight.w800,
                                          fontSize: 15,
                                          color: Colors.black87,
                                        ),
                                        maxLines: isExpanded ? null : 2,
                                        overflow: isExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        dateText,
                                        style: const TextStyle(fontSize: 12, color: Colors.black45),
                                      ),
                                    ],
                                  ),
                                ),
                                if (imageUrl.isNotEmpty) ...[
                                  const SizedBox(width: 16),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: R2Image(
                                      storeId: widget.storeId,
                                      imagePathOrId: imageUrl,
                                      width: 60,
                                      height: 60,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ]
                              ],
                            ),
                            if (isExpanded) ...[
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                child: Divider(height: 1),
                              ),
                              Text(content, style: const TextStyle(fontSize: 14, height: 1.5, color: Colors.black87)),
                              if (imageUrl.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: GestureDetector(
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => FullScreenImageViewer(imageUrl: imageUrl, storeId: widget.storeId),
                                        ),
                                      );
                                    },
                                    child: R2Image(
                                      storeId: widget.storeId,
                                      imagePathOrId: imageUrl,
                                      fit: BoxFit.contain,
                                      width: double.infinity,
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: () async {
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
                                    if (mounted) setState((){});
                                  },
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.blue.shade700,
                                    textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                  ),
                                  child: const Text('전체화면에서 보기 >'),
                                )
                              )
                            ]
                          ],
                        ),
                      ),
                    ),
                  );
                }
              );
            },
          );
        },
      ),
    );
  }
}

