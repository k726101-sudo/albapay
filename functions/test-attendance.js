const admin = require("firebase-admin");
const { getFirestore } = require("firebase-admin/firestore");

if (!admin.apps.length) {
  admin.initializeApp();
}

async function testAttendance() {
  const db = getFirestore();
  const dbRest = require('firebase/firestore'); // Needs firebase client SDK to simulate user rules
  // Wait, I can't easily test rules using Admin SDK because Admin SDK bypasses all rules.
}
