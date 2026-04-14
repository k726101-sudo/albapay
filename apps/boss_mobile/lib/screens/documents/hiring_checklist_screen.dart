import 'dart:typed_data';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:signature/signature.dart';
import 'package:shared_logic/shared_logic.dart';
import '../../models/worker.dart';

// ─── 섹션 1: 구비서류 목록 ───────────────────────────────────────────
const _requiredDocs = [
  {'no': '1', 'name': '이 력 서', 'issuer': '', 'note': ''},
  {'no': '2', 'name': '주민등록등본', 'issuer': '주민등록지', 'note': '가족사항이 안나올 시 가족관계증명원 제출'},
  {'no': '3', 'name': '근 로 계 약 서', 'issuer': '고용노동부', 'note': '단시간근로자 포함'},
  {'no': '4', 'name': '휴일 및 야간근로 동의서', 'issuer': '고용노동부', 'note': '여성근로자'},
  {'no': '5', 'name': '친권자 동의서', 'issuer': '고용노동부', 'note': '청소년(만 18세 미만)'},
  {'no': '6', 'name': '통장 사본', 'issuer': '금융기관', 'note': '근로자 본인명의'},
  {'no': '7', 'name': '보건증', 'issuer': '보건소', 'note': ''},
];

// ─── 섹션 2: 확인/동의서 항목 ──────────────────────────────────────
const _consentItems = [
  '고용한 모든 근로자에 대해 근로계약을 체결한다.',
  '청소년(만 18세미만)에 대하여는 그 연령을 증명하는 가족관계기록사항에 대한 증명서와 친권자 동의서를 갖추고 있다.',
  '여성근로자를 야간/휴일에 근로시키는 경우 동의를 받는다.',
  '최저임금법에 의거, 법정 최저임금에 대해 주지 받고, 이를 확인 했습니다.',
  '본인의 근로조건(시급, 근로일별 근로시간, 휴가/휴일 등)에 대해 숙지했습니다.',
  '직장(점포) 내 성희롱 발생 관련하여 성희롱 예방교육을 받았습니다.(처리절차 및 조치기준 포함)',
  '연장, 야간, 휴일 근로에 대해 자발적으로 동의했습니다.',
  '금품청산 관련 최종급여 약속한 지급일에, 퇴직금은 최종급여 지급 후 14일 이내 정산함을 동의했습니다.',
];


class HiringChecklistScreen extends StatefulWidget {
  final Worker worker;
  final String storeId;
  final LaborDocument document;

  final VoidCallback? onNext;
  final String? nextButtonLabel;
  final bool isWizardMode;

  const HiringChecklistScreen({
    super.key,
    required this.worker,
    required this.storeId,
    required this.document,
    this.onNext,
    this.nextButtonLabel,
    this.isWizardMode = false,
  });

  @override
  State<HiringChecklistScreen> createState() => _HiringChecklistScreenState();
}

class _HiringChecklistScreenState extends State<HiringChecklistScreen> {
  // 각 동의 항목의 체크 상태 (9개)
  final List<bool> _checked = List.generate(_consentItems.length, (_) => false);
  
  // 날짜 (기본: 오늘)
  late DateTime _signDate;

  // 서명 컨트롤러
  final SignatureController _sigController = SignatureController(
    penStrokeWidth: 3,
    penColor: Colors.black,
    exportBackgroundColor: Colors.white,
  );

  bool _isSaving = false;
  Uint8List? _savedSignatureBytes;

  @override
  void initState() {
    super.initState();
    _signDate = DateTime.now();

    // 저장된 데이터 로드
    if (widget.document.dataJson != null) {
      try {
        final Map<String, dynamic> data = jsonDecode(widget.document.dataJson!);
        if (data['checked'] != null && data['checked'] is List) {
          final List<dynamic> savedChecked = data['checked'];
          for (int i = 0; i < _checked.length && i < savedChecked.length; i++) {
            _checked[i] = savedChecked[i] as bool;
          }
        }
        if (data['signatureBase64'] != null) {
          _savedSignatureBytes = base64Decode(data['signatureBase64']);
        }
      } catch (e) {
        debugPrint('Failed to load checklist data: $e');
      }
    }

    // 이미 완료된 문서인데 체크가 누락되어 있다면 구버전 데이터 지원을 위해 모두 활성화
    if (widget.document.status == 'completed') {
      for (int i = 0; i < _checked.length; i++) {
        _checked[i] = true;
      }
    }
  }

