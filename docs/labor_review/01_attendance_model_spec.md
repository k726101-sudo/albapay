# 01. 출퇴근 기록 데이터 모델 (Attendance Model)

> 출처: `packages/shared_logic/lib/src/models/attendance_model.dart`

---

## 1. 핵심 필드 정의

### 1.1 식별 필드

| 필드명 | 타입 | 설명 |
|--------|------|------|
| `id` | String | 출퇴근 기록 고유 ID (형식: `{workerId}_{timestamp}`) |
| `staffId` | String | 근로자 고유 ID |
| `storeId` | String | 매장(사업장) 고유 ID |

### 1.2 시간 기록 필드

| 필드명 | 타입 | 설명 | 법적 근거 |
|--------|------|------|-----------|
| `clockIn` | DateTime | **급여 계산용 출근 시각** — 지각 유예, 조기출근 보정이 적용된 시각 | 근로기준법 제17조 |
| `originalClockIn` | DateTime? | **실제 출근 기록 시각** — 알바생이 QR/앱으로 찍은 원본 시각 | 증빙 보존 목적 |
| `clockOut` | DateTime? | **급여 계산용 퇴근 시각** — 연장승인/조퇴 보정이 적용된 시각 | |
| `originalClockOut` | DateTime? | **실제 퇴근 기록 시각** — 원본 퇴근 시각 | 증빙 보존 목적 |

> **핵심 원칙**: `originalClockIn/Out`은 절대 수정하지 않고 원본 보존합니다.
> 급여 계산은 항상 `clockIn/Out`을 기준으로 합니다.

### 1.3 근무표 연동 필드

| 필드명 | 타입 | 설명 |
|--------|------|------|
| `scheduledShiftStartIso` | String? | 계약서/근무표 기준 예정 출근 시각 (ISO 8601) |
| `scheduledShiftEndIso` | String? | 계약서/근무표 기준 예정 퇴근 시각 (ISO 8601) |

### 1.4 휴게 시간 필드

| 필드명 | 타입 | 설명 | 법적 근거 |
|--------|------|------|-----------|
| `breakStart` | DateTime? | 실제 휴게 시작 시각 (수동 기록 시) | 근로기준법 제54조 |
| `breakEnd` | DateTime? | 실제 휴게 종료 시각 (수동 기록 시) | |

> 휴게 시간이 수동 기록되지 않은 경우, 계산 엔진은 다음 우선순위로 처리합니다:
> 1. `breakStart/End` 실제 기록값 사용
> 2. 근로자 설정의 `breakStartTime/EndTime` 구간과 실제 근무시간의 겹침(Overlap) 계산
> 3. `breakMinutesPerShift` 고정값에 대해 실제/예정 근무시간 비례 적용

### 1.5 상태 관리 필드

| 필드명 | 타입 | 값 | 설명 |
|--------|------|-----|------|
| `attendanceStatus` | String | `Normal` | 정상 출퇴근 (자동 승인됨) |
| | | `pending_approval` | 사장님 승인 대기 (지각, 근무표 불일치) |
| | | `Unplanned` | 근무표에 없는 날 출근 (대타 등) |
| | | `UnplannedApproved` | 비예정 출근 → 사장님 승인 완료 |
| | | `approved` | 사장님이 수동 승인 |
| | | `rejected` | 사장님이 거부 (급여 미반영) |
| `isAutoApproved` | bool | | 시스템이 자동 승인했는지 여부 |

### 1.6 수정 이력 필드

| 필드명 | 타입 | 설명 | 법적 근거 |
|--------|------|------|-----------|
| `isEditedByBoss` | bool | 사장님이 출퇴근 시간을 수정했는지 여부 | 근로기준법 제48조 (임금대장 기재) |
| `editedAt` | DateTime? | 수정 일시 | |
| `editReason` | String? | 수정 사유 (분쟁 대비) | |

### 1.7 연장근무 필드

| 필드명 | 타입 | 설명 | 법적 근거 |
|--------|------|------|-----------|
| `overtimeApproved` | bool | 예정 퇴근 이후 초과 근무 승인 여부 | 근로기준법 제53조 |
| `earlyClockOutReason` | String? | 조퇴 사유 | |
| `isSpecialOvertime` | bool | 52시간 특별연장 승인 여부 | 근로기준법 제53조 제4항 |
| `specialOvertimeReason` | String? | 특별연장 사유 | |

### 1.8 연차/유급휴일 필드

| 필드명 | 타입 | 설명 | 법적 근거 |
|--------|------|------|-----------|
| `isAnnualLeave` | bool | 연차 사용일 여부 | 근로기준법 제60조 |
| `isAttendanceEquivalent` | bool | 출근으로 간주하는 유급휴일 (근로자의 날, 연차 사용일 등) | 근로기준법 제60조 제6항 |

---

## 2. 출퇴근 상태 전이도

```
[QR 스캔 / 앱 출근]
       ↓
  ┌─────────────────┐
  │ 근무표와 비교     │
  └────┬──────┬─────┘
       │      │
  일치 + 유예 내  │ 불일치 / 휴무일
       │         │
  ┌────▼────┐  ┌─▼──────────────┐
  │ Normal  │  │ pending_approval│ (또는 Unplanned)
  │ (자동승인)│  │ (사장님 승인 대기) │
  └─────────┘  └────┬──────┬────┘
                    │      │
              승인   │      │ 거부
                    │      │
              ┌─────▼──┐ ┌─▼────────┐
              │approved│ │ rejected │
              │(급여O) │ │ (급여X)  │
              └────────┘ └──────────┘
```

---

## 3. 급여 계산 시 사용되는 필드 요약

급여 계산 엔진(`payroll_calculator.dart`)은 다음 필드만 사용합니다:

| 목적 | 사용 필드 |
|------|----------|
| 순수 근로시간 산출 | `clockIn`, `clockOut` |
| 연장근무 판정 | `scheduledShiftEndIso`, `overtimeApproved`, `isEditedByBoss` |
| 휴게 시간 차감 | `breakStart`, `breakEnd` → 없으면 근로자 설정값 사용 |
| 주휴수당 만근 판정 | `clockOut` 존재 여부, `isAttendanceEquivalent` |
| 급여 포함/제외 | `attendanceStatus` ≠ `rejected` |
