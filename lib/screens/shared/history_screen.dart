import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/app_user.dart';
import '../../models/ping.dart';
import '../../services/ping_service.dart';
import '../../theme/app_theme.dart';
import '../pnm/ping_detail_screen.dart';

/// Shared archive view. Same content for everyone — every chapter-completed
/// ping appears here, regardless of role or original eligibility. The "MINE"
/// chip lights up if the viewer authored the ping (active) or contributed a
/// completed claim to it (PNM).
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final me = context.watch<AppUser>();
    final pings = context.read<PingService>();
    return Scaffold(
      appBar: AppBar(title: const Text('HISTORY')),
      body: StreamBuilder<List<Ping>>(
        stream: pings.watchCompletedPings(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final completed = snap.data ?? const <Ping>[];
          if (completed.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Text(
                  'No completed pings in the chapter yet.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: SepColors.blueGray),
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: completed.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _HistoryRow(ping: completed[i], me: me),
          );
        },
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.ping, required this.me});
  final Ping ping;
  final AppUser me;

  @override
  Widget build(BuildContext context) {
    // For PNM viewer prefer their personal completion timestamp.
    final ts = me.isPnm
        ? (ping.claimFor(me.uid)?.completedAt ?? ping.completedAt ?? ping.createdAt)
        : (ping.completedAt ?? ping.createdAt);
    // "MINE" lights up for the active creator OR for a PNM who personally
    // contributed a completed claim. Lets each viewer instantly see their
    // own footprint in the chapter history.
    final mine = me.isActive
        ? ping.createdBy == me.uid
        : (ping.claimFor(me.uid)?.isCompleted ?? false);
    return Card(
      child: ListTile(
        leading: const Icon(Icons.check_circle, color: SepColors.success),
        title: Row(
          children: [
            Expanded(
              child: Text(
                ping.taskDescription,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            if (mine)
              const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text('MINE'),
                ),
              ),
          ],
        ),
        subtitle: Text(
          'by ${ping.createdByName} · ${ping.claims.length}/${ping.capacity} done · '
          '${DateFormat.yMMMd().add_jm().format(ts)}',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: SepColors.blueGray),
        ),
        trailing: const Icon(Icons.chevron_right, color: SepColors.blueGray),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => Provider<AppUser>.value(
              value: me,
              child: PingDetailScreen(pingId: ping.id),
            ),
          ),
        ),
      ),
    );
  }
}
