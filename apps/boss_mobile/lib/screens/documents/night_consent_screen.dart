import 'dart:typed_data';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:signature/signature.dart';
import 'package:shared_logic/shared_logic.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../models/worker.dart';
import '../../models/store_info.dart';

class NightConsentScreen extends StatefulWidget {
  final Worker worker;
  final LaborDocument document;

  final VoidCallback? onNext;
  final String? nextButtonLabel;
  final bool isWizardMode;

  const NightConsentScreen({
    super.key,
    required this.worker,
    required this.document,
    this.onNext,
    this.nextButtonLabel,
    this.isWizardMode = false,
  });

  @override
  State<NightConsentScreen> createState() => _NightConsentScreenState();
}

class _NightConsentScreenState extends State<NightConsentScreen> {
  // 근로자 인적사항
  late final TextEditingController _nameCtrl;
  late final TextEditingController _ageCtrl;
  late final TextEditingController _birthDateCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _phoneCtrl;

  // 근로자 유형 체크박스
  bool _isWoman = false;
  bool _isMinor = false;
  bool _isPregnant = false;
  bool _isPregnantNow = false;
  bool _isPostPartum = false;

  // 고용 형태 체크박스 (중복 선택 가능)
  bool _isRegular = false;
  bool _isIrregular = false;
  bool _isPartTime = true; // 기본: 파트타임 선택
  bool _isOther = false;
  final TextEditingController _otherJobTypeCtrl = TextEditingController();

  // 점포명 (StoreInfo에서 자동 로드)
  late String _storeName;
  late String _ownerName;
  late String _storeAddress;
  late String _storePhone;

  // 서명
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
    final w = widget.worker;

    // StoreInfo 로드
    final store = Hive.box<StoreInfo>('store').get('current');
    _storeName = store?.storeName ?? '';
    _ownerName = store?.ownerName ?? '';
    _storeAddress = store?.address ?? '';
    _storePhone = store?.phone ?? '';

    // 나이 계산
    int age = 0;
    try {
      final birth = DateTime.parse(w.birthDate.replaceAll('.', '-').replaceAll('/', '-'));
      age = DateTime.now().year - birth.year;
    } catch (_) {}

    _nameCtrl = TextEditingController(text: w.name);
    _ageCtrl = TextEditingController(text: age > 0 ? '$age' : '');
    _birthDateCtrl = TextEditingController(text: w.birthDate);
    _addressCtrl = TextEditingController();
    _phoneCtrl = TextEditingController(text: w.phone);

    // 미성년자 자동 체크
    if (age > 0 && age < 18) _isMinor = true;

    // 저장된 데이터 로드
    if (widget.document.dataJson != null) {
      try {
        final data = jsonDecode(widget.document.dataJson!) as Map<String, dynamic>;
        _nameCtrl.text = data['name'] ?? _nameCtrl.text;
        _ageCtrl.text = data['age'] ?? _ageCtrl.text;
        _birthDateCtrl.text = data['birthDate'] ?? w.birthDate;
        _addressCtrl.text = data['address'] ?? '';
        _phoneCtrl.text = data['phone'] ?? _phoneCtrl.text;

        _isWoman = data['isWoman'] ?? _isWoman;
        _isMinor = data['isMinor'] ?? _isMinor;
        _isPregnant = data['isPregnant'] ?? _isPregnant;
        _isPregnantNow = data['isPregnantNow'] ?? _isPostPartum;
        _isPostPartum = data['isPostPartum'] ?? _isPostPartum;

        _isRegular = data['isRegular'] ?? _isRegular;
        _isIrregular = data['isIrregular'] ?? _isIrregular;
        _isPartTime = data['isPartTime'] ?? _isPartTime;
        _isOther = data['isOther'] ?? _isOther;
        _otherJobTypeCtrl.text = data['otherJobType'] ?? '';

        if (data['signatureBase64'] != null) {
          _savedSignatureBytes = base64Decode(data['signatureBase64']);
        }
      } catch (e) {
        debugPrint('Failed to load night consent data: $e');
      }
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _ageCtrl.dispose();
    _birthDateCtrl.dispose();
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    _otherJobTypeCtrl.dispose();
    _sigController.dispose();
    super.dispose();
  }

