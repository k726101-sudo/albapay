import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AlbaMessageListScreen extends StatefulWidget {
  final String storeId;
  final String workerName;
  final bool showAppBar;

  const AlbaMessageListScreen({
    super.key,
    required this.storeId,
    required this.workerName,
    this.showAppBar = true,
  });

  @override
  State<AlbaMessageListScreen> createState() => _AlbaMessageListScreenState();
}

class _AlbaMessageListScreenState extends State<AlbaMessageListScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> _addMessage(String title) async {
    if (widget.storeId.isEmpty) return;

    await _db.collection('stores').doc(widget.storeId).collection('todos').add({
      'title': title,
      'done': false,
      'createdAt': FieldValue.serverTimestamp(),
      'authorName': widget.workerName,
      'isBoss': false,
      'order': DateTime.now().millisecondsSinceEpoch,
    });
  }

  void _showAddDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('전달사항 작성'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: '사장님이나 다른 알바생에게 남길 메모를 입력하세요.',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () {
              final title = controller.text.trim();
              if (title.isNotEmpty) {
                _addMessage(title);
                Navigator.pop(ctx);
              }
            },
            child: const Text('작성'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleDone(String id, bool currentDone) async {
    if (widget.storeId.isEmpty) return;

    await _db.collection('stores').doc(widget.storeId).collection('todos').doc(id).update({
      'done': !currentDone,
      if (!currentDone) 'completedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _deleteMessage(String id) async {
    if (widget.storeId.isEmpty) return;
    await _db.collection('stores').doc(widget.storeId).collection('todos').doc(id).delete();
  }

  @override
  Widget build(BuildContext context) {
    Widget body = StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _db
          .collection('stores')
          .doc(widget.storeId)
          .collection('todos')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return const Center(
            child: Text('등록된 전달사항이 없습니다.', style: TextStyle(color: Colors.grey)),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data();
            final title = data['title']?.toString() ?? '내용 없음';
            final isDone = data['done'] == true;
            final author = data['authorName']?.toString() ?? '작성자 미상';
            final isBoss = data['isBoss'] == true;

            return Card(
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              margin: const EdgeInsets.symmetric(vertical: 6),
              child: ListTile(
                leading: Checkbox(
                  value: isDone,
                  onChanged: (val) => _toggleDone(doc.id, isDone),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                ),
                title: Text(
                  title,
                  style: TextStyle(
                    decoration: isDone ? TextDecoration.lineThrough : null,
                    color: isDone ? Colors.grey : Colors.black87,
                    fontWeight: isDone ? FontWeight.normal : FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  '작성자: $author${isBoss ? ' (사장님)' : ''}', 
                  style: TextStyle(fontSize: 12, color: isBoss ? Colors.blue.shade700 : Colors.black54)
                ),
                trailing: TextButton.icon(
                  icon: const Icon(Icons.delete_outline, size: 18, color: Colors.grey),
                  label: const Text('삭제', style: TextStyle(color: Colors.grey)),
                  onPressed: () => _deleteMessage(doc.id),
                ),
              ),
            );
          },
        );
      },
    );

    if (!widget.showAppBar) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F5F5),
        body: body,
        floatingActionButton: FloatingActionButton(
          onPressed: _showAddDialog,
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          elevation: 2,
          child: const Icon(Icons.add),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('전달사항 관리'),
      ),
      body: body,
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}