  @override
  void dispose() {
    _sigController.dispose();
    super.dispose();
  }

  Future<void> _saveStatus() async {
    try {
      String? sigBase64;
      if (_sigController.isNotEmpty) {
        final sigBytes = await _sigController.toPngBytes();
        if (sigBytes != null) {
          sigBase64 = base64Encode(sigBytes);
        }
      } else if (_savedSignatureBytes != null) {
        sigBase64 = base64Encode(_savedSignatureBytes!);
      }

      final data = {
        'checked': _checked,
        'signDate': _signDate.toIso8601String(),
        'signatureBase64': ?sigBase64,
      };

      await FirebaseFirestore.instance
          .collection('stores')
          .doc(widget.document.storeId)
          .collection('documents')
          .doc(widget.document.id)
          .set({
        ...widget.document.toMap(),
        'status': 'completed',
        'dataJson': jsonEncode(data),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Failed to save document status: $e');
    }
  }

  bool get _allChecked => _checked.every((c) => c);

  Future<void> _savePdf() async {
    if (!_allChecked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('모든 확인/동의 항목을 체크해 주세요.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (_sigController.isEmpty && _savedSignatureBytes == null && widget.document.status != 'completed') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('하단 서명란에 서명해 주세요.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      await _saveStatus();
      final signatureBytes = _sigController.isNotEmpty 
          ? await _sigController.toPngBytes()
          : _savedSignatureBytes;
      final pdfBytes = await _generateChecklistPdf(signatureBytes);

      await Printing.sharePdf(
        bytes: pdfBytes,
        filename: '채용체크리스트_${widget.worker.name}.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF 생성 오류: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<Uint8List> _generateChecklistPdf(Uint8List? signatureBytes) async {
    final font = await PdfGoogleFonts.nanumGothicRegular();
    final boldFont = await PdfGoogleFonts.nanumGothicBold();

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(base: font, bold: boldFont),
    );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (ctx) => [
          // 제목
          pw.Center(
            child: pw.Text('채 용 체 크 리 스 트',
              style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
          ),
          pw.SizedBox(height: 24),

          // 1. 채용 구비서류
          pw.Text('1. 채용 구비서류',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.Table(
            border: pw.TableBorder.all(),
            columnWidths: {
              0: const pw.FixedColumnWidth(30),
              1: const pw.FlexColumnWidth(2),
              2: const pw.FlexColumnWidth(1.5),
              3: const pw.FlexColumnWidth(2.5),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                children: ['No.', '서  류  명', '발 급 처', '기타사항']
                    .map((h) => pw.Padding(
                          padding: const pw.EdgeInsets.all(5),
                          child: pw.Center(
                            child: pw.Text(h,
                                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                          ),
                        ))
                    .toList(),
              ),
              ..._requiredDocs.map((doc) => pw.TableRow(
                    children: [
                      _pdfCell(doc['no']!, bold: true),
                      _pdfCell(doc['name']!, bold: true),
                      _pdfCell(doc['issuer']!),
                      _pdfCell(doc['note']!),
                    ],
                  )),
            ],
          ),
          pw.SizedBox(height: 20),

          // 2. 확인/동의서
          pw.Text('2. 확인 / 동의서',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.Table(
            border: pw.TableBorder.all(),
            columnWidths: {
              0: const pw.FixedColumnWidth(28),
              1: const pw.FlexColumnWidth(4),
              2: const pw.FixedColumnWidth(55),
              3: const pw.FixedColumnWidth(55),
            },
            children: [
              // 헤더
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                children: [
                  _pdfCell('No.', bold: true),
                  _pdfCell('리 스 트', bold: true),
                  _pdfCell('사용자\n서명', bold: true, center: true),
                  _pdfCell('근로자\n서명', bold: true, center: true),
                ],
              ),
              // 동의 항목 rows
              ..._consentItems.asMap().entries.map((e) => pw.TableRow(
                    children: [
                      _pdfCell('${e.key + 1}', bold: true, center: true),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(5),
                        child: pw.Text(e.value, style: pw.TextStyle(fontSize: 9)),
                      ),
                      // 사용자 서명 - 체크 표시
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Center(
                          child: pw.Text(
                            _checked[e.key] ? '✔' : '',
                            style: pw.TextStyle(fontSize: 14, color: PdfColors.blue900),
                          ),
                        ),
                      ),
                      // 근로자 서명 (마지막 항목에만 서명 이미지)
                      e.key == _consentItems.length - 1 && signatureBytes != null
                          ? pw.Padding(
                              padding: const pw.EdgeInsets.all(2),
                              child: pw.Image(pw.MemoryImage(signatureBytes), width: 40, height: 30),
                            )
                          : pw.SizedBox(height: 30),
                    ],
                  )),
            ],
          ),
          pw.SizedBox(height: 20),

          // 날짜 및 서명
          pw.Center(
            child: pw.Text(
              '${_signDate.year} 년   ${_signDate.month} 월   ${_signDate.day} 일',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12),
            ),
          ),
          pw.SizedBox(height: 16),
          if (signatureBytes != null)
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                pw.Text('근로자 서명: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                pw.Image(pw.MemoryImage(signatureBytes), width: 80, height: 40),
              ],
            ),
        ],
      ),
    );

    return pdf.save();
  }

