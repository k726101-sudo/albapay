# Firestore Worker-Only Cleanup Checklist

`staff` 컬렉션을 완전히 정리하고, `workers` 단일 구조로 운영하기 위한 체크리스트입니다.

## 1) 데이터 구조 기준 확정

- [ ] 직원 문서는 `stores/{storeId}/workers/{workerId}` 경로만 사용한다.
- [ ] 전역 `staff` 컬렉션은 신규 write를 금지한다.
- [ ] 앱 코드에서 직원 조회/저장은 `WorkerService`만 사용한다.

권장 직원 문서 필드:

- `name`, `phone`, `workerType`
- `hourlyWage`, `weeklyHours`, `weeklyHolidayPay`
- `checkInTime`, `checkOutTime`, `workDays`
- `hasHealthCert`, `healthCertExpiry`
- `status` (`active`/`inactive`)
- `createdAt`

## 2) 마이그레이션 점검 (개발 단계)

- [ ] 앱 시작 시 `WorkerService.migrateStaffToWorker()`가 1회 수행되는지 확인
- [ ] `staff` -> `workers` 복사 후 샘플 사용자로 데이터 일치 확인
- [ ] 신규 직원 등록 시 `workers`에만 생성되는지 확인
- [ ] 퇴사 처리 시 `workers/{id}.status`만 변경되는지 확인

검증 쿼리 예시(콘솔 기준):

- [ ] `staff` 문서 수 = 0 또는 더 이상 증가하지 않음
- [ ] `stores/{storeId}/workers` 문서 수가 실제 인원과 일치

## 3) Firestore Security Rules 정리

목표:

- `staff` 경로 write 차단
- `stores/{storeId}/workers/{workerId}`만 허용

최소 권장 규칙 예시:

```rules
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    function isSignedIn() {
      return request.auth != null;
    }

    function isStoreMember(storeId) {
      return isSignedIn() &&
        get(/databases/$(database)/documents/users/$(request.auth.uid)).data.storeId == storeId;
    }

    // New source of truth
    match /stores/{storeId}/workers/{workerId} {
      allow read, write: if isStoreMember(storeId);
    }

    // Legacy collection lock-down
    match /staff/{docId} {
      allow read: if false;
      allow write: if false;
    }
  }
}
```

## 4) 인덱스/쿼리 확인

- [ ] `stores/{storeId}/workers` 조회가 정상인지 확인
- [ ] `status` 조건 필터를 쓰면 필요한 composite index 생성
- [ ] `createdAt` 정렬 사용 시 인덱스 생성

## 5) 레거시 코드 제거 최종 점검

- [ ] `rg "Staff|streamStaff|collection\\('staff'\\)"` 결과가 앱 코드에서 0인지 확인
- [ ] `shared_logic`에서 `staff_model.dart` export가 없는지 확인
- [ ] 배포 전 `migrateStaffToWorker()`를 유지할지/제거할지 결정

## 6) 운영 전환(선택)

- [ ] 안정화 후 `migrateStaffToWorker()` 자동 실행 제거
- [ ] 필요하면 Admin 스크립트로 `staff` 컬렉션 백업 후 삭제
- [ ] 팀 문서에 "직원 소스 오브 트루스 = workers" 명시

## 7) QA 시나리오

- [ ] 직원 등록 -> 목록/대시보드 즉시 반영
- [ ] 앱 재시작 후 Hive 캐시 + Firebase 동기화 정상
- [ ] 오프라인 상태에서 목록 조회 가능
- [ ] 온라인 복귀 시 Firebase 변경사항이 Hive에 반영
- [ ] 퇴사 처리 후 active 목록에서 즉시 제외

