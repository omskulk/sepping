// Wipes ONLY users tagged with isTestUser=true. Real chapter accounts are
// untouched because they will never have that flag.
//
// Also deletes every /strikes and /strikeRequests doc that references a
// test user (since those are meaningless once the user is gone).
//
// Usage:
//   node unseed.js

const { auth, db } = require("./firebase-init");

async function deleteCollectionWhere(name, field, op, value) {
  const snap = await db.collection(name).where(field, op, value).get();
  if (snap.empty) return 0;
  const batch = db.batch();
  snap.docs.forEach((d) => batch.delete(d.ref));
  await batch.commit();
  return snap.size;
}

(async () => {
  console.log("Unseeding test data...");

  // 1. Find all test users
  const testUsers = await db.collection("users").where("isTestUser", "==", true).get();
  const testUids = testUsers.docs.map((d) => d.id);
  console.log(`  Found ${testUids.length} test users in Firestore.`);

  if (testUids.length === 0) {
    console.log("Nothing to delete.");
    process.exit(0);
  }

  // 2. Delete strikes/strikeRequests linked to any test user.
  //    Firestore "in" queries cap at 30 values, so we chunk by 30.
  const chunk = (arr, n) => Array.from({ length: Math.ceil(arr.length / n) }, (_, i) => arr.slice(i * n, i * n + n));

  let strikeCount = 0;
  let requestCount = 0;
  for (const ids of chunk(testUids, 30)) {
    strikeCount += await deleteCollectionWhere("strikes", "pnmUid", "in", ids);
    requestCount += await deleteCollectionWhere("strikeRequests", "issuedBy", "in", ids);
    // strikeRequests targeting these PNMs — pnmUids is array, query with array-contains-any
    const targeted = await db
      .collection("strikeRequests")
      .where("pnmUids", "array-contains-any", ids)
      .get();
    if (!targeted.empty) {
      const b = db.batch();
      targeted.docs.forEach((d) => b.delete(d.ref));
      await b.commit();
      requestCount += targeted.size;
    }
  }
  console.log(`  Deleted ${strikeCount} strikes, ${requestCount} strikeRequests.`);

  // 3. Delete pings created by or assigned to test users (keeps prod pings safe).
  let pingCount = 0;
  for (const ids of chunk(testUids, 30)) {
    pingCount += await deleteCollectionWhere("pings", "createdBy", "in", ids);
    pingCount += await deleteCollectionWhere("pings", "assignedTo", "in", ids);
  }
  console.log(`  Deleted ${pingCount} pings.`);

  // 4. Delete the user docs.
  const userBatch = db.batch();
  testUsers.docs.forEach((d) => userBatch.delete(d.ref));
  await userBatch.commit();
  console.log(`  Deleted ${testUsers.size} user docs.`);

  // 5. Delete the Auth records (no batch API; loop one at a time).
  let authDeleted = 0;
  for (const uid of testUids) {
    try {
      await auth.deleteUser(uid);
      authDeleted++;
    } catch (err) {
      if (err.code !== "auth/user-not-found") {
        console.warn(`  Could not delete auth user ${uid}: ${err.message}`);
      }
    }
  }
  console.log(`  Deleted ${authDeleted} auth users.`);

  console.log("\nDone. Real chapter data was not touched.");
  process.exit(0);
})();
