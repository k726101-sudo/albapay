// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:convert';
import 'dart:html' as html;

/// 검증 결과 JSON 다운로드/불러오기 서비스 (웹 전용)
class VerifyExportService {
  /// JSON 파일 다운로드
  static void downloadJson({
    required Map<String, dynamic> data,
    required String filename,
  }) {
    final jsonStr = const JsonEncoder.withIndent('  ').convert(data);
    final bytes = utf8.encode(jsonStr);
    final blob = html.Blob([bytes], 'application/json;charset=utf-8');
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..setAttribute('download', filename)
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  /// JSON 파일 선택 → 콜백으로 데이터 반환
  static void loadJson({
    required void Function(Map<String, dynamic> data) onLoaded,
    required void Function(String error) onError,
  }) {
    final input = html.FileUploadInputElement()..accept = '.json';
    input.click();
    input.onChange.listen((event) {
      final file = input.files?.first;
      if (file == null) return;

      final reader = html.FileReader();
      reader.readAsText(file);
      reader.onLoadEnd.listen((e) {
        try {
          final content = reader.result as String;
          final data = jsonDecode(content) as Map<String, dynamic>;
          onLoaded(data);
        } catch (e) {
          onError('JSON 파싱 오류: $e');
        }
      });
    });
  }

  /// 검증 결과를 저장용 JSON으로 변환
  static Map<String, dynamic> buildExportData({
    required String firmName,
    required String workerName,
    required String workerNumber,
    required String verifyType,
    required Map<String, dynamic> inputData,
    required Map<String, dynamic> resultData,
  }) {
    return {
      'meta': {
        'firmName': firmName,
        'workerName': workerName,
        'workerNumber': workerNumber,
        'verifyType': verifyType,
        'createdAt': DateTime.now().toIso8601String(),
        'appVersion': 'AlbaPay Verify v1.0',
      },
      'input': inputData,
      'result': resultData,
    };
  }

  /// 파일명 생성
  static String buildFilename({
    required String firmName,
    required String workerName,
    required String verifyType,
  }) {
    final date = DateTime.now();
    final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final firm = firmName.isNotEmpty ? firmName : '미지정';
    final worker = workerName.isNotEmpty ? workerName : '미지정';
    return '검증_${firm}_${worker}_${verifyType}_$dateStr.json';
  }
}
