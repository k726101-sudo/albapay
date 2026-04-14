import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_logic/shared_logic.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/store_info.dart';
import '../services/boss_logout.dart';
import 'login_screen.dart';
import 'documents/document_management_screen.dart';
import 'documents/local_document_vault_screen.dart';
import 'documents/retired_worker_management_screen.dart';
import 'education/education_tracking_screen.dart';
import 'health/health_certificate_alert_management_screen.dart';
import 'store_info_page.dart';
import 'staff/staff_list_screen.dart';
import 'settings/settings_screen.dart';
import '../services/worker_service.dart';
import 'settings/backup_screen.dart';
import 'settings/withdraw_screen.dart';

/// Brand colors aligned with the rest of the boss app.
const Color kMainTabNavy = Color(0xFF0032A0);
const Color kMainTabCoral = Color(0xFFE07A5F);

Future<void> _openLegalUrl(BuildContext context, String url) async {
  final uri = Uri.parse(url);
  if (!context.mounted) return;
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } else if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('링크를 열 수 없습니다: $url')),
    );
  }
}

Future<void> _confirmBossLogout(BuildContext context) async {
  final confirm = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('로그아웃'),
      content: const Text('정말 로그아웃 하시겠습니까?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('확인', style: TextStyle(color: Color(0xFFE24B4A))),
        ),
      ],
    ),
  );
  if (confirm != true || !context.mounted) return;
  await performBossLogout(AuthService());
  if (!context.mounted) return;
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const LoginScreen()),
    (route) => false,
  );
}

Future<void> _runBackfillInviteCodes(BuildContext context) async {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );

  try {
    final count = await WorkerService.backfillAllInviteCodes();
    if (!context.mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('초대 코드 복구 완료: $count건')),
    );
  } catch (e) {
    if (context.mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('복구 실패: $e')),
      );
    }
  }
}

