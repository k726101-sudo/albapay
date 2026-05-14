import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../theme/verify_theme.dart';

/// 개발자 전용 관리 패널 — 접근코드 발급/관리, 사용 현황 조회
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  User? _user;
  bool _isAuthorized = false;
  bool _isLoading = true;

  // ★ 관리자 UID — 사장님의 Google 계정 UID로 교체
  // Firebase Console → Authentication → Users 에서 확인
  static const _adminUids = <String>{
    // 여기에 사장님 UID 추가
    // 예: 'abc123def456...',
  };

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      setState(() {
        _user = user;
        _isAuthorized = _adminUids.isEmpty || _adminUids.contains(user.uid);
        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _signIn() async {
    setState(() => _isLoading = true);
    try {
      final provider = GoogleAuthProvider();
      await FirebaseAuth.instance.signInWithPopup(provider);
      await _checkAuth();
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('로그인 실패: $e'), backgroundColor: VerifyTheme.accentRed),
        );
      }
    }
  }

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
    setState(() {
      _user = null;
      _isAuthorized = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_user == null) {
      return _buildLoginView();
    }

    if (!_isAuthorized) {
      return _buildUnauthorizedView();
    }

    return _buildAdminPanel();
  }

  Widget _buildLoginView() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('관리자 로그인'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pushReplacementNamed(context, '/'),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.admin_panel_settings, size: 48, color: VerifyTheme.accentPrimary),
                  const SizedBox(height: 16),
                  const Text('관리자 인증', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('Google 계정으로 로그인하세요.', style: TextStyle(color: VerifyTheme.textSecondary)),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: _signIn,
                    icon: const Icon(Icons.login),
                    label: const Text('Google 로그인'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUnauthorizedView() {
    return Scaffold(
      appBar: AppBar(title: const Text('접근 거부')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.block, size: 48, color: VerifyTheme.accentRed),
            const SizedBox(height: 16),
            Text('${_user?.email}', style: const TextStyle(color: VerifyTheme.textSecondary)),
            const SizedBox(height: 8),
            const Text('관리자 권한이 없는 계정입니다.'),
            const SizedBox(height: 24),
            ElevatedButton(onPressed: _signOut, child: const Text('다른 계정으로 로그인')),
          ],
        ),
      ),
    );
  }

  Widget _buildAdminPanel() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('⚙️ 검증기 관리 패널'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              onPressed: _signOut,
              icon: const Icon(Icons.logout, size: 16, color: VerifyTheme.textSecondary),
              label: Text(_user?.email ?? '', style: const TextStyle(color: VerifyTheme.textSecondary, fontSize: 12)),
            ),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              _buildAddCodeSection(),
              const SizedBox(height: 24),
              _buildCodeListSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAddCodeSection() {
    final firmNameController = TextEditingController();
    final codeController = TextEditingController();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('새 접근코드 발급', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: codeController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(labelText: '코드 (예: CODE-001)'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: firmNameController,
                    decoration: const InputDecoration(labelText: '노무법인명'),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: () async {
                    final code = codeController.text.trim().toUpperCase();
                    final name = firmNameController.text.trim();
                    if (code.isEmpty || name.isEmpty) return;

                    await FirebaseFirestore.instance
                        .collection('verify_access')
                        .doc(code)
                        .set({
                      'firmName': name,
                      'enabled': true,
                      'createdAt': FieldValue.serverTimestamp(),
                      'createdBy': _user?.email ?? '',
                    });

                    codeController.clear();
                    firmNameController.clear();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('코드가 발급되었습니다.'), backgroundColor: VerifyTheme.accentGreen),
                      );
                    }
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('발급'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCodeListSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('발급된 코드 목록', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('verify_access')
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(
                      child: Text('발급된 코드가 없습니다.', style: TextStyle(color: VerifyTheme.textSecondary)),
                    ),
                  );
                }

                return DataTable(
                  columns: const [
                    DataColumn(label: Text('코드')),
                    DataColumn(label: Text('노무법인')),
                    DataColumn(label: Text('상태')),
                    DataColumn(label: Text('생성일')),
                    DataColumn(label: Text('관리')),
                  ],
                  rows: docs.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final enabled = data['enabled'] as bool? ?? false;
                    final createdAt = data['createdAt'] as Timestamp?;

                    return DataRow(cells: [
                      DataCell(Text(
                        doc.id,
                        style: const TextStyle(fontWeight: FontWeight.w600, letterSpacing: 1),
                      )),
                      DataCell(Text(data['firmName'] ?? '')),
                      DataCell(
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: enabled
                                ? VerifyTheme.accentGreen.withValues(alpha: 0.15)
                                : VerifyTheme.accentRed.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            enabled ? '활성' : '차단',
                            style: TextStyle(
                              color: enabled ? VerifyTheme.accentGreen : VerifyTheme.accentRed,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      DataCell(Text(
                        createdAt != null
                            ? '${createdAt.toDate().year}-${createdAt.toDate().month.toString().padLeft(2, '0')}-${createdAt.toDate().day.toString().padLeft(2, '0')}'
                            : '-',
                        style: const TextStyle(color: VerifyTheme.textSecondary, fontSize: 13),
                      )),
                      DataCell(
                        TextButton(
                          onPressed: () {
                            FirebaseFirestore.instance
                                .collection('verify_access')
                                .doc(doc.id)
                                .update({'enabled': !enabled});
                          },
                          child: Text(
                            enabled ? '차단' : '활성화',
                            style: TextStyle(
                              color: enabled ? VerifyTheme.accentOrange : VerifyTheme.accentGreen,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ]);
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
