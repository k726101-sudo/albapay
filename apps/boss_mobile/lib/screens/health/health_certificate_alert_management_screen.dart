import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/worker.dart';
import '../../services/worker_service.dart';
import '../../widgets/store_id_gate.dart';
import '../../services/health_certificate_alert_service.dart';
import 'package:shared_logic/shared_logic.dart';

class HealthCertificateAlertManagementScreen extends StatefulWidget {
  const HealthCertificateAlertManagementScreen({super.key});

  @override
  State<HealthCertificateAlertManagementScreen> createState() =>
      _HealthCertificateAlertManagementScreenState();
}

class _HealthCertificateAlertManagementScreenState
    extends State<HealthCertificateAlertManagementScreen> {
  final _alertService = HealthCertificateAlertService();
  bool _loading = false;

  void _showSettings(BuildContext context, String storeId, DocumentReference<Map<String, dynamic>> settingsRef) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _HealthCertificateSettingsPanel(
        storeId: storeId,
        settingsRef: settingsRef,
        alertService: _alertService,
      ),
    );
  }

  void _showMessagingOptions(BuildContext context, Worker worker) {
    final expiry = worker.healthCertExpiry ?? '';
    final msg = '보건증 만료 안내드립니다. ${worker.name}님 보건증 만료일은 $expiry 입니다. 만료 전 재발급 부탁드립니다.';
    
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('${worker.name}님에게 안내 발송', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            ListTile(
              leading: const CircleAvatar(backgroundColor: Colors.blue, child: Icon(Icons.sms, color: Colors.white)),
              title: const Text('문자(SMS) 발송'),
              onTap: () {
                Navigator.pop(context);
                _sendSms(recipients: [worker.phone], message: msg);
              },
            ),
            ListTile(
              leading: const CircleAvatar(backgroundColor: Color(0xFFFAE100), child: Icon(Icons.chat_bubble, color: Color(0xFF3C1E1E))),
              title: const Text('카카오톡 전송'),
              onTap: () {
                Navigator.pop(context);
                _sendKakaoViaShare(msg);
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _showAddOrEditDialog(BuildContext context, {Worker? existing}) {
    final nameCtrl = TextEditingController(text: existing?.name);
    final phoneCtrl = TextEditingController(text: existing?.phone);
    DateTime selectedDate = DateTime.tryParse(existing?.healthCertExpiry ?? '') ?? AppClock.now();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? '보건증 관리 대상 추가' : '정보 수정'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '이름 (필수)')),
              TextField(
                controller: phoneCtrl,
                decoration: const InputDecoration(labelText: '전화번호 (필수/안내발송용)'),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text('만료일: '),
                  TextButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: AppClock.now().subtract(const Duration(days: 365)),
                        lastDate: AppClock.now().add(const Duration(days: 365 * 2)),
                      );
                      if (picked != null) {
                        setDialogState(() => selectedDate = picked);
                      }
                    },
                    child: Text(selectedDate.toIso8601String().substring(0, 10)),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
            TextButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                final phone = phoneCtrl.text.trim();
                if (name.isEmpty || phone.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('이름과 전화번호를 모두 입력해주세요.')));
                  return;
                }
                
                final w = existing?.copyWith(
                  name: name,
                  phone: phone,
                  healthCertExpiry: selectedDate.toIso8601String().substring(0, 10),
                  hasHealthCert: true,
                ) ?? Worker(
                  id: 'health_${DateTime.now().millisecondsSinceEpoch}',
                  name: name,
                  phone: phone,
                  birthDate: '',
                  workerType: 'regular',
                  hourlyWage: 0,
                  isPaidBreak: false,
                  breakMinutes: 0,
                  workDays: const [],
                  checkInTime: '09:00',
                  checkOutTime: '18:00',
                  weeklyHours: 0,
                  weeklyHolidayPay: false,
                  startDate: AppClock.now().toIso8601String().substring(0, 10),
                  isProbation: false,
                  probationMonths: 0,
                  allowances: const [],
                  hasHealthCert: true,
                  healthCertExpiry: selectedDate.toIso8601String().substring(0, 10),
                  status: 'health_only',
                  createdAt: AppClock.now().toIso8601String(),
                );

                await WorkerService.save(w);
                if (context.mounted) {
                  Navigator.pop(context);
                  setState(() {});
                }
              },
              child: const Text('저장'),
            ),
          ],
        ),
      ),
    );
  }

  void _showItemOptions(BuildContext context, Worker worker) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('정보 및 날짜 수정'),
              onTap: () {
                Navigator.pop(context);
                _showAddOrEditDialog(context, existing: worker);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('삭제', style: TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(context);
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('삭제 확인'),
                    content: Text('${worker.name}님의 기록을 완전히 삭제하시겠습니까?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
                      TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('삭제', style: TextStyle(color: Colors.red))),
                    ],
                  ),
                );
                if (confirm == true) {
                  await WorkerService.hardDelete(worker.id);
                  setState(() {});
                }
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  String _onlyDigits(String raw) => raw.replaceAll(RegExp(r'[^0-9]'), '');

  Future<void> _sendSms({
    required List<String> recipients,
    required String message,
  }) async {
    final phones = recipients.map(_onlyDigits).where((e) => e.isNotEmpty).toList();
    if (phones.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('수신번호가 없습니다.')),
      );
      return;
    }
    final uri = Uri(
      scheme: 'sms',
      path: phones.join(','),
      queryParameters: {'body': message},
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _sendKakaoViaShare(String message) async {
    await SharePlus.instance.share(
      ShareParams(text: message),
    );
  }

  Future<void> _pickAndSaveDate(Worker worker) async {
    final initial = DateTime.tryParse(worker.healthCertExpiry ?? '') ?? AppClock.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: AppClock.now().subtract(const Duration(days: 365)),
      lastDate: AppClock.now().add(const Duration(days: 365 * 2)),
      locale: const Locale('ko', 'KR'),
    );
    if (picked != null) {
      final newDateStr = picked.toIso8601String().substring(0, 10);
      setState(() => _loading = true);
      try {
        final updated = worker.copyWith(
          hasHealthCert: true,
          healthCertExpiry: newDateStr,
        );
        await WorkerService.save(updated);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${worker.name}님의 보건증 만료일이 $newDateStr로 업데이트되었습니다.')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('업데이트 실패: $e')),
          );
        }
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StoreIdGate(
      builder: (context, storeId) {
        final settingsRef = FirebaseFirestore.instance
            .collection('stores')
            .doc(storeId)
            .collection('notificationSettings')
            .doc('healthCertificate');

        return Scaffold(
          appBar: AppBar(
            title: const Text('보건증 관리'),
            actions: [
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => _showSettings(context, storeId, settingsRef),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: _buildMainContent(),
          floatingActionButton: FloatingActionButton(
            onPressed: () => _showAddOrEditDialog(context),
            backgroundColor: const Color(0xFF2D62ED),
            child: const Icon(Icons.add, color: Colors.white),
          ),
        );
      },
    );
  }

  Widget _buildMainContent() {
    final workers = WorkerService.getForHealthManagement();
    final today = AppClock.now();
    final todayKey = DateTime(today.year, today.month, today.day);

    if (workers.isEmpty) {
      return const Center(child: Text('등록된 재직 직원이 없습니다.'));
    }

    int expired = 0, d7 = 0, d15 = 0, d30 = 0;
    for (var w in workers) {
      final expiry = DateTime.tryParse(w.healthCertExpiry ?? '');
      if (expiry != null) {
        final diff = DateTime(expiry.year, expiry.month, expiry.day).difference(todayKey).inDays;
        if (diff < 0) {
          expired++;
        } else if (diff <= 7) d7++;
        else if (diff <= 15) d15++;
        else if (diff <= 30) d30++;
      }
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _summaryChip('만료', expired, Colors.red),
              _summaryChip('7일전', d7, Colors.deepOrange),
              _summaryChip('15일전', d15, Colors.orange),
              _summaryChip('1달전', d30, Colors.blue),
            ],
          ),
        ),
        const Divider(),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: workers.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final w = workers[index];
              final expiry = DateTime.tryParse(w.healthCertExpiry ?? '');
              
              String dDayText = '날짜 미등록';
              Color badgeColor = Colors.grey;
              if (expiry != null) {
                final diff = DateTime(expiry.year, expiry.month, expiry.day).difference(todayKey).inDays;
                if (diff < 0) {
                  dDayText = '만료 ${-diff}일 경과';
                  badgeColor = Colors.red;
                } else if (diff == 0) {
                  dDayText = '오늘 만료';
                  badgeColor = Colors.orange;
                } else {
                  dDayText = 'D-$diff';
                  badgeColor = diff <= 7 ? Colors.redAccent : (diff <= 30 ? Colors.orange : const Color(0xFF2D6A4F));
                }
              }

              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: Colors.grey.shade200),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  title: Text(w.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('만료일: ${w.healthCertExpiry ?? '정보 없음'}', style: const TextStyle(fontSize: 12)),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: badgeColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      dDayText,
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                  onTap: () => _showMessagingOptions(context, w),
                  onLongPress: () => _showItemOptions(context, w),
                ),
              );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.all(12),
          color: Colors.grey.shade50,
          child: const Text('직원을 누르면 문자/카톡 안내를 보냅니다. 길게 누르면 수정/삭제가 가능합니다.', 
            style: TextStyle(fontSize: 11, color: Colors.grey), textAlign: TextAlign.center),
        ),
      ],
    );
  }

  Widget _summaryChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text('$label $count건', style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }
}