class StaffTabContent extends StatelessWidget {
  const StaffTabContent({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1a1a2e),
        title: const Text('직원 관리', style: TextStyle(color: Colors.white)),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          child: ListView(
            children: [
              menuBigCard(
                context,
                icon: Icons.people_alt_rounded,
                title: '직원 관리',
                subtitle: '근무자 정보/퇴사/보건증 상태',
                color: kMainTabNavy,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const StaffListScreen()),
                ),
              ),
              const SizedBox(height: 12),
              menuBigCard(
                context,
                icon: Icons.health_and_safety_outlined,
                title: '보건증 알림',
                subtitle: '임박/만료 알림 설정 및 발송',
                color: kMainTabCoral,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const HealthCertificateAlertManagementScreen(),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              menuBigCard(
                context,
                icon: Icons.school_rounded,
                title: '교육 관리',
                subtitle: '필수 교육 이수 현황',
                color: const Color(0xFF2A9D8F),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const EducationTrackingScreen(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DocumentsTabContent extends StatelessWidget {
  const DocumentsTabContent({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1a1a2e),
        title: const Text('노무서류', style: TextStyle(color: Colors.white)),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          child: ListView(
            children: [
              menuBigCard(
                context,
                icon: Icons.article_rounded,
                title: '노무 서류',
                subtitle: '근로계약서/동의서/명부',
                color: const Color(0xFF8E44AD),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const DocumentManagementScreen(),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              menuBigCard(
                context,
                icon: Icons.person_off_rounded,
                title: '퇴사자 관리',
                subtitle: '퇴사자 서류 기록 보관/복직',
                color: Colors.blueGrey.shade700,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const RetiredWorkerManagementScreen(),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              menuBigCard(
                context,
                icon: Icons.folder_copy_rounded,
                title: '서류 보관',
                subtitle: '사업장 문서 로컬 보관',
                color: kMainTabNavy,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const LocalDocumentVaultScreen(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SettingsTabContent extends StatefulWidget {
  const SettingsTabContent({super.key});

  @override
  State<SettingsTabContent> createState() => _SettingsTabContentState();
}

class _SettingsTabContentState extends State<SettingsTabContent> {
  @override
  void initState() {
    super.initState();
    _pingLastLogin();
  }

  Future<void> _pingLastLogin() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      try {
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'lastLoginAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('Failed to ping last login: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final storeBox = Hive.box<StoreInfo>('store');
    return ValueListenableBuilder<Box<StoreInfo>>(
      valueListenable: storeBox.listenable(),
      builder: (context, box, _) {
        final store = box.get('current');
        final storeName = (store?.storeName.trim().isNotEmpty ?? false)
            ? store!.storeName.trim()
            : '매장명 미설정';
        final isRegistered = store?.isRegistered ?? false;

        return Scaffold(
          backgroundColor: const Color(0xFFF2F2F7),
          appBar: AppBar(
            backgroundColor: const Color(0xFF1a1a2e),
            title: const Text(
              '설정',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
            elevation: 0,
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _buildUnregisteredBanner(isRegistered),
                  const SizedBox(height: 24),
                  _buildSectionLabel('사업장'),
                  _buildSettingsGroup([
                    _buildSettingsRow(
                      icon: Icons.store_outlined,
                      iconBg: const Color(0xFF1a6ebd),
                      title: '사업장 정보',
                      subtitle: storeName,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const StoreInfoPage()),
                      ),
                    ),
                    _buildSettingsRow(
                      icon: Icons.access_time_outlined,
                      iconBg: const Color(0xFF286b3a),
                      title: '출퇴근 설정',
                      subtitle: 'QR 출퇴근 사용 여부',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const StoreInfoPage(
                            initialFocus: StoreInfoPageFocus.commute,
                          ),
                        ),
                      ),
                    ),
                    _buildSettingsRow(
                      icon: Icons.qr_code_2_rounded,
                      iconBg: const Color(0xFF4F46E5),
                      title: '출퇴근용 QR 생성',
                      subtitle: '직원 QR 체크인/퇴근용 코드',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const StoreAttendanceQrScreen(),
                        ),
                      ),
                    ),
                    _buildSettingsRow(
                      icon: Icons.payments_outlined,
                      iconBg: const Color(0xFFd4700a),
                      title: '급여·보험 설정',
                      subtitle: '정산 주기, 지급일, 두루누리',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const StoreInfoPage(
                            initialFocus: StoreInfoPageFocus.payroll,
                          ),
                        ),
                      ),
                      isLast: true,
                    ),
                  ]),
                  const SizedBox(height: 24),
                  _buildSectionLabel('사업장 규모'),
                  _EmployeeSizeSwitchSection(storeInfoBox: box),
                  const SizedBox(height: 24),
                  _buildSectionLabel('데이터 관리'),
                  _buildBackupSection(),
                  const SizedBox(height: 24),
                  _buildSectionLabel('알림'),
                  _buildSettingsGroup([
                    _buildSettingsRow(
                      icon: Icons.notifications_outlined,
                      iconBg: const Color(0xFF8B5CF6),
                      title: '푸시알림 설정',
                      subtitle: '보건증 만료, 급여일 알림',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              const HealthCertificateAlertManagementScreen(),
                        ),
                      ),
                      isLast: true,
                    ),
                  ]),
                  const SizedBox(height: 24),
                  _buildSectionLabel('앱 정보'),
                  _buildSettingsGroup([
                    _buildSettingsRow(
                      icon: Icons.shield_outlined,
                      iconBg: const Color(0xFF6B7280),
                      title: '면책 고지',
                      subtitle: '급여 계산 참고용 안내',
                      onTap: () => _openLegalUrl(
                        context,
                        'https://standard-albapay.web.app/terms',
                      ),
                    ),
                    _buildSettingsRow(
                      icon: Icons.privacy_tip_outlined,
                      iconBg: const Color(0xFF6B7280),
                      title: '개인정보처리방침',
                      subtitle: '',
                      onTap: () => _openLegalUrl(
                        context,
                        'https://standard-albapay.web.app/privacy',
                      ),
                    ),
                    _buildSettingsRow(
                      icon: Icons.info_outline,
                      iconBg: const Color(0xFF6B7280),
                      title: '버전',
                      subtitle: '1.0.0',
                      onTap: null,
                      showChevron: false,
                      isLast: true,
                    ),
                  ]),
                  const SizedBox(height: 24),
                  _buildSectionLabel('계정'),
                  _buildSettingsGroup([
                    _buildSettingsRow(
                      icon: Icons.logout_rounded,
                      iconBg: const Color(0xFFE24B4A),
                      title: '로그아웃',
                      subtitle: '이 기기에서 로그아웃합니다',
                      onTap: () => _confirmBossLogout(context),
                      titleColor: const Color(0xFFE24B4A),
                      isLast: false,
                    ),
                    _buildSettingsRow(
                      icon: Icons.person_remove_rounded,
                      iconBg: const Color(0xFF333333),
                      title: '회원 탈퇴',
                      subtitle: '모든 데이터를 파기하고 계정을 삭제합니다',
                      onTap: () async {
                        final sid = await WorkerService.resolveStoreId();
                        if (!context.mounted) return;
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => WithdrawScreen(storeId: sid)),
                        );
                      },
                      titleColor: const Color(0xFF333333),
                      isLast: true,
                    ),
                  ]),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildUnregisteredBanner(bool isRegistered) {
    if (isRegistered) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF0DC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFd4700a), width: 0.5),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: Color(0xFFd4700a),
            size: 20,
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              '사업장 정보를 등록해주세요',
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF854F0B),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const StoreInfoPage()),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFd4700a),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                '등록',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 13,
          color: Color(0xFF888888),
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildSettingsGroup(List<Widget> children) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E5EA), width: 0.5),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildBackupSection() {
    return _buildSettingsGroup([
      _buildSettingsRow(
        icon: Icons.security,
        iconBg: const Color(0xFF10B981),
        title: '데이터 백업/복원 관리',
        subtitle: '수동 파일 백업/복원 및 보관 데이터 관리',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const BackupScreen()),
        ),
        isLast: true,
      ),
    ]);
  }


  Widget _buildSettingsRow({
    required IconData icon,
    required Color iconBg,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
    bool showChevron = true,
    bool isLast = false,
    Color? titleColor,
  }) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: titleColor,
                        ),
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF888888),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (showChevron)
                  const Icon(
                    Icons.chevron_right,
                    color: Color(0xFFBBBBBB),
                    size: 20,
                  ),
              ],
            ),
          ),
        ),
        if (!isLast)
          const Divider(
            height: 1,
            thickness: 0.5,
            indent: 60,
            endIndent: 0,
            color: Color(0xFFF0F0F0),
          ),
      ],
    );
  }
}

