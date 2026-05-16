import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:printing/printing.dart';
import 'package:shared_logic/shared_logic.dart';
import '../../models/store_info.dart';

class PdfGeneratorService {
  /// 한글 폰트 로드 (NotoSansKR - Local Assets)
  static Future<pw.Font> _loadFont() async {
    try {
      final data = await rootBundle.load('assets/fonts/NotoSansKR-Regular.ttf');
      return pw.Font.ttf(data);
    } catch (e) {
      debugPrint('Local font load error: $e. Falling back to Google Fonts.');
      return await PdfGoogleFonts.nanumGothicRegular();
    }
  }

  static Future<pw.Font> _loadBoldFont() async {
    try {
      final data = await rootBundle.load('assets/fonts/NotoSansKR-Bold.ttf');
      return pw.Font.ttf(data);
    } catch (e) {
      debugPrint('Local bold font load error: $e. Falling back to Google Fonts.');
      return await PdfGoogleFonts.nanumGothicBold();
    }
  }

  /// Hive에서 StoreInfo를 읽어 PDF 데이터를 제공하는 헬퍼
  static Map<String, String> _loadStoreDefaults() {
    try {
      final store = Hive.box<StoreInfo>('store').get('current');
      return {
        'storeName': store?.storeName ?? '',
        'ownerName': store?.ownerName ?? '',
        'storeAddress': store?.address ?? '',
        'storePhone': store?.phone ?? '',
      };
    } catch (_) {
      return {
        'storeName': '',
        'ownerName': '',
        'storeAddress': '',
        'storePhone': '',
      };
    }
  }

