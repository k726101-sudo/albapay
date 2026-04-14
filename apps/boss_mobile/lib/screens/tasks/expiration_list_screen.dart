import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:boss_mobile/widgets/store_id_gate.dart';

class ExpirationListScreen extends StatefulWidget {
  final bool showAppBar;
  const ExpirationListScreen({super.key, this.showAppBar = true});

  @override
  State<ExpirationListScreen> createState() => _ExpirationListScreenState();
}

class _ExpirationListScreenState extends State<ExpirationListScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  
  @override
  void initState() {
    super.initState();
  }

  Future<void> _addExpiration(String productName, String quantity, DateTime dueDate, String storeId) async {
    if (storeId.isEmpty) return;

    await _db.collection('stores').doc(storeId).collection('expirations').add({
      'productName': productName,
      'quantity': quantity,
      'dueDate': Timestamp.fromDate(dueDate),
      'dueDateString': DateFormat('yyyy-MM-dd').format(dueDate),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  void _showAddDialog(String storeId) {
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
                          Text('폐기 예정일: ${DateFormat('yyyy-MM-dd').format(selectedDate)}'),
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
                      _addExpiration(name, qty, selectedDate, storeId);
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

  Future<void> _deleteExpiration(String id, String storeId) async {
    if (storeId.isEmpty) return;

    await _db.collection('stores').doc(storeId).collection('expirations').doc(id).delete();
  }

  bool _isCleanedUp = false;

  Future<void> _cleanupExpiredItems(String storeId, List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) async {
    if (_isCleanedUp || storeId.isEmpty) return;
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
          _db.collection('stores').doc(storeId).collection('expirations').doc(doc.id).delete().catchError((_) {});
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StoreIdGate(
      builder: (context, storeId) {
        Widget body = StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _db
              .collection('stores')
              .doc(storeId)
              .collection('expirations')
              .orderBy('dueDate', descending: false)
              .snapshots(),
          builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data!.docs;
        _cleanupExpiredItems(storeId, docs);

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
                leading: Icon(
                  Icons.inventory_rounded, 
                  color: isWarning ? Colors.redAccent : Colors.teal,
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
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.grey),
                  onPressed: () => _deleteExpiration(doc.id, storeId),
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
        title: const Text('유통기한 관리'),
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
