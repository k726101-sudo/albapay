import 'package:flutter/material.dart';
import 'package:shared_logic/shared_logic.dart';
import 'request_substitution_screen.dart';

class SubstitutionBoardScreen extends StatelessWidget {
  const SubstitutionBoardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const String storeId = 'placeholder-store-id';
    final dbService = DatabaseService();

    return Scaffold(
      appBar: AppBar(title: const Text('근무 교대 게시판')),
      body: FutureBuilder<List<Substitution>>(
        future: dbService.getSubstitutions(storeId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final substitutions = snapshot.data ?? [];

          if (substitutions.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                   const Icon(Icons.swap_horiz, size: 64, color: Colors.grey),
                   const SizedBox(height: 16),
                   const Text('현재 올라온 대근 요청이 없습니다.'),
                   const SizedBox(height: 24),
                   ElevatedButton(
                     onPressed: () => Navigator.push(
                       context,
                       MaterialPageRoute(builder: (context) => const RequestSubstitutionScreen()),
                     ),
                     child: const Text('내가 대근 요청하기'),
                   ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: substitutions.length,
            itemBuilder: (context, index) {
              final sub = substitutions[index];
              return _buildSubstitutionCard(context, sub);
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const RequestSubstitutionScreen()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('대근 요청'),
      ),
    );
  }

  Widget _buildSubstitutionCard(BuildContext context, Substitution sub) {
    return Card(
      child: ListTile(
        title: Text('${sub.startTime.hour}:${sub.startTime.minute} ~ ${sub.endTime.hour}:${sub.endTime.minute}'),
        subtitle: Text('사유: 개인 사정 | 보상: 시급 + @'),
        trailing: ElevatedButton(
          onPressed: () {
            // TODO: Logic to accept substitution
          },
          child: const Text('내가 할게요'),
        ),
      ),
    );
  }
}
