import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_logic/shared_logic.dart';
import 'package:uuid/uuid.dart';

import '../../models/store_info.dart';

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
  final _startDayController = TextEditingController(text: '1');
  final _endDayController = TextEditingController(text: '31');
  final _paydayController = TextEditingController(text: '10');
  
  bool? _isFiveOrMore; // null means not selected yet
  
  final _dbService = DatabaseService();
  bool _isLoading = false;
  final _db = FirebaseFirestore.instance;

  // Focus Nodes for auto-focus
  final _nameFocus = FocusNode();
  final _addressFocus = FocusNode();
  final _repNameFocus = FocusNode();
  final _repPhoneFocus = FocusNode();
  final _startDayFocus = FocusNode();

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
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

  void _nextPage() {
    FocusScope.of(context).unfocus(); // dismiss keyboard before sliding
    if (_currentPage < _totalPages - 1) {
      _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
      // Auto focus logic
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

  void _prevPage() {
    FocusScope.of(context).unfocus();
    if (_currentPage > 0) {
      _pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    } else {
      Navigator.of(context).pop();
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
        return s != null && s >= 1 && s <= 31 && e != null && e >= 1 && e <= 31 && p != null && p >= 1 && p <= 31;
      default: return false;
    }
  }

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

      final store = Store(
        id: const Uuid().v4(),
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
        {'storeId': store.id},
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
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('매장 등록 실패: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildTitle(String text, {String? subtitle}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, height: 1.4)),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          Text(subtitle, style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
        ],
        const SizedBox(height: 32),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_currentPage > 0) {
          _prevPage();
          return false;
        }
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _prevPage,
          ),
          title: const Text('사업장 등록'),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(4),
            child: LinearProgressIndicator(
              value: (_currentPage + 1) / _totalPages,
              backgroundColor: Colors.grey.shade200,
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.blueAccent),
            ),
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(), // Disable swipe
                  onPageChanged: (index) {
                    setState(() {
                      _currentPage = index;
                    });
                  },
                  children: [
                    // Page 0: 5인 이상 여부
                    Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildTitle('가장 먼저,\n상시 근로자가 5인 이상인가요?', subtitle: '연장·야간·휴일근로 가산수당 등 법정 수당 계산 방식에 반영됩니다.'),
                          _buildSelectionCard(
                            title: '예 (5인 이상)',
                            isSelected: _isFiveOrMore == true,
                            onTap: () {
                              setState(() => _isFiveOrMore = true);
                              Future.delayed(const Duration(milliseconds: 200), _nextPage);
                            },
                          ),
                          const SizedBox(height: 12),
                          _buildSelectionCard(
                            title: '아니요 (5인 미만)',
                            isSelected: _isFiveOrMore == false,
                            onTap: () {
                              setState(() => _isFiveOrMore = false);
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
                            onSubmitted: (_) {
                              if (_isNextEnabled()) _nextPage();
                            },
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
                            onSubmitted: (_) {
                              if (_isNextEnabled()) _nextPage();
                            },
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
                            onSubmitted: (_) {
                              if (_isNextEnabled()) _nextPage();
                            },
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
                          _buildTitle('대표자 연락처를\n입력해주세요.', subtitle: '주요 알림이나 안내를 위해 사용됩니다.'),
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
                            onSubmitted: (_) {
                              if (_isNextEnabled()) _nextPage();
                            },
                          ),
                        ],
                      ),
                    ),

                    // Page 5: 정산 기간 및 급여일
                    Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildTitle('정산 기간 및 급여일을\n설정해주세요.', subtitle: '종료일이 시작일보다 작으면 자동으로 다음 달로 계산됩니다.'),
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
                          const SizedBox(height: 24),
                          TextButton.icon(
                            onPressed: () {
                              setState(() {
                                _startDayController.text = '16';
                                _endDayController.text = '15';
                                _paydayController.text = '20';
                              });
                            },
                            icon: const Icon(Icons.auto_fix_high),
                            label: const Text('예시 입력: 16일 ~ 익월 15일 정산, 20일 지급'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              
              // Bottom Next Button
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton(
                    onPressed: _isNextEnabled() && !_isLoading ? _nextPage : null,
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text(
                            _currentPage == _totalPages - 1 ? '설정 완료' : '다음',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSelectionCard({required String title, required bool isSelected, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue.shade50 : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? Colors.blueAccent : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? Colors.blueAccent : Colors.black87,
          ),
        ),
      ),
    );
  }
}

