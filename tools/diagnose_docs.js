const admin = require('firebase-admin');
const serviceAccount = require('../service-account.json');

if (admin.apps.length === 0) {
    admin.initializeApp({
        credential: admin.credential.cert(serviceAccount)
    });
}

const db = admin.firestore();

async function listAllWorkers() {
    const storeId = 'debug_store_v30';
    console.log(`--- Listing All Workers in Store: ${storeId} ---`);

    const workersSnap = await db.collection('stores').doc(storeId).collection('workers').get();
    
    if (workersSnap.empty) {
        console.log(`❌ No workers found in store ${storeId}`);
        return;
    }

    workersSnap.forEach(doc => {
        const d = doc.data();
        console.log(`👤 Worker: ${d.name} [id: ${doc.id}]`);
        console.log(`   - phone: ${d.phone}`);
        console.log(`   - inviteCode: ${d.inviteCode}`);
        console.log(`   - status: ${d.status}`);
        console.log(`   - uid: ${d.uid || 'Not linked'}`);
    });

    const docsSnap = await db.collection('stores').doc(storeId).collection('documents').get();
    console.log(`\n--- Documents in Store ---`);
    docsSnap.forEach(doc => {
        const d = doc.data();
        console.log(`📄 Doc: ${d.title} [id: ${doc.id}]`);
        console.log(`   - staffId: ${d.staffId}`);
        console.log(`   - status: ${d.status}`);
    });
}

listAllWorkers().catch(console.error);
