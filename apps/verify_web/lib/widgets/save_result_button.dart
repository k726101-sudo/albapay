import 'package:flutter/material.dart';
import '../theme/verify_theme.dart';
import '../services/verify_export_service.dart';
import 'verify_meta_header.dart';

/// 검증 결과 저장 버튼 — 각 탭의 결과 영역에 삽입
class SaveResultButton extends StatelessWidget {
  final String verifyType;
  final Map<String, dynamic> Function() buildInputData;
  final Map<String, dynamic> Function() buildResultData;

  const SaveResultButton({
    super.key,
    required this.verifyType,
    required this.buildInputData,
    required this.buildResultData,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 44,
      child: OutlinedButton.icon(
        onPressed: () => _save(context),
        icon: const Icon(Icons.download, size: 18),
        label: const Text('검증 결과 JSON 저장', style: TextStyle(fontSize: 13)),
        style: OutlinedButton.styleFrom(
          foregroundColor: VerifyTheme.accentGreen,
          side: BorderSide(color: VerifyTheme.accentGreen.withValues(alpha: 0.5)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }

  void _save(BuildContext context) {
    final data = VerifyExportService.buildExportData(
      firmName: VerifyMeta.firmName,
      workerName: VerifyMeta.workerName,
      workerNumber: VerifyMeta.workerNumber,
      verifyType: verifyType,
      inputData: buildInputData(),
      resultData: buildResultData(),
    );

    final filename = VerifyExportService.buildFilename(
      firmName: VerifyMeta.firmName,
      workerName: VerifyMeta.workerName,
      verifyType: verifyType,
    );

    VerifyExportService.downloadJson(data: data, filename: filename);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✅ $filename 저장됨'),
        backgroundColor: VerifyTheme.accentGreen.withValues(alpha: 0.8),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
