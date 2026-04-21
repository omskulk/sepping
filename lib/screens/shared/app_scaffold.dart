import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/app_user.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../active/bulletin_screen.dart';
import '../active/strike_amendments_screen.dart';
import '../active/strike_approvals_screen.dart';
import '../active/strike_request_form.dart';
import '../pnm/my_strikes_screen.dart';
import 'history_screen.dart';
import 'leaderboard_screen.dart';

/// Shared chrome for the two role-home screens. Keeps the header look identical
/// across roles so the app feels coherent as you switch accounts while testing.
class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    required this.title,
    required this.body,
    this.floatingActionButton,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final Widget body;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AppUser>();
    return Scaffold(
      appBar: AppBar(
        title: Text(title.toUpperCase()),
        actions: [
          if (user.isActive)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(
                child: Chip(
                  backgroundColor: SepColors.lightBlue,
                  label: Text('${user.pingCredits} credits',
                      style: const TextStyle(color: SepColors.darkNavy)),
                ),
              ),
            ),
          // Active-only entry point to the chapter-wide draft bulletin.
          // Lives on its own page so the home screen's published-pings
          // list has the full right column.
          if (user.isActive)
            IconButton(
              tooltip: 'Bulletin (drafts)',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => Provider<AppUser>.value(
                    value: user,
                    child: const BulletinScreen(),
                  ),
                ),
              ),
              icon: const Icon(Icons.assignment_outlined),
            ),
          IconButton(
            tooltip: 'History',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => Provider<AppUser>.value(
                  value: user,
                  child: const HistoryScreen(),
                ),
              ),
            ),
            icon: const Icon(Icons.history),
          ),
          IconButton(
            tooltip: 'Leaderboard',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => Provider<AppUser>.value(
                  value: user,
                  child: const LeaderboardScreen(),
                ),
              ),
            ),
            icon: const Icon(Icons.emoji_events_outlined),
          ),
          _StrikeMenu(user: user),
          IconButton(
            tooltip: 'Sign out',
            onPressed: () => context.read<AuthService>().signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
        bottom: subtitle == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(28),
                child: Container(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  color: SepColors.navy,
                  child: Text(
                    subtitle!,
                    style: const TextStyle(color: SepColors.lightBlue, fontSize: 13),
                  ),
                ),
              ),
      ),
      body: body,
      floatingActionButton: floatingActionButton,
    );
  }
}

/// Single popup-menu entry point for everything strike-related, role-aware:
///   - PNM:    "My strikes" (read-only count + reasons)
///   - Active: "Submit strike request" (for the NME to review)
///   - NME:    "Strike approvals" inbox + "Strike amendments" audit/edit
class _StrikeMenu extends StatelessWidget {
  const _StrikeMenu({required this.user});
  final AppUser user;

  // Pushed routes mount at MaterialApp's Navigator — ABOVE the `Provider<AppUser>.value`
  // in AuthGate. Without re-injecting here, AppScaffold's `context.watch<AppUser>()`
  // inside the pushed strike screens throws ProviderNotFoundException.
  void _go(BuildContext context, Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Provider<AppUser>.value(value: user, child: screen),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Strikes',
      icon: const Icon(Icons.gavel),
      onSelected: (v) {
        switch (v) {
          case 'submit':
            _go(context, const StrikeRequestForm());
            break;
          case 'approvals':
            _go(context, const StrikeApprovalsScreen());
            break;
          case 'amendments':
            _go(context, const StrikeAmendmentsScreen());
            break;
          case 'mine':
            _go(context, const MyStrikesScreen());
            break;
        }
      },
      itemBuilder: (_) => [
        if (user.isPnm)
          const PopupMenuItem(value: 'mine', child: Text('My strikes')),
        if (user.isActive)
          const PopupMenuItem(
              value: 'submit', child: Text('Submit strike request')),
        if (user.isNme) ...[
          const PopupMenuDivider(),
          const PopupMenuItem(
              value: 'approvals', child: Text('Strike approvals')),
          const PopupMenuItem(
              value: 'amendments', child: Text('Strike amendments')),
        ],
      ],
    );
  }
}
