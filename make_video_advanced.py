import os
import numpy as np
from PIL import Image, ImageOps, ImageDraw, ImageFont
import imageio

image_dir = 'AlbaManager_UserManual/images'
output_path = 'AlbaManager_UserManual/user_manual_video_captioned.mp4'
font_path = '/System/Library/Fonts/AppleSDGothicNeo.ttc'

target_width = 1080
target_height = 2340

# Define parts and captions
storyboard = [
    {
        "part_title": "1부: 로그인 및 홈 대시보드",
        "frames": [
            ("login_screen.png", "알바급여정석 로그인 화면: 전화번호로 간편하게 시작하세요."),
            ("dashboard.png", "사장님 메인 대시보드: 실시간 이번 달 예상 인건비를 한눈에 파악!"),
            ("dashboard_2.png", "가장 시급한 업무와 직원 요청사항을 카드 형태로 확인."),
            ("dashboard_3.png", "빠른 메뉴를 통해 주요 기능으로 즉시 이동 가능합니다."),
        ]
    },
    {
        "part_title": "2부: 매장 기본 설정",
        "frames": [
            ("store_setup_top.png", "매장 설정 (상단): 급여일과 정산 시작일을 설정하여 기준을 잡습니다."),
            ("store_setup_bottom.png", "매장 설정 (하단): 상시근로자 5인 이상 여부 등 법적 기준을 세팅!"),
        ]
    },
    {
        "part_title": "3부: 직원 스케줄 및 등록",
        "frames": [
            ("add_staff_top.png", "직원 등록 (상단): 이름, 시급, 근무 정보를 입력하세요."),
            ("add_staff_bottom.png", "직원 등록 (하단): 수습 기간, 휴게 시간 등 세부 수당 규정을 설정."),
            ("worker_registry.png", "직원 명부 (요약): 현재 근무 중인 모든 직원의 상태를 확인."),
            ("worker_registry_2.png", "직원 관리 (상세): 과거 퇴사자까지 완벽하게 기록 보존."),
        ]
    },
    {
        "part_title": "4부: 노무 서류 자동 생성",
        "frames": [
            ("labor_contract.png", "전자 근로계약서 (1): 입력된 시급/시간을 바탕으로 근로기준법에 맞게 자동 작성!"),
            ("labor_contract_2.png", "전자 근로계약서 (2): 휴게시간과 주휴수당 조항까지 완벽 적용."),
            ("night_consent.png", "야간근로 동의서: 관련 법적 서류도 터치 한 번에 자동 구성."),
            ("night_consent_2.png", "야간근로 동의서 상세 부분 및 서명 란."),
            ("hiring_checklist.png", "채용 점검표 (1): 사장님이 놓치기 쉬운 필수 고지 항목 체크."),
            ("hiring_checklist_2.png", "채용 점검표 (2): 알바생 폰으로 발송되어 비대면 모바일 전자 서명!"),
        ]
    },
    {
        "part_title": "5부: 강력한 급여 리포트",
        "frames": [
            ("payroll_report.png", "급여 리포트 요약: 이번 달 총 지출 예상액과 매장 법적 상태 모니터링."),
            ("payroll_report_2.png", "급여 리포트 하단: 연내 주휴수당 리스크, 휴게 미분리 예외 건수 경고."),
            ("payroll_detail.png", "급여 상세보기 (1): 해당 직원의 기본급, 주휴수당, 야간가산 자동 산출."),
            ("payroll_detail_2.png", "급여 상세보기 (2): 소득세/4대보험 공제액까지 계산된 최종 실지급액."),
            ("payroll_detail_3.png", "급여 상세보기 (3): 출퇴근 기록 및 휴게시간 체류 이력 증빙 화면."),
        ]
    },
    {
        "part_title": "6부: 알바생 전용 웹 (앱 설치 불필요)",
        "frames": [
            ("alba_web_dashboard.png", "알바생 웹 홈: 내 이번 달 예상 월급과 출퇴근 QR 코드가 바로 등장!"),
            ("alba_web_schedule.png", "웹 스케줄 뷰: 달력 형태로 내 근무 일정과 급여액 확인."),
            ("alba_web_schedule_2.png", "날짜를 누르면 그날의 시급과 수당 세부 내역이 표시됩니다."),
            ("alba_web_payroll.png", "웹 급여명세서 (1): 사장님이 발송한 카톡 링크를 열면 나오는 정식 명세서."),
            ("alba_web_payroll_2.png", "웹 급여명세서 (2): 법적 양식에 맞춘 공제 내역 및 실수령액."),
            ("alba_web_doc.png", "문서 서명함: 사장님이 보낸 근로계약서에 손가락으로 싸인하기."),
            ("alba_web_vault.png", "나의 금고 (문서함): 서명 완료된 지난 계약서와 월급 명세서 영구 보관."),
            ("alba_web_manual.png", "웹 매뉴얼: 알바생이 스스로 기능을 배울 수 있는 안내 센터."),
        ]
    }
]