Widget menuBigCard(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String subtitle,
  required Color color,
  required VoidCallback onTap,
}) {
  return Card(
    elevation: 2,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    child: InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: color.withValues(alpha: 0.14),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.black54,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    ),
  );
}

// ─── 5인 기준 마스터 스위치 섹션 ───────────────────────────────────────────

class _EmployeeSizeSwitchSection extends StatefulWidget {
  final Box<StoreInfo> storeInfoBox;
  const _EmployeeSizeSwitchSection({required this.storeInfoBox});

  @override
  State<_EmployeeSizeSwitchSection> createState() =>
      _EmployeeSizeSwitchSectionState();
}

class _EmployeeSizeSwitchSectionState
    extends State<_EmployeeSizeSwitchSection> {
  bool _isSaving = false;

  // storeId를 모든 직원의 정보에서 가져옵니다.
  String get _storeId {
    final workers = WorkerService.getAll();
    return workers
        .map((w) => w.storeId)
        .firstWhere((id) => id.trim().isNotEmpty, orElse: () => '');
  }

  Future<void> _setMode(String mode, bool autoIsFiveOrMore, {String? reason}) async {
    final storeId = _storeId;
    if (storeId.isEmpty) return;
    setState(() => _isSaving = true);
    try {
      final bool finalIsFiveOrMore = mode == 'auto'
          ? autoIsFiveOrMore
          : mode == 'manual_5plus';
      final Map<String, dynamic> up = {
        'employeeSizeMode': mode,
        'isFiveOrMore': finalIsFiveOrMore,
      };
      if (reason != null) {
        up['employeeSizeChangeReason'] = reason;
        up['employeeSizeChangeAt'] = FieldValue.serverTimestamp();
      }
      await FirebaseFirestore.instance.collection('stores').doc(storeId).update(up);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _showReasonDialog(String mode, bool autoIsFiveOrMore) async {
    final controller = TextEditingController();
    final String label = mode == 'manual_5plus' ? '5인 이상 고정' : '5인 미만 고정';
    
    final reason = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text('$label 사유 입력'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('설정을 수동으로 변경하는 사유를 입력해주세요.\n(예: "가족 2명 제외로 실제 5인 미만임")',
                style: TextStyle(fontSize: 13, color: Colors.black54)),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: '사유를 입력하세요',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.all(12),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('저장'),
          ),
        ],
      ),
    );

    if (reason != null && reason.isNotEmpty) {
      await _setMode(mode, autoIsFiveOrMore, reason: reason);
    }
  }

  @override
  Widget build(BuildContext context) {
    final storeId = _storeId;
    if (storeId.isEmpty) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE5E5EA), width: 0.5),
        ),
        child: const Text('사업장 정보를 먼저 등록해주세요.',
            style: TextStyle(fontSize: 13, color: Colors.black54)),
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('stores')
          .doc(storeId)
          .snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() ?? {};
        final mode = data['employeeSizeMode']?.toString() ?? 'auto';
        final autoAvg = (data['averageWorkers'] as num?)?.toDouble() ?? 0.0;
        final daysWithFive = (data['daysWithFiveOrMore'] as num?)?.toInt() ?? 0;
        final totalDays = (data['totalBusinessDays'] as num?)?.toInt() ?? 0;
        // 자동 판정 결과 (Firestore에 저장된 isFiveOrMore 참조)
        final autoIsFiveOrMore = data['isFiveOrMore'] as bool? ?? false;

        // 최종 유효 판정
        bool effectiveIsFive;
        String effectiveLabel;
        Color effectiveColor;
        if (mode == 'manual_5plus') {
          effectiveIsFive = true;
          effectiveLabel = '5인 이상 고정';
          effectiveColor = const Color(0xFF1a6ebd);
        } else if (mode == 'manual_under5') {
          effectiveIsFive = false;
          effectiveLabel = '5인 미만 고정';
          effectiveColor = const Color(0xFF555555);
        } else {
          effectiveIsFive = autoIsFiveOrMore;
          effectiveLabel = autoIsFiveOrMore ? '5인 이상 자동 판정' : '5인 미만 자동 판정';
          effectiveColor = autoIsFiveOrMore
              ? const Color(0xFF1a6ebd)
              : const Color(0xFF555555);
        }

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE5E5EA), width: 0.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 현황 요약 배너
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: effectiveColor.withValues(alpha: 0.08),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          effectiveIsFive
                              ? Icons.business_center
                              : Icons.store_outlined,
                          size: 16,
                          color: effectiveColor,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          effectiveLabel,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: effectiveColor,
                          ),
                        ),
                        if (_isSaving) ...const [
                          SizedBox(width: 8),
                          SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ],
                      ],
                    ),
                    if (mode == 'auto' && totalDays > 0) ...[
                      const SizedBox(height: 4),
                      Text(
                        '평균 ${autoAvg.toStringAsFixed(1)}명 · 5인↑ 출근일 $daysWithFive/$totalDays일',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.black54,
                        ),
                      ),
                    ] else if (mode == 'auto') ...[
                      const SizedBox(height: 4),
                      const Text(
                        '이번 달 출근 데이터 집계 중...',
                        style: TextStyle(fontSize: 11, color: Colors.black54),
                      ),
                    ],
                  ],
                ),
              ),

              const Divider(height: 1, thickness: 0.5, color: Color(0xFFF0F0F0)),

              // 라디오 선택지
              _modeRadioTile(
                title: '자동 판정',
                subtitle: '법적 2단계 기준 (평균 + 과반수 날짜)으로 자동 계산',
                value: 'auto',
                groupValue: mode,
                autoIsFiveOrMore: autoIsFiveOrMore,
                onChanged: (v) => _setMode(v, autoIsFiveOrMore),
              ),
              const Divider(height: 1, thickness: 0.5, indent: 56, color: Color(0xFFF0F0F0)),
              _modeRadioTile(
                title: '5인 미만 고정',
                subtitle: '연장·야간·휴일 가산수당 미적용 / 연차 미발생',
                value: 'manual_under5',
                groupValue: mode,
                autoIsFiveOrMore: autoIsFiveOrMore,
                onChanged: (v) => _showReasonDialog(v, autoIsFiveOrMore),
              ),
              const Divider(height: 1, thickness: 0.5, indent: 56, color: Color(0xFFF0F0F0)),
              _modeRadioTile(
                title: '5인 이상 고정',
                subtitle: '연장·야간·휴일 1.5배 가산수당 / 연차 발생',
                value: 'manual_5plus',
                groupValue: mode,
                autoIsFiveOrMore: autoIsFiveOrMore,
                onChanged: (v) => _showReasonDialog(v, autoIsFiveOrMore),
                isLast: true,
              ),
              const Divider(height: 1, thickness: 0.5, color: Color(0xFFF0F0F0)),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Text(
                  '본 결과는 데이터 기반 추정치이며 최종 결정에 따른 책임은 사업주에게 있습니다.',
                  style: TextStyle(fontSize: 10, color: Colors.black38),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _modeRadioTile({
    required String title,
    required String subtitle,
    required String value,
    required String groupValue,
    required bool autoIsFiveOrMore,
    required void Function(String) onChanged,
    bool isLast = false,
  }) {
    final isSelected = value == groupValue;
    return InkWell(
      borderRadius: BorderRadius.circular(isLast ? 0 : 0),
      onTap: _isSaving ? null : () => onChanged(value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Radio<String>(
              value: value,
              groupValue: groupValue,
              onChanged: _isSaving ? null : (v) => onChanged(v!),
              activeColor: const Color(0xFF1a6ebd),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? const Color(0xFF1a6ebd)
                          : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                        fontSize: 11, color: Colors.black45),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
