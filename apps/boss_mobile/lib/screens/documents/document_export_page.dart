import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:shared_logic/shared_logic.dart';
import 'package:printing/printing.dart';
import 'package:http/http.dart' as http;
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
      Uint8List? pdfBytes;

      // ── 1. R2 확정본 우선 (immutable — 재생성 금지) ──
      if (doc.pdfR2DocId != null && doc.pdfR2DocId!.isNotEmpty) {
        try {
          final archiveUrl = await PdfArchiveService.instance.getArchivedPdfUrl(doc);
          if (archiveUrl != null) {
            final response = await http.get(Uri.parse(archiveUrl));
            if (response.statusCode == 200) {
              pdfBytes = response.bodyBytes;
              debugPrint('✅ R2 확정본 PDF 사용 (재생성 없음)');
            }
          }
        } catch (e) {
          debugPrint('R2 확정본 다운로드 실패, 동적 생성 폴백: $e');
        }
      }

      // ── 2. 폴백: R2 확정본이 없는 경우에만 동적 생성 ──
      if (pdfBytes == null) {
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
            ownerSignatureBytes: null,
            workerSignatureBytes: null,
          );
        } else if (doc.type == DocumentType.night_consent) {
          final Map<String, dynamic> consentData = doc.dataJson != null 
              ? jsonDecode(doc.dataJson!) 
              : {};
              
          pdfBytes = await PdfGeneratorService.generateNightConsent(
            document: doc,
            consentData: consentData,
          );
        } else if (doc.type == DocumentType.worker_record) {
          final Map<String, dynamic> recordData = doc.dataJson != null 
              ? jsonDecode(doc.dataJson!) 
              : {};
              
          pdfBytes = await PdfGeneratorService.generateWorkerRecord(
            document: doc,
            recordData: recordData,
          );
        }
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
                // soft delete 필터 + 기간 필터링 (createdAt 기준)
                final filteredDocs = allDocs.where((doc) => !doc.isDeleted).where((doc) {
                  final date = doc.createdAt;
                  return !date.isBefore(_startDate) && !date.isAfter(_endDate.add(const Duration(days: 1)));
                }).where((doc) => 
                  doc.type == DocumentType.contract_full || 
                  doc.type == DocumentType.contract_part || 
                  doc.type == DocumentType.wageStatement || 
                  doc.type == DocumentType.wage_amendment ||
                  doc.type == DocumentType.night_consent ||
                  doc.type == DocumentType.worker_record
                ).toList()
                ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

                if (filteredDocs.isEmpty) {
                  return const Center(child: Text('해당 기간에 발행된 서류가 없습니다.'));
                }

                return _buildGroupedList(filteredDocs);
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

  String _getWorkerName(LaborDocument doc) {
    if (doc.dataJson != null && doc.dataJson!.isNotEmpty) {
      try {
        final data = jsonDecode(doc.dataJson!);
        if (data['workerName'] != null) return data['workerName'];
        if (data['name'] != null) return data['name'];
        if (data['staffName'] != null) return data['staffName'];
      } catch (_) {}
    }
    // Fallback: extract from title if it contains a dash like "홍길동_근로계약서"
    final parts = doc.title.split(RegExp(r'[_ -]'));
    if (parts.isNotEmpty && parts[0].length >= 2 && parts[0].length <= 4) {
      if (!parts[0].contains('계약서') && !parts[0].contains('명세서')) {
         return parts[0];
      }
    }
    return '이름 미상';
  }

  Widget _buildGroupedList(List<LaborDocument> docs) {
    // Group by Month -> Worker Name -> List<LaborDocument>
    final grouped = <String, Map<String, List<LaborDocument>>>{};
    for (var doc in docs) {
      final monthKey = '${doc.createdAt.year}년 ${doc.createdAt.month.toString().padLeft(2, '0')}월';
      final workerName = _getWorkerName(doc);
      
      grouped.putIfAbsent(monthKey, () => {});
      grouped[monthKey]!.putIfAbsent(workerName, () => []).add(doc);
    }
    
    final sortedMonths = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
    
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: sortedMonths.length,
      itemBuilder: (context, i) {
        final monthKey = sortedMonths[i];
        final workerGroups = grouped[monthKey]!;
        final sortedWorkers = workerGroups.keys.toList()..sort();
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
             // Month Header
             Container(
               color: Colors.blue.shade50,
               padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
               child: Text(
                 monthKey, 
                 style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey, fontSize: 13)
               ),
             ),
             // Worker blocks
             ...sortedWorkers.map((workerName) {
               final items = workerGroups[workerName]!;
               return Column(
                 crossAxisAlignment: CrossAxisAlignment.stretch,
                 children: [
                   Padding(
                     padding: const EdgeInsets.only(left: 16, top: 12, bottom: 4),
                     child: Text(
                       '👤 $workerName', 
                       style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87)
                     ),
                   ),
                   ...items.map((doc) => _buildDocTile(doc)).toList(),
                   const Divider(height: 1),
                 ],
               );
             }).toList(),
          ],
        );
      },
    );
  }

  Widget _buildDocTile(LaborDocument doc) {
    return Dismissible(
      key: Key(doc.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.red.shade400,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20.0),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (direction) async {
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('서류 삭제'),
            content: Text('${doc.title} 문서를 정말 삭제하시겠습니까?\n삭제 후 복구할 수 없습니다.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true), 
                child: const Text('삭제', style: TextStyle(color: Colors.red))
              ),
            ],
          ),
        );
      },
      onDismissed: (direction) async {
        try {
          await DatabaseService().deleteDocument(widget.storeId, doc.id);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('문서가 삭제되었습니다.')),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('삭제 실패: $e')),
            );
          }
        }
      },
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
        title: Text(doc.title, style: const TextStyle(fontSize: 14)),
        subtitle: Text(
          '발행일: ${doc.createdAt.toIso8601String().substring(0, 10)}',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.picture_as_pdf, color: Colors.red),
          onPressed: _isLoading ? null : () => _exportToPdf(doc),
        ),
      ),
    );
  }
}

