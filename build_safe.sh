#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# AlbaPay 안전 빌드 스크립트 (Safe Build)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# 사용법:
#   ./build_safe.sh           → 디버그 APK 빌드
#   ./build_safe.sh release   → 릴리즈 APK 빌드
#   ./build_safe.sh appbundle → AAB (Play Store) 빌드
#
# 이 스크립트는 빌드 전에 반드시 법률 컴플라이언스 테스트를
# 실행합니다. 테스트가 1건이라도 실패하면 빌드를 중단하여
# 법적으로 위험한 코드가 앱으로 나가는 것을 차단합니다.
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
SHARED_LOGIC="$PROJECT_ROOT/packages/shared_logic"
BOSS_MOBILE="$PROJECT_ROOT/apps/boss_mobile"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  🛡  AlbaPay 안전 빌드 시스템"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ── STEP 1: 법률 컴플라이언스 테스트 실행 ──
echo "📋 [1/2] 법률 컴플라이언스 테스트 실행 중..."
echo "    대상: 근로기준법 시행령 제7조의2, 제55조, 제56조, 제60조, 최저임금법 제6조"
echo ""

cd "$SHARED_LOGIC"

if flutter test test/compliance/ --reporter expanded 2>&1; then
    echo ""
    echo "✅ 법률 테스트 전부 PASS — 빌드를 진행합니다."
    echo ""
else
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  ❌ 법률 테스트 FAIL — 빌드를 중단합니다!"
    echo ""
    echo "  하나 이상의 노동법 컴플라이언스 테스트가 실패했습니다."
    echo "  이 상태로 앱을 배포하면 임금 체불 등 법적 리스크가 발생합니다."
    echo ""
    echo "  실패한 테스트를 확인하세요:"
    echo "    cd packages/shared_logic"
    echo "    flutter test test/compliance/ --reporter expanded"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    exit 1
fi

# ── STEP 2: Flutter 앱 빌드 ──
cd "$BOSS_MOBILE"

BUILD_MODE="${1:-debug}"

echo "📦 [2/2] Flutter 앱 빌드 ($BUILD_MODE)..."
echo ""

case "$BUILD_MODE" in
    release)
        flutter build apk --release
        ;;
    appbundle)
        flutter build appbundle --release
        ;;
    debug|*)
        flutter build apk --debug
        ;;
esac

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✅ 빌드 완료 — 법률 테스트 통과 + APK 생성 성공"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
