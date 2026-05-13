import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_logic/shared_logic.dart';
import '../widgets/store_id_gate.dart';
import 'notice_create_screen.dart';
import '../widgets/full_screen_image_viewer.dart';

class NoticeListScreen extends StatelessWidget {
  final bool showAppBar;
  const NoticeListScreen({super.key, this.showAppBar = true});

  @override
  Widget build(BuildContext context) {
    return StoreIdGate(
      builder: (context, storeId) {
        return Scaffold(
          appBar: showAppBar ? AppBar(
            title: const Text('공지 관리'),
            actions: [
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const NoticeCreateScreen(),
                  ),
                ),
              ),
            ],
          ) : null,
          body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('stores')
                .doc(storeId)
                .collection('notices')
                .orderBy('createdAt', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final docs = snapshot.data?.docs ?? [];
              
              // 기한 만료된 공지사항 파기 (비동기)
              final now = DateTime.now();
              for (final doc in docs) {
                final d = doc.data();
                final publishUntil = d['publishUntil'];
                if (publishUntil is Timestamp) {
                  if (publishUntil.toDate().isBefore(now)) {
                    FirebaseFirestore.instance
                        .collection('stores')
                        .doc(storeId)
                        .collection('notices')
                        .doc(doc.id)
                        .delete()
                        .catchError((_) {});
                  }
                }
              }

              // 화면 표출 전 즉시 필터링
              final activeDocs = docs.where((doc) {
                final d = doc.data();
                final publishUntil = d['publishUntil'];
                if (publishUntil is Timestamp) {
                  return !publishUntil.toDate().isBefore(now);
                }
                return true;
              }).toList();


              if (activeDocs.isEmpty) {
                return const Center(
                  child: Text('작성된 공지가 없습니다.'),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: activeDocs.length,
                separatorBuilder: (_, __) => const Divider(height: 32),
                itemBuilder: (context, index) {
                  final doc = activeDocs[index];
                  final d = doc.data();
                  final title = d['title']?.toString() ?? '제목 없음';
                  final content = d['content']?.toString() ?? '';
                  final createdAt = d['createdAt'];

                  String dateText = '';
                  if (createdAt is Timestamp) {
                    final dt = createdAt.toDate();
                    dateText = '${dt.year}.${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')}';
                  }

                  final imageUrl = d['imageUrl']?.toString() ?? '';
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
                          onTap: () {
                            setItemState(() => isExpanded = !isExpanded);
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
                                          if (dateText.isNotEmpty)
                                            Text(
                                              dateText,
                                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                                            ),
                                          const SizedBox(height: 4),
                                          Text(
                                            title,
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                            maxLines: isExpanded ? null : 2,
                                            overflow: isExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (imageUrl.isNotEmpty && !isExpanded) ...[
                                      const SizedBox(width: 12),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: R2Image(
                                          storeId: storeId,
                                          imagePathOrId: imageUrl,
                                          width: 48,
                                          height: 48,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                    ],
                                    const SizedBox(width: 8),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                                      onPressed: () => _confirmDelete(context, storeId, doc.id),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                    ),
                                  ],
                                ),
                                if (!isExpanded && imageUrl.isEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    content,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 14, color: Colors.black54),
                                  ),
                                ],
                                if (isExpanded) ...[
                                  const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 12),
                                    child: Divider(height: 1),
                                  ),
                                  Text(
                                    content,
                                    style: const TextStyle(fontSize: 14, height: 1.5, color: Colors.black87),
                                  ),
                                  if (imageUrl.isNotEmpty) ...[
                                    const SizedBox(height: 12),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: GestureDetector(
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => FullScreenImageViewer(imageUrl: imageUrl, storeId: storeId),
                                            ),
                                          );
                                        },
                                        child: R2Image(
                                          storeId: storeId,
                                          imagePathOrId: imageUrl,
                                          fit: BoxFit.contain,
                                          width: double.infinity,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
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
      },
    );
  }

  Future<void> _confirmDelete(BuildContext context, String storeId, String noticeId) async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('공지 삭제'),
        content: const Text('정말로 이 공지를 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (proceed == true) {
      await FirebaseFirestore.instance
          .collection('stores')
          .doc(storeId)
          .collection('notices')
          .doc(noticeId)
          .delete();
    }
  }
}
