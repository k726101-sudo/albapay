const { initializeTestEnvironment, assertFails, assertSucceeds } = require('@firebase/rules-unit-testing');
const fs = require('fs');

async function main() {
  let testEnv = await initializeTestEnvironment({
    projectId: "standard-albapay-test",
    firestore: {
      rules: fs.readFileSync("/Users/kimkyoungil/Downloads/pb-manager antigravity/firestore.rules", "utf8"),
    },
  });

  const uid = "alba_user_123";
  const storeId = "store_abc";
  const workerId = "worker_xyz";

  // setup db using an admin context
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await db.collection("users").doc(uid).set({
      storeId: storeId,
      workerId: workerId,
      role: "worker"
    });
  });

  // test alba context
  const albaDb = testEnv.authenticatedContext(uid).firestore();

  const attendanceData = {
    staffId: workerId,
    storeId: storeId,
    clockIn: "2026-05-07T12:00:00.000Z",
    clockOut: null,
    isEditedByBoss: false,
    overtimeApproved: false,
    isAttendanceEquivalent: false
  };

  try {
    await assertSucceeds(albaDb.collection("attendance").doc("att1").set(attendanceData));
    console.log("SUCCESS: rule allowed it");
  } catch (err) {
    console.error("FAIL: rule denied it", err);
  }

  await testEnv.cleanup();
}
main();
