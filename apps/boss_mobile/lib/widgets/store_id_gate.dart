import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../screens/store/store_setup_screen.dart';

class StoreIdGate extends StatelessWidget {
  const StoreIdGate({super.key, required this.builder});

  final Widget Function(BuildContext context, String storeId) builder;

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const StoreSetupScreen();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final data = snap.data?.data();
        final storeId = data?['storeId'];
        
        if (data != null && data.containsKey('demoError') && data['demoError'].toString().isNotEmpty) {
           return Scaffold(
             backgroundColor: Colors.white,
             body: Center(
               child: Padding(
                 padding: const EdgeInsets.all(24.0),
                 child: Column(
                   mainAxisAlignment: MainAxisAlignment.center,
                   children: [
                     Text('서버 에러 발생:\n${data['demoError']}', style: const TextStyle(color: Colors.red, fontSize: 16)),
                     const SizedBox(height: 24),
                     FilledButton.icon(
                       onPressed: () async {
                         // demoError 클리어 후 재시도
                         await FirebaseFirestore.instance.collection('users').doc(uid).update({'demoError': FieldValue.delete()});
                       },
                       icon: const Icon(Icons.refresh),
                       label: const Text('다시 시도'),
                     ),
                     const SizedBox(height: 12),
                     TextButton(
                       onPressed: () async {
                         await FirebaseAuth.instance.signOut();
                       },
                       child: const Text('로그아웃', style: TextStyle(color: Colors.grey)),
                     ),
                   ],
                 ),
               ),
             ),
           );
        }
        
        if (data != null && data.containsKey('seederDebug') && data['seederDebug'].toString().isNotEmpty && data['isLoadingDemo'] == true) {
            // We just let it fall through to the loading screen or if we want to freeze it we could
        }

        if (storeId is! String || storeId.trim().isEmpty) {
          return const StoreSetupScreen();
        }

        if (data?['isLoadingDemo'] == true) {
          return Scaffold(
            backgroundColor: const Color(0xFFF2F2F7),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 24),
                  Text(
                    '가상 체험 환경을\n생성하는 중입니다...',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      height: 1.4,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return builder(context, storeId);
      },
    );
  }
}

