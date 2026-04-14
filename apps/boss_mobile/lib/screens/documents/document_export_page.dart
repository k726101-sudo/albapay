import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_logic/shared_logic.dart';
import 'package:printing/printing.dart';
import '../../utils/pdf/pdf_generator_service.dart';

class DocumentExportPage extends StatefulWidget {
  final String storeId;

  const DocumentExportPage({super.key, required this.storeId});

  @override
  State<DocumentExportPage> createState() => _DocumentExportPageState();
}

class _DocumentExportPageState extends State<DocumentExportPage> {
  DateTime _startDate = AppClock.now().subtract(const Duration(days: 30));
  DateTime _endDate = AppClock.now();
  bool _isLoading = false;

  Future<void> _selectDateRange(BuildContext context) async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
    }
  }

  Future<void> _exportToPdf(LaborDocument doc) async {
    setState(() => _isLoading = true);
    try {
      dynamic pdfBytes;
      if (doc.type == DocumentType.contract_full || doc.type == DocumentType.contract_part) {
        Map<String, dynamic> contractData = {};
        if (doc.dataJson != null && doc.dataJson!.isNotEmpty) {
          try {
            contractData = jsonDecode(doc.dataJson!);
          } catch (e) {
            debugPrint('Failed to decode contract data: $e');
          }
        }
        
        if (doc.type == DocumentType.contract_full) {
          pdfBytes = await PdfGeneratorService.generateFullContract(
            document: doc,
            contractData: contractData,
          );
        } else {
          pdfBytes = await PdfGeneratorService.generatePartTimeContract(
            document: doc,
            contractData: contractData,
          );
        }
      } else if (doc.type == DocumentType.wageStatement) {
        final Map<String, dynamic> wageData = doc.dataJson != null 
            ? jsonDecode(doc.dataJson!) 
            : {};
        pdfBytes = await PdfGeneratorService.generateWageStatement(
          document: doc, 
          wageData: wageData
        );
      } else if (doc.type == DocumentType.wage_amendment) {
        final Map<String, dynamic> amendmentData = doc.dataJson != null 
            ? jsonDecode(doc.dataJson!) 
            : {};
        
        pdfBytes = await PdfGeneratorService.generateWageAmendment(
          document: doc, 
          amendmentData: amendmentData,
          ownerSignatureBytes: null, // TODO: Signature support in export
          workerSignatureBytes: null,
        );
      }

      if (pdfBytes != null) {
        await Printing.sharePdf(bytes: pdfBytes, filename: '${doc.title}.pdf');
      }
    } catch (e, stack) {
      debugPrint('PDF Export Error: $e\n$stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('PDF 생성 실패: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('기간별 서류 발급 (PDF)'),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.blue.shade50,
            child: Row(
              children: [
                const Icon(Icons.date_range, color: Colors.blue),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('조회 기간', style: TextStyle(fontSize: 12, color: Colors.blue)),
                      Text(
                        '${_startDate.toIso8601String().substring(0, 10)} ~ ${_endDate.toIso8601String().substring(0, 10)}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => _selectDateRange(context),
                  child: const Text('변경'),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<List<LaborDocument>>(
              stream: DatabaseService().streamDocuments(widget.storeId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final allDocs = snapshot.data ?? [];
                // 기간 필터링 (createdAt 기준)
                final filteredDocs = allDocs.where((doc) {
                  final date = doc.createdAt;
                  return !date.isBefore(_startDate) && !date.isAfter(_endDate.add(const Duration(days: 1)));
                }).where((doc) => 
                  doc.type == DocumentType.contract_full || 
                  doc.type == DocumentType.contract_part || 
                  doc.type == DocumentType.wageStatement || 
                  doc.type == DocumentType.wage_amendment
                ).toList()
                ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

                if (filteredDocs.isEmpty) {
                  return const Center(child: Text('해당 기간에 발행된 서류가 없습니다.'));
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: filteredDocs.length,
                  separatorBuilder: (_, __) => const Divider(),
                  itemBuilder: (context, index) {
                    final doc = filteredDocs[index];
                    return ListTile(
                      title: Text(doc.title),
                      subtitle: Text('발행일: ${doc.createdAt.toIso8601String().substring(0, 10)}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.picture_as_pdf, color: Colors.red),
                        onPressed: _isLoading ? null : () => _exportToPdf(doc),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              '※ 법적 보관 기간(3년) 내의 서류만 조회 및 발급 가능합니다.',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ),
        ],
      ),
    );
  }
}
