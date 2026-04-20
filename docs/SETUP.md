# SigEP Ping — setup & run

Already done by you (you did these while the coffee was brewing):

- ✅ Node + npm + firebase-tools + flutterfire CLI installed
- ✅ Firebase project `sepping77` created
- ✅ Auth (Email/Password), Firestore (test mode), Storage enabled
- ✅ Blaze plan with a $5 budget alert
- ✅ `flutterfire configure` run → `lib/firebase_options.dart` generated
- ✅ Google Maps JS API + Geocoding API enabled; restricted API key in `web/index.html`

## First run

From `~/redmed/sepping`:

```bash
flutter pub get
flutter run -d chrome
```

That should open Chrome at something like `http://localhost:53xxx`. Sign up one account
as `active` and one as `pnm` (use different emails) to see both flows.

If Chrome opens on a port the Maps key doesn't recognize, edit the referrer list on
your API key in Google Cloud Console and add the specific port, or just keep hitting
reload — the `localhost:*` entry covers all ports.

## Deploy the security rules (recommended before sharing the app)

Firestore is in test mode, which auto-expires after 30 days. Before that — and before
you give real chapter members the URL — deploy the rules shipped in this repo:

```bash
# from ~/redmed/sepping (one-time per machine)
firebase use --add        # pick sepping77, alias it "default"

# one-time init to wire rules files to Firebase:
firebase init firestore   # press Enter to accept firestore.rules
firebase init storage     # press Enter to accept storage.rules
# say NO when asked to overwrite existing firestore.rules/storage.rules

# deploy
firebase deploy --only firestore:rules,storage:rules
```

## Adding ping credits manually

There's no admin UI yet. To grant an Active more credits:

1. Firebase console → Firestore → `users` → pick the user's doc
2. Edit `pingCredits` → save

Or use the Firebase CLI:
```bash
# example - only works if you have admin privileges; not documented here
```

## Running on iOS (when you're ready)

1. `flutterfire configure` again in `~/redmed/sepping`; this time select `ios` too.
2. That writes `ios/Runner/GoogleService-Info.plist`.
3. Get a **Maps SDK for iOS** key (different from the JS one!) in Google Cloud Console,
   restrict by bundle ID.
4. Add to `ios/Runner/AppDelegate.swift`:
   ```swift
   import GoogleMaps
   GMSServices.provideAPIKey("YOUR_IOS_KEY")
   ```
5. Add camera + location permission strings to `ios/Runner/Info.plist`
   (`NSCameraUsageDescription`, `NSLocationWhenInUseUsageDescription`).
6. `flutter run -d <device>`.

## Troubleshooting

- **"This page can't load Google Maps correctly"** — referrer mismatch. Make sure the
  Chrome URL host (`localhost` / `127.0.0.1`) matches an entry in the key's Website
  restrictions, and that the key's API restrictions include Maps JavaScript API.
- **Map is a grey box, no error** — the `<script>` tag probably didn't load; check
  Network tab. Often a missing `&loading=async` or an ad blocker.
- **"PERMISSION_DENIED" in console when writing a ping** — rules are deployed and you
  don't match them. Double-check the user doc has `role: "active"`.
- **Images don't upload** — you forgot to enable Storage, or the user isn't signed in
  when the upload starts. The rules require `request.auth != null`.
- **Hot reload shows a blank map** — Flutter web map widget doesn't survive hot
  reload well. Hot restart (`R` in the terminal) instead.

## Known limitations (track these before demoing)

- No admin to approve proof — photo upload auto-completes the ping.
- Client-side credit transactions; a determined user with dev tools can bypass.
- No way to cancel a mis-drop pin yet.
- No push notifications.
- Web only.

## Branch conventions

This code was written on `cbb` (coffee break branch) without per-file approval per the
project's "BLIND BUILD" clause in `CLAUDE.md`. Review diffs normally and commit when
satisfied; commits are your call, not Claude's.
