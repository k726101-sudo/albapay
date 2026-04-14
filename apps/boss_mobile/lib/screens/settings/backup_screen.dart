import 'package:flutter/material.dart';
import '../../services/backup_service.dart';
import '../../services/server_cleanup_service.dart';
import '../../services/worker_service.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _isLoading = false;

  Future<void> _handleBackup() async {
    setState(() => _isLoading = true);
    try {
      await BackupService.runBackup(silent: false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('백업 파일 공유(저장)가 완료되었습니다.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('오류: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleRestore() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('백업 파일로 복원'),
        content: const Text(
          '저장해둔 백업 파일(.enc)을 선택하여 복원합니다.\n복원이 완료되면 현재 기기의 데이터는 삭제되고 백업 시점의 상태로 완전히 덮어쓰여집니다. 진행하시겠습니까?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('복원 진행하기')),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _isLoading = true);
    try {
      await BackupService.restoreFromFile();
      if (!mounted) return;
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('복원 완료'),
          content: const Text('데이터 복원이 성공적으로 완료되었습니다.\n앱을 완전히 종료한 후 다시 실행해 주십시오!'),
          actions: [
            FilledButton(
              onPressed: () {
                // To force restart, just go to root or exit, handled by user
                Navigator.pop(ctx);
              },
              child: const Text('확인'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('복원에 실패했습니다: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleServerCleanup() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('서버 데이터 정리'),
        content: const Text(
          '1년 이상 된 데이터는 압축(Archive) 처리하며, 3년이 지난 데이터는 기기에 보관 후 서버에서 영구 삭제합니다.\n\n이 작업은 서버 비용 절감 및 법적 보존 기간 준수를 위해 수행됩니다.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF6B7280)),
            child: const Text('지금 정리'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _isLoading = true);
    try {
      final storeId = await WorkerService.resolveStoreId();
      if (storeId.isNotEmpty) {
        await ServerCleanupService.runAutomaticCleanup(storeId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('서버 데이터 정리가 완료되었습니다.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('정리 실패: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleInviteCodeBackfill() async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final count = await WorkerService.backfillAllInviteCodes();
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('초대 코드 복구 완료: $count건')),
      );
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('복구 실패: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('데이터 백업/복원 관리'),
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Icon(Icons.security, size: 60, color: Colors.indigo),
              const SizedBox(height: 16),
              const Text(
                '로컬 파일 백업 센터',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                '앱 데이터를 암호화하여 직접 관리하고 복원할 수 있습니다. 생성된 파일은 카카오톡 내게쓰기, 파일 관리자 등에 저장해두세요.',
                style: TextStyle(fontSize: 14, color: Colors.black87),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),

              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.blue.shade200),
                ),
                tileColor: Colors.blue.shade50,
                leading: const Icon(Icons.cloud_download, color: Colors.blue),
                title: const Text('백업 파일 다운로드 및 공유', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('현재 기기의 데이터를 추출하여 파일로 저장합니다.'),
                onTap: _isLoading ? null : _handleBackup,
              ),
              
              const SizedBox(height: 16),
              
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.green.shade200),
                ),
                tileColor: Colors.green.shade50,
                leading: const Icon(Icons.restore, color: Colors.green),
                title: const Text('백업 파일로 복원하기', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('보관 중인 백업 파일을 불러와 덮어씁니다.'),
                onTap: _isLoading ? null : _handleRestore,
              ),

              const SizedBox(height: 16),

              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.shade300),
                ),
                leading: const Icon(Icons.cleaning_services_outlined, color: Colors.grey),
                title: const Text('과거 데이터 서버 비우기'),
                subtitle: const Text('1년/3년 보존 주기 데이터를 수동 정리합니다.'),
                onTap: _isLoading ? null : _handleServerCleanup,
              ),

              const SizedBox(height: 16),

              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.indigo.shade200),
                ),
                leading: const Icon(Icons.refresh_rounded, color: Colors.indigo),
                title: const Text('직원 초대 코드 일괄 복구'),
                subtitle: const Text('누락된 직원 초대 코드를 서버에서 복구합니다.'),
                onTap: _isLoading ? null : _handleInviteCodeBackfill,
              ),
            ],
          ),
          if (_isLoading)
            Container(
              color: Colors.black.withValues(alpha: 0.3),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}
