const admin = require('firebase-admin');
const serviceAccount = require('../service-account.json');

if (admin.apps.length === 0) {
    admin.initializeApp({
        credential: admin.credential.cert(serviceAccount)
    });
}

const db = admin.firestore();

async function fixUserData() {
    const storeId = 'debug_store_v30';
    const testPhone = '01053192915';
    const testAlbaWorkerId = 'CzQTe8uK3CUs1Ggo9DNO4yXo1Gm2'; // From diagnostic logs

    console.log(`--- Fixing User Data for ${testPhone} ---`);

    // 1. 유저의 UID를 전화번호로 찾거나, 이미 알고 있는 UID를 사용
    // 사장님 앱에서 '테스트 알바'로 등록된 정보의 UID가 CzQTe8uK3CUs1Ggo9DNO4yXo1Gm2 임을 확인했습니다.
    const uid = 'CzQTe8uK3CUs1Ggo9DNO4yXo1Gm2';

    // 2. 해당 유저 문서 업데이트
    await db.collection('users').doc(uid).set({
        'storeId': storeId,
        'workerId': testAlbaWorkerId,
        'phone': testPhone,
        'updatedAt': admin.firestore.FieldValue.serverTimestamp()
    }, { merge: true });

    console.log(`✅ Updated users/${uid} with workerId: ${testAlbaWorkerId} and storeId: ${storeId}`);

    // 3. 만약 다른 UID로 로그인 중일 수도 있으니, 해당 전화번호를 가진 worker 문서에도 UID를 업데이트
    const workersSnap = await db.collection('stores').doc(storeId).collection('workers')
        .where('phone', '==', testPhone).get();
    
    if (!workersSnap.empty) {
        for (const doc of workersSnap.docs) {
            await doc.ref.update({ uid: uid });
            console.log(`✅ Linked worker document ${doc.id} to UID ${uid}`);
        }
    } else {
        // 만약 전화번호가 01000000000 이라면? (전 진단에서 확인됨)
        console.log(`⚠️ Phone ${testPhone} not found in workers. Checking fallback...`);
        const fallbackWorkers = await db.collection('stores').doc(storeId).collection('workers')
            .where('phone', '==', '01000000000').get();
        for (const doc of fallbackWorkers.docs) {
            await doc.ref.update({ phone: testPhone, uid: uid });
            console.log(`✅ Updated fallback worker ${doc.id} with REAL phone ${testPhone} and UID ${uid}`);
        }
    }

    console.log('--- Data Fix Complete ---');
}

fixUserData().catch(console.error);
