import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_logic/shared_logic.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../models/store_info.dart';

/// SharedPreferences 키 상수
class _DraftKeys {
  static const completed = 'store_onboarding_completed';
  static const name = 'store_draft_name';
  static const owner = 'store_draft_owner';
  static const phone = 'store_draft_phone';
  static const address = 'store_draft_address';
  static const isFiveOrMore = 'store_draft_five_or_more'; // '0','1','' 저장
  static const startDay = 'store_draft_start_day';
  static const endDay = 'store_draft_end_day';
  static const payday = 'store_draft_payday';
}

/// 온보딩 완료 여부 확인 (main.dart에서 호출)
Future<bool> isStoreOnboardingCompleted() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_DraftKeys.completed) ?? false;
}

/// Draft 전체 삭제
Future<void> clearStoreDraft() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_DraftKeys.name);
  await prefs.remove(_DraftKeys.owner);
  await prefs.remove(_DraftKeys.phone);
  await prefs.remove(_DraftKeys.address);
  await prefs.remove(_DraftKeys.isFiveOrMore);
  await prefs.remove(_DraftKeys.startDay);
  await prefs.remove(_DraftKeys.endDay);
  await prefs.remove(_DraftKeys.payday);
}

class StoreSetupScreen extends StatefulWidget {
  const StoreSetupScreen({super.key});

  @override
  State<StoreSetupScreen> createState() => _StoreSetupScreenState();
}

