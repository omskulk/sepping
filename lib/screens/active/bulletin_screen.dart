import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/app_user.dart';
import '../../models/ping.dart';
import '../../services/ping_service.dart';
import '../../theme/app_theme.dart';
import 'publish_ping_dialog.dart';

/// Standalone draft bulletin. Lives on its own page (instead of a sidebar
/// pane on ActiveHome) so the published-pings list on the home screen has
/// the full right column to itself. Any active can browse the bulletin;
/// only the original creator gets the PUBLISH affordance per row.
class BulletinScreen extends StatelessWidget {
  const BulletinScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final me = context.watch<AppUser>();
    final pings = context.read<PingService>();
    return Scaffold(
      appBar: AppBar(title: const Text('BULLETIN (DRAFTS)')),
      body: StreamBuilder<List<Ping>>(
        stream: pings.watchAllPings(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final drafts = (snap.data ?? const <Ping>[])
              .where((p) => p.isDraft)
              .toList();
          if (drafts.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Text(
                  'No drafts yet.\nDrop a pin from the home screen to start one.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: SepColors.blueGray),
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: drafts.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _DraftCard(ping: drafts[i], me: me),
          );
        },
      ),
    );
  }
}

class _DraftCard extends StatelessWidget {
  const _DraftCard({required this.ping, required this.me});
  final Ping ping;
  final AppUser me;

  @override
  Widget build(BuildContext context) {
    final mine = ping.createdBy == me.uid;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    ping.taskDescription,
                    style: Theme.of(context).textTheme.titleSmall,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text('${ping.totalCost} cr'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'by ${ping.createdByName} · ${ping.capacity} slot${ping.capacity == 1 ? '' : 's'} · '
              '${ping.creditCostPer} cr/slot',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: SepColors.blueGray),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                if (mine)
                  ElevatedButton.icon(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => PublishPingDialog(ping: ping),
                    ),
                    icon: const Icon(Icons.send_outlined, size: 16),
                    label: const Text('PUBLISH'),
                  )
                else
                  const Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text('Read-only · creator publishes'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
