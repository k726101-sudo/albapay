import re

def extract_replacements(log_path):
    with open(log_path, 'r', encoding='utf-8') as f:
        content = f.read()

    # Find all "replace_file_content" or "multi_replace_file_content"
    # But it's easier to just find the code blocks in the tool outputs.
    matches = re.findall(r'The following changes were made by the .* tool to: (.*?\.dart).*?\[diff_block_start\](.*?)\[diff_block_end\]', content, re.DOTALL)
    
    for file, diff in matches:
        if "payroll_dashboard_screen.dart" in file:
            print(f"--- diff for {file} ---")
            print(diff)

extract_replacements('/Users/kimkyoungil/.gemini/antigravity/brain/a74d202c-996d-4ba6-8c79-337d60382384/.system_generated/logs/overview.txt')
extract_replacements('/Users/kimkyoungil/.gemini/antigravity/brain/9795abaf-8957-4b14-ac90-790fe6a05f96/.system_generated/logs/overview.txt')
