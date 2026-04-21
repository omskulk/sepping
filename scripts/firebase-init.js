// Shared Admin SDK initializer used by every script in this folder.
// Reads the service account key from ../serviceAccountKey.json (gitignored).
//
// If you ever rotate the key:
//   1. Generate a new one in Firebase Console -> Project Settings -> Service Accounts.
//   2. Move it to /serviceAccountKey.json (overwrite the old one).
//   3. Revoke the old key in the Console.

const admin = require("firebase-admin");
const path = require("path");

const KEY_PATH = path.join(__dirname, "..", "serviceAccountKey.json");

let serviceAccount;
try {
  serviceAccount = require(KEY_PATH);
} catch (err) {
  console.error(
    `Could not load service account key at ${KEY_PATH}.\n` +
      `Download a new one from Firebase Console -> Project Settings -> Service Accounts.`
  );
  process.exit(1);
}

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
  });
}

module.exports = {
  admin,
  auth: admin.auth(),
  db: admin.firestore(),
};
