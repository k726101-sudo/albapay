import 'package:flutter/material.dart';
import 'package:shared_logic/shared_logic.dart';
import 'package:url_launcher/url_launcher.dart';

class EducationDetailScreen extends StatefulWidget {
  final EducationContent content;
  final String? storeId;
  final String? workerId;
  final String? workerName;

  const EducationDetailScreen({
    super.key, 
    required this.content,
    this.storeId,
    this.workerId,
    this.workerName,
  });

  @override
  State<EducationDetailScreen> createState() => _EducationDetailScreenState();
}

class _EducationDetailScreenState extends State<EducationDetailScreen> {
  bool _isVideoFinished = false;
  int? _selectedAnswer;
  bool _isQuizPassed = false;
  bool _isConsentChecked = false;

  void _handleVideoFinish() {
    setState(() => _isVideoFinished = true);
  }

  void _handleQuizSubmit() async {
    if (_selectedAnswer == 0) { // Assuming index 0 is correct for mock
      if (!_isConsentChecked) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('교육 수료 확인란에 체크해 주세요.')),
        );
        return;
      }
      
      setState(() => _isQuizPassed = true);
      
      final dbService = DatabaseService();
      final record = EducationRecord(
        id: AppClock.now().millisecondsSinceEpoch.toString(),
        storeId: widget.storeId ?? 'unknown-store-id',
        staffId: widget.workerId ?? 'unknown-staff-id',
        educationContentId: widget.content.id,
        completedAt: AppClock.now(),
        score: 100,
      );

      try {
        await dbService.saveEducationRecord(record);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('퀴즈를 통과했습니다! 교육 이수가 완료되었습니다.')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('기억 저장 실패: $e')),
          );
        }
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('다시 한번 생각해보세요.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.content.title)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () async {
                final url = widget.content.videoUrl;
                if (url.isNotEmpty) {
                  final uri = Uri.parse(url);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  } else {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('영상을 열 수 없습니다.')),
                      );
                    }
                  }
                }
              },
              child: Container(
                height: 200,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.play_circle_fill, size: 60, color: Colors.blueAccent),
                        const SizedBox(height: 12),
                        const Text('여기를 눌러 영상을 시청하세요', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            
            if (!_isVideoFinished) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Column(
                  children: [
                    const Text('영상을 끝까지 시청하신 후 아래 버튼을 눌러주세요.', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.deepOrange)),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
                      onPressed: _handleVideoFinish,
                      child: const Text('네, 영상 시청을 완료했습니다'),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            Text(widget.content.description ?? '', style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 32),
            if (_isVideoFinished) _buildQuizSection(),
            if (_isQuizPassed) ...[
              const SizedBox(height: 32),
              const Center(
                child: Icon(Icons.verified, color: Colors.blue, size: 80),
              ),
              const SizedBox(height: 16),
              const Center(
                child: Text('교육 수료증명 생성이 완료되었습니다.\n수고하셨습니다!', 
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)
                )
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildQuizSection() {
    if (widget.content.quizzes.isEmpty) return const SizedBox();
    final quiz = widget.content.quizzes.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('확인 퀴즈', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        Text(quiz.question, style: const TextStyle(fontSize: 16)),
        const SizedBox(height: 12),
        ...List.generate(quiz.options.length, (index) {
          return RadioListTile<int>(
            title: Text(quiz.options[index]),
            value: index,
            groupValue: _selectedAnswer,
            onChanged: (val) => setState(() => _selectedAnswer = val),
          );
        }),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue.shade200),
          ),
          child: CheckboxListTile(
            title: const Text(
              '[필수] 본인은 해당 직무 교육 및 예방 영상을 모두 성실히 시청하였으며, 그 주요 내용을 충분히 식별 및 숙지하였음을 확인합니다.',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
            value: _isConsentChecked,
            onChanged: (val) => setState(() => _isConsentChecked = val ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            activeColor: Colors.blue,
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: (_selectedAnswer != null && _isConsentChecked && !_isQuizPassed) ? _handleQuizSubmit : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('교육 수료 확인 및 제출', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }
}
