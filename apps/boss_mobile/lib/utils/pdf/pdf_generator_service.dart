import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:http/http.dart' as http;
import 'package:firebase_storage/firebase_storage.dart';
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
    final wagePaymentDay = contractData['wagePaymentDay'] ?? '   ';

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
                    pw.Text('- (시간, 일, 월)급 : $hourlyWage 원  ※해당사항에 O표', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                    pw.Text('- 상여금 : 있음 (    ) ________________ 원, 없음 ( O )', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                    pw.Text('- 기타급여(제수당 등) : 있음 (    ), 없음 ( O ) ________________원, ________________원', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                    pw.Text('- 가산임금율(상시근로자 5인 이상 : 연장, 야간, 휴일근로 등)', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(left: 8),
                      child: pw.Text(': 법내 초과근로는 가산임금을 지급하지 않고, 1일 및 1주 법정기준근로시간을 초과하는 경우,\n  야간 및 휴일근로의 경우 통상임금의 50% 가산 지급', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text('- 임금지급일 : 매월(매주 또는 매일) $wagePaymentDay 일  ※휴일의 경우는 전일 지급', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                    pw.Text('- 지급방법 : 근로자에게 직접지급(    ), 근로자 명의 예금통장에 입금( O )', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                  ]
                )
              ),
              
              pw.SizedBox(height: 8),
              pw.Text('7. 연차유급휴가', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
              pw.Padding(
                padding: const pw.EdgeInsets.only(left: 12, top: 2),
                child: pw.Text('- 연차유급휴가는 근로기준법에서 정하는 바에 따라 부여함 ※상시근로자 5인 이상', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
              ),
              
              pw.SizedBox(height: 8),
              pw.Text('8. 근로계약서 교부', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
              pw.Padding(
                padding: const pw.EdgeInsets.only(left: 12, top: 2),
                child: pw.Text('- 사업주는 근로계약을 체결함과 동시에 본 계약서를 사본하여 근로자의 교부요구와 관계없이\n  근로자에게 교부함(근로기준법 제17조 이행)', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
              ),
              
              pw.SizedBox(height: 8),
              pw.Text('9. 기 타', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
              pw.Padding(
                padding: const pw.EdgeInsets.only(left: 12, top: 2),
                child: pw.Text('- 이 계약에 정함이 없는 사항은 근로기준법령에 의함', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
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

    // 교부 증명 페이지 추가
    _appendDeliveryProof(pdf, document, font);

    return pdf.save();
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
                      _centeredCell('50%, 상시 5인이상 점포', font),
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
              pw.Table(
                border: pw.TableBorder.all(),
                children: [
                  _pdfTableRow(['항목', '금액 (원)', '계산방법/산출근거'], font, isHeader: true),
                  _pdfTableRow(['기본급', '${wageData['basePay']?.toInt()}', '시급 ${wageData['hourlyRate']}원 × ${wageData['pureLaborHours']}시간'], font),
                  if ((wageData['premiumPay'] as num? ?? 0) > 0)
                    _pdfTableRow(['연장/야간/휴일수당', '${wageData['premiumPay']?.toInt()}', '가산 대상 시간 × 0.5배'], font),
                  if ((wageData['weeklyHolidayPay'] as num? ?? 0) > 0)
                    _pdfTableRow(['주휴수당', '${wageData['weeklyHolidayPay']?.toInt()}', '주 15시간 이상 소정근로 시 발생'], font),
                  if ((wageData['breakPay'] as num? ?? 0) > 0)
                    _pdfTableRow(['근로장려수당', '${wageData['breakPay']?.toInt()}', '-'], font),
                  if ((wageData['otherAllowancePay'] as num? ?? 0) > 0)
                    _pdfTableRow(['기타수당', '${wageData['otherAllowancePay']?.toInt()}', '-'], font),
                  _pdfTableRow(['지급액 합계 (세전총지급액)', '${(wageData['totalPay'] as num?)?.toInt() ?? 0}', '기본급 + 제수당 합계'], font),
                  
                  if ((wageData['mealNonTaxable'] as num? ?? 0) > 0)
                    _pdfTableRow(['└ (포함) 비과세 식대', '${(wageData['mealNonTaxable'] as num?)?.toInt()}', '과세 대상액 산정 시 제외금액'], font),
                    
                  if ((wageData['insuranceDeduction'] as num? ?? 0) > 0)
                    _pdfTableRow(['4대보험 등 공제액', '-${(wageData['insuranceDeduction'] as num?)?.toInt()}', '과세 대상액의 약 9.4% 예상치'], font),
                    
                  if ((wageData['previousMonthAdjustment'] as num? ?? 0) != 0)
                    _pdfTableRow(['전월 이월/정산금', '${(wageData['previousMonthAdjustment'] as num?)?.toInt()}', '별도 등록된 이월/정산금'], font),

                  _pdfTableRow(['최종 실지급액 (차인지급액)', '${(wageData['netPay'] as num?)?.toInt() ?? 0}', '지급액 합계 - 공제액 + 이월금'], font, isHeader: true),
                ],
              ),
              pw.SizedBox(height: 10),
              pw.Text('* 본 명세서는 근로기준법 제48조 제2항에 따라 교부되었습니다.', 
                style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.grey700)),
              
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
  static void _appendDeliveryProof(pw.Document pdf, LaborDocument document, pw.Font font) {
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

              pw.Spacer(),

              // 푸터
              pw.Divider(),
              pw.SizedBox(height: 8),
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
  static Future<String> generateAndUploadFinalPdf({
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

    // 3. Firebase Storage 업로드
    final storageRef = FirebaseStorage.instance
        .ref()
        .child('stores')
        .child(document.storeId)
        .child('documents')
        .child('${document.id}.pdf');

    final uploadTask = await storageRef.putData(
      pdfBytes,
      SettableMetadata(contentType: 'application/pdf'),
    );

    final downloadUrl = await uploadTask.ref.getDownloadURL();

    // 4. Firestore 상태 업데이트 (sent 상태로 변경)
    await FirebaseFirestore.instance
        .collection('stores')
        .doc(document.storeId)
        .collection('documents')
        .doc(document.id)
        .update({
      'status': 'sent',
      'sentAt': FieldValue.serverTimestamp(),
      'pdfUrl': downloadUrl,
    });

    return downloadUrl;
  }
}
