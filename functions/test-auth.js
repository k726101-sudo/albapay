const admin = require("firebase-admin");
const fs = require('fs');

if (!admin.apps.length) {
  admin.initializeApp();
}

async function run() {
  try {
    const uid = "alba_user_123";
    const customToken = await admin.auth().createCustomToken(uid);
    console.log(customToken);
  } catch(e) {
    console.log("Error:", e);
  }
}
run();
