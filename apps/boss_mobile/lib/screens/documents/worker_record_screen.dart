import 'dart:typed_data';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_logic/shared_logic.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../models/worker.dart';
import '../../models/store_info.dart';

class WorkerRecordScreen extends StatefulWidget {
  final Worker worker;
  final LaborDocument document;

  final VoidCallback? onNext;
  final String? nextButtonLabel;
  final bool isWizardMode;
    
  const WorkerRecordScreen({
    super.key,
    required this.worker,
    required this.document,
    this.onNext,
    this.nextButtonLabel,
    this.isWizardMode = false,
  });

  @override
  State<WorkerRecordScreen> createState() => _WorkerRecordScreenState();
}

class _WorkerRecordScreenState extends State<WorkerRecordScreen> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _birthCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _dependentsCtrl;
  late final TextEditingController _jobDutyCtrl;
  late final TextEditingController _skillCtrl;
  late final TextEditingController _educationCtrl;
  late final TextEditingController _careerCtrl;
  late final TextEditingController _militaryCtrl;
  late final TextEditingController _dismissDateCtrl;
  late final TextEditingController _retireDateCtrl;
  late final TextEditingController _reasonCtrl;
  late final TextEditingController _settlementCtrl;
  late final TextEditingController _hireDateCtrl;
  late final TextEditingController _renewDateCtrl;
  late final TextEditingController _contractConditionCtrl;
  late final TextEditingController _specialNoteCtrl;

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final w = widget.worker;

    // StoreInfo 로드
    final store = Hive.box<StoreInfo>('store').get('current');
    final storeName = store?.storeName ?? '';

    // 임금 조건 자동 구성
    final dayNames = ['일', '월', '화', '수', '목', '금', '토'];
    final workDayStr = w.workDays.map((d) => dayNames[d % 7]).join(', ');
    final contractCondition =
        '시급: ${w.hourlyWage.toInt()}원\n'
        '근무요일: $workDayStr\n'
        '근무시간: ${w.checkInTime} ~ ${w.checkOutTime}\n'
        '휴게시간: ${w.breakMinutes.toInt()}분';

    _nameCtrl = TextEditingController(text: w.name);
    _birthCtrl = TextEditingController(text: w.birthDate);
    _addressCtrl = TextEditingController(text: '');
    _phoneCtrl = TextEditingController(text: w.phone);
    _dependentsCtrl = TextEditingController();
    _jobDutyCtrl = TextEditingController(text: '판매 및 기타업무');
    _skillCtrl = TextEditingController();
    _educationCtrl = TextEditingController();
    _careerCtrl = TextEditingController();
    _militaryCtrl = TextEditingController();
    _dismissDateCtrl = TextEditingController();
    _retireDateCtrl = TextEditingController(text: w.endDate ?? '');
    _reasonCtrl = TextEditingController();
    _settlementCtrl = TextEditingController();
    _hireDateCtrl = TextEditingController(text: w.startDate);
    _renewDateCtrl = TextEditingController();
    _contractConditionCtrl = TextEditingController(text: contractCondition);
    _specialNoteCtrl = TextEditingController();

    // 저장된 데이터 로드
    if (widget.document.dataJson != null) {
      try {
        final data = jsonDecode(widget.document.dataJson!) as Map<String, dynamic>;
        _nameCtrl.text = data['name'] ?? _nameCtrl.text;
        _birthCtrl.text = data['birth'] ?? _birthCtrl.text;
        _addressCtrl.text = data['address'] ?? _addressCtrl.text;
        _phoneCtrl.text = data['phone'] ?? _phoneCtrl.text;
        _dependentsCtrl.text = data['dependents'] ?? '';
        _jobDutyCtrl.text = data['jobDuty'] ?? _jobDutyCtrl.text;
        _skillCtrl.text = data['skill'] ?? '';
        _educationCtrl.text = data['education'] ?? '';
        _careerCtrl.text = data['career'] ?? '';
        _militaryCtrl.text = data['military'] ?? '';
        _dismissDateCtrl.text = data['dismissDate'] ?? '';
        _retireDateCtrl.text = data['retireDate'] ?? _retireDateCtrl.text;
        _reasonCtrl.text = data['reason'] ?? '';
        _settlementCtrl.text = data['settlement'] ?? '';
        _hireDateCtrl.text = data['hireDate'] ?? _hireDateCtrl.text;
        _renewDateCtrl.text = data['renewDate'] ?? '';
        _contractConditionCtrl.text = data['contractCondition'] ?? _contractConditionCtrl.text;
        _specialNoteCtrl.text = data['specialNote'] ?? '';
      } catch (e) {
        debugPrint('Failed to load worker record data: $e');
      }
    }
  }

  @override
  void dispose() {
    for (final c in [
      _nameCtrl, _birthCtrl, _addressCtrl, _phoneCtrl, _dependentsCtrl,
      _jobDutyCtrl, _skillCtrl, _educationCtrl, _careerCtrl, _militaryCtrl,
      _dismissDateCtrl, _retireDateCtrl, _reasonCtrl, _settlementCtrl,
      _hireDateCtrl, _renewDateCtrl, _contractConditionCtrl, _specialNoteCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _saveStatus() async {
    try {
      final data = {
        'name': _nameCtrl.text,
        'birth': _birthCtrl.text,
        'address': _addressCtrl.text,
        'phone': _phoneCtrl.text,
        'dependents': _dependentsCtrl.text,
        'jobDuty': _jobDutyCtrl.text,
        'skill': _skillCtrl.text,
        'education': _educationCtrl.text,
        'career': _careerCtrl.text,
        'military': _militaryCtrl.text,
        'dismissDate': _dismissDateCtrl.text,
        'retireDate': _retireDateCtrl.text,
        'reason': _reasonCtrl.text,
        'settlement': _settlementCtrl.text,
        'hireDate': _hireDateCtrl.text,
        'renewDate': _renewDateCtrl.text,
        'contractCondition': _contractConditionCtrl.text,
        'specialNote': _specialNoteCtrl.text,
      };

      final newDataJson = jsonEncode(data);
      final newHash = SecurityMetadataHelper.generateDocumentHash(
        type: widget.document.type.name,
        staffId: widget.document.staffId,
        content: widget.document.content,
        dataJson: newDataJson,
        createdAt: widget.document.createdAt.toIso8601String(),
      );

      await FirebaseFirestore.instance
          .collection('stores')
          .doc(widget.document.storeId)
          .collection('documents')
          .doc(widget.document.id)
          .set({
        ...widget.document.toMap(),
        'status': 'completed',
        'dataJson': newDataJson,
        'documentHash': newHash,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Failed to save document status: $e');
    }
  }

  Future<void> _generatePdf() async {
    setState(() => _isSaving = true);
    try {
      await _saveStatus();
      final bytes = await _buildPdf();
      await Printing.sharePdf(
        bytes: bytes,
        filename: '근로자명부_${_nameCtrl.text}.pdf',
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

  Future<Uint8List> _buildPdf() async {
    final font = await PdfGoogleFonts.nanumGothicRegular();
    final bold = await PdfGoogleFonts.nanumGothicBold();

    // StoreInfo 로드 (PDF 렌더링에 사용)
    final store = Hive.box<StoreInfo>('store').get('current');
    final storeName = store?.storeName ?? '';
    final ownerName = store?.ownerName ?? '';

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(base: font, bold: bold),
    );

    pw.Widget cell(String text, {bool isBold = false, bool center = false, double fontSize = 9}) {
      final widget = pw.Text(
        text,
        style: pw.TextStyle(fontSize: fontSize, fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal),
        textAlign: center ? pw.TextAlign.center : pw.TextAlign.left,
      );
      return pw.Padding(padding: const pw.EdgeInsets.all(4), child: center ? pw.Center(child: widget) : widget);
    }

    pw.Widget labelCell(String text) => cell(text, isBold: true, center: true);
    pw.Widget valueCell(String text) => cell(text);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('[고용노동부 서식]', style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
            pw.SizedBox(height: 4),
            pw.Container(
              width: double.infinity,
              decoration: pw.BoxDecoration(border: pw.Border.all()),
              child: pw.Column(
                children: [
                  // 사업장 정보
                  if (storeName.isNotEmpty)
                    pw.Container(
                      width: double.infinity,
                      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(bottom: pw.BorderSide()),
                        color: PdfColor(0.96, 0.96, 0.98),
                      ),
                      child: pw.Row(
                        children: [
                          pw.Text('사업장: ', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                          pw.Text(storeName, style: pw.TextStyle(fontSize: 9)),
                          pw.SizedBox(width: 20),
                          if (ownerName.isNotEmpty) ...[
                            pw.Text('대표자: ', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                            pw.Text(ownerName, style: pw.TextStyle(fontSize: 9)),
                          ],
                        ],
                      ),
                    ),

                  // 제목
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.symmetric(vertical: 8),
                    child: pw.Center(
                      child: pw.Text('근로자 명부',
                          style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
                    ),
                  ),


                  // ①성명 / ②생년월일
                  pw.Table(
                    border: pw.TableBorder.all(),
                    columnWidths: {
                      0: const pw.FixedColumnWidth(55),
                      1: const pw.FlexColumnWidth(1),
                      2: const pw.FixedColumnWidth(60),
                      3: const pw.FlexColumnWidth(1),
                    },
                    children: [
                      pw.TableRow(children: [
                        labelCell('①성명'),
                        valueCell(_nameCtrl.text),
                        labelCell('②생년월일'),
                        valueCell(_birthCtrl.text),
                      ]),
                    ],
                  ),

                  // ③주소
                  pw.Table(
                    border: pw.TableBorder.all(),
                    columnWidths: {
                      0: const pw.FixedColumnWidth(55),
                      1: const pw.FlexColumnWidth(2),
                      2: const pw.FixedColumnWidth(90),
                    },
                    children: [
                      pw.TableRow(children: [
                        labelCell('③주소'),
                        valueCell(_addressCtrl.text),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(4),
                          child: pw.Text('(전화 : ${_phoneCtrl.text})', style: pw.TextStyle(fontSize: 9)),
                        ),
                      ]),
                    ],
                  ),

                  // ④부양가족 / ⑤종사업무
                  pw.Table(
                    border: pw.TableBorder.all(),
                    columnWidths: {
                      0: const pw.FixedColumnWidth(55),
                      1: const pw.FixedColumnWidth(60),
                      2: const pw.FixedColumnWidth(65),
                      3: const pw.FlexColumnWidth(1),
                    },
                    children: [
                      pw.TableRow(children: [
                        labelCell('④부양가족'),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(4),
                          child: pw.Text('${_dependentsCtrl.text} 명', style: pw.TextStyle(fontSize: 9)),
                        ),
                        labelCell('⑤종 사 업 무'),
                        valueCell(_jobDutyCtrl.text),
                      ]),
                    ],
                  ),

                  // 이력 + 퇴직 합성 테이블
                  pw.Table(
                    border: pw.TableBorder.all(),
                    columnWidths: {
                      0: const pw.FixedColumnWidth(28),
                      1: const pw.FixedColumnWidth(60),
                      2: const pw.FlexColumnWidth(1),
                      3: const pw.FixedColumnWidth(28),
                      4: const pw.FixedColumnWidth(65),
                      5: const pw.FlexColumnWidth(1),
                    },
                    children: [
                      pw.TableRow(children: [
                        _rotatedLabel('이\n력'),
                        labelCell('⑥기능 및 자격'),
                        valueCell(_skillCtrl.text),
                        _rotatedLabel('퇴\n직'),
                        labelCell('⑩해고일'),
                        pw.Padding(padding: const pw.EdgeInsets.all(4),
                          child: pw.Text(_dismissDateCtrl.text.isEmpty ? '        년    월    일' : _dismissDateCtrl.text, style: pw.TextStyle(fontSize: 9))),
                      ]),
                      pw.TableRow(children: [
                        pw.SizedBox(),
                        labelCell('⑦최종 학력'),
                        valueCell(_educationCtrl.text),
                        pw.SizedBox(),
                        labelCell('⑪퇴직일'),
                        pw.Padding(padding: const pw.EdgeInsets.all(4),
                          child: pw.Text(_retireDateCtrl.text.isEmpty ? '        년    월    일' : _retireDateCtrl.text, style: pw.TextStyle(fontSize: 9))),
                      ]),
                      pw.TableRow(children: [
                        pw.SizedBox(),
                        labelCell('⑧경력'),
                        valueCell(_careerCtrl.text),
                        pw.SizedBox(),
                        labelCell('⑫사 유'),
                        valueCell(_reasonCtrl.text),
                      ]),
                      pw.TableRow(children: [
                        pw.SizedBox(),
                        labelCell('⑨병역'),
                        valueCell(_militaryCtrl.text),
                        pw.SizedBox(),
                        labelCell('⑬금품청산 등'),
                        valueCell(_settlementCtrl.text),
                      ]),
                    ],
                  ),

                  // ⑭고용일 / ⑮근로계약갱신일
                  pw.Table(
                    border: pw.TableBorder.all(),
                    columnWidths: {
                      0: const pw.FixedColumnWidth(90),
                      1: const pw.FlexColumnWidth(1),
                      2: const pw.FixedColumnWidth(85),
                      3: const pw.FlexColumnWidth(1),
                    },
                    children: [
                      pw.TableRow(children: [
                        labelCell('⑭고용일(계약기간)'),
                        pw.Padding(padding: const pw.EdgeInsets.all(4),
                          child: pw.Text('${_hireDateCtrl.text}  (    )', style: pw.TextStyle(fontSize: 9))),
                        labelCell('⑮근로계약갱신일'),
                        pw.Padding(padding: const pw.EdgeInsets.all(4),
                          child: pw.Text(_renewDateCtrl.text.isEmpty ? '     년    월    일' : _renewDateCtrl.text, style: pw.TextStyle(fontSize: 9))),
                      ]),
                    ],
                  ),

                  // ⑯근로계약조건
                  pw.Table(
                    border: pw.TableBorder.all(),
                    columnWidths: {
                      0: const pw.FixedColumnWidth(28),
                      1: const pw.FlexColumnWidth(1),
                    },
                    children: [
                      pw.TableRow(
                        children: [
                          pw.Container(
                            height: 90,
                            child: pw.Center(
                              child: pw.Text('<16>\n근로\n계약\n조건',
                                  style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
                                  textAlign: pw.TextAlign.center),
                            ),
                          ),
                          pw.Container(
                            height: 90,
                            padding: const pw.EdgeInsets.all(6),
                            child: pw.Text(_contractConditionCtrl.text, style: pw.TextStyle(fontSize: 9)),
                          ),
                        ],
                      ),
                    ],
                  ),

                  // ⑰특기사항
                  pw.Table(
                    border: pw.TableBorder.all(),
                    columnWidths: {
                      0: const pw.FlexColumnWidth(1),
                    },
                    children: [
                      pw.TableRow(
                        children: [
                          pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Padding(
                                padding: const pw.EdgeInsets.all(5),
                                child: pw.Text('<17>특기사항(교육, 건강, 휴직등)',
                                    style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                              ),
                              pw.Container(
                                height: 80,
                                padding: const pw.EdgeInsets.all(6),
                                child: pw.Text(_specialNoteCtrl.text, style: pw.TextStyle(fontSize: 9)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return pdf.save();
  }

  static pw.Widget _rotatedLabel(String text) {
    return pw.Container(
      width: 28,
      child: pw.Center(
        child: pw.Text(text,
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            textAlign: pw.TextAlign.center),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: const Text('근로자 명부'),
        backgroundColor: const Color(0xFF1A1A2E),
        foregroundColor: Colors.white,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton.icon(
              onPressed: _isSaving ? null : _generatePdf,
              icon: _isSaving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.picture_as_pdf_outlined, color: Colors.white),
              label: const Text('PDF', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
                          onPressed: _isSaving ? null : _generatePdf,
                          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF286b3a)),
                          icon: const Icon(Icons.picture_as_pdf),
                          label: const Text('PDF 서류 발급 / 공유하기', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            _sectionBadge('고용노동부 서식'),
            const SizedBox(height: 12),
            _sectionCard('기본 정보', [
              _field('① 성명', _nameCtrl),
              _field('② 생년월일', _birthCtrl, hint: 'YYYY-MM-DD'),
              _field('③ 주소', _addressCtrl),
              _field('   전화', _phoneCtrl),
              _field('④ 부양가족 수', _dependentsCtrl, hint: '명', keyboardType: TextInputType.number),
              _field('⑤ 종사업무', _jobDutyCtrl),
            ]),
            const SizedBox(height: 16),

            _sectionCard('이력', [
              _field('⑥ 기능 및 자격', _skillCtrl),
              _field('⑦ 최종 학력', _educationCtrl),
              _field('⑧ 경력', _careerCtrl),
              _field('⑨ 병역', _militaryCtrl),
            ]),
            const SizedBox(height: 16),

            _sectionCard('퇴직 정보', [
              _field('⑩ 해고일', _dismissDateCtrl, hint: 'YYYY-MM-DD'),
              _field('⑪ 퇴직일', _retireDateCtrl, hint: 'YYYY-MM-DD'),
              _field('⑫ 사유', _reasonCtrl),
              _field('⑬ 금품청산 등', _settlementCtrl),
            ]),
            const SizedBox(height: 16),

            _sectionCard('계약 정보', [
              _field('⑭ 고용일 (계약기간)', _hireDateCtrl, hint: 'YYYY-MM-DD'),
              _field('⑮ 근로계약 갱신일', _renewDateCtrl, hint: 'YYYY-MM-DD'),
            ]),
            const SizedBox(height: 16),

            _sectionCard('⑯ 근로계약 조건', [
              _multilineField(_contractConditionCtrl, minLines: 5),
            ]),
            const SizedBox(height: 16),

            _sectionCard('⑰ 특기사항 (교육, 건강, 휴직 등)', [
              _multilineField(_specialNoteCtrl, minLines: 5),
            ]),
            const SizedBox(height: 32),

            if (!widget.isWizardMode)
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _generatePdf,
                  icon: _isSaving
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.picture_as_pdf_outlined),
                  label: Text(_isSaving ? '생성 중...' : 'PDF로 저장 & 공유'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A1A2E),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            const SizedBox(height: 30),
            
            if (widget.isWizardMode && widget.onNext != null)
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () async {
                    await _saveStatus();
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
            const SizedBox(height: 16),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 60),
          ],
        ),
      ),
    );
  }

  Widget _sectionBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF2C2C54),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  Widget _sectionCard(String title, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1A1A2E))),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl,
      {String? hint, TextInputType keyboardType = TextInputType.text}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: ctrl,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          filled: true,
          fillColor: const Color(0xFFF7F7FA),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFF1A1A2E), width: 1.5),
          ),
          labelStyle: const TextStyle(fontSize: 13, color: Colors.grey),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      ),
    );
  }

  Widget _multilineField(TextEditingController ctrl, {int minLines = 4}) {
    return TextField(
      controller: ctrl,
      minLines: minLines,
      maxLines: null,
      decoration: InputDecoration(
        filled: true,
        fillColor: const Color(0xFFF7F7FA),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF1A1A2E), width: 1.5),
        ),
        contentPadding: const EdgeInsets.all(14),
      ),
    );
  }
}
