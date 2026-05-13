import re

path = 'AlbaManager_UserManual/AlbaPay_Calculations_Report_Full.md'
with open(path, 'r', encoding='utf-8') as f:
    text = f.read()

text = re.sub(r'확인을 증명하기 위한', '확인을 기록하기 위한', text)
text = re.sub(r'정확히 추적\(노무 증명\)', '추적(노무 이력 관리)', text)
text = re.sub(r'산출 결과은 113개 자동화 테스트로 보장하면서도', '산출 로직은 114개 자동화 테스트로 검증하면서도', text)
text = re.sub(r'promotionExemptPayoutAmount를 정확히 산출합니다', 'promotionExemptPayoutAmount를 산출합니다', text)
text = re.sub(r'정확히 알고 있는가', '명확히 인지하고 있는가', text)
text = re.sub(r'정확히 목표 급여', '설정된 목표 급여', text)

with open(path, 'w', encoding='utf-8') as f:
    f.write(text)
print("Replacements 2 done.")
