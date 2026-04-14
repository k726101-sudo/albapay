import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AlbaExpirationListScreen extends StatefulWidget {
  final String storeId;
  final bool showAppBar;

  const AlbaExpirationListScreen({
    super.key,
    required this.storeId,
    this.showAppBar = true,
  });

  @override
  State<AlbaExpirationListScreen> createState() => _AlbaExpirationListScreenState();
}

class _AlbaExpirationListScreenState extends State<AlbaExpirationListScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  bool _isCleanedUp = false;

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  Future<void> _addExpiration(String productName, String quantity, DateTime dueDate) async {
    if (widget.storeId.isEmpty) return;

    await _db.collection('stores').doc(widget.storeId).collection('expirations').add({
      'productName': productName,
      'quantity': quantity,
      'dueDate': Timestamp.fromDate(dueDate),
      'dueDateString': _formatDate(dueDate),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  void _showAddDialog() {
    final nameController = TextEditingController();
    final qtyController = TextEditingController();
    DateTime selectedDate = DateTime.now();

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (stCtx, setState) {
            return AlertDialog(
              title: const Text('유통기한 등록'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: '품목명',
                      hintText: '예: 우유, 샌드위치',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: qtyController,
                    decoration: const InputDecoration(
                      labelText: '수량 또는 비고',
                      hintText: '예: 2개',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: stCtx,
                        initialDate: selectedDate,
                        firstDate: DateTime.now().subtract(const Duration(days: 30)),
                        lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
                      );
                      if (picked != null) {
                        setState(() {
                          selectedDate = picked;
                        });
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('폐기 예정일: ${_formatDate(selectedDate)}'),
                          const Icon(Icons.calendar_today, size: 18),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('취소'),
                ),
                FilledButton(
                  onPressed: () {
                    final name = nameController.text.trim();
                    final qty = qtyController.text.trim();
                    if (name.isNotEmpty) {
                      _addExpiration(name, qty, selectedDate);
                      Navigator.pop(ctx);
                    }
                  },
                  child: const Text('등록'),
                ),
              ],
            );
          }
        );
      },
    );
  }

  Future<void> _deleteExpiration(String id) async {
    if (widget.storeId.isEmpty) return;
    await _db.collection('stores').doc(widget.storeId).collection('expirations').doc(id).delete();
  }

  Future<void> _cleanupExpiredItems(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) async {
    if (_isCleanedUp || widget.storeId.isEmpty) return;
    _isCleanedUp = true;
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final yesterdayStart = todayStart.subtract(const Duration(days: 1));
    for (final doc in docs) {
      final ts = doc.data()['dueDate'];
      if (ts is Timestamp) {
        final dt = ts.toDate();
        final dueDay = DateTime(dt.year, dt.month, dt.day);
        if (dueDay.isBefore(yesterdayStart)) {
          _db.collection('stores').doc(widget.storeId).collection('expirations').doc(doc.id).delete().catchError((_) {});
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget body = StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _db
          .collection('stores')
          .doc(widget.storeId)
          .collection('expirations')
          .orderBy('dueDate', descending: false)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data!.docs;
        _cleanupExpiredItems(docs);

        if (docs.isEmpty) {
          return const Center(
            child: Text('등록된 유통기한이 없습니다.', style: TextStyle(color: Colors.grey)),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data();
            final name = data['productName']?.toString() ?? '품목';
            final qty = data['quantity']?.toString() ?? '';
            final dueStr = data['dueDateString']?.toString() ?? '';
            
            // Highlight if past or today
            bool isWarning = false;
            final ts = data['dueDate'];
            if (ts is Timestamp) {
              final dueDt = ts.toDate();
              final now = DateTime.now();
              final dueDay = DateTime(dueDt.year, dueDt.month, dueDt.day);
              final nowDay = DateTime(now.year, now.month, now.day);
              if (dueDay.isBefore(nowDay) || dueDay.isAtSameMomentAs(nowDay)) {
                isWarning = true;
              }
            }

            return Card(
              elevation: 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: isWarning ? Colors.redAccent.withValues(alpha: 0.5) : Colors.transparent),
              ),
              margin: const EdgeInsets.symmetric(vertical: 6),
              child: ListTile(
                leading: const Icon(
                  Icons.inventory_2_outlined, 
                  color: Colors.teal,
                ),
                title: Text(
                  name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  qty.isNotEmpty ? '수량: $qty\n기한: $dueStr' : '기한: $dueStr',
                  style: TextStyle(
                    color: isWarning ? Colors.redAccent : Colors.black54,
                    fontWeight: isWarning ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                trailing: TextButton.icon(
                  icon: const Icon(Icons.delete_outline, size: 18, color: Colors.grey),
                  label: const Text('삭제', style: TextStyle(color: Colors.grey)),
                  onPressed: () => _deleteExpiration(doc.id),
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
        title: const Text('유통기한 관리'),
      ),
      body: body,
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}