class _HealthCertificateSettingsPanel extends StatefulWidget {
  final String storeId;
  final DocumentReference<Map<String, dynamic>> settingsRef;
  final HealthCertificateAlertService alertService;

  const _HealthCertificateSettingsPanel({
    required this.storeId,
    required this.settingsRef,
    required this.alertService,
  });

  @override
  State<_HealthCertificateSettingsPanel> createState() => _HealthCertificateSettingsPanelState();
}

class _HealthCertificateSettingsPanelState extends State<_HealthCertificateSettingsPanel> {
  bool _loading = false;

  Future<void> _save(Map<String, dynamic> current, String key, bool val) async {
    final next = Map<String, dynamic>.from(current);
    next[key] = val;
    await widget.settingsRef.set({
      ...next,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 20, 16, MediaQuery.of(context).padding.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('보건증 알림 설정', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: widget.settingsRef.snapshots(),
            builder: (context, snapshot) {
              final s = snapshot.data?.data() ?? {};
              final pushBoss = s['pushBoss'] ?? true;
              final pushStaff = s['pushStaff'] ?? true;
              final sms = s['sms'] ?? false;
              final kakao = s['kakao'] ?? false;

              return Column(
                children: [
                  SwitchListTile(
                    title: const Text('사장님 푸시 알림'),
                    value: pushBoss,
                    onChanged: (v) => _save(s, 'pushBoss', v),
                  ),
                  SwitchListTile(
                    title: const Text('알바생 푸시 알림'),
                    value: pushStaff,
                    onChanged: (v) => _save(s, 'pushStaff', v),
                  ),
                  SwitchListTile(
                    title: const Text('문자(SMS) 발송'),
                    value: sms,
                    onChanged: (v) => _save(s, 'sms', v),
                  ),
                  SwitchListTile(
                    title: const Text('카카오 알림톡 발송'),
                    value: kakao,
                    onChanged: (v) => _save(s, 'kakao', v),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _loading
                ? null
                : () async {
                    setState(() => _loading = true);
                    try {
                      await widget.alertService.syncAlerts(storeId: widget.storeId);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('동기화 완료')));
                      }
                    } finally {
                      if (mounted) setState(() => _loading = false);
                    }
                  },
            icon: const Icon(Icons.sync),
            label: Text(_loading ? '처리 중...' : '지금 전체 데이터 동기화'),
          ),
        ],
      ),
    );
  }
}
