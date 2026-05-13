import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_logic/shared_logic.dart';
import '../widgets/full_screen_image_viewer.dart';

/// 사장님이 작성한 공지 1건 상세 (알바 웹)
class NoticeDetailScreen extends StatefulWidget {
  const NoticeDetailScreen({
    super.key,
    required this.storeId,
    required this.noticeId,
    required this.workerId,
    required this.workerName,
  });

  final String storeId;
  final String noticeId;
  final String workerId;
  final String workerName;

  @override
  State<NoticeDetailScreen> createState() => _NoticeDetailScreenState();
}

class _NoticeDetailScreenState extends State<NoticeDetailScreen> {
  bool _isMarking = false;
  String? _localReadAt;

  @override
  void initState() {
    super.initState();
    _loadReadStatus();
  }

  Future<void> _loadReadStatus() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _localReadAt = prefs.getString('read_notice_${widget.workerId}_${widget.noticeId}');
      });
    }
  }

  Future<void> _markAsRead() async {
    setState(() => _isMarking = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now().toIso8601String();
      await prefs.setString('read_notice_${widget.workerId}_${widget.noticeId}', now);
      if (mounted) {
        setState(() => _localReadAt = now);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('읽음 확인 실패: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isMarking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('공지사항'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
      ),
      body: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        future: FirebaseFirestore.instance
            .collection('stores')
            .doc(widget.storeId)
            .collection('notices')
            .doc(widget.noticeId)
            .get(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final doc = snap.data;
          if (doc == null || !doc.exists) {
            return const Center(child: Text('공지를 찾을 수 없습니다.'));
          }
          final d = doc.data() ?? {};
          final title = d['title']?.toString() ?? '';
          final content = d['content']?.toString() ?? '';
          final imageUrl = d['imageUrl']?.toString() ?? '';
          final createdAt = d['createdAt'];

          String dateText = '';
          if (createdAt is Timestamp) {
            final dt = createdAt.toDate();
            dateText = '${dt.year}.${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')}';
          }

          final isRead = _localReadAt != null;
          String readAtText = '';
          if (isRead) {
            final dt = DateTime.tryParse(_localReadAt!);
            if (dt != null) {
              readAtText = '${dt.year}.${dt.month}.${dt.day} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
            }
          }

          return Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(15),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (dateText.isNotEmpty)
                          Text(
                            dateText,
                            style: const TextStyle(fontSize: 13, color: Colors.black54),
                          ),
                        if (dateText.isNotEmpty) const SizedBox(height: 8),
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            height: 1.3,
                          ),
                        ),
                        if (imageUrl.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
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
                                width: double.infinity,
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        SelectableText(
                          content,
                          style: const TextStyle(fontSize: 16, height: 1.55),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Container(
                padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + MediaQuery.of(context).padding.bottom),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: isRead
                    ? Container(
                        height: 54,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Text(
                            '확인 일시: $readAtText',
                            style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w600),
                          ),
                        ),
                      )
                    : SizedBox(
                        height: 54,
                        width: double.infinity,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF1a6ebd),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: _isMarking ? null : _markAsRead,
                          child: Text(
                            _isMarking ? '처리 중...' : '공지 확인 완료',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
