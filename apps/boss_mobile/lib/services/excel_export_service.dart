import 'dart:io';
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_logic/shared_logic.dart';
import '../models/worker.dart';

class ExcelExportService {
  static Future<void> exportPayroll({
    required List<({Worker worker, PayrollCalculationResult result})> payrollData,
    required String storeName,
    required DateTime periodStart,
    required DateTime periodEnd,
  }) async {
    final excel = Excel.createExcel();
    final sheet = excel['Sheet1'];

    // 1. 헤더 스타일 정의
    final headerStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('#F0F0F0'),
      horizontalAlign: HorizontalAlign.Center,
      fontColorHex: ExcelColor.fromHexString('#333333'),
    );

    // 2. 컬럼 제목 설정 (A~J)
    final headers = [
      '성명',
      '사원번호(ID)',
      '정산 기간',
      '총 근로시간/일수',
      '세전 총급여',
      '비과세 식대',
      '과세 대상액(A)',
      '4대 보험 공제(B)',
      '전월 정산금(C)',
      '최종 실지급액(Net)',
    ];

    for (int i = 0; i < headers.length; i++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
      cell.value = TextCellValue(headers[i]);
      cell.cellStyle = headerStyle;
    }

    // 2-1. 컬럼 너비(비율) 조정
    sheet.setColumnWidth(0, 12.0); // 성명
    sheet.setColumnWidth(1, 15.0); // ID
    sheet.setColumnWidth(2, 24.0); // 정산 기간
    sheet.setColumnWidth(3, 20.0); // 총 근로시간/일수
    sheet.setColumnWidth(4, 16.0); // 세전 총급여
    sheet.setColumnWidth(5, 14.0); // 비과세 식대
    sheet.setColumnWidth(6, 16.0); // 과세 대상액
    sheet.setColumnWidth(7, 16.0); // 4대 보험 공제
    sheet.setColumnWidth(8, 16.0); // 전월 정산금
    sheet.setColumnWidth(9, 18.0); // 최종 실지급액

    // 3. 데이터 행 삽입
    final currencyFormat = NumberFormat('#,###');
    final dateFormat = DateFormat('yyyy.MM.dd');
    final periodString = '${dateFormat.format(periodStart)}~${dateFormat.format(periodEnd)}';

    for (int i = 0; i < payrollData.length; i++) {
      final data = payrollData[i];
      final r = data.result;
      final rowIndex = i + 1;

      // A: 성명
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex)).value = TextCellValue(data.worker.name);
      
      // B: 사원번호
      final empId = data.worker.employeeId?.trim() ?? '';
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rowIndex)).value = TextCellValue(empId);
      
      // C: 정산 기간
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: rowIndex)).value = TextCellValue(periodString);
      
      // D: 근로시간/일수
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: rowIndex)).value = 
          TextCellValue('${r.pureLaborHours.toStringAsFixed(1)}시간 / ${r.annualLeaveSummary.calculationBasis.length}일');

      // E: 세전 총급여
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: rowIndex)).value = TextCellValue(currencyFormat.format(r.totalPay.toInt()));
      
      // F: 비과세 식대 (신규 추가)
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: rowIndex)).value = TextCellValue(currencyFormat.format(r.mealNonTaxable.toInt()));
      
      // G: 과세 대상액 (A)
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: rowIndex)).value = TextCellValue(currencyFormat.format(r.taxableWage.toInt()));
      
      // H: 4대 보험 공제 (B)
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: rowIndex)).value = TextCellValue(currencyFormat.format(r.insuranceDeduction.toInt()));
      
      // I: 전월 정산금 (C)
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: rowIndex)).value = TextCellValue(currencyFormat.format(r.previousMonthAdjustment.toInt()));
      
      // J: 최종 실지급액 (Bold)
      final netCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 9, rowIndex: rowIndex));
      netCell.value = TextCellValue(currencyFormat.format(r.netPay.toInt()));
      netCell.cellStyle = CellStyle(bold: true);
    }

    // 4. 하단 필수 법적 고지 (Footer)
    final footerRow = payrollData.length + 3;
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: footerRow)).value = 
        TextCellValue('※ 1. 본 리포트에는 소득세 및 지방세가 반영되지 않았습니다. 세무 신고 결과에 따라 별도 정산하십시오.');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: footerRow + 1)).value = 
        TextCellValue('※ 2. 주민등록번호 등 인적 사항은 별도 보관 중인 기초 서류를 대조하십시오.');

    // 5. 파일 저장 및 공유
    final String fileName = '${storeName}_급여신고데이터_${DateFormat('yyyyMM').format(periodEnd)}.xlsx';
    final directory = await getTemporaryDirectory();
    final path = '${directory.path}/$fileName';
    final file = File(path);

    final bytes = excel.encode();
    if (bytes != null) {
      await file.writeAsBytes(bytes);
      
      await SharePlus.instance.share(ShareParams(
        files: [XFile(path)],
        subject: '$storeName 급여 리포트 ($periodString)',
      ));

      // 공유 후 파일 삭제 (보안 및 미니멀리즘)
      Future.delayed(const Duration(minutes: 5), () async {
        if (await file.exists()) {
          await file.delete();
        }
      });
    }
  }
}
