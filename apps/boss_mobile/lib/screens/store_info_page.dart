import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_logic/shared_logic.dart';
import 'package:uuid/uuid.dart';

import '../models/store_info.dart';
import '../models/worker.dart';
import '../services/boss_logout.dart';

const Map<String, Map<String, dynamic>> businessTypes = {
  'food': {
    'label': '음식·숙박업',
    'desc': '식당, 카페, 베이커리, 편의점',
    'rate': 0.009,
  },
  'retail': {
    'label': '도소매업',
    'desc': '일반 소매점, 마트',
    'rate': 0.0079,
  },
  'office': {
    'label': '사무·서비스업',
    'desc': '사무직, IT, 학원',
    'rate': 0.006,
  },
  'beauty': {
    'label': '미용·세탁업',
    'desc': '미용실, 세탁소',
    'rate': 0.0081,
  },
  'manufacturing': {
    'label': '제조업',
    'desc': '공장, 생산직',
    'rate': 0.0112,
  },
  'etc': {
    'label': '기타',
    'desc': '위에 해당 없음',
    'rate': 0.0147,
  },
};

/// 설정 탭에서 출퇴근·급여 항목 눌렀을 때 해당 구역으로 스크롤
enum StoreInfoPageFocus {
  commute,
  payroll,
}

class StoreInfoPage extends StatefulWidget {
  const StoreInfoPage({
    super.key,
    this.isOnboarding = false,
    this.initialFocus,
  });

  final bool isOnboarding;
  final StoreInfoPageFocus? initialFocus;

  @override
  State<StoreInfoPage> createState() => _StoreInfoPageState();
}

class _StoreInfoPageState extends State<StoreInfoPage> {
  final GlobalKey _commuteSectionKey = GlobalKey();
  final GlobalKey _payrollSectionKey = GlobalKey();

  final _storeNameController = TextEditingController();
  final _ownerNameController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  final _bizNumberController = TextEditingController();
  final _gracePeriodController = TextEditingController(text: '5');
  final _branchCodeController = TextEditingController();

  bool _showBranchCode = false;

  String _selectedType = 'food';
  double _accidentRate = 0.009;
  bool _useQr = true;
  int _payDay = 10;
  int _payPeriodStartDay = 16;
  int _payPeriodEndDay = 15;
  bool _isDuruNuri = false;
  int _duruNuriMonths = 36;
  bool _isFiveOrMore = false;
  bool _isFiveOrMoreCalculatedValue = false;
  String _isFiveOrMoreChangeReason = '';

