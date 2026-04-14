import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models/worker.dart';
import '../../services/invitation_service.dart';

class StaffInviteCodeScreen extends StatefulWidget {
  const StaffInviteCodeScreen({
    super.key,
    required this.storeId,
    required this.worker,
  });

  final String storeId;
  final Worker worker;

  @override
  State<StaffInviteCodeScreen> createState() => _StaffInviteCodeScreenState();
}

class _StaffInviteCodeScreenState extends State<StaffInviteCodeScreen> {
  bool _loading = true;
  String? _inviteCode;
  String? _storeName;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final storeSnap = await FirebaseFirestore.instance
          .collection('stores')
          .doc(widget.storeId)
          .get();
      final storeName = storeSnap.data()?['storeName']?.toString().trim();

      final workerSnap = await FirebaseFirestore.instance
          .collection('stores')
          .doc(widget.storeId)
          .collection('workers')
          .doc(widget.worker.id)
          .get();

      final data = workerSnap.data() ?? {};
      var inviteCode =
          (data['inviteCode'] ?? data['invite_code'])?.toString().trim();

      if (inviteCode == null || inviteCode.isEmpty) {
        inviteCode = _generateInviteCode();
        await FirebaseFirestore.instance
            .collection('stores')
            .doc(widget.storeId)
            .collection('workers')
            .doc(widget.worker.id)
            .set(
          {'inviteCode': inviteCode, 'updatedAt': FieldValue.serverTimestamp()},
          SetOptions(merge: true),
        );
      }
      await FirebaseFirestore.instance.collection('invites').doc(inviteCode).set({
        'storeId': widget.storeId,
        'workerId': widget.worker.id,
        'staffName': widget.worker.name,
        'baseWage': widget.worker.hourlyWage,
        'createdAt': FieldValue.serverTimestamp(),
        'usedAt': null,
      }, SetOptions(merge: true));

      if (!mounted) return;
      setState(() {
        _storeName = storeName ?? '-';
        _inviteCode = inviteCode;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _storeName = '-';
        _inviteCode = null;
      });
    }
  }

  String _generateInviteCode() {
    const letters = 'ABCDEFGHJKLMNPRSTUVWXYZ';
    const digits = '23456789';
    const alphabet = '$letters$digits';
    final rnd = Random.secure();
    return List<String>.generate(
      6,
      (_) => alphabet[rnd.nextInt(alphabet.length)],
    ).join();
  }

  @override
  Widget build(BuildContext context) {
    final canShare = !_loading && _inviteCode != null && (_storeName ?? '').isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: const Text('초대 코드 전송'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '방금 생성된 초대 코드입니다.',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 14),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('매장: ${_storeName ?? '-'}'),
                          const SizedBox(height: 6),
                          Text('알바생: ${widget.worker.name}'),
                          const SizedBox(height: 6),
                          Text(
                            '초대 코드: ${_inviteCode ?? '-'}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: canShare
                        ? () async {
                            await InvitationService.shareInviteLink(
                              storeName: _storeName ?? '-',
                              storeId: widget.storeId,
                              staffName: widget.worker.name,
                              inviteCode: _inviteCode!,
                            );
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('공유 창이 열렸습니다.')),
                            );
                          }
                        : null,
                    child: const Text('초대 코드 전송'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('완료'),
                  )
                ],
              ),
            ),
    );
  }
}

