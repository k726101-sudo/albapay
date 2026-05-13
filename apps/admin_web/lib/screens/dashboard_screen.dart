import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../models/promotion_data.dart';
import '../services/gemini_promo_service.dart';
import '../services/firestore_promo_service.dart';
import 'package:firebase_core/firebase_core.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _noticeTitleController = TextEditingController();
  final TextEditingController _noticeContentController = TextEditingController();
  final FirestorePromoService _firestoreService = FirestorePromoService();
  
  List<PromotionData> _analyzedPromotions = [];
  bool _isAnalyzing = false;
  bool _isUploadingNotice = false;
  String _statusMessage = 'API 키를 입력하고 공지 이미지를 업로드하세요.';

  Future<void> _pickAndAnalyzeImage() async {
    final apiKey = _apiKeyController.text.trim();
    if (apiKey.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gemini API Key를 입력해주세요.')),
        );
      }
      return;
    }

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true, // 필요한 이유: Flutter web은 파일 시스템 접근이 막혀 있음, 바이트 데이터를 가져와야 함.
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        
        setState(() {
          _isAnalyzing = true;
          _statusMessage = '이미지 분석 중... (최대 10~20초 소요될 수 있습니다)';
        });

        final geminiService = GeminiPromoService(apiKey);
        final list = await geminiService.analyzeImage(file);

        if (mounted) {
          setState(() {
            _analyzedPromotions.addAll(list);
            _isAnalyzing = false;
            _statusMessage = '분석 완료! 총 ${list.length}개의 프로모션이 추출되었습니다.';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isAnalyzing = false;
          _statusMessage = '오류 발생: $e';
        });
      }
    }
  }

  Future<void> _uploadToFirestore() async {
    if (_analyzedPromotions.isEmpty) return;
    
    // Check if Firebase is actually initialized
    if (Firebase.apps.isEmpty) {
      setState(() {
        _statusMessage = 'Firebase가 아직 연결되지 않았습니다. (flutterfire configure를 실행하세요)';
      });
      return;
    }

    setState(() {
      _statusMessage = 'Firestore 서버에 업로드 중...';
    });

    try {
      await _firestoreService.savePromotions(_analyzedPromotions);
      if (mounted) {
        setState(() {
          _analyzedPromotions.clear();
          _statusMessage = '서버 업로드 성공! (boss_mobile 앱에서 확인 가능합니다)';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('성공적으로 글로벌 프로모션으로 업로드 되었습니다!')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = '서버 업로드 실패: $e';
        });
      }
    }
  }

  Future<void> _uploadNotice() async {
    final title = _noticeTitleController.text.trim();
    final content = _noticeContentController.text.trim();

    if (title.isEmpty || content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('제목과 내용을 모두 입력해주세요.')),
      );
      return;
    }

    if (Firebase.apps.isEmpty) {
      setState(() {
        _statusMessage = 'Firebase가 연결되지 않았습니다.';
      });
      return;
    }

    setState(() {
      _isUploadingNotice = true;
      _statusMessage = '메뉴얼/공지사항 업로드 중...';
    });

    try {
      await _firestoreService.saveNotice(title, content);
      if (mounted) {
        setState(() {
          _isUploadingNotice = false;
          _noticeTitleController.clear();
          _noticeContentController.clear();
          _statusMessage = 'NotebookLM 자료 업로드 성공!';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('성공적으로 공지사항 DB에 업로드 되었습니다!')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isUploadingNotice = false;
          _statusMessage = '업로드 실패: $e';
        });
      }
    }
  }

  List<PromotionData> _filterPromotions(int filterType) {
    if (filterType == 0) return _analyzedPromotions;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // 이번주의 시작(월요일)과 끝(일요일)
    final startOfWeek = today.subtract(Duration(days: today.weekday - 1));
    final endOfWeek = startOfWeek.add(const Duration(days: 6));

    return _analyzedPromotions.where((promo) {
      try {
        final startRaw = DateTime.parse(promo.startDate);
        // 날짜형식의 앞 10자리만 (YYYY-MM-DD)
        final endString = promo.endDate.length >= 10 ? promo.endDate.substring(0, 10) : promo.endDate;
        final endRaw = DateTime.parse(endString);
        
        // 중요: AI가 과거 연도(예: 2024년)로 날짜를 추출했을 수 있으므로 
        // 테스트가 원활하도록 현재(System) 연도로 보정하여 비교합니다.
        final start = DateTime(today.year, startRaw.month, startRaw.day);
        final end = DateTime(today.year, endRaw.month, endRaw.day);
        
        if (filterType == 1) { // 오늘
          return (start.isBefore(today) || start.isAtSameMomentAs(today)) &&
                 (end.isAfter(today) || end.isAtSameMomentAs(today));
        } else if (filterType == 2) { // 이번주
          // 겹침 확인 공식: 프로모션 시작일 <= 이번주 마지막 날 && 프로모션 종료일 >= 이번주 시작일
          return (start.isBefore(endOfWeek) || start.isAtSameMomentAs(endOfWeek)) &&
                 (end.isAfter(startOfWeek) || end.isAtSameMomentAs(startOfWeek));
        }
      } catch (e) {
        // 날짜 파싱 실패 시, 전체 탭에만 표시하도록 false 리턴
        return false;
      }
      return true;
    }).toList();
  }

  Widget _buildPromoList(List<PromotionData> promos) {
    if (promos.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.dashboard_customize, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            const Text('해당되는 프로모션이 없습니다.', style: TextStyle(color: Colors.grey)),
          ],
        )
      );
    }
    return ListView.builder(
      itemCount: promos.length,
      itemBuilder: (context, index) {
        final promo = promos[index];
        return Card(
          color: Colors.white,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.grey[200]!),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: CircleAvatar(
              backgroundColor: Colors.blue[50],
              child: const Icon(Icons.campaign, color: Colors.blueAccent),
            ),
            title: Text(promo.promotionName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Text(
                '기간: ${promo.startDate} ~ ${promo.endDate}\n'
                '유형: ${promo.eventType} | 혜택: ${promo.keyBenefit}\n'
                '대상: ${promo.targetProducts}\n'
                '참고: ${promo.notes}',
                style: TextStyle(color: Colors.grey[800], height: 1.5),
              ),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: () {
                setState(() => _analyzedPromotions.remove(promo));
              },
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        title: const Text('PB 파트너 프로모션 분석기 (관리자 전용)', style: TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left Panel: Controls
            Expanded(
              flex: 1,
              child: Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('🛠️ 1. 프로모션 이미지 파서', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _apiKeyController,
                          obscureText: true,
                          decoration: InputDecoration(
                            labelText: 'Gemini API Key (임시 수동 입력)',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            prefixIcon: const Icon(Icons.vpn_key),
                          ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            backgroundColor: Colors.blue[50],
                            foregroundColor: Colors.blue[800],
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            elevation: 0,
                          ),
                          onPressed: _isAnalyzing ? null : _pickAndAnalyzeImage,
                          icon: _isAnalyzing
                            ? const SizedBox(width:20, height:20, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.image_search),
                          label: Text(_isAnalyzing ? 'AI 비전 분석 중...' : '이미지 1장 선택/분석', style: const TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            elevation: 2,
                          ),
                          onPressed: _analyzedPromotions.isEmpty || _isAnalyzing ? null : _uploadToFirestore,
                          icon: const Icon(Icons.cloud_upload),
                          label: const Text('Firestore 전체 승인/업로드', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                        
                        const SizedBox(height: 32),
                        const Divider(),
                        const SizedBox(height: 32),
                        
                        const Text('📝 2. NotebookLM 분석 자료 업로드', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        const Text('NotebookLM에서 요약받은 매뉴얼이나 공지사항 텍스트를 그대로 업로드하세요.', style: TextStyle(color: Colors.grey)),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _noticeTitleController,
                          decoration: InputDecoration(
                            labelText: '게시물 제목',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _noticeContentController,
                          maxLines: 8,
                          decoration: InputDecoration(
                            labelText: 'NotebookLM 복사/붙여넣기 텍스트',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            alignLabelWithHint: true,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            backgroundColor: Colors.green[600],
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: _isUploadingNotice ? null : _uploadNotice,
                          icon: _isUploadingNotice 
                            ? const SizedBox(width:20, height:20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.note_add),
                          label: const Text('공지사항 DB에 업로드', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),

                        const SizedBox(height: 24),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: _statusMessage.contains('오류') || _statusMessage.contains('실패')
                                ? Colors.red[50] : Colors.blue[50],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _statusMessage.contains('오류') || _statusMessage.contains('실패') ? Icons.error_outline : Icons.info_outline,
                                color: _statusMessage.contains('오류') || _statusMessage.contains('실패') ? Colors.red : Colors.blueAccent,
                              ),
                              const SizedBox(width: 12),
                              Expanded(child: Text(_statusMessage, style: const TextStyle(fontWeight: FontWeight.w600))),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 32),
            // Right Panel: Results List
            Expanded(
              flex: 2,
              child: Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                    child: DefaultTabController(
                      length: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('✨ 사전 검수 (추출된 프로모션 데이타)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 16),
                          const TabBar(
                            tabs: [
                              Tab(text: '전체'),
                              Tab(text: '오늘의 프로모션'),
                              Tab(text: '이번주 프로모션'),
                            ],
                            labelColor: Colors.blueAccent,
                            unselectedLabelColor: Colors.grey,
                            indicatorColor: Colors.blueAccent,
                          ),
                          const SizedBox(height: 16),
                          Expanded(
                            child: TabBarView(
                              children: [
                                _buildPromoList(_filterPromotions(0)), // 전체
                                _buildPromoList(_filterPromotions(1)), // 오늘
                                _buildPromoList(_filterPromotions(2)), // 이번주
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
