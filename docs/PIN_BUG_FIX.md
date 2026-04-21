# Bugfix: pin click-through on Flutter web

## Symptom

When dropping a ping as an active:

1. Tap a location on the map → marker appears, "Drop a ping" dialog opens
2. Click the **DROP PIN** button inside the dialog
3. The marker visibly moves to the location of the button you just clicked
4. The ping fires at the wrong (or duplicate) location

Reported by Om while testing the active flow.

## Root cause

`google_maps_flutter_web` renders Google Maps as a real `<iframe>` via
Flutter's `HtmlElementView` platform-view mechanism. This is fundamentally
different from a normal Flutter widget tree:

- A normal Flutter dialog (`showDialog`) renders as Flutter widgets in the
  same canvas, and pointer events are dispatched top-down by the framework.
- An `HtmlElementView` is a real DOM element living **outside** the Flutter
  canvas. The browser's native event system can deliver clicks to it
  regardless of what Flutter has painted on top.

Result: the click on **DROP PIN** registered as a Flutter event (closing the
dialog and firing the ping) **and** as a DOM click on the underlying map
iframe (firing `GoogleMap.onTap` again with the screen coordinates of the
button).

This is a known wart of `HtmlElementView`. The Flutter team's official
mitigation is the [`pointer_interceptor`](https://pub.dev/packages/pointer_interceptor)
package, which inserts an invisible HTML element above the platform view to
swallow events that would otherwise leak through.

## Fix

### Primary: wrap the dialog in `PointerInterceptor`

`lib/screens/active/drop_ping_dialog.dart`:

```dart
import 'package:pointer_interceptor/pointer_interceptor.dart';
// ...
return PointerInterceptor(
  child: AlertDialog( ... ),
);
```

`PointerInterceptor` is a no-op on non-web platforms, so this change is safe
for the eventual iOS/Android builds.

### Defense-in-depth: ignore map taps while a dialog is open

`lib/screens/active/active_home.dart` already tracked `_pendingTap`, which is
non-null exactly while the dialog is open. We now pass `onTap: null` to
`GoogleMap` in that state, so even if `PointerInterceptor` somehow misses a
gesture (different package version, different platform plugin behavior), the
worst case is the map ignores the leak instead of acting on it:

```dart
final dialogOpen = _pendingTap != null;
final map = _MapPanel(
  ...
  onTap: dialogOpen ? null : _onTap,
);
```

`_MapPanel.onTap` was widened to `void Function(LatLng)?` to accept null.

## Dependency added

`pubspec.yaml`:

```yaml
pointer_interceptor: ^0.10.1+2
```

Maintained by Flutter Community / formerly Flutter team. Stable, ~tiny.

## Verification steps

After `flutter pub get` and `flutter run -d chrome`:

1. Sign in as an active.
2. Tap somewhere on the map. Dialog appears.
3. **Click anywhere inside the dialog (button, slider, dropdown, blank space).**
   The map's marker should NOT move, and no second dialog should open.
4. Click the dialog's DROP PIN button. Snackbar confirms one ping dropped at
   the **original** tap location, not the button location.
5. Verify in Firestore that a single `/pings/*` doc exists with the correct
   lat/lng.

## Why both fixes (and not just one)

- `PointerInterceptor` alone: bulletproof on web, but it's a third-party
  package — version drift could regress this.
- `dialogOpen` guard alone: works without any new dependency, but it relies on
  Flutter knowing the click reached the map. If a future change makes the map
  consume the click before `onTap` is checked (e.g., starts panning the
  camera), the guard misses.

Both together: the click is blocked at the DOM layer, and even if a stray
gesture sneaks through, the `onTap` handler is wired to null so nothing
happens. Cheap insurance.