  static pw.Widget _pdfCell(String text, {bool bold = false, bool center = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(5),
      child: center
          ? pw.Center(
              child: pw.Text(text,
                  style: pw.TextStyle(fontSize: 9, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
            )
          : pw.Text(text,
              style: pw.TextStyle(fontSize: 9, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: const Text('채용 체크리스트'),
        backgroundColor: const Color(0xFF1A1A2E),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Text(
                '${_checked.where((c) => c).length}/${_consentItems.length} 완료',
                style: const TextStyle(fontSize: 13, color: Colors.white70),
              ),
            ),
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.document.status == 'completed')
              Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF3DE),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF286b3a).withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.check_circle_outline, size: 48, color: Color(0xFF286b3a)),
                      const SizedBox(height: 12),
                      const Text('작성 완료된 서류입니다.', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: FilledButton.icon(
                          onPressed: _isSaving ? null : _savePdf,
                          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF286b3a)),
                          icon: const Icon(Icons.picture_as_pdf),
                          label: const Text('PDF 서류 발급 / 공유하기', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            // ── Section 1: 채용 구비서류 ──────────────────────────────
            _sectionTitle('1. 채용 구비서류'),
            const SizedBox(height: 8),
            _buildRequiredDocsTable(),
            const SizedBox(height: 24),

            // ── Section 2: 확인/동의서 ───────────────────────────────
            _sectionTitle('2. 확인 / 동의서'),
            const SizedBox(height: 4),
            const Text(
              '각 항목을 읽고 터치하여 확인하세요.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            _buildConsentList(),
            const SizedBox(height: 24),

            // ── 서명란 ────────────────────────────────────────────────
            if (_allChecked) ...[
              _sectionTitle('3. 최종 서명'),
              const SizedBox(height: 8),
              Text(
                '${_signDate.year}년 ${_signDate.month}월 ${_signDate.day}일',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF1A1A2E), width: 1.5),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2)),
                  ],
                ),
                clipBehavior: Clip.hardEdge,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      color: const Color(0xFF1A1A2E),
                      child: const Text(
                        '근로자 서명',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                    if (_savedSignatureBytes != null)
                      Container(
                        height: 180,
                        color: Colors.white,
                        width: double.infinity,
                        alignment: Alignment.center,
                        child: Image.memory(_savedSignatureBytes!),
                      )
                    else
                      Signature(
                        controller: _sigController,
                        height: 180,
                        backgroundColor: Colors.white,
                      ),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (_savedSignatureBytes != null)
                            TextButton.icon(
                              onPressed: () => setState(() => _savedSignatureBytes = null),
                              icon: const Icon(Icons.edit, size: 16),
                              label: const Text('다시 서명하기'),
                              style: TextButton.styleFrom(foregroundColor: Colors.blue),
                            )
                          else
                            TextButton.icon(
                              onPressed: _sigController.clear,
                              icon: const Icon(Icons.refresh, size: 16),
                              label: const Text('초기화'),
                              style: TextButton.styleFrom(foregroundColor: Colors.grey),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '서명 시 날짜·기기 정보가 함께 기록됩니다.',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
              const SizedBox(height: 32),

              // PDF 저장 버튼
              if (!widget.isWizardMode)
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton.icon(
                    onPressed: _isSaving ? null : _savePdf,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Icon(Icons.picture_as_pdf_outlined),
                    label: Text(_isSaving ? '저장 중...' : 'PDF로 저장 & 공유'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A1A2E),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              const SizedBox(height: 30),
            ] else ...[
              // 아직 미완료 상태일 때 안내
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange.shade700),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        '모든 확인/동의 항목을 체크하면 서명란이 활성화됩니다.',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
            ],
            
            if (widget.isWizardMode && widget.onNext != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: () async {
                    if (_allChecked && (_sigController.isNotEmpty || _savedSignatureBytes != null)) {
                      await _saveStatus();
                    }
                    if (widget.onNext != null) widget.onNext!();
                  },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1a6ebd),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text(widget.nextButtonLabel ?? '다음 서류 작성하기', 
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 60),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E)),
    );
  }

  Widget _buildRequiredDocsTable() {
    const headerStyle = TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white);
    const cellStyle = TextStyle(fontSize: 11);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6)],
      ),
      clipBehavior: Clip.hardEdge,
      child: Table(
        border: TableBorder.all(color: Colors.grey.shade200),
        columnWidths: const {
          0: FixedColumnWidth(32),
          1: FlexColumnWidth(2),
          2: FlexColumnWidth(1.5),
          3: FlexColumnWidth(2.5),
        },
        children: [
          // 헤더
          TableRow(
            decoration: const BoxDecoration(color: Color(0xFF2C2C54)),
            children: ['No.', '서 류 명', '발 급 처', '기 타 사 항']
                .map((h) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                      child: Text(h, style: headerStyle, textAlign: TextAlign.center),
                    ))
                .toList(),
          ),
          // 데이터
          ..._requiredDocs.asMap().entries.map((e) => TableRow(
                decoration: BoxDecoration(
                  color: e.key.isEven ? Colors.white : const Color(0xFFF8F8FB),
                ),
                children: [
                  _tableCell(e.value['no']!, bold: true, center: true),
                  _tableCell(e.value['name']!, bold: true),
                  _tableCell(e.value['issuer']!, center: true),
                  _tableCell(e.value['note']!, style: cellStyle.copyWith(fontSize: 10, color: Colors.grey.shade700)),
                ],
              )),
        ],
      ),
    );
  }

  Widget _tableCell(String text, {bool bold = false, bool center = false, TextStyle? style}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      child: Text(
        text,
        textAlign: center ? TextAlign.center : TextAlign.left,
        style: style ?? TextStyle(fontSize: 11, fontWeight: bold ? FontWeight.bold : FontWeight.normal),
      ),
    );
  }

  Widget _buildConsentList() {
    return Column(
      children: _consentItems.asMap().entries.map((e) {
        final index = e.key;
        final text = e.value;
        final isChecked = _checked[index];

        return GestureDetector(
          onTap: () => setState(() => _checked[index] = !_checked[index]),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isChecked ? const Color(0xFFEAF3DE) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isChecked ? const Color(0xFF286b3a) : Colors.grey.shade300,
                width: isChecked ? 1.5 : 1,
              ),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4, offset: const Offset(0, 2)),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 번호 배지
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: isChecked ? const Color(0xFF286b3a) : const Color(0xFF1A1A2E),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Center(
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // 내용
                Expanded(
                  child: Text(
                    text,
                    style: TextStyle(
                      fontSize: 13,
                      color: isChecked ? const Color(0xFF1B4332) : Colors.black87,
                      height: 1.5,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // 체크 아이콘
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: isChecked
                      ? const Icon(Icons.check_circle, color: Color(0xFF286b3a), size: 24, key: ValueKey('checked'))
                      : Icon(Icons.radio_button_unchecked, color: Colors.grey.shade400, size: 24, key: const ValueKey('unchecked')),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
