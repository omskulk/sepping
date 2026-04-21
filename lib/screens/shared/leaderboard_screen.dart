import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/app_user.dart';
import '../../services/user_service.dart';
import '../../theme/app_theme.dart';

class LeaderboardScreen extends StatelessWidget {
  const LeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final users = context.read<UserService>();
    return Scaffold(
      appBar: AppBar(title: const Text('PNM LEADERBOARD')),
      body: StreamBuilder<List<AppUser>>(
        stream: users.watchLeaderboard(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final list = snap.data ?? const [];
          if (list.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('No PNMs yet.'),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(height: 6),
            itemBuilder: (_, i) {
              final u = list[i];
              return Card(
                child: ListTile(
                  leading: _RankBadge(rank: i + 1),
                  title: Text(u.displayName,
                      style: Theme.of(context).textTheme.titleSmall),
                  subtitle: Text(u.email,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: SepColors.blueGray)),
                  trailing: Chip(
                    backgroundColor: SepColors.lightBlue,
                    label: Text('${u.completedPings} pings',
                        style: const TextStyle(color: SepColors.darkNavy)),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank});
  final int rank;

  @override
  Widget build(BuildContext context) {
    final bg = switch (rank) {
      1 => const Color(0xFFD4AF37),
      2 => const Color(0xFFB0B7C3),
      3 => const Color(0xFFCD7F32),
      _ => SepColors.navy,
    };
    return CircleAvatar(
      backgroundColor: bg,
      foregroundColor: SepColors.light,
      child: Text('$rank'),
    );
  }
}