class _StoreSetupScreenState extends State<StoreSetupScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  final int _totalPages = 6;

  // Form Controllers
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _repNameController = TextEditingController();
  final _repPhoneController = TextEditingController();
  final _startDayController = TextEditingController(text: '16');
  final _endDayController = TextEditingController(text: '15');
  final _paydayController = TextEditingController(text: '10');

  bool? _isFiveOrMore;

  final _dbService = DatabaseService();
  bool _isLoading = false;
  final _db = FirebaseFirestore.instance;

  // Focus Nodes
  final _nameFocus = FocusNode();
  final _addressFocus = FocusNode();
  final _repNameFocus = FocusNode();
  final _repPhoneFocus = FocusNode();
  final _startDayFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    // 각 컨트롤러 변경 시 자동 draft 저장
    _nameController.addListener(_autoDraft);
    _addressController.addListener(_autoDraft);
    _repNameController.addListener(_autoDraft);
    _repPhoneController.addListener(_autoDraft);
    _startDayController.addListener(_autoDraft);
    _endDayController.addListener(_autoDraft);
    _paydayController.addListener(_autoDraft);

    // 진입 시 draft 확인
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkDraftOnEntry());
  }

  @override
  void dispose() {
    _nameController.removeListener(_autoDraft);
    _addressController.removeListener(_autoDraft);
    _repNameController.removeListener(_autoDraft);
    _repPhoneController.removeListener(_autoDraft);
    _startDayController.removeListener(_autoDraft);
    _endDayController.removeListener(_autoDraft);
    _paydayController.removeListener(_autoDraft);

    _pageController.dispose();
    _nameController.dispose();
    _addressController.dispose();
    _repNameController.dispose();
    _repPhoneController.dispose();
    _startDayController.dispose();
    _endDayController.dispose();
    _paydayController.dispose();
    _nameFocus.dispose();
    _addressFocus.dispose();
    _repNameFocus.dispose();
    _repPhoneFocus.dispose();
    _startDayFocus.dispose();
    super.dispose();
  }

  // ── Draft 자동 저장 ──
  Future<void> _autoDraft() async {
    if (!_hasAnyInput()) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_DraftKeys.name, _nameController.text.trim());
    await prefs.setString(_DraftKeys.owner, _repNameController.text.trim());
    await prefs.setString(_DraftKeys.phone, _repPhoneController.text.trim());
    await prefs.setString(_DraftKeys.address, _addressController.text.trim());
    if (_isFiveOrMore != null) {
      await prefs.setString(_DraftKeys.isFiveOrMore, _isFiveOrMore! ? '1' : '0');
    }
    await prefs.setString(_DraftKeys.startDay, _startDayController.text.trim());
    await prefs.setString(_DraftKeys.endDay, _endDayController.text.trim());
    await prefs.setString(_DraftKeys.payday, _paydayController.text.trim());
  }

  bool _hasAnyInput() {
    return _nameController.text.trim().isNotEmpty ||
        _repNameController.text.trim().isNotEmpty ||
        _repPhoneController.text.trim().isNotEmpty ||
        _addressController.text.trim().isNotEmpty;
  }

  // ── 진입 시 draft 확인 다이얼로그 ──
  Future<void> _checkDraftOnEntry() async {
    final prefs = await SharedPreferences.getInstance();
    final draftName = prefs.getString(_DraftKeys.name) ?? '';
    if (draftName.isEmpty) return;

    if (!mounted) return;
    final resume = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.edit_note, color: Color(0xFF1a6ebd)),
            SizedBox(width: 8),
            Text('이어서 입력할까요?'),
          ],
        ),
        content: Text(
          '이전에 입력하던 사업장 정보가 있어요.\n($draftName)\n\n이어서 입력하시겠습니까?',
          style: const TextStyle(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('새로 시작', style: TextStyle(color: Colors.grey)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('이어서 입력'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (resume == true) {
      _restoreDraft(prefs);
    } else {
      await clearStoreDraft();
    }
  }

  // ── Draft 복원 ──
  void _restoreDraft(SharedPreferences prefs) {
    final name = prefs.getString(_DraftKeys.name) ?? '';
    final owner = prefs.getString(_DraftKeys.owner) ?? '';
    final phone = prefs.getString(_DraftKeys.phone) ?? '';
    final address = prefs.getString(_DraftKeys.address) ?? '';
    final fiveStr = prefs.getString(_DraftKeys.isFiveOrMore) ?? '';
    final startDay = prefs.getString(_DraftKeys.startDay) ?? '16';
    final endDay = prefs.getString(_DraftKeys.endDay) ?? '15';
    final payday = prefs.getString(_DraftKeys.payday) ?? '10';

    setState(() {
      _nameController.text = name;
      _repNameController.text = owner;
      _repPhoneController.text = phone;
      _addressController.text = address;
      if (fiveStr == '1') _isFiveOrMore = true;
      if (fiveStr == '0') _isFiveOrMore = false;
      _startDayController.text = startDay.isEmpty ? '16' : startDay;
      _endDayController.text = endDay.isEmpty ? '15' : endDay;
      _paydayController.text = payday.isEmpty ? '10' : payday;
    });
  }

  // ── 뒤로가기 핸들러 ──
  Future<void> _prevPage() async {
    FocusScope.of(context).unfocus();
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      // 첫 페이지에서 뒤로가기: draft 저장 후 나가기
      if (_hasAnyInput()) {
        await _autoDraft();
      }
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<bool> _onWillPop() async {
    if (_currentPage > 0) {
      _prevPage();
      return false;
    }
    if (_hasAnyInput()) await _autoDraft();
    return true;
  }

  // ── 다음 페이지 ──
  void _nextPage() {
    FocusScope.of(context).unfocus();
    if (_currentPage < _totalPages - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      Future.delayed(const Duration(milliseconds: 300), () {
        if (!mounted) return;
        switch (_currentPage) {
          case 1: _nameFocus.requestFocus(); break;
          case 2: _addressFocus.requestFocus(); break;
          case 3: _repNameFocus.requestFocus(); break;
          case 4: _repPhoneFocus.requestFocus(); break;
          case 5: _startDayFocus.requestFocus(); break;
        }
      });
    } else {
      _handleSave();
    }
  }

  bool _isNextEnabled() {
    switch (_currentPage) {
      case 0: return _isFiveOrMore != null;
      case 1: return _nameController.text.trim().isNotEmpty;
      case 2: return _addressController.text.trim().isNotEmpty;
      case 3: return _repNameController.text.trim().isNotEmpty;
      case 4:
        final digits = _repPhoneController.text.replaceAll(RegExp(r'[^0-9]'), '');
        return digits.length >= 10;
      case 5:
        final s = int.tryParse(_startDayController.text.trim());
        final e = int.tryParse(_endDayController.text.trim());
        final p = int.tryParse(_paydayController.text.trim());
        return s != null && s >= 1 && s <= 31 &&
               e != null && e >= 1 && e <= 31 &&
               p != null && p >= 1 && p <= 31;
      default: return false;
    }
  }

  // ── 최종 저장 ──
  Future<void> _handleSave() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isLoading = true);

    try {
      final name = _nameController.text.trim();
      final repName = _repNameController.text.trim();
      final repPhoneDigits = _repPhoneController.text.replaceAll(RegExp(r'[^0-9]'), '');
      final address = _addressController.text.trim();
      final startDay = int.parse(_startDayController.text.trim());
      final endDay = int.parse(_endDayController.text.trim());
      final payday = int.parse(_paydayController.text.trim());

      final storeId = const Uuid().v4();
      final store = Store(
        id: storeId,
        name: name,
        ownerId: user.uid,
        representativeName: repName,
        representativePhoneNumber: repPhoneDigits,
        address: address,
        latitude: 37.5665,
        longitude: 126.9780,
        settlementStartDay: startDay,
        settlementEndDay: endDay,
        payday: payday,
        isFiveOrMore: _isFiveOrMore ?? false,
      );

      await _dbService.createStore(store);
      await _db.collection('users').doc(user.uid).set(
        {'storeId': storeId},
        SetOptions(merge: true),
      );

      final box = Hive.box<StoreInfo>('store');
      await box.put(
        'current',
        StoreInfo(
          storeName: name,
          ownerName: repName,
          phone: repPhoneDigits,
          address: address,
          payDay: payday,
          payPeriodStartDay: startDay,
          payPeriodEndDay: endDay,
          isRegistered: true,
          isFiveOrMore: _isFiveOrMore ?? false,
        ),
      );

      // ── 온보딩 완료 플래그 기록 + draft 삭제 ──
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_DraftKeys.completed, true);
      await clearStoreDraft();

      // OnboardingGuideService 완료 처리
      OnboardingGuideService.instance.completeStep(OnboardingStep.storeSetup);

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('매장 등록 실패: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildTitle(String text, {String? subtitle}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, height: 1.4),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          Text(subtitle, style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
        ],
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildSelectionCard({
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFEBF3FF) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? const Color(0xFF1a6ebd) : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [BoxShadow(color: const Color(0xFF1a6ebd).withValues(alpha: 0.1), blurRadius: 8, offset: const Offset(0, 2))]
              : [],
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? const Color(0xFF1a6ebd) : Colors.black87,
                ),
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle, color: Color(0xFF1a6ebd), size: 22),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _currentPage == 0,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) _prevPage();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF2F2F7),
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _prevPage,
          ),
          title: const Text(
            '사업장 등록',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(4),
            child: LinearProgressIndicator(
              value: (_currentPage + 1) / _totalPages,
              backgroundColor: Colors.grey.shade200,
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF1a6ebd)),
              minHeight: 4,
            ),
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              // 진행 단계 텍스트
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${_currentPage + 1} / $_totalPages',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                    ),
                    if (_currentPage > 0)
                      GestureDetector(
                        onTap: () async {
                          // draft 저장 후 나가기 (나중에 입력)
                          await _autoDraft();
                          if (mounted) Navigator.of(context).pop();
                        },
                        child: Text(
                          '나중에 입력',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade500,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (index) => setState(() => _currentPage = index),
                  children: [
                    // Page 0: 5인 이상 여부
                    Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildTitle(
                            '가장 먼저,\n상시 근로자가 5인 이상인가요?',
                            subtitle: '연장·야간·휴일근로 가산수당 등 법정 수당 계산 방식에 반영됩니다.',
                          ),
                          _buildSelectionCard(
                            title: '예 (5인 이상)',
                            isSelected: _isFiveOrMore == true,
                            onTap: () {
                              setState(() => _isFiveOrMore = true);
                              _autoDraft();
                              Future.delayed(const Duration(milliseconds: 200), _nextPage);
                            },
                          ),
                          const SizedBox(height: 12),
                          _buildSelectionCard(
                            title: '아니요 (5인 미만)',
                            isSelected: _isFiveOrMore == false,
                            onTap: () {
                              setState(() => _isFiveOrMore = false);
                              _autoDraft();
                              Future.delayed(const Duration(milliseconds: 200), _nextPage);
                            },
                          ),
                        ],
                      ),
                    ),

                    // Page 1: 매장 이름
                    Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildTitle('사업장(매장)의\n이름을 알려주세요.'),
                          TextField(
                            controller: _nameController,
                            focusNode: _nameFocus,
                            style: const TextStyle(fontSize: 20),
                            decoration: const InputDecoration(
                              hintText: '예: 정석 카페',
                              border: UnderlineInputBorder(),
                            ),
                            onChanged: (_) => setState(() {}),
                            onSubmitted: (_) { if (_isNextEnabled()) _nextPage(); },
                          ),
                        ],
                      ),
                    ),

                    // Page 2: 매장 주소
                    Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildTitle('사업장의 주소를\n입력해주세요.'),
                          TextField(
                            controller: _addressController,
                            focusNode: _addressFocus,
                            style: const TextStyle(fontSize: 20),
                            decoration: const InputDecoration(
                              hintText: '전체 주소 입력',
                              border: UnderlineInputBorder(),
                            ),
                            onChanged: (_) => setState(() {}),
                            onSubmitted: (_) { if (_isNextEnabled()) _nextPage(); },
                          ),
                        ],
                      ),
                    ),

                    // Page 3: 대표자 이름
                    Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildTitle('대표자 성함을\n입력해주세요.'),
                          TextField(
                            controller: _repNameController,
                            focusNode: _repNameFocus,
                            style: const TextStyle(fontSize: 20),
                            decoration: const InputDecoration(
                              hintText: '대표자 본명',
                              border: UnderlineInputBorder(),
                            ),
                            onChanged: (_) => setState(() {}),
                            onSubmitted: (_) { if (_isNextEnabled()) _nextPage(); },
                          ),
                        ],
                      ),
                    ),

                    // Page 4: 대표자 연락처
                    Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildTitle(
                            '대표자 연락처를\n입력해주세요.',
                            subtitle: '주요 알림이나 안내를 위해 사용됩니다.',
                          ),
                          TextField(
                            controller: _repPhoneController,
                            focusNode: _repPhoneFocus,
                            keyboardType: TextInputType.phone,
                            style: const TextStyle(fontSize: 20),
                            decoration: const InputDecoration(
                              hintText: '예: 010-1234-5678',
                              border: UnderlineInputBorder(),
                            ),
                            onChanged: (_) => setState(() {}),
                            onSubmitted: (_) { if (_isNextEnabled()) _nextPage(); },
                          ),
                        ],
                      ),
                    ),

                    // Page 5: 정산 기간 및 급여일
                    SingleChildScrollView(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildTitle(
                            '정산 기간 및 급여일을\n설정해주세요.',
                            subtitle: '나중에 사업장 설정에서 언제든지 변경할 수 있어요.',
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _startDayController,
                                  focusNode: _startDayFocus,
                                  keyboardType: TextInputType.number,
                                  style: const TextStyle(fontSize: 20),
                                  decoration: const InputDecoration(
                                    labelText: '정산 시작일',
                                    suffixText: '일',
                                  ),
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 16),
                                child: Text('~', style: TextStyle(fontSize: 20)),
                              ),
                              Expanded(
                                child: TextField(
                                  controller: _endDayController,
                                  keyboardType: TextInputType.number,
                                  style: const TextStyle(fontSize: 20),
                                  decoration: const InputDecoration(
                                    labelText: '정산 종료일',
                                    suffixText: '일',
                                  ),
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          TextField(
                            controller: _paydayController,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(fontSize: 20),
                            decoration: const InputDecoration(
                              labelText: '급여 지급일',
                              suffixText: '일',
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 16),
                          // 예시 자동채우기
                          OutlinedButton.icon(
                            onPressed: () => setState(() {
                              _startDayController.text = '16';
                              _endDayController.text = '15';
                              _paydayController.text = '20';
                            }),
                            icon: const Icon(Icons.auto_fix_high, size: 16),
                            label: const Text('예시 입력: 16일~익월15일, 20일 지급'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.grey.shade600,
                              side: BorderSide(color: Colors.grey.shade300),
                            ),
                          ),
                        ],
                      ),
                    ),

                  ],
                ),
              ),

              // 하단 '다음' 버튼
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton(
                    onPressed: _isNextEnabled() && !_isLoading ? _nextPage : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF1a6ebd),
                      disabledBackgroundColor: Colors.grey.shade300,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                          )
                        : Text(
                            _currentPage == _totalPages - 1 ? '설정 완료' : '다음',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
