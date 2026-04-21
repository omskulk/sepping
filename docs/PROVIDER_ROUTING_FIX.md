# Bug: "Could not find the correct Provider<AppUser> above ..."

## Symptom

Clicking **Strike approvals** or **Strike amendments** from the gavel menu
(as the NME) produced a full-screen red error in the Flutter `ErrorWidget`:

```
Error: Could not find the correct Provider<AppUser> above this
StrikeApprovalsScreen Widget
```

Same error for `StrikeAmendmentsScreen`. The pages never rendered.

## Root cause

`AuthGate` → `_RoleRouter` produces an `AppUser` and wraps the role-home
screen in `Provider<AppUser>.value`:

```dart
return Provider<AppUser>.value(
  value: appUser,
  child: appUser.isActive ? const ActiveHome() : const PnmHome(),
);
```

That provider sits **below** `MaterialApp`'s top-level Navigator. When
`AppScaffold._StrikeMenu._go` ran
`Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen))`,
the new route was mounted by that top-level Navigator, which means the
pushed subtree was **above** the `Provider<AppUser>.value` in the widget
tree. So `AppScaffold`'s `context.watch<AppUser>()` inside the pushed
strike screens threw `ProviderNotFoundException`.

This is the single most common Provider pitfall with Flutter's Navigator:
routes pushed on the root navigator don't inherit providers scoped below
`MaterialApp`.

## Fix

Re-inject `AppUser` at the push site. `_go` now wraps the pushed screen in
`Provider<AppUser>.value` with the user already available in scope:

```dart
void _go(BuildContext context, Widget screen) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => Provider<AppUser>.value(value: user, child: screen),
    ),
  );
}
```

The leaderboard push was patched the same way for consistency (even though
`LeaderboardScreen` itself doesn't `watch<AppUser>()` today — if anyone adds
one, it won't break).

## Alternatives considered

- **Lift `Provider<AppUser>` above `MaterialApp`.** Cleanest architecturally,
  but requires restructuring `AuthGate` into a `StreamProvider<AppUser?>`
  exposed through `MaterialApp.builder`. More moving parts for equal effect
  in MVP.
- **`MaterialApp.onGenerateRoute`.** Would let us wrap every route
  centrally, but we don't currently use named routes.
- **Use `rootNavigator: false`.** Requires a nested `Navigator` below
  `Provider<AppUser>.value`, more plumbing than the surgical fix is worth.

The surgical fix is local to one file (`app_scaffold.dart`), keeps the
existing `AuthGate` structure, and makes the coupling explicit: if you push
a screen that needs `AppUser`, you re-provide it at the push.
