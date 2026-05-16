import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_logic/shared_logic.dart';
import 'package:flutter/services.dart';
import '../models/worker.dart';

class PdfExportResult {
  final File file;
  final String sha256;
  final String? r2DocId;

  PdfExportResult({
    required this.file,
    required this.sha256,
    this.r2DocId,
  });
}

class PdfExportService {
  /// 급여대장 및 근태확정서를 PDF로 생성하고 선택적으로 R2 Storage에 업로드합니다.
  static Future<PdfExportResult> exportAndUploadPayrollPdf({
    required String storeId,
    required String storeName,
    required DateTime periodStart,
    required DateTime periodEnd,
    required List<({Worker worker, PayrollCalculationResult result})> payrollData,
  }) async {
    final pdf = pw.Document();

    // 1. 한글 폰트 로드
    // 앱 내에 assets/fonts/NotoSansKR-Regular.ttf 가 있다고 가정
    // 없다면 기본 폰트 사용 시 한글 깨짐 발생 (프로젝트 구조에 맞게 수정 필요)
    pw.Font? fallbackFont;
    try {
      final fontData = await rootBundle.load('assets/fonts/Pretendard-Regular.otf');
      fallbackFont = pw.Font.ttf(fontData);
    } catch (e) {
      // 폰트가 없을 경우의 fallback (시스템 폰트 의존 시 한글 깨질 수 있음)
    }

    final currencyFormat = NumberFormat('#,###');
    final dateFormat = DateFormat('yyyy.MM.dd');
    final periodString = '${dateFormat.format(periodStart)}~${dateFormat.format(periodEnd)}';

    // 2. 급여대장 페이지 생성
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        theme: pw.ThemeData.withFont(
          base: fallbackFont,
        ),
        build: (pw.Context context) {
          return [
            pw.Header(
              level: 0,
              child: pw.Text('$storeName 급여대장 및 근태확정서', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
            ),
            pw.SizedBox(height: 10),
            pw.Text('정산 기간: $periodString', style: const pw.TextStyle(fontSize: 14)),
            pw.SizedBox(height: 20),
            pw.TableHelper.fromTextArray(
              context: context,
              headers: ['성명', 'ID', '총 근로시간/일', '세전 총급여', '비과세 식대', '과세 대상액', '4대보험', '실지급액'],
              data: payrollData.map((data) {
                final r = data.result;
                return [
                  data.worker.name,
                  data.worker.employeeId ?? '',
                  '${r.pureLaborHours.toStringAsFixed(1)} / ${r.annualLeaveSummary.calculationBasis.length}',
                  currencyFormat.format(r.totalPay.toInt()),
                  currencyFormat.format(r.mealNonTaxable.toInt()),
                  currencyFormat.format(r.taxableWage.toInt()),
                  currencyFormat.format(r.insuranceDeduction.toInt()),
                  currencyFormat.format(r.netPay.toInt()),
                ];
              }).toList(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
              cellHeight: 30,
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.center,
                2: pw.Alignment.center,
                3: pw.Alignment.centerRight,
                4: pw.Alignment.centerRight,
                5: pw.Alignment.centerRight,
                6: pw.Alignment.centerRight,
                7: pw.Alignment.centerRight,
              },
            ),
            pw.SizedBox(height: 30),
            pw.Paragraph(text: '※ 본 리포트는 앱 내 계산 결과이며, 세무 신고 결과에 따라 실제 금액은 상이할 수 있습니다.'),
            pw.Paragraph(text: '※ 본 서류는 $storeName 의 전자적 급여 마감 승인에 의해 생성된 원본 파일입니다.'),
            pw.SizedBox(height: 50),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.end,
              children: [
                pw.Text('생성일시: ${DateFormat('yyyy.MM.dd HH:mm:ss').format(DateTime.now())}'),
              ],
            ),
          ];
        },
      ),
    );

    // 3. 파일 저장
    final String yyyyMM = DateFormat('yyyy-MM').format(periodEnd);
    final String fileName = '${yyyyMM}_${storeId}_payroll.pdf';
    final directory = await getTemporaryDirectory();
    final path = '${directory.path}/$fileName';
    final file = File(path);
    final bytes = await pdf.save();
    await file.writeAsBytes(bytes);

    // 4. SHA256 해시 추출
    final sha256Hash = await R2StorageService.instance.calculateSha256(file);

    // 5. R2 스토리지 업로드 (Cloud Backup)
    String? docId;
    try {
      docId = await R2StorageService.instance.secureUpload(
        storeId: storeId,
        docType: 'payroll_ledger',
        file: file,
        mimeType: 'application/pdf',
        skipCompression: true, // PDF는 이미지 압축 스킵
      );
    } catch (e) {
      // 업로드 실패 시 로컬 파일이라도 반환 (로그 기록 등 필요)
      print('PDF R2 Upload Failed: $e');
    }

    return PdfExportResult(
      file: file,
      sha256: sha256Hash,
      r2DocId: docId,
    );
  }
}
