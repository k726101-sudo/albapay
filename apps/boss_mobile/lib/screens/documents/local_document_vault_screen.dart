import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_logic/shared_logic.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum LocalDocCategory {
  businessRegistration('사업자등록증'),
  salesPermit('영업허가증'),
  hygieneCertificate('위생교육 필증'),
  insurance('보험/산재 서류'),
  etc('기타');

  const LocalDocCategory(this.label);
  final String label;
}

class LocalStoredDoc {
  final String id;
  final String fileName;
  final String localPath;
  final LocalDocCategory category;
  final DateTime createdAt;
  final String? memo;

  LocalStoredDoc({
    required this.id,
    required this.fileName,
    required this.localPath,
    required this.category,
    required this.createdAt,
    this.memo,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'fileName': fileName,
        'localPath': localPath,
        'category': category.name,
        'createdAt': createdAt.toIso8601String(),
        'memo': memo,
      };

  static LocalStoredDoc fromJson(Map<String, dynamic> json) => LocalStoredDoc(
        id: json['id'] as String,
        fileName: json['fileName'] as String,
        localPath: json['localPath'] as String,
        category: LocalDocCategory.values.byName(json['category'] as String),
        createdAt: DateTime.parse(json['createdAt'] as String),
        memo: json['memo'] as String?,
      );
}

class LocalDocumentVaultScreen extends StatefulWidget {
  const LocalDocumentVaultScreen({super.key});

  @override
  State<LocalDocumentVaultScreen> createState() =>
      _LocalDocumentVaultScreenState();
}

class _LocalDocumentVaultScreenState extends State<LocalDocumentVaultScreen> {
  static const _prefsKey = 'local_document_vault_v1';
  final _picker = ImagePicker();

  bool _loading = true;
  List<LocalStoredDoc> _docs = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) {
      setState(() {
        _docs = const [];
        _loading = false;
      });
      return;
    }
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      final docs = decoded
          .map((e) => LocalStoredDoc.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      setState(() {
        _docs = docs;
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _docs = const [];
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(_docs.map((d) => d.toJson()).toList());
    await prefs.setString(_prefsKey, raw);
  }

  Future<Directory> _vaultDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/vault_documents');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<void> _addFromFiles(LocalDocCategory category) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: false,
    );
    final file = result?.files.single;
    final path = file?.path;
    if (path == null) return;
    final name = file?.name;
    final originalName =
        (name == null || name.trim().isEmpty) ? 'file_${AppClock.now().millisecondsSinceEpoch}' : name;
    await _importFile(File(path), originalName, category);
  }

  Future<void> _addFromCamera(LocalDocCategory category) async {
    final x = await _picker.pickImage(source: ImageSource.camera);
    if (x == null) return;
    final originalName =
        (x.name.trim().isEmpty) ? 'camera_${AppClock.now().millisecondsSinceEpoch}.jpg' : x.name;
    await _importFile(File(x.path), originalName, category);
  }

  Future<void> _addFromGallery(LocalDocCategory category) async {
    final x = await _picker.pickImage(source: ImageSource.gallery);
    if (x == null) return;
    final originalName =
        (x.name.trim().isEmpty) ? 'gallery_${AppClock.now().millisecondsSinceEpoch}.jpg' : x.name;
    await _importFile(File(x.path), originalName, category);
  }

  Future<void> _importFile(
    File src,
    String originalName,
    LocalDocCategory category,
  ) async {
    setState(() => _loading = true);
    try {
      final dir = await _vaultDir();
      final id = AppClock.now().microsecondsSinceEpoch.toString();
      final safeName = originalName.isEmpty ? 'document' : originalName;
      final ext = safeName.contains('.') ? safeName.split('.').last : '';
      final destName = ext.isEmpty ? id : '$id.$ext';
      final destPath = '${dir.path}/$destName';
      await src.copy(destPath);

      final doc = LocalStoredDoc(
        id: id,
        fileName: safeName,
        localPath: destPath,
        category: category,
        createdAt: AppClock.now(),
      );
      final next = [doc, ..._docs];
      setState(() => _docs = next);
      await _save();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('저장 실패: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _delete(LocalStoredDoc doc) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('삭제할까요?'),
        content: Text('“${doc.fileName}” 파일을 이 기기에서 삭제합니다.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('삭제')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _loading = true);
    try {
      final f = File(doc.localPath);
      if (await f.exists()) {
        await f.delete();
      }
      final next = _docs.where((d) => d.id != doc.id).toList();
      setState(() => _docs = next);
      await _save();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showAddSheet() async {
    LocalDocCategory category = LocalDocCategory.businessRegistration;
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            return SafeArea(
              bottom: true,
              top: false,
              left: false,
              right: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('서류 추가',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<LocalDocCategory>(
                      initialValue: category,
                      items: LocalDocCategory.values
                          .map((c) => DropdownMenuItem(value: c, child: Text(c.label)))
                          .toList(),
                      onChanged: (v) => setSheet(() => category = v ?? category),
                      decoration: const InputDecoration(labelText: '분류'),
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      leading: const Icon(Icons.camera_alt_outlined),
                      title: const Text('카메라로 촬영'),
                      onTap: () {
                        Navigator.pop(ctx);
                        _addFromCamera(category);
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.photo_outlined),
                      title: const Text('갤러리에서 선택'),
                      onTap: () {
                        Navigator.pop(ctx);
                        _addFromGallery(category);
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.attach_file),
                      title: const Text('파일에서 선택 (PDF 등)'),
                      onTap: () {
                        Navigator.pop(ctx);
                        _addFromFiles(category);
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('서류 보관 (로컬)'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _showAddSheet,
            icon: const Icon(Icons.add),
            tooltip: '추가',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.shade100),
                  ),
                  child: const Text(
                    '서류는 이 기기(로컬)에만 저장됩니다.\n'
                    '기기 분실/교체 시 복구가 어려울 수 있으니 유의하세요.',
                  ),
                ),
                const SizedBox(height: 12),
                if (_docs.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 48),
                    child: Center(child: Text('저장된 서류가 없습니다. 우측 상단 + 로 추가하세요.')),
                  ),
                for (final doc in _docs)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.insert_drive_file_outlined),
                      title: Text(doc.fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${doc.category.label} · ${doc.createdAt.year}/${doc.createdAt.month.toString().padLeft(2, '0')}'),
                          const SizedBox(height: 4),
                          _buildExpiryText(doc.createdAt),
                        ],
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: _loading ? null : () => _delete(doc),
                      ),
                    ),
                  ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _loading ? null : _showAddSheet,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildExpiryText(DateTime createdAt) {
    final expiryDate = DateTime(createdAt.year + PayrollConstants.defaultRetentionYears, createdAt.month, createdAt.day);
    final now = AppClock.now();
    final daysLeft = expiryDate.difference(now).inDays;

    if (daysLeft < 0) {
      return const Text('보존 기한 만료', style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold));
    } else if (daysLeft <= 30) {
      return Text('폐기 D-$daysLeft (임박)', style: const TextStyle(fontSize: 12, color: Colors.redAccent, fontWeight: FontWeight.bold));
    } else {
      return Text('법정 보존 기한: $daysLeft일 남음', style: const TextStyle(fontSize: 11, color: Colors.blueGrey));
    }
  }
}

