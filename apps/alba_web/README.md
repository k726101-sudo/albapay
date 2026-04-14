# 알바급여정석 – 알바용 (Flutter Web)

알바(직원)가 **웹 브라우저**에서 사용하는 클라이언트입니다. **Flutter Web**으로 구현되어 있습니다.

- **로그인**: 사장님이 공유한 초대 링크(`?invite=...`)로 접속 후, 전화번호(SMS) 인증
- **기능**: 출퇴근 기록, 근무 교대/교대 요청, 교육, 공지 등 (Firestore + shared_logic 연동)

## 실행 방법 (Flutter Web)

```bash
# 의존성 설치
flutter pub get

# 로컬에서 웹으로 실행 (Chrome 등)
flutter run -d chrome

# 프로덕션 웹 빌드 (build/web 에 산출)
flutter build web
```

## 배포

- `flutter build web` 결과물(`build/web/`)을 Firebase Hosting, Vercel, Netlify 등 정적 호스팅에 올리면 됩니다.
- Firebase 프로젝트(`standard-albapay`)의 **Web 앱**이 등록되어 있어야 하며, Authentication → Authorized domains에 배포 도메인을 추가해야 합니다.

## 프로젝트 구조

- `lib/main.dart` – 앱 진입점, Firebase 초기화, 세션 유지(LOCAL)
- `lib/screens/login_screen.dart` – 초대 링크 + 전화번호 로그인
- `lib/screens/attendance/` – 출퇴근 화면
- 공통 로직: `packages/shared_logic` (Dart)
