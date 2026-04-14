import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../widgets/store_id_gate.dart';

class NoticeCreateScreen extends StatefulWidget {
  const NoticeCreateScreen({super.key});

  @override
  State<NoticeCreateScreen> createState() => _NoticeCreateScreenState();
}

class _NoticeCreateScreenState extends State<NoticeCreateScreen> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  bool _saving = false;
  bool _hasDueDate = false;
  DateTime _publishUntil = DateTime.now().add(const Duration(days: 7));

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StoreIdGate(
      builder: (context, storeId) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('공지 작성'),
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: '제목',
                  hintText: '예: 이번 주 위생점검 안내',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _contentController,
                decoration: const InputDecoration(
                  labelText: '내용',
                  hintText: '공지 내용을 입력하세요.',
                ),
                minLines: 6,
                maxLines: 10,
              ),
              const SizedBox(height: 16),
              StatefulBuilder(
                builder: (context, setFieldState) {
                  return Column(
                    children: [
                      SwitchListTile(
                        title: const Text('게시 기한 설정', style: TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          _hasDueDate 
                              ? '기한: ${_publishUntil.year}년 ${_publishUntil.month}월 ${_publishUntil.day}일' 
                              : '설정하지 않으면 직접 삭제할 때까지 유지됩니다.',
                          style: TextStyle(color: _hasDueDate ? Colors.blue.shade700 : Colors.black54, fontSize: 12),
                        ),
                        value: _hasDueDate,
                        activeThumbColor: Colors.blue,
                        onChanged: (val) async {
                          if (val) {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _publishUntil,
                              firstDate: DateTime.now(),
                              lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
                            );
                            if (picked != null) {
                              setFieldState(() {
                                _publishUntil = picked;
                                _hasDueDate = true;
                              });
                            }
                          } else {
                            setFieldState(() {
                              _hasDueDate = false;
                            });
                          }
                        },
                      ),
                    ],
                  );
                }
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 54,
                child: FilledButton.icon(
                  icon: const Icon(Icons.send_rounded),
                  onPressed: _saving
                      ? null
                      : () async {
                          final title = _titleController.text.trim();
                          final content = _contentController.text.trim();

                          if (title.isEmpty || content.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('제목과 내용을 입력해 주세요.'),
                              ),
                            );
                            return;
                          }

                          setState(() => _saving = true);
                          try {
                            final id = const Uuid().v4();
                            final data = <String, dynamic>{
                              'id': id,
                              'title': title,
                              'content': content,
                              'createdAt': FieldValue.serverTimestamp(),
                              'resolved': false,
                            };
                            
                            if (_hasDueDate) {
                              data['publishUntil'] = Timestamp.fromDate(
                                DateTime(_publishUntil.year, _publishUntil.month, _publishUntil.day, 23, 59, 59)
                              );
                            }

                            await FirebaseFirestore.instance
                                .collection('stores')
                                .doc(storeId)
                                .collection('notices')
                                .doc(id)
                                .set(data);
                            if (!context.mounted) return;
                            Navigator.pop(context);
                          } catch (e) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('공지 저장 실패: $e')),
                            );
                          } finally {
                            if (!mounted) return;
                            setState(() => _saving = false);
                          }
                        },
                  label: Text(_saving ? '저장 중...' : '작성 완료'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

