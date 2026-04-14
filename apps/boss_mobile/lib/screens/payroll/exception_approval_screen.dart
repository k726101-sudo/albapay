import 'package:flutter/material.dart';

class ExceptionApprovalScreen extends StatelessWidget {
  const ExceptionApprovalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leadingWidth: 100,
        leading: TextButton.icon(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_ios, size: 16, color: Colors.black87),
          label: const Text('이전 화면', style: TextStyle(color: Colors.black87, fontSize: 13, height: 1.1)),
        ),
        title: const Text('예외 근무 승인'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _buildExceptionCard(
            context,
            '박지성',
            '지각 (오차 범위 초과)',
            '예정 시간 09:00인데 09:12에 출근했습니다. 시스템이 자동 승인을 보류하고 사장님의 확인을 기다립니다.',
            '오전 09:12 (오늘)',
            originalTime: '09:12',
            expectedTime: '09:00',
          ),
          const SizedBox(height: 16),
          _buildExceptionCard(
            context,
            '이민수',
            'WiFi 인증 누락',
            '출근 시 매장 WiFi에 연결되지 않은 상태로 기록되었습니다.',
            '오전 09:00 (오늘)',
          ),
        ],
      ),
    );
  }

  Widget _buildExceptionCard(
    BuildContext context,
    String name,
    String title,
    String reason,
    String time, {
    String? originalTime,
    String? expectedTime,
  }) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Text(time, style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                title,
                style: TextStyle(color: Colors.red.shade800, fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
            const SizedBox(height: 12),
            if (originalTime != null && expectedTime != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: Row(
                  children: [
                    _timeBadge('실제: $originalTime', Colors.red),
                    const SizedBox(width: 8),
                    _timeBadge('예정: $expectedTime', Colors.blue),
                  ],
                ),
              ),
            Text(reason, style: const TextStyle(color: Colors.black87)),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {},
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                    child: const Text('반려'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('정상 승인 처리되었습니다.')),
                      );
                    },
                    child: const Text('예외 승인'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _timeBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }
}
