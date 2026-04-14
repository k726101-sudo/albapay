import 'package:flutter/material.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import 'package:intl/intl.dart';

import 'notice_list_screen.dart';
import 'notice_create_screen.dart';
import 'education/education_tracking_screen.dart';
import 'tasks/message_list_screen.dart';
import 'tasks/expiration_list_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:boss_mobile/widgets/store_id_gate.dart';

class NoticeEducationTabScreen extends StatefulWidget {
  final int initialIndex;

  const NoticeEducationTabScreen({
    super.key,
    this.initialIndex = 0,
  });

  @override
  State<NoticeEducationTabScreen> createState() => _NoticeEducationTabScreenState();
}

class _NoticeEducationTabScreenState extends State<NoticeEducationTabScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  
  @override
  void initState() {
    super.initState();
  }

  void _showAddMessageDialog(String storeId) {
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
            onPressed: () async {
              final title = controller.text.trim();
              if (title.isNotEmpty) {
                if (storeId.isNotEmpty) {
                  await _db.collection('stores').doc(storeId).collection('todos').add({
                    'title': title,
                    'done': false,
                    'createdAt': FieldValue.serverTimestamp(),
                    'authorName': '사장님',
                    'isBoss': true,
                    'order': DateTime.now().millisecondsSinceEpoch,
                  });
                }
                if (context.mounted) Navigator.pop(ctx);
              }
            },
            child: const Text('작성'),
          ),
        ],
      ),
    );
  }

  void _showAddExpirationDialog(String storeId) {
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
                  onPressed: () async {
                    final name = nameController.text.trim();
                    final qty = qtyController.text.trim();
                    if (name.isNotEmpty) {
                      if (storeId.isNotEmpty) {
                        await _db.collection('stores').doc(storeId).collection('expirations').add({
                          'productName': name,
                          'quantity': qty,
                          'dueDate': Timestamp.fromDate(selectedDate),
                          'dueDateString': DateFormat('yyyy-MM-dd').format(selectedDate),
                          'createdAt': FieldValue.serverTimestamp(),
                        });
                      }
                      if (context.mounted) Navigator.pop(ctx);
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

  @override
  Widget build(BuildContext context) {
    return StoreIdGate(
      builder: (context, storeId) {
        return DefaultTabController(
          length: 4,
          initialIndex: widget.initialIndex,
          child: Scaffold(
        appBar: AppBar(
          title: const Text('공지 및 업무'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: '공지사항'),
              Tab(text: '전달사항'),
              Tab(text: '유통기한'),
              Tab(text: '교육 및 매뉴얼'),
            ],
            indicatorColor: Colors.black,
            labelColor: Colors.black,
            unselectedLabelColor: Colors.grey,
          ),
        ),
        body: const TabBarView(
          children: [
            NoticeListScreen(showAppBar: false),
            MessageListScreen(showAppBar: false),
            ExpirationListScreen(showAppBar: false),
            EducationTrackingScreen(showAppBar: false),
          ],
        ),
        floatingActionButton: SpeedDial(
          icon: Icons.add,
          activeIcon: Icons.close,
          spacing: 3,
          mini: false,
          childPadding: const EdgeInsets.all(5),
          spaceBetweenChildren: 4,
          backgroundColor: const Color(0xFFEF9F27),
          foregroundColor: Colors.white,
          elevation: 8.0,
          animationCurve: Curves.elasticInOut,
          children: [
            SpeedDialChild(
              child: const Icon(Icons.campaign),
              backgroundColor: Colors.blueAccent,
              foregroundColor: Colors.white,
              label: '공지 작성',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const NoticeCreateScreen(),
                  ),
                );
              },
            ),
            SpeedDialChild(
              child: const Icon(Icons.check_circle_outline),
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              label: '전달사항 작성',
              onTap: () => _showAddMessageDialog(storeId),
            ),
            SpeedDialChild(
              child: const Icon(Icons.inventory_2_outlined),
              backgroundColor: Colors.deepOrange,
              foregroundColor: Colors.white,
              label: '유통기한 등록',
              onTap: () => _showAddExpirationDialog(storeId),
            ),
          ],
        ),
      ),
    );
      },
    );
  }
}
