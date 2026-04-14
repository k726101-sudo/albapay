# Firebase – 다음 단계 (초기 설정 이후)

초기 설정 가이드(1~5단계)를 마친 뒤 진행할 작업입니다.

---

## 1단계: Firestore 규칙 적용 (테스트 모드 벗어나기)

테스트 모드는 **일정 기간 뒤 자동 만료**되고, 그동안 누구나 DB에 접근할 수 있어 위험합니다.  
**“로그인한 사용자만 읽기/쓰기”** 로 바꿔 두는 것을 권장합니다.

### 하는 방법

1. Firebase 콘솔 → **Firestore Database** → **규칙(Rules)** 탭 클릭
2. 아래 규칙으로 **기존 내용을 통째로 교체**한 뒤 **“게시”** 클릭

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // 로그인한 사용자만 읽기/쓰기 허용 (최소 보안)
    match /{document=**} {
      allow read, write: if request.auth != null;
    }
  }
}
```

- **의미**: Firebase Authentication으로 로그인한 사용자만 모든 컬렉션을 읽고 쓸 수 있습니다. 비로그인 사용자는 전부 차단됩니다.
- **주의**: 알바는 “초대 링크로 들어와서 전화번호 로그인” 후에만 Firestore를 쓰므로, 위 규칙이면 동작합니다. 사장님 앱도 로그인 후에만 데이터를 쓰면 됩니다.

---

## 2단계: 앱/웹 실행해서 로그인 확인

설정이 제대로 됐는지 **실제로 로그인**이 되는지 확인합니다.

### 사장님 앱 (Android / iOS)

```bash
cd apps/boss_mobile
flutter pub get
flutter run -d chrome   # 또는 연결된 기기 ID
```

- **이메일 링크**: 이메일 입력 → “이메일로 로그인 링크 받기” → 메일에서 링크 복사 → 앱의 “링크 붙여넣기”에 붙여넣고 “링크로 로그인 완료”
- **Android**: 구글 로그인 버튼
- **iOS**: Apple 로그인 버튼

### 알바 웹 (Flutter Web)

```bash
cd apps/alba_web
flutter pub get
flutter run -d chrome
```

- **주의**: 알바 로그인은 **초대 링크가 있어야** 합니다. URL에 `?invite=초대ID` 가 있어야 전화번호 입력/인증번호 받기가 가능합니다.
- 테스트용 초대 문서를 Firestore `invites` 컬렉션에 수동으로 하나 만든 뒤, 그 문서 ID를 `invite` 값으로 넣어서 접속해 보세요.

**예시**  
Firestore에 `invites` 컬렉션 → 문서 ID `test-invite-1` → 필드: `storeId: "매장ID"`, `staffName: "테스트"`  
접속 URL: `http://localhost:xxxx/?invite=test-invite-1`

---

## 3단계: (선택) 나중에 더 세밀한 규칙 넣기

나중에 다음을 적용할 수 있습니다.

- **퇴사자 차단**: `staff/{uid}` 문서에 `isActive: false` 또는 `resignedAt` 필드를 두고, 규칙에서 “해당 사용자는 읽기/쓰기 거부”
- **초대(invites)**: “생성은 매장 사장(owner)만, 조회/업데이트(소비)는 로그인한 사용자”
- **stores, attendance 등**: `storeId`·`ownerId` 기준으로 “본인 매장만” 제한

이때는 컬렉션 구조와 앱 동작이 확정된 뒤, 별도 규칙 초안을 만들어 적용하는 것이 좋습니다.

---

## 체크리스트

- [ ] Firestore 규칙을 “로그인한 사용자만” 으로 변경하고 게시함
- [ ] 사장님 앱에서 이메일 링크 또는 구글/애플 로그인 성공 확인
- [ ] 알바 웹에서 `?invite=...` 로 접속 후 전화번호 로그인 성공 확인 (초대 문서는 미리 Firestore에 생성)

이후에는 **GPS/위치 기반 출퇴근**, **공지**, **교육** 기능 구현으로 이어가면 됩니다.