  Future<void> _saveStatus() async {
    try {
      final data = {
        'name': _nameCtrl.text,
        'age': _ageCtrl.text,
        'birthDate': _birthDateCtrl.text,
        'address': _addressCtrl.text,
        'phone': _phoneCtrl.text,
        'isWoman': _isWoman,
        'isMinor': _isMinor,
        'isPregnant': _isPregnant,
        'isPregnantNow': _isPregnantNow,
        'isPostPartum': _isPostPartum,
        'isRegular': _isRegular,
        'isIrregular': _isIrregular,
        'isPartTime': _isPartTime,
        'isOther': _isOther,
        'otherJobType': _otherJobTypeCtrl.text,
      };

      String? sigBase64;
      if (_sigController.isNotEmpty) {
        final sigBytes = await _sigController.toPngBytes();
        if (sigBytes != null) sigBase64 = base64Encode(sigBytes);
      } else if (_savedSignatureBytes != null) {
        sigBase64 = base64Encode(_savedSignatureBytes!);
      }
      if (sigBase64 != null) {
        data['signatureBase64'] = sigBase64;
      }

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
        'status': 'boss_signed',
        'dataJson': newDataJson,
        'documentHash': newHash,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Failed to save document status: $e');
    }
  }

  Future<void> _generatePdf() async {
    if (_sigController.isEmpty && _savedSignatureBytes == null && 
        widget.document.status != 'completed' && widget.document.status != 'boss_signed') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('하단 서명란에 서명해 주세요.'), backgroundColor: Colors.red),
      );
      return;
    }
    setState(() => _isSaving = true);
    try {
      await _saveStatus();
      final sigBytes = _sigController.isNotEmpty ? await _sigController.toPngBytes() : _savedSignatureBytes;
      final bytes = await _buildPdf(sigBytes);
      await Printing.sharePdf(bytes: bytes, filename: '휴일및야간근로동의서_${_nameCtrl.text}.pdf');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PDF 오류: $e')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<Uint8List> _buildPdf(Uint8List? sigBytes) async {
    final font = await PdfGoogleFonts.nanumGothicRegular();
    final bold = await PdfGoogleFonts.nanumGothicBold();

    final pdf = pw.Document(theme: pw.ThemeData.withFont(base: font, bold: bold));

    final now = DateTime.now();

    String jobType = '';
    final types = <String>[];
    if (_isRegular) types.add('정규직');
    if (_isIrregular) types.add('비정규직(단시간근로자, 파견근로자)');
    if (_isPartTime) types.add('파트타임 아르바이트');
    if (_isOther && _otherJobTypeCtrl.text.isNotEmpty) types.add('기타: ${_otherJobTypeCtrl.text}');
    jobType = types.join(', ');

    pw.Widget checkRow(bool checked, String label, {double fontSize = 11}) {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(checked ? '■' : '□', style: pw.TextStyle(fontSize: fontSize, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(width: 6),
            pw.Text(label, style: pw.TextStyle(fontSize: fontSize)),
          ],
        ),
      );
    }

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 50, vertical: 40),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // 제목
            pw.Center(
              child: pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: pw.BoxDecoration(border: pw.Border.all(width: 1.5)),
                child: pw.Text('휴일 및 야간근로 동의서',
                    style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
              ),
            ),
            pw.SizedBox(height: 24),

            // 근로자 인적사항
            pw.Text('○ 근로자 인적사항', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
            pw.SizedBox(height: 10),
            _pdfInfoLine('성          명', '${_nameCtrl.text}   (만 ${_ageCtrl.text} 세)', font, bold),
            _pdfInfoLine('생 년 월 일', _birthDateCtrl.text, font, bold),
            _pdfInfoLine('주          소', _addressCtrl.text, font, bold),
            _pdfInfoLine('연    락    처', _phoneCtrl.text, font, bold),
            pw.SizedBox(height: 20),

            // 해당 유형 체크
            pw.RichText(
              text: pw.TextSpan(
                style: pw.TextStyle(font: font, fontSize: 11),
                children: [
                  const pw.TextSpan(text: '상기 본인은 (아래 해당사항마다 모두 "'),
                  pw.TextSpan(text: '☑', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  const pw.TextSpan(text: '" 또는 "'),
                  pw.TextSpan(text: '■', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  const pw.TextSpan(text: '"로 표시)'),
                ],
              ),
            ),
            pw.SizedBox(height: 10),
            checkRow(_isWoman, '여자'),
            checkRow(_isMinor, '미성년자 (만 15세 ~ 만 18세 미만)'),
            checkRow(_isPregnant, '임산부'),
            checkRow(_isPregnantNow, '임신 중'),
            checkRow(_isPostPartum, '출산 후 1년 이내인 자로서'),
            pw.Padding(
              padding: const pw.EdgeInsets.only(left: 18, top: 2),
              child: pw.Text(
                '( 단 연소자, 임신 중이거나 출산 후 1년 이내인 여성의 경우 동의서 외 노동부장관 인가 필요)',
                style: pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700),
              ),
            ),
            pw.SizedBox(height: 20),

            // 점포명
            pw.Row(
              children: [
                pw.Text('○ 점포명 : ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                pw.Text(_storeName, style: pw.TextStyle(
                  fontSize: 12, fontWeight: pw.FontWeight.bold, decoration: pw.TextDecoration.underline)),
                pw.Text(' 에서', style: pw.TextStyle(fontSize: 11)),
              ]
            ),
            pw.SizedBox(height: 14),

            // 고용 형태
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(_isRegular ? '■' : '□', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                pw.Text(' 정규직, ', style: pw.TextStyle(fontSize: 11)),
                pw.Text(_isIrregular ? '■' : '□', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                pw.Text(' 비정규직(단시간근로자, 파견근로자), ', style: pw.TextStyle(fontSize: 11)),
                pw.Text(_isPartTime ? '■' : '□', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                pw.Text(' 파트타임 아르바이트,', style: pw.TextStyle(fontSize: 11)),
              ],
            ),
            pw.SizedBox(height: 4),
            pw.Row(
              children: [
                pw.Text(_isOther ? '■' : '□', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                pw.Text(' 기타(직명이나 근로형태를 구체적으로 상세히 기재 : ${_otherJobTypeCtrl.text}                     )',
                    style: pw.TextStyle(fontSize: 11)),
              ],
            ),
            pw.SizedBox(height: 10),

            // 동의 본문
            pw.Text(
              '의 직원으로서 경우에 따라서는 휴일이나 야간(22:00 ~ 익일 06:00)에 근로하는 것에 동의합니다.\n\n'
              '다만, 동의한 이후에 언제든지 근로자 본인이 서면으로 휴일 및 야간근로를 하지 못할 개인적인 사정을 명백히 밝힌 경우에는 그 때부터 휴일 및 야간근로에 동의하지 아니한 것입니다.',
              style: pw.TextStyle(fontSize: 11, height: 1.7),
            ),
            pw.SizedBox(height: 36),

            // 날짜
            pw.Center(
              child: pw.Text(
                '${now.year} 년     ${now.month} 월     ${now.day} 일',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13),
              ),
            ),
            pw.SizedBox(height: 30),

            // 서명
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                pw.Text('동의한 근로자 성명 : ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
                pw.Text('${_nameCtrl.text}               ', style: pw.TextStyle(
                    fontSize: 12, decoration: pw.TextDecoration.underline)),
                pw.Text('(인)', style: pw.TextStyle(fontSize: 12)),
                if (sigBytes != null)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(left: 8),
                    child: pw.Image(pw.MemoryImage(sigBytes), width: 50, height: 30),
                  ),
              ],
            ),
          ],
        ),
      ),
    );

    return pdf.save();
  }

  static pw.Widget _pdfInfoLine(String label, String value, pw.Font font, pw.Font bold) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.SizedBox(
            width: 90,
            child: pw.Text(label, style: pw.TextStyle(font: bold, fontSize: 11)),
          ),
          pw.Text(' : ', style: pw.TextStyle(font: font, fontSize: 11)),
          pw.Text(value, style: pw.TextStyle(
            font: font,
            fontSize: 11,
            decoration: pw.TextDecoration.underline,
          )),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: const Text('휴일 및 야간근로 동의서'),
        backgroundColor: const Color(0xFF1A1A2E),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.document.status == 'boss_signed' || widget.document.status == 'completed')
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
            // ── 인적사항 ──────────────────────────────────────────────
            _card('근로자 인적사항', [
              _row([
                Expanded(flex: 3, child: _field('성명', _nameCtrl)),
                const SizedBox(width: 10),
                Expanded(flex: 2, child: _field('나이 (만)', _ageCtrl, hint: '세', keyboard: TextInputType.number)),
              ]),
              _field('생년월일(YYYYMMDD)', _birthDateCtrl, hint: 'YYYYMMDD'),
              _field('주소', _addressCtrl),
              _field('연락처', _phoneCtrl, keyboard: TextInputType.phone),
            ]),
            const SizedBox(height: 14),

            // ── 해당 사항 체크박스 ─────────────────────────────────────
            _card('해당 사항 (중복 선택 가능)', [
              const Text(
                '상기 본인은 아래 해당사항마다 모두 선택하세요.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              _check('여자', _isWoman, (v) => setState(() => _isWoman = v!)),
              _check('미성년자 (만 15세 ~ 만 18세 미만)', _isMinor, (v) => setState(() => _isMinor = v!)),
              _check('임산부', _isPregnant, (v) => setState(() => _isPregnant = v!)),
              _check('임신 중', _isPregnantNow, (v) => setState(() => _isPregnantNow = v!)),
              _check('출산 후 1년 이내인 자', _isPostPartum, (v) => setState(() => _isPostPartum = v!)),
              Padding(
                padding: const EdgeInsets.only(left: 32),
                child: Text(
                  '※ 연소자·임신 중이거나 출산 후 1년 이내인 여성의 경우\n동의서 외 노동부장관 인가 필요',
                  style: TextStyle(fontSize: 11, color: Colors.orange.shade800),
                ),
              ),
            ]),
            const SizedBox(height: 14),

            // ── 고용 형태 ──────────────────────────────────────────────
            _card('고용 형태', [
              _check('정규직', _isRegular, (v) => setState(() => _isRegular = v!)),
              _check('비정규직 (단시간근로자, 파견근로자)', _isIrregular, (v) => setState(() => _isIrregular = v!)),
              _check('파트타임 아르바이트', _isPartTime, (v) => setState(() => _isPartTime = v!)),
              _check('기타', _isOther, (v) => setState(() => _isOther = v!)),
              if (_isOther) ...[
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(left: 32),
                  child: _field('직명 또는 근로형태 상세 기재', _otherJobTypeCtrl),
                ),
              ],
            ]),
            const SizedBox(height: 14),

            // ── 동의 본문 ──────────────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF1A1A2E).withValues(alpha: 0.3)),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)],
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('동의 내용', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1A1A2E))),
                  const SizedBox(height: 10),
                  RichText(
                    text: TextSpan(
                      style: const TextStyle(fontSize: 13, color: Colors.black87, height: 1.7),
                      children: [
                        TextSpan(
                          text: _storeName,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const TextSpan(
                          text: '의 직원으로서 경우에 따라서는 '
                              '휴일이나 야간(22:00 ~ 익일 06:00)에 근로하는 것에 '
                              '동의합니다.\n\n'
                              '다만, 동의한 이후에 언제든지 근로자 본인이 서면으로 '
                              '휴일 및 야간근로를 하지 못할 개인적인 사정을 명백히 밝힌 '
                              '경우에는 그 때부터 휴일 및 야간근로에 동의하지 아니한 것입니다.',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── 서명란 (위자드 모드에서는 숨김 - 웹 번들 서명으로 처리) ──
            if (!widget.isWizardMode)
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF1A1A2E), width: 1.5),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6)],
              ),
              clipBehavior: Clip.hardEdge,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    color: const Color(0xFF1A1A2E),
                    child: Row(
                      children: [
                        const Text('동의한 근로자 서명', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                        const Spacer(),
                        Text(
                          '${DateTime.now().year}년 ${DateTime.now().month}월 ${DateTime.now().day}일',
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  if (_savedSignatureBytes != null)
                    Container(
                      height: 160,
                      color: Colors.white,
                      width: double.infinity,
                      alignment: Alignment.center,
                      child: Image.memory(_savedSignatureBytes!),
                    )
                  else
                    Signature(controller: _sigController, height: 160, backgroundColor: Colors.white),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('${_nameCtrl.text} (인)', style: const TextStyle(color: Colors.grey, fontSize: 12)),
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
            const SizedBox(height: 24),

            // ── PDF 저장 버튼 ─────────────────────────────────────────
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
              Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: () async {
                    // 위자드 모드: 서명 없이 바로 다음 단계로
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

  // ── 공용 위젯 헬퍼 ──────────────────────────────────────────────────
  Widget _card(String title, List<Widget> children) {
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

  Widget _row(List<Widget> children) => Row(children: children);

  Widget _field(String label, TextEditingController ctrl,
      {String? hint, TextInputType keyboard = TextInputType.text}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: ctrl,
        keyboardType: keyboard,
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

  Widget _check(String label, bool value, Function(bool?) onChanged) {
    return CheckboxListTile(
      value: value,
      onChanged: onChanged,
      title: Text(label, style: const TextStyle(fontSize: 13)),
      controlAffinity: ListTileControlAffinity.leading,
      dense: true,
      activeColor: const Color(0xFF1A1A2E),
      contentPadding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
    );
  }
}
