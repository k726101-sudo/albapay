import glob
import re

logs = glob.glob('/Users/kimkyoungil/.gemini/antigravity/brain/*/.system_generated/logs/overview.txt')

for log in logs:
    with open(log, 'r', encoding='utf-8') as f:
        content = f.read()
    
    if "payroll_dashboard_screen.dart" in content:
        print(f"Log: {log}")
