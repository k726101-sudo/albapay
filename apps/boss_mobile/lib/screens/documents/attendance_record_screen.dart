import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_logic/shared_logic.dart';
import '../../models/store_info.dart';
import '../../models/worker.dart';

class AttendanceRecordScreen extends StatefulWidget {
  final Worker worker;
  final String storeId;

  const AttendanceRecordScreen({
    super.key,
    required this.worker,
    required this.storeId,
  });

  @override
  State<AttendanceRecordScreen> createState() => _AttendanceRecordScreenState();
}

class _AttendanceRecordScreenState extends State<AttendanceRecordScreen> {
  DateTime _startDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _endDate = DateTime.now();
  List<Attendance> _records = [];
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    setState(() => _isLoading = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('stores')
          .doc(widget.storeId)
          .collection('attendance')
          .where('staffId', isEqualTo: widget.worker.id)
          .orderBy('clockIn')
          .get();

      final all = snap.docs
          .map((d) => Attendance.fromJson({...d.data(), 'id': d.id}))
          .where((a) {
            final day = DateTime(a.clockIn.year, a.clockIn.month, a.clockIn.day);
            final start = DateTime(_startDate.year, _startDate.month, _startDate.day);
            final end = DateTime(_endDate.year, _endDate.month, _endDate.day);
            return !day.isBefore(start) && !day.isAfter(end);
          }).toList();

      setState(() {
        _records = all;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('데이터 로드 오류: $e')),
        );
      }
    }
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      locale: const Locale('ko'),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(primary: Color(0xFF1A1A2E)),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      _loadRecords();
    }
  }

  String _fmt(DateTime dt) =>
      '${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')}';

  String _fmtTime(DateTime? dt) {
    if (dt == null) return '-';
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _fmtMinutes(int minutes) {
    if (minutes <= 0) return '-';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h == 0) return '$m분';
    if (m == 0) return '$h시간';
    return '$h시간 $m분';
  }

  int get _totalMinutes => _records.fold(0, (sum, r) => sum + r.workedMinutes);

  Future<void> _generatePdf() async {
    setState(() => _isSaving = true);
    try {
      final bytes = await _buildPdf();
      await Printing.sharePdf(
        bytes: bytes,
        filename: '출퇴근기록부_${widget.worker.name}_${_startDate.year}${_startDate.month.toString().padLeft(2,'0')}.pdf',
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PDF 오류: $e')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<Uint8List> _buildPdf() async {
    final font = await PdfGoogleFonts.nanumGothicRegular();
    final bold = await PdfGoogleFonts.nanumGothicBold();
    final store = Hive.box<StoreInfo>('store').get('current');

    final pdf = pw.Document(theme: pw.ThemeData.withFont(base: font, bold: bold));

    pw.Widget headerCell(String text) => pw.Container(
      padding: const pw.EdgeInsets.all(5),
      color: const PdfColor(0.1, 0.1, 0.18),
      child: pw.Center(child: pw.Text(text, style: pw.TextStyle(color: PdfColors.white, fontSize: 9, fontWeight: pw.FontWeight.bold))),
    );

    pw.Widget dataCell(String text, {bool center = true}) => pw.Padding(
      padding: const pw.EdgeInsets.all(5),
      child: center
          ? pw.Center(child: pw.Text(text, style: pw.TextStyle(fontSize: 9)))
          : pw.Text(text, style: pw.TextStyle(fontSize: 9)),
    );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (ctx) => [
          // 헤더
          pw.Center(
            child: pw.Text('출퇴근 기록부',
                style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          ),
          pw.SizedBox(height: 8),
          pw.Center(
            child: pw.Text(
              '${_startDate.year}.${_startDate.month.toString().padLeft(2,'0')}.${_startDate.day.toString().padLeft(2,'0')} ~ '
              '${_endDate.year}.${_endDate.month.toString().padLeft(2,'0')}.${_endDate.day.toString().padLeft(2,'0')}',
              style: pw.TextStyle(fontSize: 11),
            ),
          ),
          pw.SizedBox(height: 14),

          // 정보 박스
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400),
            columnWidths: {
              0: const pw.FixedColumnWidth(50),
              1: const pw.FlexColumnWidth(1),
              2: const pw.FixedColumnWidth(50),
              3: const pw.FlexColumnWidth(1),
            },
            children: [
              pw.TableRow(children: [
                pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('사업장명', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
                pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(store?.storeName ?? '', style: pw.TextStyle(fontSize: 9))),
                pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('대표자', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
                pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(store?.ownerName ?? '', style: pw.TextStyle(fontSize: 9))),
              ]),
              pw.TableRow(children: [
                pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('성명', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
                pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(widget.worker.name, style: pw.TextStyle(fontSize: 9))),
                pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('생년월일', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
                pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(widget.worker.birthDate, style: pw.TextStyle(fontSize: 9))),
              ]),
            ],
          ),
          pw.SizedBox(height: 12),

          // 기록 테이블
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400),
            columnWidths: {
              0: const pw.FixedColumnWidth(35),
              1: const pw.FixedColumnWidth(30),
              2: const pw.FixedColumnWidth(48),
              3: const pw.FixedColumnWidth(48),
              4: const pw.FixedColumnWidth(48),
              5: const pw.FixedColumnWidth(48),
              6: const pw.FlexColumnWidth(1),
              7: const pw.FixedColumnWidth(52),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColor(0.1, 0.1, 0.18)),
                children: [
                  headerCell('날짜'),
                  headerCell('요일'),
                  headerCell('출근'),
                  headerCell('퇴근'),
                  headerCell('휴게시작'),
                  headerCell('휴게종료'),
                  headerCell('비고'),
                  headerCell('근무시간'),
                ],
              ),
              ..._records.map((r) {
                final dayNames = ['일', '월', '화', '수', '목', '금', '토'];
                final dayName = dayNames[r.clockIn.weekday % 7];
                final breakMin = (r.breakStart != null && r.breakEnd != null)
                    ? r.breakEnd!.difference(r.breakStart!).inMinutes
                    : 0;
                String note = '';
                if (r.attendanceStatus == 'Unplanned') note = '비예정';
                if (r.isEditedByBoss) note = '수정됨';
                if (r.isSpecialOvertime) note = '특별연장';
                return pw.TableRow(children: [
                  dataCell(_fmt(r.clockIn)),
                  dataCell(dayName),
                  dataCell(_fmtTime(r.clockIn)),
                  dataCell(_fmtTime(r.clockOut)),
                  dataCell(_fmtTime(r.breakStart)),
                  dataCell(_fmtTime(r.breakEnd)),
                  dataCell(note, center: false),
                  dataCell(_fmtMinutes(r.workedMinutes)),
                ]);
              }),

              // 합계
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColor(0.93, 0.93, 0.97)),
                children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(5),
                    child: pw.Center(child: pw.Text('합계', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
                  ),
                  pw.SizedBox(),
                  pw.SizedBox(),
                  pw.SizedBox(),
                  pw.SizedBox(),
                  pw.SizedBox(),
                  pw.SizedBox(),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(5),
                    child: pw.Center(child: pw.Text(_fmtMinutes(_totalMinutes), style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
                  ),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 20),
          pw.Text(
            '※ 본 출퇴근 기록부는 ${store?.storeName ?? ''}의 근무 기록을 자동 생성한 서류입니다.',
            style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
        ],
      ),
    );

    return pdf.save();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: Text('출퇴근기록부 · ${widget.worker.name}'),
        backgroundColor: const Color(0xFF1A1A2E),
        foregroundColor: Colors.white,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton.icon(
              onPressed: _isSaving || _records.isEmpty ? null : _generatePdf,
              icon: _isSaving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.picture_as_pdf_outlined, color: Colors.white),
              label: const Text('PDF', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // 기간 선택 바
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: const Color(0xFF1A1A2E),
            child: Row(
              children: [
                const Icon(Icons.date_range, color: Colors.white70, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${_startDate.year}.${_startDate.month.toString().padLeft(2,'0')}.${_startDate.day.toString().padLeft(2,'0')} ~ '
                    '${_endDate.year}.${_endDate.month.toString().padLeft(2,'0')}.${_endDate.day.toString().padLeft(2,'0')}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
                TextButton(
                  onPressed: _selectDateRange,
                  style: TextButton.styleFrom(foregroundColor: Colors.white70),
                  child: const Text('기간 변경'),
                ),
              ],
            ),
          ),

          // 요약 카드
          if (!_isLoading)
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8)],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _summaryItem('총 출근일', '${_records.where((r) => r.clockOut != null).length}일'),
                  _summaryItem('총 근무시간', _fmtMinutes(_totalMinutes)),
                  _summaryItem('미퇴근', '${_records.where((r) => r.clockOut == null).length}건'),
                ],
              ),
            ),

          // 리스트
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _records.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.access_time_outlined, size: 48, color: Colors.grey.shade300),
                            const SizedBox(height: 12),
                            const Text('해당 기간에 출퇴근 기록이 없습니다.', style: TextStyle(color: Colors.grey)),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _records.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final r = _records[i];
                          final dayNames = ['일', '월', '화', '수', '목', '금', '토'];
                          final dayName = dayNames[r.clockIn.weekday % 7];
                          final isWeekend = r.clockIn.weekday == DateTime.sunday || r.clockIn.weekday == DateTime.saturday;
                          return Container(
                            color: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            child: Row(
                              children: [
                                // 날짜
                                SizedBox(
                                  width: 56,
                                  child: Column(
                                    children: [
                                      Text(
                                        _fmt(r.clockIn),
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: isWeekend ? Colors.red : const Color(0xFF1A1A2E),
                                        ),
                                      ),
                                      Text(
                                        dayName,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isWeekend ? Colors.red : Colors.grey,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                // 출퇴근 시간
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          _timeChip('출근', _fmtTime(r.clockIn), Colors.green),
                                          const SizedBox(width: 8),
                                          _timeChip('퇴근', _fmtTime(r.clockOut), Colors.blue),
                                          if (r.breakStart != null) ...[
                                            const SizedBox(width: 8),
                                            _timeChip('휴게', '${_fmtTime(r.breakStart)}~${_fmtTime(r.breakEnd)}', Colors.orange),
                                          ],
                                        ],
                                      ),
                                      if (r.isEditedByBoss) ...[
                                        const SizedBox(height: 2),
                                        const Text('사장님 수정', style: TextStyle(fontSize: 10, color: Colors.orange)),
                                      ],
                                    ],
                                  ),
                                ),
                                // 근무시간
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      _fmtMinutes(r.workedMinutes),
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                    if (r.clockOut == null)
                                      const Text('미퇴근', style: TextStyle(fontSize: 10, color: Colors.red)),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),

          // 하단 PDF 버튼
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _isSaving || _records.isEmpty ? null : _generatePdf,
                icon: _isSaving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.picture_as_pdf_outlined),
                label: Text(_isSaving ? '생성 중...' : 'PDF로 저장 & 공유'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A1A2E),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryItem(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1A1A2E))),
      ],
    );
  }

  Widget _timeChip(String label, String value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold)),
        const SizedBox(width: 2),
        Text(value, style: const TextStyle(fontSize: 11)),
      ],
    );
  }
}
