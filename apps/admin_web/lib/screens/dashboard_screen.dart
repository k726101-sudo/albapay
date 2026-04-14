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
  final FirestorePromoService _firestoreService = FirestorePromoService();
  
  List<PromotionData> _analyzedPromotions = [];
  bool _isAnalyzing = false;
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('🛠️ 설정 & 파일 업로드', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 24),
                      TextField(
                        controller: _apiKeyController,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: 'Gemini API Key (임시 수동 입력)',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          prefixIcon: const Icon(Icons.vpn_key),
                        ),
                      ),
                      const SizedBox(height: 24),
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
                      const SizedBox(height: 32),
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
                              _statusMessage.contains('오류') ? Icons.error_outline : Icons.info_outline,
                              color: _statusMessage.contains('오류') ? Colors.red : Colors.blueAccent,
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: Text(_statusMessage, style: const TextStyle(fontWeight: FontWeight.w600))),
                          ],
                        ),
                      ),
                      const Spacer(),
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
                    ],
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('✨ 사전 검수 (추출된 프로모션 데이타)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 16),
                      Expanded(
                        child: _analyzedPromotions.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.dashboard_customize, size: 64, color: Colors.grey[300]),
                                    const SizedBox(height: 16),
                                    const Text('오른쪽 패널에 추출된 결과가 표시됩니다.', style: TextStyle(color: Colors.grey)),
                                  ],
                                )
                              )
                            : ListView.builder(
                                itemCount: _analyzedPromotions.length,
                                itemBuilder: (context, index) {
                                  final promo = _analyzedPromotions[index];
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
                                          setState(() => _analyzedPromotions.removeAt(index));
                                        },
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
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
