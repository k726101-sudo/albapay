import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_logic/shared_logic.dart';

import 'alba_main_screen.dart';

class AlbaLoginScreen extends StatefulWidget {
  final String? initialInviteCode;
  
  const AlbaLoginScreen({super.key, this.initialInviteCode});

  @override
  State<AlbaLoginScreen> createState() => _AlbaLoginScreenState();
}

class _AlbaLoginScreenState extends State<AlbaLoginScreen> {
  final _phoneController = TextEditingController();
  final _inviteController = TextEditingController();
  final _dbService = DatabaseService();
  final _consentService = ConsentService();
  bool _isLoading = false;
  bool _isConsented = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialInviteCode != null) {
      _inviteController.text = widget.initialInviteCode!;
    }
  }

  String _normalizePhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('82') && digits.length >= 11) {
      return '0${digits.substring(2)}';
    }
    return digits;
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _rollbackPartialAlbaLogin(String uid) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).delete().timeout(const Duration(seconds: 3));
    } catch (_) {}
    try {
      await FirebaseAuth.instance.signOut().timeout(const Duration(seconds: 3));
    } catch (_) {}
  }

  Future<void> _loginWithInviteAndPhone() async {
    if (!_isConsented) {
      _toast('이용약관 및 개인정보처리방침을 확인하고 동의해 주세요.');
      return;
    }
    final invite = _inviteController.text.trim().toUpperCase();
    final phone = _normalizePhone(_phoneController.text.trim());
    if (invite.isEmpty || phone.isEmpty) {
      _toast('초대코드와 전화번호를 입력해 주세요.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      User? user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        final cred = await FirebaseAuth.instance.signInAnonymously();
        user = cred.user;
      }
      if (user == null) {
        _toast('로그인 토큰 발급에 실패했습니다.');
        setState(() => _isLoading = false);
        return;
      }

      final inviteData = await _dbService.getInvite(invite);
      final storeId = (inviteData?['storeId'] as String?)?.trim();
      
      if (storeId == null || storeId.isEmpty) {
        _toast('초대 코드가 유효하지 않습니다.');
        _rollbackPartialAlbaLogin(user.uid);
        setState(() => _isLoading = false);
        return;
      }

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
        {'storeId': storeId, 'workerId': FieldValue.delete(), 'workerName': FieldValue.delete()},
        SetOptions(merge: true),
      );

      final workerIdHint = inviteData?['workerId']?.toString().trim();
      DocumentSnapshot<Map<String, dynamic>>? matched;

      if (workerIdHint != null && workerIdHint.isNotEmpty) {
        final wdoc = await FirebaseFirestore.instance.collection('stores').doc(storeId).collection('workers').doc(workerIdHint).get();
        if (wdoc.exists) {
          final data = wdoc.data() ?? {};
          final code = (data['inviteCode'] ?? data['invite_code'])?.toString().trim();
          if (code == invite) {
            final workerPhone = _normalizePhone(data['phone']?.toString() ?? data['phoneNumber']?.toString() ?? '');
            if (workerPhone == phone && data['status']?.toString() == 'active') {
              matched = wdoc;
            }
          }
        }
      }

      if (matched == null) {
        final snap = await FirebaseFirestore.instance.collection('stores').doc(storeId).collection('workers')
            .where('inviteCode', isEqualTo: invite).where('status', isEqualTo: 'active').limit(5).get();
        for (final d in snap.docs) {
          final workerPhone = _normalizePhone(d.data()['phone']?.toString() ?? d.data()['phoneNumber']?.toString() ?? '');
          if (workerPhone == phone) {
            matched = d;
            break;
          }
        }
      }

      if (matched == null) {
        _toast('입력하신 전화번호와 일치하는 알바생을 찾을 수 없습니다.');
        _rollbackPartialAlbaLogin(user.uid);
        setState(() => _isLoading = false);
        return;
      }

      final workerId = matched.id;
      final workerName = matched.data()?['name']?.toString() ?? '직원';

      await FirebaseFirestore.instance.collection('stores').doc(storeId).collection('workers').doc(workerId)
          .set({'uid': user.uid}, SetOptions(merge: true));

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
        {'workerId': workerId, 'workerName': workerName},
        SetOptions(merge: true),
      );

      await _consentService.ensureConsentRecorded(uid: user.uid, platform: 'boss_mobile_alba_mode');

      if (!mounted) return;
      FocusScope.of(context).unfocus();
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AlbaMainScreen(storeId: storeId, workerId: workerId)));
    } catch (e) {
      _toast('에러가 발생했습니다: $e');
      final u = FirebaseAuth.instance.currentUser;
      if (u != null) await _rollbackPartialAlbaLogin(u.uid);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('알바생 등록 (초대 연동)'), backgroundColor: Colors.white),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(child: Icon(Icons.storefront, size: 64, color: Colors.blueAccent)),
              const SizedBox(height: 24),
              const Text('사장님께 받은 코드', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              TextField(
                controller: _inviteController,
                decoration: const InputDecoration(hintText: '영문/숫자 6자리', border: OutlineInputBorder()),
                textCapitalization: TextCapitalization.characters,
              ),
              const SizedBox(height: 16),
              const Text('내 전화번호', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(hintText: '01012345678', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => setState(() => _isConsented = !_isConsented),
                icon: Icon(_isConsented ? Icons.check_circle : Icons.circle_outlined, color: _isConsented ? Colors.green : Colors.grey),
                label: const Text('개인정보 처리방침 동의'),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: _isLoading ? null : _loginWithInviteAndPhone,
                  child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text('알바생 등록 및 로그인'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
