const admin = require('firebase-admin');

// Try to initialize. It might use gcloud default credentials.
admin.initializeApp({
  projectId: 'standard-albapay'
});

const db = admin.firestore();

async function check() {
  try {
    const snapshot = await db.collectionGroup('workers').get();
    let total = 0;
    let underMin = 0;
    
    snapshot.forEach(doc => {
      total++;
      const data = doc.data();
      const hw = data.hourlyWage || 0;
      const isProb = data.isProbation === true;
      const probWage = isProb ? hw * 0.9 : hw;
      
      if (probWage > 0 && probWage < 10320) {
        underMin++;
        console.log(`Violation found! Store: ${data.storeId}, Worker: ${data.name}, Type: ${data.wageType}, Hourly: ${hw}, Probation: ${isProb}, Final Rate: ${probWage}`);
      }
    });
    
    console.log(`Total workers: ${total}, Under minimum: ${underMin}`);
  } catch (e) {
    console.error(e);
  }
}

check();
