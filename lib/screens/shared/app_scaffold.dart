import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/app_user.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
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
          IconButton(
            tooltip: 'Leaderboard',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const LeaderboardScreen()),
            ),
            icon: const Icon(Icons.emoji_events_outlined),
          ),
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
