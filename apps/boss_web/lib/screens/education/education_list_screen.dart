import 'package:flutter/material.dart';
import 'package:shared_logic/shared_logic.dart';
import 'education_detail_screen.dart';

class EducationListScreen extends StatelessWidget {
  final bool showAppBar;
  final String? storeId;
  final String? workerId;
  final String? workerName;

  const EducationListScreen({
    super.key, 
    this.showAppBar = true,
    this.storeId,
    this.workerId,
    this.workerName,
  });

  @override
  Widget build(BuildContext context) {
    // Mock data for now. In real app, fetch from DatabaseService
    final List<EducationContent> contents = [
      EducationContent(
        id: 'edu-1',
        type: EducationType.sexualHarassment,
        title: '직장 내 성희롱 예방 교육',
        description: '쾌적한 근무 환경을 위해 반드시 이수해야 하는 필수 교육입니다.',
        videoUrl: 'https://youtu.be/XBV1jmygqVs?si=sYhPqC1CJRiIpYX6',
        quizzes: [
          QuizQuestion(
            question: '직장 내 성희롱의 판단 기준은 무엇인가요?',
            options: ['피해자의 주관적 사정', '행위자의 의도', '제3자의 시선', '피해자의 거부 의사 표시 여부'],
            correctIndex: 0,
          ),
        ],
      ),
      EducationContent(
        id: 'edu-2',
        type: EducationType.hygiene,
        title: '보건 및 위생 교육',
        description: '식품 취급 및 매장 위생 관리에 관한 기초 교육입니다.',
        videoUrl: 'https://example.com/video2',
        quizzes: const [],
      ),
    ];

    return Scaffold(
      appBar: showAppBar ? AppBar(title: const Text('교육 센터')) : null,
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: contents.length,
        separatorBuilder: (_, __) => const SizedBox(height: 16),
        itemBuilder: (context, index) {
          final content = contents[index];
          return Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              title: Text(content.title, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(content.description ?? ''),
              ),
              trailing: const Icon(Icons.play_circle_fill, color: Colors.blue, size: 40),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => EducationDetailScreen(
                    content: content,
                    storeId: storeId,
                    workerId: workerId,
                    workerName: workerName,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
