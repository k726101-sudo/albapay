import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:boss_mobile/widgets/store_id_gate.dart';

class MessageListScreen extends StatefulWidget {
  final bool showAppBar;
  const MessageListScreen({super.key, this.showAppBar = true});

  @override
  State<MessageListScreen> createState() => _MessageListScreenState();
}

class _MessageListScreenState extends State<MessageListScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  
  @override
  void initState() {
    super.initState();
  }

  Future<void> _addMessage(String title, String storeId) async {
    if (storeId.isEmpty) return;

    await _db.collection('stores').doc(storeId).collection('todos').add({
      'title': title,
      'done': false,
      'createdAt': FieldValue.serverTimestamp(),
      'authorName': '사장님',
      'isBoss': true,
      'order': DateTime.now().millisecondsSinceEpoch,
    });
  }

  void _showAddDialog(String storeId) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('전달사항 작성'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: '전달할 내용을 입력하세요 (예: 매장 청소 등)',
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
                _addMessage(title, storeId);
                Navigator.pop(ctx);
              }
            },
            child: const Text('작성'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleDone(String id, bool currentDone, String storeId) async {
    if (storeId.isEmpty) return;

    await _db.collection('stores').doc(storeId).collection('todos').doc(id).update({
      'done': !currentDone,
    });
  }

  Future<void> _deleteMessage(String id, String storeId) async {
    if (storeId.isEmpty) return;

    await _db.collection('stores').doc(storeId).collection('todos').doc(id).delete();
  }

  @override
  Widget build(BuildContext context) {
    return StoreIdGate(
      builder: (context, storeId) {
        Widget body = StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _db
              .collection('stores')
              .doc(storeId)
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

            return Card(
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              margin: const EdgeInsets.symmetric(vertical: 6),
              child: ListTile(
                leading: Checkbox(
                  value: isDone,
                  onChanged: (val) => _toggleDone(doc.id, isDone, storeId),
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
                subtitle: Text('작성자: $author', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.grey),
                  onPressed: () => _deleteMessage(doc.id, storeId),
                ),
              ),
            );
          },
        );
      },
    );

    if (!widget.showAppBar) {
      return body;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('전달사항 관리'),
      ),
      body: body,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddDialog(storeId),
        child: const Icon(Icons.add),
      ),
    );
      },
    );
  }
}
