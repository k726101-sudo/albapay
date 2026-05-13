import os
import json
from pathlib import Path

history_dir = os.path.expanduser('~/Library/Application Support/Code/User/History')
latest_file = None
latest_time = 0

for root, dirs, files in os.walk(history_dir):
    if 'entries.json' in files:
        entries_path = os.path.join(root, 'entries.json')
        try:
            with open(entries_path, 'r') as f:
                data = json.load(f)
            # check if entries.json belongs to payroll_dashboard_screen.dart
            if 'payroll_dashboard_screen.dart' in data.get('resource', ''):
                entries = data.get('entries', [])
                if entries:
                    last_entry = entries[-1]
                    timestamp = last_entry.get('timestamp', 0)
                    if timestamp > latest_time:
                        latest_time = timestamp
                        latest_file = os.path.join(root, last_entry.get('id'))
        except Exception as e:
            pass

if latest_file:
    print(f"LATEST: {latest_file} (Timestamp: {latest_time})")
else:
    print("Not found")
