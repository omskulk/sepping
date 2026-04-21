// Seeds the project with fake users for local testing.
// Every user written here is tagged with `isTestUser: true` so unseed.js can
// safely wipe only this data and never touch real chapter accounts.
//
// Usage:
//   node seed.js
//
// Login credentials (all share the same password by design — these are throwaway
// test accounts):
//   nme@sepping.test         / Test1234!   (active + isNme=true)
//   active01..05@sepping.test / Test1234!  (active)
//   pnm01..20@sepping.test    / Test1234!  (pnm)

const { auth, db, admin } = require("./firebase-init");

const PASSWORD = "Test1234!";
const ACTIVE_STARTING_CREDITS = 10; // mirror AuthService.activeStartingCredits

const USERS = [
  // 1 NME (an active with isNme=true; the only one who can approve strikes)
  {
    email: "nme@sepping.test",
    displayName: "NME (Test)",
    role: "active",
    isNme: true,
  },
  // 5 actives
  ...Array.from({ length: 5 }, (_, i) => ({
    email: `active${String(i + 1).padStart(2, "0")}@sepping.test`,
    displayName: `Active ${String(i + 1).padStart(2, "0")}`,
    role: "active",
    isNme: false,
  })),
  // 20 PNMs
  ...Array.from({ length: 20 }, (_, i) => ({
    email: `pnm${String(i + 1).padStart(2, "0")}@sepping.test`,
    displayName: `PNM ${String(i + 1).padStart(2, "0")}`,
    role: "pnm",
    isNme: false,
  })),
];

async function ensureUser({ email, displayName, role, isNme }) {
  // If a user with this email already exists, reuse the uid (idempotent reseed).
  let userRecord;
  try {
    userRecord = await auth.getUserByEmail(email);
  } catch (err) {
    if (err.code !== "auth/user-not-found") throw err;
    userRecord = await auth.createUser({
      email,
      password: PASSWORD,
      displayName,
      emailVerified: true,
    });
  }

  const isActive = role === "active";
  await db.collection("users").doc(userRecord.uid).set(
    {
      email,
      displayName,
      role,
      isNme,
      pingCredits: isActive ? ACTIVE_STARTING_CREDITS : 0,
      completedPings: 0,
      strikes: 0,
      isTestUser: true,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );

  return userRecord.uid;
}

(async () => {
  console.log(`Seeding ${USERS.length} users with shared password "${PASSWORD}"...`);
  let created = 0;
  for (const u of USERS) {
    try {
      const uid = await ensureUser(u);
      console.log(`  OK  ${u.email.padEnd(30)} -> ${uid}${u.isNme ? "  [NME]" : ""}`);
      created++;
    } catch (err) {
      console.error(`  FAIL ${u.email}: ${err.message}`);
    }
  }
  console.log(`\nDone. ${created}/${USERS.length} users present.`);
  console.log(
    `\nLog in to the web app with any of:\n` +
      `  nme@sepping.test\n` +
      `  active01@sepping.test ... active05@sepping.test\n` +
      `  pnm01@sepping.test ... pnm20@sepping.test\n` +
      `Password for all: ${PASSWORD}\n`
  );
  process.exit(0);
})();