  @override
  void initState() {
    super.initState();
    final store = Hive.box<StoreInfo>('store').get('current');
    if (store != null) {
      _storeNameController.text = store.storeName;
      _ownerNameController.text = store.ownerName;
      _phoneController.text = store.phone;
      _addressController.text = store.address;
      _bizNumberController.text = store.businessNumber;
      _selectedType = store.businessType;
      _accidentRate = store.accidentRate;
      _useQr = store.useQr;
      _payDay = store.payDay;
      _payPeriodStartDay = store.payPeriodStartDay;
      _payPeriodEndDay = store.payPeriodEndDay;
      _isDuruNuri = store.isDuruNuri;
      _duruNuriMonths = store.duruNuriMonths;
      _gracePeriodController.text = store.attendanceGracePeriodMinutes.toString();
      _isFiveOrMore = store.isFiveOrMore;
      _isFiveOrMoreCalculatedValue = store.isFiveOrMoreCalculatedValue;
      _isFiveOrMoreChangeReason = store.isFiveOrMoreChangeReason;
      _branchCodeController.text = store.branchCode;
    }

    _storeNameController.addListener(_onStoreNameChanged);
    _onStoreNameChanged();

    // Calculate the current estimate based on active workers
    final workers = Hive.box<Worker>('workers').values.where((w) => w.status == 'active').toList();
    _isFiveOrMoreCalculatedValue = workers.length >= 5;

    final focus = widget.initialFocus;
    if (focus != null && !widget.isOnboarding) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scrollToFocus(focus);
      });
    }
  }

  void _scrollToFocus(StoreInfoPageFocus focus) {
    final key = focus == StoreInfoPageFocus.commute
        ? _commuteSectionKey
        : _payrollSectionKey;
    final ctx = key.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeInOutCubic,
        alignment: 0.08,
      );
    }
  }

  void _onStoreNameChanged() {
    final hasParis = _storeNameController.text.contains('파리바게뜨');
    if (_showBranchCode != hasParis) {
      setState(() => _showBranchCode = hasParis);
    }
  }

  @override
  void dispose() {
    _storeNameController.removeListener(_onStoreNameChanged);
    _storeNameController.dispose();
    _ownerNameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _bizNumberController.dispose();
    _gracePeriodController.dispose();
    _branchCodeController.dispose();
    super.dispose();
  }

  Future<void> _showRiskPreventionDialog(bool newValue) async {
    final controller = TextEditingController(text: _isFiveOrMoreChangeReason);
    final isMismatch = newValue != _isFiveOrMoreCalculatedValue;

    if (!isMismatch) {
      setState(() {
        _isFiveOrMore = newValue;
        _isFiveOrMoreChangeReason = ''; // Clear reason if it matches calculation
      });
      return;
    }

    // If mismatch, ask for reason
    final reason = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Color(0xFFE24B4A)),
            const SizedBox(width: 8),
            Text(newValue ? '5인 이상 설정' : '5인 미만 설정'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              newValue
                  ? '현재 등록된 직원이 5명 미만이지만 5인 이상 사업장으로 설정하시겠습니까?'
                  : '현재 등록된 직원이 5명 이상이지만 5인 미만 사업장으로 설정하시겠습니까?',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            const Text(
              '변경 사유를 간략히 입력해 주세요. (예: "가족 2명 제외로 실제 5인 미만임")',
              style: TextStyle(fontSize: 12, color: Color(0xFF888888)),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: '사유를 입력하세요',
                hintStyle: TextStyle(fontSize: 13),
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isEmpty) return;
              Navigator.pop(ctx, controller.text.trim());
            },
            child: const Text('저장'),
          ),
        ],
      ),
    );

    if (reason != null) {
      setState(() {
        _isFiveOrMore = newValue;
        _isFiveOrMoreChangeReason = reason;
      });
    }
  }

  Future<void> _saveStoreInfo() async {
    if (_storeNameController.text.trim().isEmpty ||
        _ownerNameController.text.trim().isEmpty ||
        _phoneController.text.trim().isEmpty ||
        _addressController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('필수 항목을 모두 입력해주세요'),
          backgroundColor: Color(0xFFE24B4A),
        ),
      );
      return;
    }

    final store = StoreInfo(
      storeName: _storeNameController.text.trim(),
      ownerName: _ownerNameController.text.trim(),
      address: _addressController.text.trim(),
      phone: _phoneController.text.trim(),
      businessNumber: _bizNumberController.text.trim(),
      businessType: _selectedType,
      accidentRate: _accidentRate,
      legacyGpsRadiusUnused: 0,
      useQr: _useQr,
      payDay: _payDay,
      payPeriodStartDay: _payPeriodStartDay,
      payPeriodEndDay: _payPeriodEndDay,
      isDuruNuri: _isDuruNuri,
      duruNuriMonths: _duruNuriMonths,
      isRegistered: true,
      attendanceGracePeriodMinutes: int.tryParse(_gracePeriodController.text.trim()) ?? 5,
      isFiveOrMore: _isFiveOrMore,
      isFiveOrMoreCalculatedValue: _isFiveOrMoreCalculatedValue,
      isFiveOrMoreChangeReason: _isFiveOrMoreChangeReason,
      branchCode: _showBranchCode ? _branchCodeController.text.trim() : '',
    );

    final box = Hive.box<StoreInfo>('store');
    await box.put('current', store);

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        final sid = (userDoc.data()?['storeId'] as String?)?.trim();
        final phoneDigits = _phoneController.text.replaceAll(RegExp(r'[^0-9]'), '');

        var targetStoreId = sid;
        if (targetStoreId == null || targetStoreId.isEmpty) {
          targetStoreId = const Uuid().v4();
          final newStore = Store(
            id: targetStoreId,
            name: store.storeName,
            ownerId: user.uid,
            representativeName: store.ownerName,
            representativePhoneNumber:
                phoneDigits.isNotEmpty ? phoneDigits : _phoneController.text.trim(),
            address: store.address,
            latitude: 37.5665,
            longitude: 126.9780,
            settlementStartDay: store.payPeriodStartDay,
            settlementEndDay: store.payPeriodEndDay,
            payday: store.payDay,
            isFiveOrMore: _isFiveOrMore,
            attendanceGracePeriodMinutes: store.attendanceGracePeriodMinutes,
            branchCode: store.branchCode,
          );
          await DatabaseService().createStore(newStore);
          await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
            {'storeId': targetStoreId},
            SetOptions(merge: true),
          );
        }

        await DatabaseService().mergeStoreDocument(targetStoreId, {
          'name': store.storeName,
          'representativeName': store.ownerName,
          'representativePhoneNumber':
              phoneDigits.isNotEmpty ? phoneDigits : _phoneController.text.trim(),
          'address': store.address,
          'settlementStartDay': store.payPeriodStartDay,
          'settlementEndDay': store.payPeriodEndDay,
          'payday': store.payDay,
          'businessNumber': store.businessNumber,
          'businessType': store.businessType,
          'accidentRate': store.accidentRate,
          'useQr': store.useQr,
          'isDuruNuri': store.isDuruNuri,
          'duruNuriMonths': store.duruNuriMonths,
          'isFiveOrMore': _isFiveOrMore,
          'isFiveOrMore_ManualValue': _isFiveOrMore,
          'isFiveOrMore_CalculatedValue': _isFiveOrMoreCalculatedValue,
          'isFiveOrMore_ChangeReason': _isFiveOrMoreChangeReason,
          'attendanceGracePeriodMinutes': store.attendanceGracePeriodMinutes,
          if (store.branchCode.isNotEmpty) 'branchCode': store.branchCode,
        });
      } catch (e) {
        if (!mounted) return;
        final detail = e is FirebaseException
            ? '${e.code}: ${e.message ?? e.toString()}'
            : e.toString();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is FirebaseException && e.code == 'permission-denied'
                  ? '클라우드 저장이 거부되었습니다(permission-denied). Firebase 콘솔 → Firestore → 규칙에서 '
                      'users 본인 문서와 stores/{매장ID} 문서 쓰기를 허용했는지 확인해 주세요. ($detail)'
                  : '로컬 저장은 되었으나 클라우드 동기화 실패: $detail',
            ),
            backgroundColor: const Color(0xFFE24B4A),
          ),
        );
        return;
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('사업장 정보가 저장되었습니다'),
        backgroundColor: Color(0xFF286b3a),
      ),
    );
    // 온보딩: 사업장 등록 완료
    OnboardingGuideService.instance.completeStep(OnboardingStep.storeSetup);
    if (!widget.isOnboarding) {
      Navigator.pop(context);
    }
  }

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('로그아웃'),
        content: const Text(
          '로그아웃하면 로그인 화면으로 돌아갑니다.\n'
          '사업장 등록을 나중에 하려면 여기서 나가도 됩니다.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('로그아웃', style: TextStyle(color: Color(0xFFE24B4A))),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await performBossLogout(AuthService());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1a1a2e),
        foregroundColor: Colors.white,
        leading: widget.isOnboarding
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
        title: const Text(
          '사업장 정보',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w500,
          ),
        ),
        actions: [
          if (widget.isOnboarding)
            TextButton(
              onPressed: _confirmLogout,
              child: const Text(
                '로그아웃',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          TextButton(
            onPressed: _saveStoreInfo,
            child: const Text(
              '저장',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.isOnboarding) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F4FD),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFB8D4F0)),
                  ),
                  child: const Text(
                    '필수 정보를 입력한 뒤 「저장」하면 메인 화면으로 이동합니다. '
                    '다른 계정으로 로그인하려면 우측 상단 「로그아웃」을 눌러 주세요.',
                    style: TextStyle(fontSize: 13, height: 1.35, color: Color(0xFF1a4a7a)),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              _buildSectionLabel('기본 정보'),
              _buildInputGroup([
                _buildInputRow(
                  label: '상호명',
                  hint: '파리바게뜨 OO점',
                  controller: _storeNameController,
                  isRequired: true,
                  isLast: false,
                ),
                if (_showBranchCode)
                  _buildInputRow(
                    label: '지점 코드',
                    hint: 'PB00으로 시작 (예: PB00123)',
                    controller: _branchCodeController,
                    isRequired: false,
                    isLast: false,
                  ),
                _buildInputRow(
                  label: '대표자명',
                  hint: '홍길동',
                  controller: _ownerNameController,
                  isRequired: true,
                ),
                _buildInputRow(
                  label: '연락처',
                  hint: '010-0000-0000',
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  isRequired: true,
                ),
                _buildInputRow(
                  label: '주소',
                  hint: '서울시 OO구 OO동',
                  controller: _addressController,
                  isRequired: true,
                ),
                _buildInputRow(
                  label: '사업자등록번호',
                  hint: '000-00-00000 (선택)',
                  controller: _bizNumberController,
                  keyboardType: TextInputType.number,
                  isRequired: false,
                  isLast: true,
                ),
              ]),
              const SizedBox(height: 24),
              _buildSectionLabel('업종 선택'),
              Container(
                margin: EdgeInsets.zero,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE5E5EA), width: 0.5),
                ),
                child: Column(
                  children: businessTypes.entries.map((e) {
                    final isSelected = _selectedType == e.key;
                    final isLast = e.key == businessTypes.keys.last;
                    final rate = e.value['rate'] as double;
                    return Column(
                      children: [
                        InkWell(
                          onTap: () => setState(() {
                            _selectedType = e.key;
                            _accidentRate = rate;
                          }),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        e.value['label'] as String,
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w500,
                                          color: isSelected
                                              ? const Color(0xFF1a6ebd)
                                              : const Color(0xFF1a1a1a),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        e.value['desc'] as String,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF888888),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  '산재 ${(rate * 100).toStringAsFixed(2)}%',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF888888),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  width: 20,
                                  height: 20,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isSelected
                                          ? const Color(0xFF1a6ebd)
                                          : const Color(0xFFDDDDDD),
                                      width: 2,
                                    ),
                                    color: isSelected
                                        ? const Color(0xFF1a6ebd)
                                        : Colors.transparent,
                                  ),
                                  child: isSelected
                                      ? const Icon(Icons.check, color: Colors.white, size: 12)
                                      : null,
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (!isLast)
                          const Divider(
                            height: 1,
                            thickness: 0.5,
                            indent: 14,
                            color: Color(0xFFF0F0F0),
                          ),
                      ],
                    );
                  }).toList(),
                ),
              ),
              KeyedSubtree(
                key: _commuteSectionKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 24),
                    _buildSectionLabel('출퇴근 설정'),
                    _buildInputGroup([
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'QR 출퇴근 사용',
                                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    '매장에 QR 코드를 부착하여 출퇴근',
                                    style: TextStyle(fontSize: 12, color: Color(0xFF888888)),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: _useQr,
                              onChanged: (v) => setState(() => _useQr = v),
                              activeThumbColor: const Color(0xFF1a6ebd),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1, thickness: 0.5, indent: 14, color: Color(0xFFF0F0F0)),
                      _buildInputRow(
                        label: '지각 허용 시간',
                        hint: '예: 5',
                        controller: _gracePeriodController,
                        keyboardType: TextInputType.number,
                        isLast: false,
                      ),
                      const Padding(
                        padding: EdgeInsets.fromLTRB(14, 0, 14, 13),
                        child: Text(
                          '입력한 시간(분) 이내의 지각은 정시 출근으로 인정됩니다.',
                          style: TextStyle(fontSize: 12, color: Color(0xFF888888)),
                        ),
                      ),
                    ]),
                  ],
                ),
              ),
              KeyedSubtree(
                key: _payrollSectionKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 24),
                    _buildSectionLabel('급여 설정'),
                    _buildInputGroup([
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Text(
                                '정산 시작일',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                              ),
                            ),
                            DropdownButton<int>(
                              value: _payPeriodStartDay,
                              underline: const SizedBox(),
                              style: const TextStyle(
                                fontSize: 15,
                                color: Color(0xFF1a1a2e),
                                fontWeight: FontWeight.w500,
                              ),
                              items: List.generate(31, (i) => i + 1)
                                  .map(
                                    (d) => DropdownMenuItem<int>(
                                      value: d,
                                      child: Text('매월 $d일'),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) => setState(() => _payPeriodStartDay = v ?? 16),
                            ),
                          ],
                        ),
                      ),
                const Divider(height: 1, thickness: 0.5, indent: 14, color: Color(0xFFF0F0F0)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '정산 종료일',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                        ),
                      ),
                      DropdownButton<int>(
                        value: _payPeriodEndDay,
                        underline: const SizedBox(),
                        style: const TextStyle(
                          fontSize: 15,
                          color: Color(0xFF1a1a2e),
                          fontWeight: FontWeight.w500,
                        ),
                        items: List.generate(31, (i) => i + 1)
                            .map(
                              (d) => DropdownMenuItem<int>(
                                value: d,
                                child: Text('매월 $d일'),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => _payPeriodEndDay = v ?? 15),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, thickness: 0.5, indent: 14, color: Color(0xFFF0F0F0)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '지급일',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                        ),
                      ),
                      DropdownButton<int>(
                        value: _payDay,
                        underline: const SizedBox(),
                        style: const TextStyle(
                          fontSize: 15,
                          color: Color(0xFF1a1a2e),
                          fontWeight: FontWeight.w500,
                        ),
                        items: List.generate(28, (i) => i + 1)
                            .map(
                              (d) => DropdownMenuItem<int>(
                                value: d,
                                child: Text('매월 $d일'),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => _payDay = v ?? 10),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, thickness: 0.5, indent: 14, color: Color(0xFFF0F0F0)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 13),
                  child: Text(
                    '정산 주기: 매월 $_payPeriodStartDay일 ~ 다음달 $_payPeriodEndDay일 근무분을 매월 $_payDay일 지급',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF888888),
                    ),
                  ),
                ),
                const Divider(height: 1, thickness: 0.5, indent: 14, color: Color(0xFFF0F0F0)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '상시 근로자 5인 이상',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                            ),
                            SizedBox(height: 2),
                            Text(
                              '연장수당(1.5배) 및 주 52시간 가드 활성화',
                              style: TextStyle(fontSize: 12, color: Color(0xFF888888)),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _isFiveOrMore,
                        onChanged: (v) => _showRiskPreventionDialog(v),
                        activeThumbColor: const Color(0xFF1a6ebd),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, thickness: 0.5, indent: 14, color: Color(0xFFF0F0F0)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '두루누리 지원',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                            ),
                            SizedBox(height: 2),
                            Text(
                              '10인 미만, 월 270만원 미만 해당',
                              style: TextStyle(fontSize: 12, color: Color(0xFF888888)),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _isDuruNuri,
                        onChanged: (v) => setState(() => _isDuruNuri = v),
                        activeThumbColor: const Color(0xFF1a6ebd),
                      ),
                    ],
                  ),
                ),
                if (_isDuruNuri) ...[
                  const Divider(
                    height: 1,
                    thickness: 0.5,
                    indent: 14,
                    color: Color(0xFFF0F0F0),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '잔여 지원 개월',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                              ),
                              SizedBox(height: 2),
                              Text(
                                '4대사회보험 정보연계센터에서 확인',
                                style: TextStyle(fontSize: 12, color: Color(0xFF888888)),
                              ),
                            ],
                          ),
                        ),
                        DropdownButton<int>(
                          value: _duruNuriMonths,
                          underline: const SizedBox(),
                          style: const TextStyle(
                            fontSize: 15,
                            color: Color(0xFF1a1a2e),
                            fontWeight: FontWeight.w500,
                          ),
                          items: List.generate(37, (i) => i)
                              .map(
                                (m) => DropdownMenuItem<int>(
                                  value: m,
                                  child: Text('$m개월'),
                                ),
                              )
                              .toList(),
                          onChanged: (v) => setState(() => _duruNuriMonths = v ?? 36),
                        ),
                      ],
                    ),
                  ),
                ],
              ]),
            ],
          ),
        ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _saveStoreInfo,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1a1a2e),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: const Text(
                    '저장',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                ),
              ),
              const SizedBox(height: 40),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  '본 결과는 데이터 기반 추정치이며 최종 결정에 따른 책임은 사업주에게 있습니다.',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.black.withValues(alpha: 0.3),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 13,
          color: Color(0xFF888888),
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildInputGroup(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E5EA), width: 0.5),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildInputRow({
    required String label,
    required String hint,
    required TextEditingController controller,
    bool isRequired = false,
    bool isLast = false,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 100,
                child: Row(
                  children: [
                    Text(
                      label,
                      style: const TextStyle(fontSize: 14, color: Color(0xFF555555)),
                    ),
                    if (isRequired)
                      const Text(
                        ' *',
                        style: TextStyle(color: Color(0xFFE24B4A), fontSize: 14),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: TextField(
                  controller: controller,
                  keyboardType: keyboardType,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: const TextStyle(color: Color(0xFFBBBBBB), fontSize: 14),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (!isLast)
          const Divider(
            height: 1,
            thickness: 0.5,
            indent: 14,
            color: Color(0xFFF0F0F0),
          ),
      ],
    );
  }
}
