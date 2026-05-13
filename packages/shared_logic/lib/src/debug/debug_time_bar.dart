import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:shared_logic/src/utils/app_clock.dart';
import 'package:shared_logic/src/debug/test_data_seeder.dart';
import 'package:shared_logic/src/debug/debug_auth_constants.dart';
import 'package:shared_logic/src/debug/debug_auth_constants.dart';

/// 화면 상단에 붙는 디버그용 시각 조절 (kDebugMode 전용).
class DebugTimeControlBar extends StatelessWidget {
  const DebugTimeControlBar({super.key});

  static const double contentHeight = 64.0;

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return const SizedBox.shrink();
    return Container(
      color: Colors.cyan.shade100,
      child: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ListenableBuilder(
            listenable: AppClock.instance,
            builder: (context, _) {
              final t = AppClock.now();
              final dateLabel =
                  '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
              final timeLabel =
                  '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ROW 1: Date/Time + Session Reset + Auto Attend
                    Row(
                      children: [
                        Text(
                          '📅 $dateLabel  ⏱ $timeLabel',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                        const SizedBox(width: 16),
                        GestureDetector(
                          onTap: () async {
                            await FirebaseAuth.instance.signOut();
                          },
                          child: const Text(
                            '⟳ 세션 초기화',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.red,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        GestureDetector(
                          onTap: () async {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('가상출근 시뮬레이션 중...')),
                            );
                            // Instead of importing StoreInfo from boss_mobile (circular dependency),
                            // we just use the debug store id, or we could pass it down.
                            final realStoreId = DebugAuthConstants.debugStoreId;
                            
                            await TestDataSeeder.generateVirtualWorkerAttendances(
                              storeId: realStoreId,
                            );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('★ 한 달 치 가상 출퇴근 데이터 생성 완료!'),
                                ),
                              );
                            }
                          },
                          child: const Text(
                            '🤖 1달치 자동출근',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.indigo,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // ROW 2: Adjustments
                    Row(
                      children: [
                        _buildLabel('하루'),
                        _buildBtn(Icons.remove, () {
                          debugPrint('[Debug] Minus day');
                          AppClock.setDebugOverride(
                            t.subtract(const Duration(days: 1)),
                          );
                        }),
                        _buildBtn(Icons.add, () {
                          debugPrint('[Debug] Plus day');
                          AppClock.setDebugOverride(
                            t.add(const Duration(days: 1)),
                          );
                        }),
                        const SizedBox(width: 12),
                        _buildLabel('시간'),
                        _buildBtn(Icons.remove, () {
                          debugPrint('[Debug] Minus hour');
                          AppClock.setDebugOverride(
                            t.subtract(const Duration(hours: 1)),
                          );
                        }),
                        Text(
                          '${t.hour}시',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        _buildBtn(Icons.add, () {
                          debugPrint('[Debug] Plus hour');
                          AppClock.setDebugOverride(
                            t.add(const Duration(hours: 1)),
                          );
                        }),
                        const SizedBox(width: 12),
                        _buildLabel('분'),
                        _buildBtn(Icons.remove, () {
                          debugPrint('[Debug] Minus 10m');
                          AppClock.setDebugOverride(
                            t.subtract(const Duration(minutes: 10)),
                          );
                        }),
                        Text(
                          '${t.minute}분',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        _buildBtn(Icons.add, () {
                          debugPrint('[Debug] Plus 10m');
                          AppClock.setDebugOverride(
                            t.add(const Duration(minutes: 10)),
                          );
                        }),
                        const SizedBox(width: 16),
                        GestureDetector(
                          onTap: () => AppClock.setDebugOverride(null),
                          child: const Text(
                            '실제 시간',
                            style: TextStyle(fontSize: 11, color: Colors.blue),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) => Padding(
    padding: const EdgeInsets.only(right: 4),
    child: Text(
      text,
      style: const TextStyle(fontSize: 11, color: Colors.black54),
    ),
  );

  Widget _buildBtn(IconData icon, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    behavior: HitTestBehavior.opaque,
    child: Container(
      padding: const EdgeInsets.all(4),
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Icon(icon, size: 18),
    ),
  );
}
