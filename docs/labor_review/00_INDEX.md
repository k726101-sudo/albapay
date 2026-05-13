# 알바페이 급여 계산 엔진 — 노무법인 검토 자료 목차

> 본 문서는 '알바페이' 앱의 급여 계산 엔진 로직을 노무법인 검토를 위해 정리한 기술 문서입니다.
> 모든 계산 공식에는 관련 근로기준법 조항 번호가 매핑되어 있습니다.

---

## 검토 순서 (권장)

| 순번 | 문서 | 내용 요약 |
|------|------|-----------|
| 1 | [01_attendance_model_spec.md](01_attendance_model_spec.md) | 출퇴근 기록 데이터 모델 — 각 필드의 의미와 법적 근거 |
| 2 | [02_clock_rules_spec.md](02_clock_rules_spec.md) | 출퇴근 판정 규칙 — 지각/조퇴/유예시간/연장승인 로직 |
| 3 | [03_payroll_engine_spec.md](03_payroll_engine_spec.md) | 급여 계산 핵심 엔진 — 시급제/월급제 전체 계산 흐름 |
| 4 | [04_annual_leave_spec.md](04_annual_leave_spec.md) | 연차 저금통 — 발생/소멸/사용촉진/단시간 비례 |
| 5 | [05_severance_spec.md](05_severance_spec.md) | 퇴직금 정산 — 평균임금 산출 및 통상임금 하한선 |
| 6 | [06_test_scenarios.md](06_test_scenarios.md) | 대표 테스트 시나리오 — 시급제/월급제/연차 검증 사례 |

---

## 시스템 개요

- **앱명**: 알바페이 (AlbaPay)
- **대상**: 아르바이트/파트타임 매장 (카페, 베이커리, 편의점 등)
- **급여형태**: 시급제 / 월급제 (포괄임금제 포함)
- **적용 법령**: 근로기준법, 최저임금법, 근로자퇴직급여보장법
- **기준연도**: 2026년 (최저임금 10,320원)

## 코드 구조

```
packages/shared_logic/lib/src/
  ├── models/
  │     └── attendance_model.dart    ← 출퇴근 데이터 모델
  ├── constants/
  │     └── payroll_constants.dart   ← 법정 수치 (최저임금, 보험요율)
  └── utils/
        ├── payroll_calculator.dart  ← 핵심 정산 엔진 (시급제/월급제)
        ├── roster_attendance.dart   ← 출퇴근 판정 규칙
        ├── compliance_engine.dart   ← 52시간 가드
        └── payroll/
              ├── annual_leave_calculator.dart  ← 연차 저금통
              ├── severance_calculator.dart     ← 퇴직금 정산
              ├── shift_substitution.dart       ← 교대/대체근무
              └── payroll_models.dart           ← 입출력 모델
```
