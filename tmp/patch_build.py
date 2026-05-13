import re

boss_path = 'apps/boss_mobile/lib/screens/alba/alba_main_screen.dart'

with open(boss_path, 'r') as f:
    content = f.read()

# Replace build method signature and FutureBuilder
build_start_idx = content.find('  @override\n  Widget build(BuildContext context) {')
dash_card_idx = content.find('  Widget _dashCard(', build_start_idx)

old_build = content[build_start_idx:dash_card_idx]

new_build = old_build.replace(
'''    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: _workerFuture(),
      builder: (context, workerSnap) {
        if (workerSnap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final worker = workerSnap.data?.data() ?? const <String, dynamic>{};''',
'''    if (_isInitialLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final worker = _workerData;'''
)

# Remove the closing braces for FutureBuilder
new_build = new_build.replace(
'''      },
    );
  }
} // End of class _AlbaMainScreenState''',
'''  }
}'''
)

# Replace missing parameters
new_build = new_build.replace(
    'WorkerDocumentsScreen(storeId: widget.storeId)',
    'WorkerDocumentsScreen(storeId: widget.storeId, workerId: _workerId)'
)

new_build = new_build.replace(
    'const AlbaSettingsScreen()',
    'AlbaSettingsScreen(storeId: widget.storeId, workerId: _workerId)'
)

# Also fix the AlbaSettingsScreen inside _homeDashboard
# Wait, I already replaced _homeDashboard with alba_web's, so it has AlbaSettingsScreen()
content = content[:build_start_idx] + new_build + content[dash_card_idx:]

# Fix AlbaSettingsScreen without arguments in _homeDashboard
content = content.replace(
    'const AlbaSettingsScreen()',
    'AlbaSettingsScreen(storeId: widget.storeId, workerId: _workerId)'
)

# Wait, `isClockedIn` is used in _homeDashboard but wait, Cursor used it as ValueKey(isClockedIn) in build? No, Cursor didn't use ValueKey(isClockedIn) in build, I saw it in my head.
# Let's check.
if 'ValueKey<bool>(isClockedIn)' in content:
    content = content.replace('ValueKey<bool>(isClockedIn)', 'ValueKey<bool>(_currentOpenAttendance != null)')

with open(boss_path, 'w') as f:
    f.write(content)

print("Build patched.")
