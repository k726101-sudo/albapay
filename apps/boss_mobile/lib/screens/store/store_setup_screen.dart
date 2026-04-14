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
  final _nameController = TextEditingController();
  final _repNameController = TextEditingController();
  final _repPhoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _startDayController = TextEditingController(text: '1');
  final _endDayController = TextEditingController(text: '31');
  final _paydayController = TextEditingController(text: '10');
  bool _isFiveOrMore = false;
  final _dbService = DatabaseService();
  bool _isLoading = false;
  final _db = FirebaseFirestore.instance;

  String? _nameError;
  String? _repNameError;
  String? _repPhoneError;
  String? _addressError;
  String? _startDayError;
  String? _endDayError;
  String? _paydayError;
  int _currentStep = 0;

  void _clearErrors() {
    _nameError = null;
    _repNameError = null;
    _repPhoneError = null;
    _addressError = null;
    _startDayError = null;
    _endDayError = null;
    _paydayError = null;
  }

  Future<void> _handleSave() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(_clearErrors);
    try {
      final name = _nameController.text.trim();
      if (name.isEmpty) {
        setState(() {
          _nameError = '필수 입력입니다.';
        });
        return;
      }

      final repName = _repNameController.text.trim();
      if (repName.isEmpty) {
        setState(() {
          _repNameError = '필수 입력입니다.';
        });
        return;
      }

      final repPhoneRaw = _repPhoneController.text.trim();
      final repPhoneDigits = repPhoneRaw.replaceAll(RegExp(r'[^0-9]'), '');
      if (repPhoneDigits.length < 10) {
        setState(() {
          _repPhoneError = '전화번호를 입력해 주세요.';
        });
        return;
      }

      final address = _addressController.text.trim();
      if (address.isEmpty) {
        setState(() {
          _addressError = '주소는 필수입니다.';
        });
        return;
      }

      final startDay = int.tryParse(_startDayController.text.trim());
      if (startDay == null || startDay < 1 || startDay > 31) {
        setState(() {
          _startDayError = '1~31 사이 숫자만 입력해 주세요.';
        });
        return;
      }

      final endDay = int.tryParse(_endDayController.text.trim());
      if (endDay == null || endDay < 1 || endDay > 31) {
        setState(() {
          _endDayError = '1~31 사이 숫자만 입력해 주세요.';
        });
        return;
      }

      final payday = int.tryParse(_paydayController.text.trim());
      if (payday == null || payday < 1 || payday > 31) {
        setState(() {
          _paydayError = '1~31 사이 숫자만 입력해 주세요.';
        });
        return;
      }

      // Passed validation
      setState(() {
        _clearErrors();
        _isLoading = true;
      });

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
        isFiveOrMore: _isFiveOrMore,
      );

      await _dbService.createStore(store);
      // Map "one owner account -> one store" via users/{uid}.storeId
      await _db.collection('users').doc(user.uid).set(
        {'storeId': store.id},
        SetOptions(merge: true),
      );

      // 대시보드·설정 탭은 Hive StoreInfo를 봅니다. Firestore와 맞춰 둡니다.
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('사업장 초기 설정')),
      body: Stepper(
        type: StepperType.vertical,
        currentStep: _currentStep,
        onStepTapped: (v) => setState(() => _currentStep = v),
        controlsBuilder: (context, details) {
          final isLast = _currentStep == 2;
          return Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _isLoading
                        ? null
                        : () async {
                            if (isLast) {
                              await _handleSave();
                              return;
                            }
                            setState(() => _currentStep += 1);
                          },
                    child: _isLoading
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(isLast ? '설정 완료' : '다음'),
                  ),
                ),
                const SizedBox(width: 8),
                if (_currentStep > 0)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isLoading
                          ? null
                          : () => setState(() => _currentStep -= 1),
                      child: const Text('이전'),
                    ),
                  ),
              ],
            ),
          );
        },
        steps: [
          Step(
            isActive: _currentStep >= 0,
            title: const Text('기본 정보'),
            content: Column(
              children: [
                TextField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: '매장 이름',
                    hintText: '예: 정석 카페',
                    errorText: _nameError,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _addressController,
                  decoration: InputDecoration(
                    labelText: '주소',
                    errorText: _addressError,
                  ),
                ),
              ],
            ),
          ),
          Step(
            isActive: _currentStep >= 1,
            title: const Text('대표자 정보'),
            content: Column(
              children: [
                TextField(
                  controller: _repNameController,
                  decoration: InputDecoration(
                    labelText: '대표자 이름',
                    errorText: _repNameError,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _repPhoneController,
                  decoration: InputDecoration(
                    labelText: '대표자 전화번호',
                    hintText: '예: 010-1234-5678',
                    errorText: _repPhoneError,
                  ),
                  keyboardType: TextInputType.phone,
                ),
              ],
            ),
          ),
          Step(
            isActive: _currentStep >= 2,
            title: const Text('정산/정책'),
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _startDayController,
                        decoration: InputDecoration(
                          labelText: '정산 시작일',
                          suffixText: '일',
                          errorText: _startDayError,
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text('~'),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _endDayController,
                        decoration: InputDecoration(
                          labelText: '정산 종료일',
                          suffixText: '일',
                          errorText: _endDayError,
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '종료일이 시작일보다 작으면 다음 달로 넘어갑니다. (예: 3/16~4/15)',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _paydayController,
                  decoration: InputDecoration(
                    labelText: '급여 지급일',
                    suffixText: '일',
                    errorText: _paydayError,
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _startDayController.text = '16';
                        _endDayController.text = '15';
                        _paydayController.text = '20';
                        _clearErrors();
                      });
                    },
                    icon: const Icon(Icons.auto_fix_high),
                    label: const Text('예시 입력: 3/16~4/15, 매월 20일'),
                  ),
                ),
                SwitchListTile(
                  title: const Text('상시 근로자 5인 이상 사업장'),
                  subtitle: const Text('법정 수당 계산 방식에 반영됩니다.'),
                  value: _isFiveOrMore,
                  onChanged: (val) => setState(() => _isFiveOrMore = val),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
