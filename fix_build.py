with open('apps/boss_mobile/lib/screens/alba/alba_main_screen.dart', 'r') as f:
    lines = f.readlines()

# Find the build method start (line 2255 = index 2254)
build_start = None
for i, line in enumerate(lines):
    if '  @override' in line and i > 2200:
        # Check next line
        if i+1 < len(lines) and 'Widget build(BuildContext context)' in lines[i+1]:
            build_start = i
            break

if build_start is None:
    print("ERROR: Could not find build method")
    exit(1)

# Find the end of the class
class_end = None
for i in range(len(lines)-1, build_start, -1):
    if lines[i].strip() == '} // End of class _AlbaMainScreenState':
        class_end = i
        break

if class_end is None:
    print("ERROR: Could not find class end")
    exit(1)

print(f"Found build at line {build_start+1}, class end at line {class_end+1}")

new_build = '''  @override
  Widget build(BuildContext context) {
    if (_uid.isEmpty) {
      return const Scaffold(body: Center(child: Text('로그인이 필요합니다.')));
    }

    if (_isInitialLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final worker = _workerData;

    String getTitle() {
      if (_index == 1) return '근무표';
      if (_index == 2) return '내 급여';
      if (_index == 3) return '공지/업무';
      if (_index == 4) return '노무서류';
      return '';
    }

    Widget currentPage;
    switch (_index) {
      case 0:
        currentPage = _homeDashboard(worker);
        break;
      case 1:
        currentPage = AlbaSchedulePage(storeId: widget.storeId, workerId: _workerId);
        break;
      case 2:
        currentPage = AlbaPayrollPage(storeId: widget.storeId, workerId: _workerId, worker: worker);
        break;
      case 3:
        currentPage = NoticeEducationTabScreen(
          key: ValueKey(_subIndex),
          storeId: widget.storeId,
          workerId: _workerId,
          workerName: worker['name'] ?? '알바생',
          initialIndex: _subIndex,
        );
        break;
      case 4:
        currentPage = WorkerDocumentsScreen(storeId: widget.storeId);
        break;
      default:
        currentPage = _homeDashboard(worker);
    }

    return Scaffold(
      backgroundColor: _pageBg,
      resizeToAvoidBottomInset: false,
      appBar: _index == 0
          ? null
          : AppBar(
              title: Text(getTitle()),
              backgroundColor: Colors.white,
              foregroundColor: Colors.black87,
              elevation: 0.5,
              actions: [
                IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => AlbaSettingsScreen(storeId: widget.storeId, workerId: _workerId)));
                  },
                ),
              ],
            ),
      body: Stack(
        children: [
          Positioned.fill(child: currentPage),
          if (_topBannerMessage != null)
            Positioned(
              top: 0, left: 0, right: 0,
              child: SafeArea(
                bottom: false,
                child: Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 2))],
                    ),
                    child: Text(_topBannerMessage!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() { _index = i; if (i == 3) _subIndex = 0; }),
        backgroundColor: Colors.white,
        elevation: 12,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFF2E7D32),
        unselectedItemColor: Colors.black45,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_rounded), activeIcon: Icon(Icons.home), label: '홈'),
          BottomNavigationBarItem(icon: Icon(Icons.calendar_month_rounded), activeIcon: Icon(Icons.calendar_month), label: '근무표'),
          BottomNavigationBarItem(icon: Icon(Icons.account_balance_wallet_outlined), activeIcon: Icon(Icons.account_balance_wallet_rounded), label: '내 급여'),
          BottomNavigationBarItem(icon: Icon(Icons.campaign_outlined), activeIcon: Icon(Icons.campaign), label: '공지/업무'),
          BottomNavigationBarItem(icon: Icon(Icons.description_outlined), activeIcon: Icon(Icons.description_rounded), label: '서류'),
        ],
      ),
    );
  }
} // End of class _AlbaMainScreenState
'''

# Replace from build_start to class_end (inclusive) + any trailing blank lines
end_idx = class_end + 1
while end_idx < len(lines) and lines[end_idx].strip() == '':
    end_idx += 1

new_lines = lines[:build_start] + [new_build]
with open('apps/boss_mobile/lib/screens/alba/alba_main_screen.dart', 'w') as f:
    f.writelines(new_lines)

print("SUCCESS: Build method replaced")
