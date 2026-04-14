/**
 * 사장님 계정에 관리자 권한(admin: true) 커스텀 클레임을 부여하는 스크립트입니다.
 * 
 * 실행 방법:
 * 1. 서비스 계정 키(JSON)를 다운로드하여 같은 폴더에 둡니다.
 * 2. `TARGET_UID` 상수에 사장님의 UID를 입력합니다.
 * 3. `node set_admin_claim.js` 실행
 */

const admin = require('firebase-admin');

// TODO: 서비스 계정 키 파일 경로를 입력하세요. (Firebase 콘솔 > 설정 > 서비스 계정에서 생성 가능)
const serviceAccount = require('../service-account.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const TARGET_UID = 'pumVfttHW8MZQcbF6lx9Oblakx52'; // 확인된 Google 로그인 UID

async function setAdminClaim(uid) {
  try {
    await admin.auth().setCustomUserClaims(uid, { admin: true });
    console.log(`✅ 성공: UID ${uid} (${'k726101@gmail.com'}) 에 관리자 권한(admin: true)이 부여되었습니다.`);
    
    // 반영 확인을 위해 유저 정보 다시 불러오기
    const user = await admin.auth().getUser(uid);
    console.log('현재 커스텀 클레임:', user.customClaims);
  } catch (error) {
    console.error('❌ 실패:', error);
  }
}

setAdminClaim(TARGET_UID);
