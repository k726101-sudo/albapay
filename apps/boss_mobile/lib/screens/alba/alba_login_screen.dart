import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
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

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _rollbackPartialAlbaLogin(String uid) async {
    // users/{uid} delete는 admin 전용으로 변경됨 — signOut만 수행
    // acceptInvite Cloud Function이 실패 시 원자적으로 롤백하므로 문서 삭제 불필요
    try {
      await FirebaseAuth.instance.signOut().timeout(const Duration(seconds: 3));
    } catch (_) {}
  }

  Future<void> _loginWithInviteAndPhone() async {
    if (!_isConsented) {
      _toast('이용약관 및 개인정보처리방침을 확인하고 동의해 주세요.');
      return;
    }
    var invite = _inviteController.text.trim();
    if (!invite.toLowerCase().startsWith('demo_')) {
      invite = invite.toUpperCase();
    }
    final phone = _phoneController.text.trim().replaceAll(RegExp(r'[^0-9]'), '');
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

      // Cloud Function(인사팀)에 초대 수락 요청
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('acceptInvite');
      
      final result = await callable.call<Map<String, dynamic>>({
        'inviteCode': invite,
        'phone': phone,
      }).timeout(
        const Duration(seconds: 60),
        onTimeout: () => throw FirebaseException(
          plugin: 'functions',
          code: 'timeout',
          message: '서버 응답 대기 시간 초과. 네트워크를 확인해 주세요.',
        ),
      );

      final storeId = result.data['storeId']?.toString() ?? '';
      final workerId = result.data['workerId']?.toString() ?? '';

      if (storeId.isEmpty || workerId.isEmpty) {
        _toast('가입 처리 중 오류가 발생했습니다. 다시 시도해 주세요.');
        _rollbackPartialAlbaLogin(user.uid);
        setState(() => _isLoading = false);
        return;
      }

      await _consentService.ensureConsentRecorded(uid: user.uid, platform: 'boss_mobile_alba_mode');

      if (!mounted) return;
      FocusScope.of(context).unfocus();
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AlbaMainScreen(storeId: storeId, workerId: workerId)));
    } on FirebaseFunctionsException catch (e) {
      _toast(e.message ?? '가입 처리 중 오류가 발생했습니다.');
      final u = FirebaseAuth.instance.currentUser;
      if (u != null) await _rollbackPartialAlbaLogin(u.uid);
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
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final agreed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => const TermsConsentPopup(),
                    );
                    if (agreed == true) {
                      setState(() => _isConsented = true);
                    }
                  },
                  icon: Icon(
                    _isConsented ? Icons.check_circle : Icons.description_outlined,
                    color: _isConsented ? Colors.green : Colors.grey,
                  ),
                  label: Text(
                    _isConsented ? '약관 동의 완료' : '서비스 이용약관 및 개인정보 처리방침 확인',
                    style: TextStyle(
                      color: _isConsented ? Colors.green.shade700 : Colors.black87,
                      fontWeight: _isConsented ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: _isConsented ? Colors.green : Colors.grey.shade300),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              if (!_isConsented) ...[
                const SizedBox(height: 8),
                const Text(
                  '서비스 시작 전 약관 확인 및 동의가 필요합니다.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
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
