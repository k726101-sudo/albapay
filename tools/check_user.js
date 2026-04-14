const admin = require('firebase-admin');
const serviceAccount = require('../service-account.json');

if (admin.apps.length === 0) {
    admin.initializeApp({
        credential: admin.credential.cert(serviceAccount)
    });
}

const db = admin.firestore();

async function checkUserDoc() {
    const testPhone = '01053192915';
    console.log(`--- Checking Users for Phone: ${testPhone} ---`);

    // We don't have phone filter in users directly usually, but let's check by UID if we knew it.
    // Actually, let's find the user doc that has storeId: 'debug_store_v30'
    const usersSnap = await db.collection('users').where('storeId', '==', 'debug_store_v30').get();
    
    usersSnap.forEach(doc => {
        const d = doc.data();
        console.log(`👤 User UID: ${doc.id}`);
        console.log(`   - workerId: ${d.workerId}`);
        console.log(`   - name: ${d.name}`);
        console.log(`   - phone: ${d.phone || 'N/A'}`);
    });
}

checkUserDoc().catch(console.error);
