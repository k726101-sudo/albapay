import 'package:flutter/material.dart';
import 'package:shared_logic/shared_logic.dart';

class RequestSubstitutionScreen extends StatefulWidget {
  const RequestSubstitutionScreen({super.key});

  @override
  State<RequestSubstitutionScreen> createState() => _RequestSubstitutionScreenState();
}

class _RequestSubstitutionScreenState extends State<RequestSubstitutionScreen> {
  String? _selectedColleagueName;
  DateTime _selectedDate = AppClock.now();
  final TimeOfDay _startTime = const TimeOfDay(hour: 9, minute: 0);
  final TimeOfDay _endTime = const TimeOfDay(hour: 18, minute: 0);
  
  ComplianceResult? _complianceResult;
  bool _isLoading = false;

  // Mock data for check
  final _mockStore = Store(
    id: 's1',
    name: '정석 카페',
    ownerId: 'o1',
    representativeName: '대표자',
    representativePhoneNumber: '0000000000',
    address: '주소 미기재',
    latitude: 0,
    longitude: 0,
    settlementStartDay: 1,
    settlementEndDay: 31,
    payday: 10,
    isFiveOrMore: true,
  );

  @override
  void initState() {
    super.initState();
  }

  void _runComplianceCheck() async {
    if (_selectedColleagueName == null) return;

    setState(() => _isLoading = true);

    // Simulate getting colleague's weekly attendance from DB
    // List<Attendance> attendance = await _dbService.getWeeklyAttendance(_selectedColleague!.id, _selectedDate);
    final List<Attendance> attendance = []; 

    final start = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, _startTime.hour, _startTime.minute);
    final end = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, _endTime.hour, _endTime.minute);
    
    // Calculate difference in minutes instead of manually sending dates
    final diffMinutes = end.difference(start).inMinutes;

    final result = ComplianceEngine.checkWeeklyCompliance(
      store: _mockStore,
      currentWeeklyAttendances: attendance,
      newShiftMinutes: diffMinutes.toDouble(),
    );

    setState(() {
      _complianceResult = result;
      _isLoading = false;
    });
  }

  Future<void> _handleSubmit() async {
    if (_complianceResult != null && !_complianceResult!.isSafe) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('법적 리스크로 인해 이 요청을 진행할 수 없습니다.')),
      );
      return;
    }

    // TODO: Create and save Substitution record
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('대근 요청이 게시되었습니다.')),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('대근 요청하기')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('누구에게 부탁하실 건가요?', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            // Mock Colleague Selection
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(border: OutlineInputBorder()),
              hint: const Text('동료 선택 (전체 공개도 가능)'),
              items: [
                '이민수',
              ].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
              onChanged: (val) {
                setState(() => _selectedColleagueName = val);
                _runComplianceCheck();
              },
            ),
            const SizedBox(height: 32),
            const Text('언제인가요?', style: TextStyle(fontWeight: FontWeight.bold)),
            // Date/Time Pickers (Simplified)
            ListTile(
              title: Text('날짜: ${_selectedDate.toString().substring(0, 10)}'),
              trailing: const Icon(Icons.calendar_today),
              onTap: () async {
                final date = await showDatePicker(context: context, initialDate: _selectedDate, firstDate: AppClock.now(), lastDate: AppClock.now().add(const Duration(days: 30)));
                if (date != null) setState(() => _selectedDate = date);
                _runComplianceCheck();
              },
            ),
            const SizedBox(height: 32),
            if (_isLoading) const Center(child: CircularProgressIndicator()),
            if (_complianceResult != null) _buildComplianceFeedback(),
            const SizedBox(height: 48),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: (_selectedColleagueName != null && (_complianceResult?.isSafe ?? false)) ? _handleSubmit : null,
                child: const Text('요정 올리기'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildComplianceFeedback() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _complianceResult!.isSafe ? Colors.blue.shade50 : Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _complianceResult!.isSafe ? Colors.blue.shade200 : Colors.red.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_complianceResult!.isSafe ? Icons.check_circle : Icons.warning, color: _complianceResult!.isSafe ? Colors.blue : Colors.red),
              const SizedBox(width: 8),
              Text(
                _complianceResult!.isSafe ? '법적 리스크 없음' : '법적 리스크 탐지됨',
                style: TextStyle(fontWeight: FontWeight.bold, color: _complianceResult!.isSafe ? Colors.blue : Colors.red),
              ),
            ],
          ),
          ..._complianceResult!.warnings.map((w) => Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Text('• $w', style: const TextStyle(fontSize: 13)),
          )),
          ..._complianceResult!.blockingErrors.map((e) => Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Text('• $e', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
          )),
        ],
      ),
    );
  }
}
