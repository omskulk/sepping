// End-of-cycle reset: deletes all PNMs (and their strikes/strikeRequests/pings)
// while leaving Actives and the NME intact. Run this when a rush cycle ends and
// you're ready to onboard a new pledge class.
//
// Usage:
//   node reset-cycle.js
//
// Safety net: prompts for "YES" confirmation before deleting anything real.

const readline = require("readline");
const { auth, db } = require("./firebase-init");

function prompt(question) {
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  return new Promise((resolve) => rl.question(question, (a) => { rl.close(); resolve(a); }));
}

async function deleteAllInCollection(name) {
  const snap = await db.collection(name).get();
  if (snap.empty) return 0;
  // Firestore batches cap at 500 ops.
  let count = 0;
  let batch = db.batch();
  for (const doc of snap.docs) {
    batch.delete(doc.ref);
    count++;
    if (count % 500 === 0) {
      await batch.commit();
      batch = db.batch();
    }
  }
  await batch.commit();
  return count;
}

(async () => {
  // 1. Find PNMs.
  const pnms = await db.collection("users").where("role", "==", "pnm").get();
  console.log(`Found ${pnms.size} PNMs.`);

  // 2. Count strikes / strikeRequests for the warning.
  const [strikes, requests] = await Promise.all([
    db.collection("strikes").get(),
    db.collection("strikeRequests").get(),
  ]);

  console.log(
    `\nThis will DELETE:\n` +
      `  - ${pnms.size} PNM user docs and auth records\n` +
      `  - ${strikes.size} strikes (entire collection)\n` +
      `  - ${requests.size} strikeRequests (entire collection)\n` +
      `  - All pings created by or assigned to those PNMs\n` +
      `\nActives and the NME will be preserved.\n`
  );
  const ans = await prompt('Type "YES" to confirm: ');
  if (ans.trim() !== "YES") {
    console.log("Aborted.");
    process.exit(0);
  }

  // 3. Wipe strikes + strikeRequests entirely (they're cycle-scoped).
  const sCount = await deleteAllInCollection("strikes");
  const rCount = await deleteAllInCollection("strikeRequests");
  console.log(`  Deleted ${sCount} strikes, ${rCount} strikeRequests.`);

  // 4. Delete pings tied to PNMs.
  const pnmUids = pnms.docs.map((d) => d.id);
  const chunk = (arr, n) => Array.from({ length: Math.ceil(arr.length / n) }, (_, i) => arr.slice(i * n, i * n + n));
  let pingCount = 0;
  for (const ids of chunk(pnmUids, 30)) {
    if (ids.length === 0) continue;
    const a = await db.collection("pings").where("createdBy", "in", ids).get();
    const b = await db.collection("pings").where("assignedTo", "in", ids).get();
    const batch = db.batch();
    a.docs.forEach((d) => batch.delete(d.ref));
    b.docs.forEach((d) => batch.delete(d.ref));
    await batch.commit();
    pingCount += a.size + b.size;
  }
  console.log(`  Deleted ${pingCount} pings.`);

  // 5. Delete the PNM docs + auth records.
  const userBatch = db.batch();
  pnms.docs.forEach((d) => userBatch.delete(d.ref));
  await userBatch.commit();
  let authDeleted = 0;
  for (const uid of pnmUids) {
    try {
      await auth.deleteUser(uid);
      authDeleted++;
    } catch (err) {
      if (err.code !== "auth/user-not-found") {
        console.warn(`  Could not delete auth ${uid}: ${err.message}`);
      }
    }
  }
  console.log(`  Deleted ${pnms.size} user docs, ${authDeleted} auth users.`);

  console.log("\nCycle reset. Actives and NME preserved. Ready for next pledge class.");
  process.exit(0);
})();