def create_text_image(text, width, height, bg_color=(25, 118, 210), text_color=(255, 255, 255)):
    img = Image.new('RGB', (width, height), color=bg_color)
    draw = ImageDraw.Draw(img)
    try:
        font = ImageFont.truetype(font_path, 80)
    except:
        font = ImageFont.load_default()
    
    # Calculate text bounding box
    bbox = draw.textbbox((0, 0), text, font=font)
    text_w = bbox[2] - bbox[0]
    text_h = bbox[3] - bbox[1]
    
    x = (width - text_w) / 2
    y = (height - text_h) / 2
    
    draw.text((x, y), text, font=font, fill=text_color)
    return img

def add_caption(img, text):
    draw = ImageDraw.Draw(img)
    try:
        font = ImageFont.truetype(font_path, 40)
    except:
        font = ImageFont.load_default()
        
    # Draw semi-transparent background for text at the bottom
    caption_height = 150
    overlay = Image.new('RGBA', img.size, (0, 0, 0, 0))
    overlay_draw = ImageDraw.Draw(overlay)
    
    overlay_draw.rectangle(
        [(0, img.height - caption_height), (img.width, img.height)],
        fill=(0, 0, 0, 180)
    )
    
    img = Image.alpha_composite(img.convert('RGBA'), overlay).convert('RGB')
    draw = ImageDraw.Draw(img)
    
    # Draw text multiline horizontally centered
    bbox = draw.textbbox((0, 0), text, font=font)
    text_w = bbox[2] - bbox[0]
    text_h = bbox[3] - bbox[1]
    
    x = (img.width - text_w) / 2
    y = img.height - caption_height + (caption_height - text_h) / 2
    
    draw.text((x, y), text, font=font, fill=(255, 255, 255))
    return img

print("Initializing video compilation with parts and captions...")
writer = imageio.get_writer(output_path, fps=0.4) # 1 frame per 2.5 seconds

try:
    for part in storyboard:
        # 1. Add Part Title Screen (Show for 2.5s)
        part_img = create_text_image(part["part_title"], target_width, target_height)
        writer.append_data(np.array(part_img))
        
        # 2. Add frames for this part
        for file_name, caption in part["frames"]:
            file_path = os.path.join(image_dir, file_name)
            if not os.path.exists(file_path):
                print(f"Warning: {file_name} not found. Skipping.")
                continue
                
            img = Image.open(file_path).convert('RGB')
            # Resize smartly
            img.thumbnail((target_width, target_height), Image.Resampling.LANCZOS)
            
            # Create a blank canvas
            canvas = Image.new('RGB', (target_width, target_height), color=(242, 242, 247))
            
            # Paste image in the center
            paste_x = (target_width - img.width) // 2
            paste_y = (target_height - img.height) // 2
            canvas.paste(img, (paste_x, paste_y))
            
            # Add Caption overlay
            canvas_captioned = add_caption(canvas, caption)
            
            writer.append_data(np.array(canvas_captioned))
            
except Exception as e:
    print(f"Error processing video: {e}")
finally:
    writer.close()
    
print(f"🎉 Captioned Video successfully created at: {output_path}")
