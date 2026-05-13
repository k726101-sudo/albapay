import re

boss_path = 'apps/boss_mobile/lib/screens/alba/alba_main_screen.dart'
web_path = 'apps/alba_web/lib/screens/alba_main_screen.dart'

with open(boss_path, 'r') as f:
    boss_content = f.read()

with open(web_path, 'r') as f:
    web_content = f.read()

# --- 1. State Variables ---
# Find boss _isProcessing
boss_proc_idx = boss_content.find('bool _isProcessing = false;')
boss_uid_idx = boss_content.find('String get _uid', boss_proc_idx)

web_proc_idx = web_content.find('bool _isProcessing = false;')
web_uid_idx = web_content.find('String get _uid', web_proc_idx)

state_vars = web_content[web_proc_idx:web_uid_idx]
boss_content = boss_content[:boss_proc_idx] + state_vars + boss_content[boss_uid_idx:]

# --- 2. Loading Methods and initState ---
web_load_idx = web_content.find('Future<void> _loadDashboardData()')
web_init_end_idx = web_content.find('void dispose()', web_load_idx)

web_loading_and_init = web_content[web_load_idx:web_init_end_idx-14] # Up to before @override dispose

boss_init_idx = boss_content.find('  @override\n  void initState()')
boss_init_end_idx = boss_content.find('  @override\n  void dispose()', boss_init_idx)

boss_content = boss_content[:boss_init_idx] + web_loading_and_init + '\n\n' + boss_content[boss_init_end_idx:]

# --- 3. _homeDashboard ---
web_home_idx = web_content.find('Widget _homeDashboard(Map<String, dynamic> worker)')
web_build_idx = web_content.find('  @override\n  Widget build', web_home_idx)
web_home_func = web_content[web_home_idx:web_build_idx-4]

boss_home_idx = boss_content.find('Widget _homeDashboard(Map<String, dynamic> worker)')
boss_build_idx = boss_content.find('  @override\n  Widget build', boss_home_idx)

boss_content = boss_content[:boss_home_idx] + web_home_func + '\n\n' + boss_content[boss_build_idx:]

# --- 4. _finishClockOut ---
# Check if boss has _finishClockOut
boss_finish_idx = boss_content.find('void _finishClockOut(')
web_finish_idx = web_content.find('void _finishClockOut(')
web_finish_end_idx = web_content.find('  Future<void> _clockOut', web_finish_idx)
web_finish_func = web_content[web_finish_idx:web_finish_end_idx]

if boss_finish_idx != -1:
    boss_finish_end_idx = boss_content.find('  Future<void> _clockOut', boss_finish_idx)
    boss_content = boss_content[:boss_finish_idx] + web_finish_func + boss_content[boss_finish_end_idx:]
else:
    # Insert before _clockOut
    boss_clockout_idx = boss_content.find('  Future<void> _clockOut')
    boss_content = boss_content[:boss_clockout_idx] + '  ' + web_finish_func + boss_content[boss_clockout_idx:]


# --- 5. Fix _clockOut finally block ---
# In boss_mobile, we want to replace the first `} finally { ... }` in _clockOut
boss_clockout_start = boss_content.find('Future<void> _clockOut(')
boss_finally_start = boss_content.find('} finally {', boss_clockout_start)
boss_finally_end = boss_content.find('}', boss_finally_start + 12) + 1 # include the closing brace
# But wait, there might be nested braces inside finally.
# Let's just do a targeted replace for what we know cursor produces.
old_finally = '''    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }'''
new_finally = '''    } finally {
      if (mounted && _isProcessing) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _isProcessing) {
            setState(() => _isProcessing = false);
          }
        });
      }
    }'''
# Wait, let's use regex to safely match the finally block of _clockOut
import re
boss_content = re.sub(r'    \} finally \{\n      if \(mounted\) setState\(\(\) => _isProcessing = false\);\n    \}', new_finally, boss_content)

with open(boss_path, 'w') as f:
    f.write(boss_content)

print("Done patching.")