  /// 표준 근로계약서 (일반/풀타임) 생성
  static Future<Uint8List> generateFullContract({
    required LaborDocument document,
    required Map<String, dynamic> contractData,
    Uint8List? ownerSignatureBytes,
    Uint8List? workerSignatureBytes,
  }) async {
    final font = await _loadFont();
    final boldFont = await _loadBoldFont();

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: font,
        bold: boldFont,
      ),
    );

    final storeDefaults = _loadStoreDefaults();
    final storeName = contractData['storeName']?.toString().isNotEmpty == true
        ? contractData['storeName']
        : storeDefaults['storeName']!;
    final storeAddress = contractData['storeAddress']?.toString().isNotEmpty == true
        ? contractData['storeAddress']
        : storeDefaults['storeAddress']!;
    final ownerName = contractData['ownerName']?.toString().isNotEmpty == true
        ? contractData['ownerName']
        : storeDefaults['ownerName']!;
    final storePhone = contractData['storePhone']?.toString().isNotEmpty == true
        ? contractData['storePhone']
        : storeDefaults['storePhone']!;

    final workerName = contractData['workerName'] ?? document.staffId;
    final workerAddress = contractData['workerAddress'] ?? '';
    final workerPhone = contractData['workerPhone'] ?? '';

    final startDateStr = contractData['startDate'] ?? '    년   월   일';
    final endDateStr = contractData['endDate'] ?? '    년   월   일';

    final startTime = contractData['startTime'] ?? '   ';
    final endTime = contractData['endTime'] ?? '   ';
    final breakStart = contractData['breakStart'] ?? '   ';
    final breakEnd = contractData['breakEnd'] ?? '   ';

    final workDaysInfo = contractData['workDaysInfo'] ?? '   ';
    final weeklyHoliday = contractData['weeklyHoliday'] ?? '   ';
    
    final hourlyWage = contractData['hourlyWage'] ?? '             ';
    final monthlyWageStr = contractData['monthlyWage'] ?? '0';
    final wageType = contractData['wageType'] ?? 'hourly';
    final fixedOTHours = contractData['fixedOvertimeHours'] ?? 0;
    final fixedOTPay = contractData['fixedOvertimePay'] ?? 0;
    final sRefHours = contractData['sRefHours'] ?? 209;
    final wagePaymentDay = contractData['wagePaymentDay'] ?? '   ';
    final isMonthly = wageType == 'monthly';

    final currentYear = DateTime.now().year;
    final currentMonth = DateTime.now().month;
    final currentDay = DateTime.now().day;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 32),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: pw.BoxDecoration(border: pw.Border.all()),
                    child: pw.Text('점포 보관용', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                  ),
                ]
              ),
              pw.SizedBox(height: 10),
              pw.Center(
                child: pw.Text('표준 근로계약서', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
              ),
              pw.SizedBox(height: 30),
              
              pw.RichText(
                text: pw.TextSpan(
                  style: pw.TextStyle(font: font, fontSize: 11),
                  children: [
                    pw.TextSpan(text: storeName, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, decoration: pw.TextDecoration.underline)),
                    const pw.TextSpan(text: ' (이하 "사업주" 라 함)과(와)  '),
                    pw.TextSpan(text: '$workerName                       ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, decoration: pw.TextDecoration.underline)),
                    const pw.TextSpan(text: ' (이하 "근로자" 라 함)은\n다음과 같이 근로계약을 체결한다.'),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),

              _fullContractRow('1. 근로계약기간 : ', '$startDateStr 부터  $endDateStr 까지', font),
              _fullContractRow('2. 근 무 장 소 : ', storeName, font),
              _fullContractRow('3. 업무의 내용 : ', '판매 및 기타 업무', font),
              _fullContractRow('4. 소정근로시간 : ', '$startTime 부터 $endTime 까지 (휴게시간 : $breakStart ~ $breakEnd)', font),
              pw.Padding(
                padding: const pw.EdgeInsets.only(left: 12, top: 4, bottom: 4),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('※ 업무상 필요한 경우 법에서 정한 범위 내에서 연장근로 함에 동의 한다.', style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                    pw.Text('※ 4시간 근로시마다 30분 이상, 8시간 근무시마다 1시간 이상 휴식을 제공한다.', style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                    pw.Text('※ 근로시간은 근무시간표와 사업장 사정에 따라 사업주와 근로자의 합의하에 변경될 수 있다.', style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                  ]
                )
              ),
              _fullContractRow('5. 근무일/휴일 : ', '매주 $workDaysInfo 일(또는 매일단위) 근무 / 주휴일 매주 $weeklyHoliday 요일, 근로자의 날(5월 1일)', font),
              
              pw.SizedBox(height: 4),
              pw.Text('6. 임 금', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
              pw.Padding(
                padding: const pw.EdgeInsets.only(left: 12, top: 4),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    if (isMonthly) ...[
                      pw.Text('- 급여 형태: 월급제 (고정급)', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                      pw.Text('- 기본급: ${_fmtMoney(int.tryParse(monthlyWageStr) ?? 0)}원 (S_Ref ${sRefHours}시간 기준)', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                      pw.Text('- 시급(역산): ${_fmtMoney(int.tryParse(hourlyWage) ?? 0)}원', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                      if (fixedOTHours > 0)
                        pw.Text('- 고정연장수당: ${_fmtMoney(fixedOTPay)}원 (월 $fixedOTHours시간분)', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                    ] else ...[
                      pw.Text('- 시급: ${_fmtMoney(int.tryParse(hourlyWage) ?? 0)}원', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                    ],
                    pw.Text('- 가산임금율(사업장 운영 형태에 따라 적용 : 연장, 야간, 휴일근로 등)', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(left: 8),
                      child: pw.Text(': 법내 초과근로는 가산임금을 지급하지 않고, 1일 및 1주 법정기준근로시간을 초과하는 경우,\n  야간 및 휴일근로의 경우 통상임금의 50% 가산 지급', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text('- 임금지급일 : 매월 $wagePaymentDay 일  ※휴일의 경우는 전일 지급', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                    pw.Text('- 지급방법 : 근로자 명의 예금통장에 입금', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                  ]
                )
              ),
              
              pw.SizedBox(height: 8),
              pw.Text('7. 연차유급휴가', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
              pw.Padding(
                padding: const pw.EdgeInsets.only(left: 12, top: 2),
                child: pw.Text('- 연차유급휴가는 근로기준법에서 정하는 바에 따라 부여함 ※사업장 운영 형태에 따라 적용', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
              ),
              
              pw.SizedBox(height: 8),
              pw.Text('8. 근로계약서 교부', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
              pw.Padding(
                padding: const pw.EdgeInsets.only(left: 12, top: 2),
                child: pw.Text('- 사업주는 근로계약을 체결함과 동시에 본 계약서를 사본하여 근로자의 교부요구와 관계없이\n  근로자에게 교부함(근로기준법 제17조 이행)', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
              ),
              
              pw.SizedBox(height: 8),
              pw.Text('9. 기타 및 특약사항', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
              pw.Padding(
                padding: const pw.EdgeInsets.only(left: 12, top: 2),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('- 이 계약에 정함이 없는 사항은 근로기준법령에 의함', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                    if (isMonthly) ...[
                      pw.SizedBox(height: 6),
                      pw.Text('[특약] 주휴수당', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: PdfColors.grey800)),
                      pw.Text('기본급은 유급주휴수당을 포함하여 산정된 금액입니다. '
                        '단, 소정근로일을 개근하지 않은 경우 해당 주휴수당은 지급되지 않으며, '
                        '이에 해당하는 금액은 공제될 수 있습니다.',
                        style: pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                      if (fixedOTHours > 0) ...[
                        pw.SizedBox(height: 4),
                        pw.Text('[특약] 고정연장수당', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: PdfColors.grey800)),
                        pw.Text('고정연장수당은 실제 연장근로 발생을 전제로 하며, '
                          '해당 시간에 미달하는 경우 별도 추가 지급은 발생하지 않습니다.',
                          style: pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                      ],
                      pw.SizedBox(height: 4),
                      pw.Text('[특약] 평균 주수 합의', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: PdfColors.grey800)),
                      pw.Text('본 급여는 1개월 평균 주수(4.345주)를 기준으로 산정된 금액이며, '
                        '실제 근로 제공 여부에 따라 결근·지각·조퇴 시간에 대해서는 '
                        '관련 법령 및 내부 기준에 따라 공제될 수 있습니다.',
                        style: pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                    ],
                    if (contractData['isPaidBreak'] == true) ...[
                      pw.SizedBox(height: 6),
                      pw.Text('[특약] 유급 휴게시간', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: PdfColors.grey800)),
                      pw.Text('휴게시간은 업무 상황에 따라 변동될 수 있으며, 실제 사용하지 못한 휴게시간은 근로시간에 포함하여 계산합니다.',
                        style: pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                    ],
                  ],
                ),
              ),
              
              pw.SizedBox(height: 12),
              pw.Text('(자필로 기재) 상기 본인은 근로계약서 내용을 숙지하고, 동계약서 1부를 서면수령 하였음을 확인합니다.', style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
              pw.Container(
                height: 25,
                decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey800, width: 0.5)),
              ),
              
              pw.SizedBox(height: 20),
              pw.Center(
                child: pw.Text('$currentYear 년    $currentMonth 월    $currentDay 일', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
              ),
              
              pw.SizedBox(height: 20),
              
              // Signatures
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('(사업주) ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('사업체명 : 파리바게뜨$storeName (전화 : $storePhone)', style: pw.TextStyle(fontSize: 11)),
                        pw.Text('주       소 : $storeAddress', style: pw.TextStyle(fontSize: 11)),
                        pw.Row(
                          children: [
                            pw.Text('대  표  자 : $ownerName                  (서명)', style: pw.TextStyle(fontSize: 11)),
                            if (ownerSignatureBytes != null)
                              pw.Image(pw.MemoryImage(ownerSignatureBytes), width: 35, height: 20),
                          ]
                        ),
                      ]
                    )
                  )
                ]
              ),
              pw.SizedBox(height: 10),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('(근로자) ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('주       소 : $workerAddress', style: pw.TextStyle(fontSize: 11)),
                        pw.Text('연  락  처 : $workerPhone', style: pw.TextStyle(fontSize: 11)),
                        pw.Row(
                          children: [
                            pw.Text('성       명 : $workerName                  (서명)', style: pw.TextStyle(fontSize: 11)),
                            if (workerSignatureBytes != null)
                              pw.Image(pw.MemoryImage(workerSignatureBytes), width: 35, height: 20),
                          ]
                        ),
                      ]
                    )
                  ),
                ]
              ),
            ],
          );
        },
      ),
    );

    // SHA-256 해시 생성
    final dataHash = _computeSha256(contractData);

    // 교부 증명 페이지 추가
    _appendDeliveryProof(pdf, document, font, documentHash: dataHash);

    return pdf.save();
  }

  /// 금액 콤마 포맷
  static String _fmtMoney(int amount) {
    return amount.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
  }

  /// SHA-256 해시 계산
  static String _computeSha256(Map<String, dynamic> data) {
    final jsonStr = jsonEncode(data);
    final bytes = utf8.encode(jsonStr);
    return sha256.convert(bytes).toString();
  }

  static pw.Widget _fullContractRow(String title, String content, pw.Font font) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(title, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
          pw.Expanded(child: pw.Text(content, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11, decoration: pw.TextDecoration.underline))),
        ],
      )
    );
  }

  /// 단시간 근로자용 근로계약서 생성
  static Future<Uint8List> generatePartTimeContract({
    required LaborDocument document,
    required Map<String, dynamic> contractData,
    Uint8List? ownerSignatureBytes,
    Uint8List? workerSignatureBytes,
  }) async {
    final font = await _loadFont();
    final boldFont = await _loadBoldFont();

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: font,
        bold: boldFont,
      ),
    );

    // StoreInfo\uc5d0\uc11c \uae30\ubcf8\uac12 \ub85c\ub4dc
    final storeDefaults = _loadStoreDefaults();
    final storeName = contractData['storeName']?.toString().isNotEmpty == true
        ? contractData['storeName']
        : storeDefaults['storeName']!;
    final storeAddress = contractData['storeAddress']?.toString().isNotEmpty == true
        ? contractData['storeAddress']
        : storeDefaults['storeAddress']!;
    final ownerName = contractData['ownerName']?.toString().isNotEmpty == true
        ? contractData['ownerName']
        : storeDefaults['ownerName']!;
    final ownerPhone = contractData['ownerPhone']?.toString().isNotEmpty == true
        ? contractData['ownerPhone']
        : storeDefaults['storePhone']!;


    final workerName = contractData['workerName'] ?? document.staffId;
    final workerAddress = contractData['workerAddress'] ?? '';
    final workerPhone = contractData['workerPhone'] ?? '';

    final startDateStr = contractData['startDate'] ?? '    년   월   일';
    final endDateStr = contractData['endDate'] ?? '    년   월   일';
    
    final hourlyWage = contractData['hourlyWage'] ?? '';
    final wagePaymentDay = contractData['wagePaymentDay'] ?? '';
    final weeklyHoliday = contractData['weeklyHoliday'] ?? '';

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(height: 10),
              pw.Center(
                child: pw.Text('근로계약서(단시간 근로자용)', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
              ),
              pw.SizedBox(height: 20),
              
              pw.RichText(
                text: pw.TextSpan(
                  style: pw.TextStyle(font: font, fontSize: 11),
                  children: [
                    pw.TextSpan(text: storeName, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    const pw.TextSpan(text: ' (이하 "사업주")와 '),
                    pw.TextSpan(text: workerName, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    const pw.TextSpan(text: ' (이하 "근로자")는 다음과 같이 근로계약을 체결한다.'),
                  ],
                ),
              ),
              pw.SizedBox(height: 16),

              pw.Text('1. 근로계약기간 : $startDateStr 부터 $endDateStr 까지', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
              pw.SizedBox(height: 6),
              pw.Text('2. 근무장소 : $storeName', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
              pw.SizedBox(height: 6),
              pw.Text('3. 업무의 내용 : 판매 및 기타업무', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
              pw.SizedBox(height: 6),
              pw.Text('4. 근로일별 근로시간', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
              
              pw.SizedBox(height: 4),
              pw.Table(
                border: pw.TableBorder.all(),
                children: [
                  pw.TableRow(
                    children: [' ', '월', '화', '수', '목', '금', '토', '일'].map((t) => pw.Padding(
                      padding: const pw.EdgeInsets.all(4), 
                      child: pw.Center(child: pw.Text(t, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10))),
                    )).toList(),
                  ),
                  _buildWorkTimeRow('근로시간', contractData['workSchedule'] ?? {}, font, field: 'duration'),
                  _buildWorkTimeRow('시작시간', contractData['workSchedule'] ?? {}, font, field: 'start'),
                  _buildWorkTimeRow('종료시간', contractData['workSchedule'] ?? {}, font, field: 'end'),
                  _buildWorkTimeRow('휴게시간', contractData['workSchedule'] ?? {}, font, field: 'break'),
                ],
              ),
              pw.SizedBox(height: 8),
              
              pw.Text('주휴일: 매주 $weeklyHoliday', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
              pw.SizedBox(height: 8),
              
              pw.Text('5. 임금', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
              pw.SizedBox(height: 4),
              pw.Table(
                border: pw.TableBorder.all(),
                children: [
                  pw.TableRow(
                    children: [
                      _centeredCell('임금항목', font, isBold: true),
                      _centeredCell('금액', font, isBold: true),
                      _centeredCell('임금항목', font, isBold: true),
                      _centeredCell('금액', font, isBold: true),
                    ],
                  ),
                  pw.TableRow(
                    children: [
                      _paddedCell('①(시급, 일급, 월급)', font),
                      _paddedCell('$hourlyWage 원', font, align: pw.TextAlign.right),
                      _paddedCell('②상여금', font),
                      _paddedCell('원', font, align: pw.TextAlign.right),
                    ],
                  ),
                  pw.TableRow(
                    children: [
                      _paddedCell('③기타급여(수당)', font),
                      _paddedCell('원', font, align: pw.TextAlign.right),
                      _paddedCell('④임금지급일', font),
                      _paddedCell('매월 $wagePaymentDay 일', font, align: pw.TextAlign.right),
                    ],
                  ),
                  pw.TableRow(
                    children: [
                      _paddedCell('⑤지급방법', font),
                      _centeredCell('통장입금', font),
                      _paddedCell('⑥수당가산율', font),
                      _centeredCell('50%, 사업장 운영형태에 따라 적용', font),
                    ],
                  ),
                ]
              ),
              pw.SizedBox(height: 12),

              infoRow('6. 연차유급휴가 : ', '통상근로자의 근로시간에 비례하여 연차유급휴가 부여', font),
              pw.SizedBox(height: 6),
              infoRow('7. 사회보험적용여부 : ', _buildInsuranceText(contractData['insurance']), font),
              pw.SizedBox(height: 6),
              infoRow('8. 기타 : ', '이 계약에 정함이 없는 사항은 근로기준법령에 의함', font),
              if (contractData['isPaidBreak'] == true) ...[
                pw.SizedBox(height: 6),
                pw.Text('[특약] 유급 휴게시간: 휴게시간은 업무 상황에 따라 변동될 수 있으며, 실제 사용하지 못한 휴게시간은 근로시간에 포함하여 계산합니다.',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: PdfColors.grey700)),
              ],
              pw.SizedBox(height: 6),
              pw.Text('9. 근로계약서 교부 :', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
              pw.SizedBox(height: 2),
              pw.Text('(자필기재) 상기 본인은 본 근로계약내용을 숙지하고 동 계약서를 1부를 수령함', style: pw.TextStyle(fontSize: 11, fontStyle: pw.FontStyle.italic, color: PdfColors.grey700)),
              
              pw.Spacer(),

              pw.Table(
                border: pw.TableBorder.all(),
                columnWidths: {
                  0: const pw.FlexColumnWidth(1),
                  1: const pw.FlexColumnWidth(1),
                },
                children: [
                  pw.TableRow(
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text('사업주', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text('근로자', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                      ),
                    ],
                  ),
                  pw.TableRow(
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text('주소(점포명) : $storeAddress', style: pw.TextStyle(fontSize: 10)),
                            pw.SizedBox(height: 6),
                            pw.Row(
                              children: [
                                pw.Text('대표자 : $ownerName                  (서명) ', style: pw.TextStyle(fontSize: 10)),
                                if (ownerSignatureBytes != null)
                                  pw.Image(pw.MemoryImage(ownerSignatureBytes), width: 35, height: 20),
                              ]
                            ),
                            pw.SizedBox(height: 6),
                            pw.Text('연락처 : $ownerPhone', style: pw.TextStyle(fontSize: 10)),
                          ]
                        )
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text('주          소 : $workerAddress', style: pw.TextStyle(fontSize: 10)),
                            pw.SizedBox(height: 6),
                            pw.Row(
                              children: [
                                pw.Text('성          명 : $workerName                  (서명) ', style: pw.TextStyle(fontSize: 10)),
                                if (workerSignatureBytes != null)
                                  pw.Image(pw.MemoryImage(workerSignatureBytes), width: 35, height: 20),
                              ]
                            ),
                            pw.SizedBox(height: 6),
                            pw.Text('연    락    처 : $workerPhone', style: pw.TextStyle(fontSize: 10)),
                          ]
                        )
                      ),
                    ]
                  ),
                ]
              ),
              pw.SizedBox(height: 20),
            ],
          );
        },
      ),
    );

    // 교부 증명 페이지 추가
    _appendDeliveryProof(pdf, document, font);

    return pdf.save();
  }

  static pw.Widget infoRow(String title, String content, pw.Font font) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(title, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
        pw.Expanded(child: pw.Text(content, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11))),
      ],
    );
  }

  static pw.TableRow _buildWorkTimeRow(String label, Map<dynamic, dynamic> schedule, pw.Font font, {required String field}) {
    const days = ['월요일', '화요일', '수요일', '목요일', '금요일', '토요일', '일요일'];
    return pw.TableRow(
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.all(4),
          child: pw.Center(child: pw.Text(label, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10))),
        ),
        ...days.map((d) {
          final dayData = schedule[d] as Map<String, dynamic>?;
          String text = ' ';
          if (dayData != null) {
            if (field == 'duration') {
              try {
                final startStr = dayData['start'] as String? ?? '00:00';
                final endStr = dayData['end'] as String? ?? '00:00';
                final brkStr = dayData['break'] as String? ?? '0분';
                
                final sParts = startStr.split(':');
                final eParts = endStr.split(':');
                final sMin = int.parse(sParts[0]) * 60 + int.parse(sParts[1]);
                final eMin = int.parse(eParts[0]) * 60 + int.parse(eParts[1]);
                final bMin = int.parse(brkStr.replaceAll(RegExp(r'[^0-9]'), ''));
                
                final diff = eMin - sMin - bMin;
                if (diff > 0) {
                  final h = diff ~/ 60;
                  final m = diff % 60;
                  text = m == 0 ? '$h시간' : '$h시간 $m분';
                }
              } catch (_) {
                text = '-';
              }
            } else {
              text = dayData[field] ?? ' ';
            }
          }
          return pw.Padding(
            padding: const pw.EdgeInsets.all(4), 
            child: pw.Center(child: pw.Text(text, style: pw.TextStyle(fontSize: 9))),
          );
        }),
      ],
    );
  }

  static String _buildInsuranceText(dynamic insurance) {
    if (insurance is! Map) return '□고용보험 □산재보험 □건강보험 □국민연금';
    final emp = insurance['employment'] == true ? '■' : '□';
    final acc = insurance['accidental'] == true ? '■' : '□';
    final hea = insurance['health'] == true ? '■' : '□';
    final nat = insurance['national'] == true ? '■' : '□';
    return '$emp고용보험 $acc산재보험 $hea건강보험 $nat국민연금';
  }

  static pw.Widget _centeredCell(String text, pw.Font font, {bool isBold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Center(child: pw.Text(text, style: pw.TextStyle(fontSize: 10, fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal))),
    );
  }

  static pw.Widget _paddedCell(String text, pw.Font font, {pw.TextAlign align = pw.TextAlign.left}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Text(text, textAlign: align, style: pw.TextStyle(fontSize: 10)),
    );
  }

  /// 공통 감사 메타데이터 푸터 (모든 노무 서류 PDF 하단)
  static pw.Widget _buildAuditFooter({String? documentHash}) {
    final now = AppClock.now();
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 16),
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('디지털 검증 정보 (무결성 보장)',
              style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: PdfColors.grey600)),
          pw.Text('생성 시각: ${now.toIso8601String()}',
              style: pw.TextStyle(fontSize: 7, color: PdfColors.grey500)),
          if (documentHash != null)
            pw.Text('무결성 해시(SHA-256): $documentHash',
                style: pw.TextStyle(fontSize: 7, color: PdfColors.grey500)),
          pw.Text('App-Calculated via Alba Payroll Standard Engine v1.0 (Logic: Bottom-up Integrity Check Passed)',
              style: pw.TextStyle(fontSize: 7, color: PdfColors.grey500)),
        ],
      ),
    );
  }

  /// 임금명세서 생성
  static Future<Uint8List> generateWageStatement({
    required LaborDocument document,
    required Map<String, dynamic> wageData,
  }) async {
    final font = await _loadFont();
    final boldFont = await _loadBoldFont();

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: font,
        bold: boldFont,
      ),
    );

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(
                child: pw.Text('임 금 명 세 서', 
                  style: pw.TextStyle(font: font, fontSize: 24, fontWeight: pw.FontWeight.bold)),
              ),
              pw.SizedBox(height: 30),
              
              // 기본 정보 섹션
              _pdfSectionTitle('1. 기본 정보', font),
              pw.Table(
                border: pw.TableBorder.all(),
                children: [
                  _pdfTableRow(['성명', wageData['workerName']?.toString() ?? document.staffId, '생년월일', wageData['workerBirthDate']?.toString() ?? '-'], font),
                  _pdfTableRow(['지급일', document.sentAt?.toIso8601String().substring(0, 10) ?? '-', '정산기간', '${wageData['periodStart']?.toString().substring(0,10)} ~ ${wageData['periodEnd']?.toString().substring(0,10)}'], font),
                ],
              ),
              pw.SizedBox(height: 20),

              // 급여 내역 섹션
              _pdfSectionTitle('2. 급여 내역', font),
              pw.Builder(builder: (context) {
                final hourlyRate = (wageData['hourlyRate'] as num?)?.toDouble() ?? 0.0;
                final base = (wageData['basePay'] as num?)?.toInt() ?? 0;
                final premium = (wageData['premiumPay'] as num?)?.toInt() ?? 0;
                final weekly = (wageData['weeklyHolidayPay'] as num?)?.toInt() ?? 0;
                final breakP = (wageData['breakPay'] as num?)?.toInt() ?? 0;

                String _fH(double h) => h == h.toInt() ? h.toInt().toString() : h.toStringAsFixed(1);
                String _fHW(num v) => v == v.toInt() ? v.toInt().toString() : v.toStringAsFixed(1);

                final pureLaborHours = (wageData['pureLaborHours'] as num?)?.toDouble() ?? (hourlyRate > 0 ? base / hourlyRate : 0.0);
                final breakH = (wageData['paidBreakHours'] as num?)?.toDouble() ?? (hourlyRate > 0 ? breakP / hourlyRate : 0.0);
                final weekH = hourlyRate > 0 ? weekly / hourlyRate : 0.0;
                final premH = hourlyRate > 0 ? premium / (hourlyRate * 0.5) : 0.0;

                return pw.Table(
                  border: pw.TableBorder.all(),
                  children: [
                    _pdfTableRow(['항목', '금액 (원)', '계산방법/산출근거'], font, isHeader: true),
                    _pdfTableRow(['기본급', '${wageData['basePay']?.toInt()}', '${_fH(pureLaborHours)}시간 × ${_fHW(hourlyRate)}원'], font),
                    if ((wageData['premiumPay'] as num? ?? 0) > 0)
                      _pdfTableRow(['연장/야간/휴일수당', '${wageData['premiumPay']?.toInt()}', '${_fH(premH)}시간 × ${_fHW(hourlyRate * 0.5)}원'], font),
                    if ((wageData['weeklyHolidayPay'] as num? ?? 0) > 0)
                      _pdfTableRow(['주휴수당', '${wageData['weeklyHolidayPay']?.toInt()}', '${_fH(weekH)}시간 × ${_fHW(hourlyRate)}원 (주휴 발생 기준이 되는 시간 명시)'], font),
                    if ((wageData['breakPay'] as num? ?? 0) > 0)
                      _pdfTableRow(['유급휴게수당', '${wageData['breakPay']?.toInt()}', '${_fH(breakH)}시간 × ${_fHW(hourlyRate)}원 (휴게로 인정해 준 총시간 명시)'], font),
                    if ((wageData['laborDayAllowancePay'] as num? ?? 0) > 0)
                      _pdfTableRow(['근로자의 날 유급휴일수당', '${wageData['laborDayAllowancePay']?.toInt()}', '(${_fH((hourlyRate > 0 ? (wageData['laborDayAllowancePay'] as num) / hourlyRate : 0.0) * 5.0)} / 40시간) × 8시간 × ${_fHW(hourlyRate)}원'], font),
                    if ((wageData['otherAllowancePay'] as num? ?? 0) > 0)
                      _pdfTableRow(['기타수당', '${wageData['otherAllowancePay']?.toInt()}', '-'], font),
                    _pdfTableRow(['지급액 합계 (세전총지급액)', '${(wageData['totalPay'] as num?)?.toInt() ?? 0}', '기본급 + 제수당 합계'], font),
                    
                    if ((wageData['mealNonTaxable'] as num? ?? 0) > 0)
                      _pdfTableRow(['└ (포함) 비과세 식대', '${(wageData['mealNonTaxable'] as num?)?.toInt()}', '과세 대상액 산정 시 제외금액'], font),
                      
                    if ((wageData['insuranceDeduction'] as num? ?? 0) > 0) ...[
                      _pdfTableRow(['4대보험 및 세금 공제액', '-${(wageData['insuranceDeduction'] as num?)?.toInt()}', '과세 대상액 기준'], font),
                      if ((wageData['nationalPension'] as num? ?? 0) > 0)
                        _pdfTableRow(['  └ 국민연금', '-${(wageData['nationalPension'] as num?)?.toInt()}', '-'], font),
                      if ((wageData['healthInsurance'] as num? ?? 0) > 0)
                        _pdfTableRow(['  └ 건강보험', '-${(wageData['healthInsurance'] as num?)?.toInt()}', '-'], font),
                      if ((wageData['longTermCareInsurance'] as num? ?? 0) > 0)
                        _pdfTableRow(['  └ 장기요양보험', '-${(wageData['longTermCareInsurance'] as num?)?.toInt()}', '-'], font),
                      if ((wageData['employmentInsurance'] as num? ?? 0) > 0)
                        _pdfTableRow(['  └ 고용보험', '-${(wageData['employmentInsurance'] as num?)?.toInt()}', '-'], font),
                      if ((wageData['businessIncomeTax'] as num? ?? 0) > 0)
                        _pdfTableRow(['  └ 사업소득세 (3%)', '-${(wageData['businessIncomeTax'] as num?)?.toInt()}', '-'], font),
                      if ((wageData['localIncomeTax'] as num? ?? 0) > 0)
                        _pdfTableRow(['  └ 지방소득세 (0.3%)', '-${(wageData['localIncomeTax'] as num?)?.toInt()}', '-'], font),
                    ],
                      
                    if ((wageData['previousMonthAdjustment'] as num? ?? 0) != 0)
                      _pdfTableRow(['전월 이월/정산금', '${(wageData['previousMonthAdjustment'] as num?)?.toInt()}', '별도 등록된 이월/정산금'], font),

                    _pdfTableRow(['최종 실지급액 (차인지급액)', '${(wageData['netPay'] as num?)?.toInt() ?? 0}', '지급액 합계 - 공제액 + 이월금'], font, isHeader: true),
                  ],
                );
              }),
              pw.SizedBox(height: 10),
              pw.Text('* 본 명세서는 근로기준법 제48조 제2항에 따라 교부되었습니다.', 
                style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.grey700)),
              
              // 계산 기초 섹션
              pw.SizedBox(height: 12),
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: pw.BorderRadius.circular(4),
                  border: pw.Border.all(color: PdfColors.grey300),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('계산 기초', style: pw.TextStyle(font: font, fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      '산정 기준: 시급 ${_fmtMoney((wageData['hourlyRate'] as num?)?.round() ?? 0)}원 / '
                      '월 소정근로 ${(wageData['sRefHours'] as num?)?.toInt() ?? 209}시간 (S_Ref 평균 4.345주 기준)',
                      style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey600),
                    ),
                    pw.Text(
                      'App-Calculated via Alba Payroll Standard Engine v1.0',
                      style: pw.TextStyle(font: font, fontSize: 7, color: PdfColors.grey500),
                    ),
                  ],
                ),
              ),
              
              pw.Spacer(),
              
              // 교부 확인 섹션
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(border: pw.Border.all()),
                child: pw.Column(
                  children: [
                    pw.Text('위와 같이 급여명세서를 전자적으로 교부하였음을 확인합니다.', style: pw.TextStyle(font: font, fontSize: 11)),
                    pw.SizedBox(height: 10),
                    pw.Text('발행일: ${AppClock.now().toIso8601String().substring(0, 10)}', style: pw.TextStyle(font: font, fontSize: 11)),
                    pw.SizedBox(height: 10),
                    pw.Text('(인/서명 생략 - 전자 시스템 발급)', style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey)),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );

    // 교부 증명 페이지 추가
    _appendDeliveryProof(pdf, document, font);

    return pdf.save();
  }

  static pw.Widget _pdfSectionTitle(String title, pw.Font font) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Text(title, style: pw.TextStyle(font: font, fontSize: 12, fontWeight: pw.FontWeight.bold)),
    );
  }

  static pw.TableRow _pdfTableRow(List<String> cells, pw.Font font, {bool isHeader = false}) {
    return pw.TableRow(
      children: cells.map((c) => pw.Padding(
        padding: const pw.EdgeInsets.all(6),
        child: pw.Text(c, 
          style: pw.TextStyle(
            font: font, 
            fontSize: isHeader ? 10 : 9, 
            fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal
          ),
          textAlign: pw.TextAlign.center,
        ),
      )).toList(),
    );
  }

  /// 임금 변경 합의서 생성
  static Future<Uint8List> generateWageAmendment({
    required LaborDocument document,
    required Map<String, dynamic> amendmentData,
    Uint8List? ownerSignatureBytes,
    Uint8List? workerSignatureBytes,
  }) async {
    final font = await _loadFont();
    final boldFont = await _loadBoldFont();

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: font,
        bold: boldFont,
      ),
    );
    
    final oldWage = (amendmentData['oldWage'] as num? ?? 0).toDouble();
    final newWage = (amendmentData['newWage'] as num? ?? 0).toDouble();
    final effectiveDay = amendmentData['effectiveDate'] ?? '${PayrollConstants.minimumWageEffectiveYear}년 1월 1일';
    final increaseAmount = newWage - oldWage;

    final storeDefaults = _loadStoreDefaults();
    final storeName = amendmentData['storeName'] ?? storeDefaults['storeName'] ?? '';

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.SizedBox(height: 20),
              pw.Text('임 금 변 경 합 의 서', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 40),
              
              pw.Container(
                alignment: pw.Alignment.centerLeft,
                child: pw.Text('원 근로계약의 효력은 그대로 유지하되, 임금 관련 조항을 아래와 같이 변경함에 상호 합의합니다.', 
                  style: pw.TextStyle(fontSize: 12)),
              ),
              pw.SizedBox(height: 30),
              
              pw.Container(
                padding: const pw.EdgeInsets.all(24),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(width: 1, color: PdfColors.grey),
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Column(
                  children: [
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('기존 시급', style: pw.TextStyle(fontSize: 14)),
                        pw.Text('${oldWage.toInt().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')} 원', 
                          style: pw.TextStyle(fontSize: 14, decoration: pw.TextDecoration.lineThrough)),
                      ],
                    ),
                    pw.SizedBox(height: 12),
                    pw.Text('↓', style: pw.TextStyle(fontSize: 20, color: PdfColors.blue)),
                    pw.SizedBox(height: 12),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('변경 시급', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                        pw.Text('${newWage.toInt().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')} 원', 
                          style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.blue)),
                      ],
                    ),
                    pw.Divider(color: PdfColors.grey400),
                    pw.Align(
                      alignment: pw.Alignment.centerRight,
                      child: pw.Text('(증액: +${increaseAmount.toInt().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')} 원)', 
                        style: pw.TextStyle(fontSize: 12, color: PdfColors.green)),
                    ),
                  ],
                ),
              ),
              
              pw.SizedBox(height: 50),
              pw.Text('적용일자: $effectiveDay', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
              
              pw.Spacer(),
              
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                   pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('사업주 (파리바게뜨 $storeName)', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(height: 10),
                      pw.Stack(
                        alignment: pw.Alignment.center,
                        children: [
                          pw.Text('(인/서명)', style: pw.TextStyle(fontSize: 10, color: PdfColors.grey)),
                          if (ownerSignatureBytes != null)
                            pw.Image(pw.MemoryImage(ownerSignatureBytes), width: 70, height: 45),
                        ]
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('근로자 (${document.staffId})', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(height: 10),
                      pw.Stack(
                        alignment: pw.Alignment.center,
                        children: [
                          pw.Text('(인/서명)', style: pw.TextStyle(fontSize: 10, color: PdfColors.grey)),
                          if (workerSignatureBytes != null)
                            pw.Image(pw.MemoryImage(workerSignatureBytes), width: 70, height: 45),
                        ]
                      ),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 20),
            ],
          );
        },
      ),
    );

    // 교부 증명 페이지 첨부
    _appendDeliveryProof(pdf, document, font);

    return pdf.save();
  }

  /// 디지털 교부 완료 증명 페이지를 PDF에 추가합니다.
  /// 사장님(1차)과 알바생(2차) 두 기기의 메타데이터를 시각화하여
  /// '하이브리드 교차 검증 완료' 도장을 찍습니다.
  static void _appendDeliveryProof(pw.Document pdf, LaborDocument document, pw.Font font, {String? documentHash}) {
    final bossMeta = document.bossSignatureMetadata;
    final employeeMeta = document.signatureMetadata;

    // 두 기기 메타데이터가 모두 있을 때만 인증 완료 도장 표시
    final isBothVerified = bossMeta != null && employeeMeta != null;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (pw.Context ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // 헤더
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                decoration: pw.BoxDecoration(
                  color: PdfColor.fromHex('#1A1A2E'),
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      '디지털 교부 완료 증명서',
                      style: pw.TextStyle(font: font, fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      '본 문서는 전자적 방법으로 서명·교부된 노무서류의 법적 효력을 증명합니다.',
                      style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.white),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 24),
 
              // 인증 상태 배지
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: isBothVerified ? PdfColor.fromHex('#EAF3DE') : PdfColor.fromHex('#FFF0DC'),
                  borderRadius: pw.BorderRadius.circular(6),
                  border: pw.Border.all(
                    color: isBothVerified ? PdfColor.fromHex('#286b3a') : PdfColor.fromHex('#854F0B'),
                  ),
                ),
                child: pw.Text(
                  isBothVerified
                      ? '✔ 하이브리드 교차 검증 완료 — 사장님 기기 + 알바생 기기 양측 인증'
                      : '⏳ 검증 진행 중 — 알바생 서명 대기',
                  style: pw.TextStyle(
                    font: font,
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                    color: isBothVerified ? PdfColor.fromHex('#286b3a') : PdfColor.fromHex('#854F0B'),
                  ),
                ),
              ),
              pw.SizedBox(height: 20),

              // 서류 정보
              _pdfInfoRow('서류 제목', document.title, font),
              _pdfInfoRow('서류 ID', document.id, font),
              _pdfInfoRow('교부 확정일시', document.deliveryConfirmedAt?.toIso8601String() ?? '-', font),
              pw.SizedBox(height: 20),
              pw.Divider(),
              pw.SizedBox(height: 16),
 
              // 1차 메타데이터: 사장님
              pw.Text('1차 서명 — 사업주 (사장님)', style: pw.TextStyle(font: font, fontSize: 14, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 8),
              if (bossMeta != null) ...[
                _pdfInfoRow('서명 일시', bossMeta['timestamp']?.toString() ?? '-', font),
                _pdfInfoRow('기기 모델', bossMeta['device']?.toString() ?? '-', font),
                _pdfInfoRow('기기 ID', bossMeta['deviceId']?.toString() ?? '-', font),
                _pdfInfoRow('IP 주소', bossMeta['ipAddress']?.toString() ?? '-', font),
                _pdfInfoRow('GPS 좌표', bossMeta['gps']?.toString() ?? '-', font),
              ] else
                pw.Text('서명 정보 없음 (사장님 서명 대기 중)', style: pw.TextStyle(font: font, color: PdfColors.grey)),
 
              pw.SizedBox(height: 20),
              pw.Divider(),
              pw.SizedBox(height: 16),
 
              // 2차 메타데이터: 알바생
              pw.Text('2차 서명 — 근로자 (알바생)', style: pw.TextStyle(font: font, fontSize: 14, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 8),
              if (employeeMeta != null) ...[
                _pdfInfoRow('서명 일시', employeeMeta['timestamp']?.toString() ?? '-', font),
                _pdfInfoRow('기기 모델', employeeMeta['device']?.toString() ?? '-', font),
                _pdfInfoRow('기기 ID', employeeMeta['deviceId']?.toString() ?? '-', font),
                _pdfInfoRow('IP 주소', employeeMeta['ipAddress']?.toString() ?? '-', font),
                _pdfInfoRow('GPS 좌표', employeeMeta['gps']?.toString() ?? '-', font),
              ] else
                pw.Text('서명 정보 없음 (알바생 서명 대기 중)', style: pw.TextStyle(font: font, color: PdfColors.grey)),

              pw.SizedBox(height: 20),

              // ★ 문서 무결성 해시 (SHA-256)
              pw.Divider(),
              pw.SizedBox(height: 8),
              pw.Text('문서 무결성 검증', style: pw.TextStyle(font: font, fontSize: 14, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 8),
              if (document.documentHash != null && document.documentHash!.isNotEmpty) ...[
                _pdfInfoRow('해시 알고리즘', 'SHA-256', font),
                _pdfInfoRow('문서 해시', document.documentHash!, font),
                pw.SizedBox(height: 4),
                pw.Text(
                  '상기 해시값은 문서 생성 시점의 핵심 데이터(서류유형, 직원ID, 본문, 구조화 데이터, 생성일시)로부터 산출되었습니다. '
                  '동일한 입력값으로 해시를 재계산하여 일치 여부를 확인하면 문서의 위·변조 여부를 검증할 수 있습니다.',
                  style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey600),
                ),
              ] else
                pw.Text('해시 미생성 (이전 버전 문서)', style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey)),

              pw.Spacer(),

              // 푸터
              pw.Divider(),
              pw.SizedBox(height: 8),
              if (documentHash != null) ...[
                pw.Text(
                  '무결성 해시(SHA-256): $documentHash',
                  style: pw.TextStyle(font: font, fontSize: 7, color: PdfColors.grey),
                ),
                pw.SizedBox(height: 2),
              ],
              pw.Text(
                'App-Calculated via Alba Payroll Standard Engine v1.0 (Logic: Bottom-up Integrity Check Passed)',
                style: pw.TextStyle(font: font, fontSize: 7, color: PdfColors.grey),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                '본 증명서는 알바급여정석 시스템에 의해 자동 생성되었습니다. '
                '원본 데이터는 AES-256 암호화 방식으로 서버에 보관되며, '
                '법정 보존 기간(3년)이 경과한 후 파기됩니다.',
                style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.grey),
              ),
            ],
          );
        },
      ),
    );
  }

  static pw.Widget _pdfInfoRow(String label, String value, pw.Font font) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 90,
            child: pw.Text(label, style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey700)),
          ),
          pw.Text(': ', style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey)),
          pw.Expanded(
            child: pw.Text(value, style: pw.TextStyle(font: font, fontSize: 10)),
          ),
        ],
      ),
    );
  }

  /// 최종 PDF 생성 및 스토리지 업로드 (교부 프로세스)
  /// 계약서 PDF 생성 → R2 아카이브 → 교부 상태 업데이트
  /// (Firebase Storage 업로드 제거 — R2가 유일한 PDF 보관소)
  static Future<void> generateAndUploadFinalPdf({
    required LaborDocument document,
    required Map<String, dynamic> contractData,
  }) async {
    // 1. 서명 이미지 다운로드 (있는 경우)
    Uint8List? ownerSig;
    Uint8List? workerSig;

    try {
      if (document.bossSignatureUrl != null && document.bossSignatureUrl!.isNotEmpty) {
        final res = await http.get(Uri.parse(document.bossSignatureUrl!));
        if (res.statusCode == 200) ownerSig = res.bodyBytes;
      }
      if (document.signatureUrl != null && document.signatureUrl!.isNotEmpty) {
        final res = await http.get(Uri.parse(document.signatureUrl!));
        if (res.statusCode == 200) workerSig = res.bodyBytes;
      }
    } catch (e) {
      debugPrint('Error downloading signatures for PDF: $e');
    }

    // 2. 문서 타입에 따른 PDF 생성
    Uint8List pdfBytes;
    if (document.type == DocumentType.contract_full) {
      pdfBytes = await generateFullContract(
        document: document,
        contractData: contractData,
        ownerSignatureBytes: ownerSig,
        workerSignatureBytes: workerSig,
      );
    } else if (document.type == DocumentType.contract_part) {
      pdfBytes = await generatePartTimeContract(
        document: document,
        contractData: contractData,
        ownerSignatureBytes: ownerSig,
        workerSignatureBytes: workerSig,
      );
    } else {
      throw Exception('지원하지 않는 문서 타입입니다 (${document.type})');
    }

    // 3. R2 아카이브 (immutable 확정본 보관)
    try {
      await PdfArchiveService.instance.archiveSignedDocument(
        doc: document,
        pdfBytes: pdfBytes,
      );
      debugPrint('✅ 계약서 PDF R2 아카이브 완료: ${document.id}');
    } catch (e) {
      debugPrint('⚠️ R2 아카이브 실패 (교부는 계속 진행): $e');
    }

    // 4. Firestore 상태 업데이트 (sent 상태로 변경, pdfUrl 제거)
    await FirebaseFirestore.instance
        .collection('stores')
        .doc(document.storeId)
        .collection('documents')
        .doc(document.id)
        .update({
      'status': 'sent',
      'sentAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<Uint8List> generateNightConsent({
    required LaborDocument document,
    required Map<String, dynamic> consentData,
  }) async {
    final pdf = pw.Document();
    final font = await _loadFont();
    final boldFont = await _loadBoldFont();
    final defaults = _loadStoreDefaults();

    pw.Widget? sigImage;
    if (consentData['signatureBase64'] != null) {
      try {
        final img = pw.MemoryImage(base64Decode(consentData['signatureBase64']));
        sigImage = pw.Image(img, width: 80, height: 40);
      } catch (_) {}
    }

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(
                child: pw.Text('야간 및 휴일근로 동의서', style: pw.TextStyle(font: boldFont, fontSize: 24)),
              ),
              pw.SizedBox(height: 30),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey400),
                children: [
                  _pdfTableRow(['사업장명', defaults['storeName'] ?? '', '대표자명', defaults['ownerName'] ?? ''], font),
                  _pdfTableRow(['성명', consentData['name'] ?? '', '생년월일', consentData['birthDate'] ?? ''], font),
                  _pdfTableRow(['주소', consentData['address'] ?? '', '연락처', consentData['phone'] ?? ''], font),
                ]
              ),
              pw.SizedBox(height: 30),
              pw.Text('  본인은 관련 법률 및 사업장의 운영 규정에 따라 다음과 같이 야간 및 휴일근로에 동의합니다.', style: pw.TextStyle(font: font, fontSize: 13, lineSpacing: 2)),
              pw.SizedBox(height: 15),
              pw.Text('   1. 야간근로 (22:00 ~ 06:00) 동의', style: pw.TextStyle(font: boldFont, fontSize: 12)),
              pw.Text('   2. 휴일근로 (주휴일 및 법정 공휴일) 동의', style: pw.TextStyle(font: boldFont, fontSize: 12)),
              pw.SizedBox(height: 30),
              pw.Text('본 동의는 근로자 본인의 자발적 의사에 의한 것이며, 야간 및 휴일에 근로할 경우 법정 가산수당이 지급됨을 숙지합니다.', style: pw.TextStyle(font: font, fontSize: 13, lineSpacing: 2)),
              pw.Spacer(),
              pw.Container(
                alignment: pw.Alignment.centerRight,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('작성일: ${document.createdAt.year}년 ${document.createdAt.month}월 ${document.createdAt.day}일', style: pw.TextStyle(font: font, fontSize: 13)),
                    pw.SizedBox(height: 10),
                    pw.Row(
                      mainAxisSize: pw.MainAxisSize.min,
                      children: [
                        pw.Text('성명: ${consentData['name'] ?? ''} (서명/인) ', style: pw.TextStyle(font: font, fontSize: 14)),
                        if (sigImage != null) sigImage,
                      ]
                    )
                  ]
                )
              ),
              pw.SizedBox(height: 20),
            ],
          );
        },
      ),
    );
    return pdf.save();
  }

  static Future<Uint8List> generateWorkerRecord({
    required LaborDocument document,
    required Map<String, dynamic> recordData,
  }) async {
    final pdf = pw.Document();
    final font = await _loadFont();
    final boldFont = await _loadBoldFont();
    final defaults = _loadStoreDefaults();

    pw.Widget? sigImage;
    if (recordData['signatureBase64'] != null) {
      try {
        final img = pw.MemoryImage(base64Decode(recordData['signatureBase64']));
        sigImage = pw.Image(img, width: 80, height: 40);
      } catch (_) {}
    }

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(
                child: pw.Text('근로자 명부', style: pw.TextStyle(font: boldFont, fontSize: 24)),
              ),
              pw.SizedBox(height: 30),
              pw.Text('사업장 정보', style: pw.TextStyle(font: boldFont, fontSize: 14)),
              pw.SizedBox(height: 5),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey400),
                children: [
                  _pdfTableRow(['사업장명', defaults['storeName'] ?? '', '대표자', defaults['ownerName'] ?? ''], font),
                  _pdfTableRow(['소재지', defaults['storeAddress'] ?? '', '연락처', defaults['storePhone'] ?? ''], font),
                ]
              ),
              pw.SizedBox(height: 20),
              pw.Text('근로자 인적사항 (근로기준법 제41조)', style: pw.TextStyle(font: boldFont, fontSize: 14)),
              pw.SizedBox(height: 5),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey400),
                children: [
                  _pdfTableRow(['성명', recordData['name'] ?? '', '생년월일', recordData['birthDate'] ?? ''], font),
                  _pdfTableRow(['주소', recordData['address'] ?? '', '연락처', recordData['phone'] ?? ''], font),
                  _pdfTableRow(['고용형태', recordData['jobType'] ?? '상용/단기', '채용일자', recordData['hireDate'] ?? document.createdAt.toString().substring(0, 10)], font),
                  _pdfTableRow(['종사 업무', recordData['duty'] ?? '매장 업무 전반', '계약기간', recordData['contractDate'] ?? '별도 계약서 참조'], font),
                ]
              ),
              pw.Spacer(),
              pw.Container(
                alignment: pw.Alignment.centerRight,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('작성일: ${document.createdAt.year}년 ${document.createdAt.month}월 ${document.createdAt.day}일', style: pw.TextStyle(font: font, fontSize: 13)),
                    pw.SizedBox(height: 10),
                    pw.Row(
                      mainAxisSize: pw.MainAxisSize.min,
                      children: [
                        pw.Text('성명: ${recordData['name'] ?? ''} (확인/인) ', style: pw.TextStyle(font: font, fontSize: 14)),
                        if (sigImage != null) sigImage,
                      ]
                    )
                  ]
                )
              ),
              pw.SizedBox(height: 20),
            ],
          );
        },
      ),
    );
    return pdf.save();
  }

  static Future<Uint8List> generateParentalConsent({
    required Map<String, dynamic> storeDefaults,
    required String workerName,
    required String workerBirthDate,
    required String workerAddress,
    required String workerPhone,
    String hourlyWage = '',
    String workDays = '',
    String workingHours = '',
    String startDate = '',
  }) async {
    final pdf = pw.Document();
    final font = await _loadFont();
    final boldFont = await _loadBoldFont();

    final storeName = storeDefaults['storeName'] ?? '';
    final storeAddress = storeDefaults['storeAddress'] ?? '';
    final ownerName = storeDefaults['ownerName'] ?? '';
    final storePhone = storeDefaults['storePhone'] ?? '';

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(height: 10),
              pw.Center(
                child: pw.Text('친권자(후견인) 동의서',
                    style: pw.TextStyle(
                        font: boldFont,
                        fontSize: 24,
                        decoration: pw.TextDecoration.underline)),
              ),
              pw.SizedBox(height: 6),
              pw.Center(
                child: pw.Text('[근로기준법 제66조, 제67조에 의거]',
                    style: pw.TextStyle(
                        font: font, fontSize: 10, color: PdfColors.grey700)),
              ),
              pw.SizedBox(height: 30),

              // 1. 연소 근로자 정보
              pw.Text('1. 연소 근로자 (미성년자)',
                  style: pw.TextStyle(font: boldFont, fontSize: 13)),
              pw.SizedBox(height: 5),
              pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.grey500),
                  children: [
                    _pdfTableRow(
                        ['성명', workerName, '생년월일', workerBirthDate], font),
                    _pdfTableRow(
                        ['주소', workerAddress, '연락처', workerPhone], font),
                  ]),
              pw.SizedBox(height: 20),

              // 2. 근무처 정보
              pw.Text('2. 근무처 정보',
                  style: pw.TextStyle(font: boldFont, fontSize: 13)),
              pw.SizedBox(height: 5),
              pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.grey500),
                  children: [
                    _pdfTableRow(
                        ['사업장명', storeName, '대표자', ownerName], font),
                    _pdfTableRow(
                        ['사업장 주소', storeAddress, '연락처', storePhone], font),
                  ]),
              pw.SizedBox(height: 20),

              // 3. 근로 조건
              pw.Text('3. 근로 조건',
                  style: pw.TextStyle(font: boldFont, fontSize: 13)),
              pw.SizedBox(height: 5),
              pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.grey500),
                  children: [
                    _pdfTableRow(['업무 내용', '매장 관리 및 고객 응대', '시급',
                      hourlyWage.isNotEmpty ? '${hourlyWage}원' : '          원'], font),
                    _pdfTableRow(['근무 요일', workDays.isNotEmpty ? workDays : ' ',
                      '근무 시간', workingHours.isNotEmpty ? workingHours : ' '], font),
                    _pdfTableRow(['근로계약 시작일', startDate.isNotEmpty ? startDate : '      년    월    일',
                      '비고', '1일 7시간, 주 35시간 이내'], font),
                  ]),
              pw.SizedBox(height: 20),

              // 4. 친권자 정보
              pw.Text('4. 친권자 (또는 후견인)',
                  style: pw.TextStyle(font: boldFont, fontSize: 13)),
              pw.SizedBox(height: 5),
              pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.black),
                  children: [
                    _pdfTableRow(['성명', ' ', '연소자와의 관계', ' '], font),
                    _pdfTableRow(['생년월일', ' ', '연락처', ' '], font),
                  ]),
              pw.Table(
                  border: const pw.TableBorder(
                    left: pw.BorderSide(color: PdfColors.black),
                    right: pw.BorderSide(color: PdfColors.black),
                    bottom: pw.BorderSide(color: PdfColors.black),
                    verticalInside: pw.BorderSide(color: PdfColors.black),
                  ),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(1),
                    1: const pw.FlexColumnWidth(3),
                  },
                  children: [
                    _pdfTableRow(['주소', ' '], font),
                  ]),
              pw.SizedBox(height: 20),

              // 5. 동의문
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey700),
                ),
                child: pw.Text(
                  '  본인은 위 연소자의 법정대리인(친권자/후견인)으로서, 위 연소자가 '
                  '위 사업장(${storeName.isNotEmpty ? storeName : "          "})에서 '
                  '위와 같은 조건으로 근로하는 것에 법적으로 동의합니다.',
                  style: pw.TextStyle(
                      font: font, fontSize: 12, lineSpacing: 4),
                ),
              ),
              pw.SizedBox(height: 12),

              // 법적 주의사항
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('※ 법적 유의사항',
                          style: pw.TextStyle(
                              font: boldFont,
                              fontSize: 10,
                              color: PdfColors.grey800)),
                      pw.SizedBox(height: 4),
                      pw.Text(
                          '• 근로기준법 제66조: 18세 미만자에 대하여는 친권자/후견인의 동의서와 가족관계증명서를 사업장에 비치',
                          style: pw.TextStyle(
                              font: font,
                              fontSize: 9,
                              color: PdfColors.grey700)),
                      pw.Text(
                          '• 근로기준법 제67조: 18세 미만자의 근로계약은 친권자/후견인이 대리 체결 불가 (본인 직접 체결)',
                          style: pw.TextStyle(
                              font: font,
                              fontSize: 9,
                              color: PdfColors.grey700)),
                      pw.Text(
                          '• 근로기준법 제69조: 연소자의 근로시간은 1일 7시간, 1주 35시간 초과 금지',
                          style: pw.TextStyle(
                              font: font,
                              fontSize: 9,
                              color: PdfColors.grey700)),
                      pw.Text(
                          '• 근로기준법 제70조: 오후 10시~오전 6시 야간근로 및 휴일근로 원칙 금지 (본인 동의 + 고용노동부 인가 시 예외)',
                          style: pw.TextStyle(
                              font: font,
                              fontSize: 9,
                              color: PdfColors.grey700)),
                    ]),
              ),
              pw.Spacer(),

              // 첨부서류 안내
              pw.Text('첨부 서류 (반드시 함께 제출)',
                  style: pw.TextStyle(font: boldFont, fontSize: 11)),
              pw.SizedBox(height: 4),
              pw.Text('  □ 가족관계증명서 1부',
                  style: pw.TextStyle(font: font, fontSize: 11)),
              pw.Text('  □ 주민등록등본 또는 등·초본 1부 (주소 확인용)',
                  style: pw.TextStyle(font: font, fontSize: 11)),
              pw.SizedBox(height: 20),

              // 날짜 및 서명란
              pw.Center(
                  child: pw.Text('20    년      월      일',
                      style: pw.TextStyle(font: boldFont, fontSize: 14))),
              pw.SizedBox(height: 24),
              pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  children: [
                    pw.Text('동의인 (친권자/후견인):  ',
                        style: pw.TextStyle(font: boldFont, fontSize: 14)),
                    pw.Container(
                        width: 120,
                        decoration: const pw.BoxDecoration(
                            border: pw.Border(
                                bottom: pw.BorderSide(width: 1)))),
                    pw.SizedBox(width: 10),
                    pw.Text('(서명 또는 인)',
                        style: pw.TextStyle(font: font, fontSize: 12)),
                  ]),
              pw.SizedBox(height: 16),
              pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  children: [
                    pw.Text('사업주 확인:  ',
                        style: pw.TextStyle(font: boldFont, fontSize: 14)),
                    pw.Container(
                        width: 120,
                        decoration: const pw.BoxDecoration(
                            border: pw.Border(
                                bottom: pw.BorderSide(width: 1)))),
                    pw.SizedBox(width: 10),
                    pw.Text('(서명 또는 인)',
                        style: pw.TextStyle(font: font, fontSize: 12)),
                  ]),
              pw.SizedBox(height: 16),
            ],
          );
        },
      ),
    );
    return pdf.save();
  }

  /// ─── 연차 사용촉진 서면 통보서 PDF 생성 (근로기준법 제61조) ───
  ///
  /// [step] 1 = 1차 촉진 (연차 사용 시기 지정 요청)
  ///         2 = 2차 촉진 (사장님 직접 사용 날짜 지정)
  static Future<Uint8List> generateLeavePromotionNotice({
    required int step,
    required String workerName,
    required double unusedDays,
    required DateTime batchGrantDate,
    required DateTime batchExpiryDate,
    required bool isPreAnniversary,
    List<String> designatedDates = const [],
    String? auditHash,
  }) async {
    final font = await _loadFont();
    final boldFont = await _loadBoldFont();

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(base: font, bold: boldFont),
    );

    final storeDefaults = _loadStoreDefaults();
    final storeName = storeDefaults['storeName'] ?? '';
    final ownerName = storeDefaults['ownerName'] ?? '';

    final now = AppClock.now();
    final grantLabel = '${batchGrantDate.year}년 ${batchGrantDate.month}월 ${batchGrantDate.day}일';
    final expiryLabel = '${batchExpiryDate.year}년 ${batchExpiryDate.month}월 ${batchExpiryDate.day}일';

    final leaveType = isPreAnniversary ? '입사 1년 미만 발생 연차' : '정기 연차 (입사 ${_yearLabel(batchGrantDate, batchExpiryDate)})';
    final legalBasis = isPreAnniversary
        ? '근로기준법 제61조 제2항 (1년 미만 근로자 연차 사용촉진)'
        : '근로기준법 제61조 제1항 (연차유급휴가 사용촉진)';
    final deadlineType = isPreAnniversary ? '3개월/1개월' : '6개월/2개월';

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(
                child: pw.Text(
                  step == 1
                      ? '연차유급휴가 사용촉진 통보서 (제1차)'
                      : '연차유급휴가 사용시기 지정 통보서 (제2차)',
                  style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Center(
                child: pw.Text('[$legalBasis]', style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
              ),
              pw.SizedBox(height: 30),

              // 수신자 정보
              pw.Container(
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(border: pw.Border.all()),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('수 신 : $workerName 귀하', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 8),
                    pw.Text('발 신 : $storeName 대표 $ownerName', style: pw.TextStyle(fontSize: 12)),
                    pw.SizedBox(height: 4),
                    pw.Text('발신일 : ${now.year}년 ${now.month}월 ${now.day}일', style: pw.TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),

              // 제목
              pw.Text(
                step == 1
                    ? '제목: 미사용 연차유급휴가 사용 시기 지정 요청'
                    : '제목: 미사용 연차유급휴가 사용 시기 지정 통보',
                style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 16),

              // 본문
              if (step == 1) ...[
                pw.Text(
                  '귀하의 $leaveType 중 미사용 연차가 아래와 같이 있으므로, '
                  '$legalBasis에 의거하여 사용 시기를 정하여 통보하여 주시기 바랍니다.',
                  style: pw.TextStyle(fontSize: 11, lineSpacing: 4),
                ),
                pw.SizedBox(height: 16),
                pw.Text('※ 본 통보서 수령 후 10일 이내에 미사용 연차의 사용 시기를 서면으로 통보하여 주십시오.',
                  style: pw.TextStyle(fontSize: 10, color: PdfColors.red, fontWeight: pw.FontWeight.bold)),
                pw.Text('※ 10일 이내에 통보하지 않을 경우, 사용자가 직접 사용 시기를 지정하여 서면 통보합니다.',
                  style: pw.TextStyle(fontSize: 10, color: PdfColors.red)),
              ] else ...[
                pw.Text(
                  '귀하가 제1차 촉진 통보($leaveType) 수령 후 10일 이내에 '
                  '사용 시기를 통보하지 않았으므로, $legalBasis에 의거하여 '
                  '사용자가 아래와 같이 미사용 연차의 사용 시기를 직접 지정합니다.',
                  style: pw.TextStyle(fontSize: 11, lineSpacing: 4),
                ),
              ],
              pw.SizedBox(height: 20),

              // 연차 상세 테이블
              pw.Text('■ 미사용 연차 내역', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 8),
              pw.Table(
                border: pw.TableBorder.all(),
                children: [
                  pw.TableRow(children: [
                    _paddedCell('구분', font, align: pw.TextAlign.center),
                    _paddedCell('내용', font, align: pw.TextAlign.center),
                  ]),
                  pw.TableRow(children: [
                    _paddedCell('연차 유형', font),
                    _paddedCell(leaveType, font),
                  ]),
                  pw.TableRow(children: [
                    _paddedCell('연차 발생일', font),
                    _paddedCell(grantLabel, font),
                  ]),
                  pw.TableRow(children: [
                    _paddedCell('연차 소멸 예정일', font),
                    _paddedCell(expiryLabel, font),
                  ]),
                  pw.TableRow(children: [
                    _paddedCell('미사용 연차 수', font),
                    _paddedCell('${unusedDays.toStringAsFixed(1)}일', font),
                  ]),
                  pw.TableRow(children: [
                    _paddedCell('촉진 기한 유형', font),
                    _paddedCell('소멸일 기준 $deadlineType 전', font),
                  ]),
                ],
              ),

              if (step == 2 && designatedDates.isNotEmpty) ...[
                pw.SizedBox(height: 16),
                pw.Text('■ 지정된 사용 날짜', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 8),
                ...designatedDates.map((d) => pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 4),
                  child: pw.Text('  • $d', style: pw.TextStyle(fontSize: 11)),
                )),
              ],

              pw.Spacer(),

              // 서명란
              pw.Container(
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(border: pw.Border.all()),
                child: pw.Column(
                  children: [
                    pw.Text('위와 같이 ${step == 1 ? "연차 사용 시기 지정을 요청" : "연차 사용 시기를 지정"}합니다.',
                      style: pw.TextStyle(fontSize: 11)),
                    pw.SizedBox(height: 16),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text('사용자(대표): $ownerName', style: pw.TextStyle(fontSize: 11)),
                            pw.Text('사업장: $storeName', style: pw.TextStyle(fontSize: 11)),
                            pw.SizedBox(height: 20),
                            pw.Text('(서명/인)', style: pw.TextStyle(fontSize: 10, color: PdfColors.grey)),
                          ],
                        ),
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text('근로자: $workerName', style: pw.TextStyle(fontSize: 11)),
                            pw.SizedBox(height: 4),
                            pw.Text('수령 확인일:               년       월       일', style: pw.TextStyle(fontSize: 11)),
                            pw.SizedBox(height: 16),
                            pw.Text('(서명/인)', style: pw.TextStyle(fontSize: 10, color: PdfColors.grey)),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 8),

              // 감사 메타데이터 (위변조 방지)
              pw.Container(
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('디지털 검증 정보 (무결성 보장)', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: PdfColors.grey600)),
                    pw.Text('생성 시각: ${now.toIso8601String()}', style: pw.TextStyle(fontSize: 7, color: PdfColors.grey500)),
                    if (auditHash != null)
                      pw.Text('무결성 해시: $auditHash', style: pw.TextStyle(fontSize: 7, color: PdfColors.grey500)),
                    pw.Text('알바급여 정석 앱 자동 생성 — 본 문서는 근로기준법 제61조에 근거한 법적 서면입니다.',
                      style: pw.TextStyle(fontSize: 7, color: PdfColors.grey500)),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  static String _yearLabel(DateTime grant, DateTime expiry) {
    final diff = expiry.year - grant.year;
    if (expiry.month < grant.month || (expiry.month == grant.month && expiry.day < grant.day)) {
      return '${diff}년차';
    }
    return '${diff + 1}년차';
  }
}
