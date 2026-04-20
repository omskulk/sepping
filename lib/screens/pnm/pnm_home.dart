import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/app_user.dart';
import '../../models/ping.dart';
import '../../services/ping_service.dart';
import '../../theme/app_theme.dart';
import '../shared/app_scaffold.dart';
import 'ping_detail_screen.dart';

class PnmHome extends StatelessWidget {
  const PnmHome({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AppUser>();
    final pings = context.read<PingService>();
    return AppScaffold(
      title: 'PNM · ${user.displayName}',
      subtitle: 'Your assigned pings. Go there, prove it, climb the board.',
      body: StreamBuilder<List<Ping>>(
        stream: pings.watchPingsAssignedTo(user.uid),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final list = snap.data ?? const [];
          if (list.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No pings assigned yet.\nStay ready.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: SepColors.blueGray),
                ),
              ),
            );
          }

          final pending = list.where((p) => p.status == PingStatus.pending).toList();
          final done = list.where((p) => p.status == PingStatus.completed).toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              if (pending.isNotEmpty) ...[
                Text('TO DO',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                ...pending.map((p) => _PingRow(ping: p)),
                const SizedBox(height: 24),
              ],
              if (done.isNotEmpty) ...[
                Text('COMPLETED',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                ...done.map((p) => _PingRow(ping: p)),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _PingRow extends StatelessWidget {
  const _PingRow({required this.ping});
  final Ping ping;

  @override
  Widget build(BuildContext context) {
    final pending = ping.status == PingStatus.pending;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => PingDetailScreen(pingId: ping.id),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(
                pending ? Icons.location_on : Icons.check_circle,
                color: pending ? SepColors.navy : SepColors.success,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(ping.taskDescription,
                        style: Theme.of(context).textTheme.titleSmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Text(
                      'From ${ping.createdByName} · ${DateFormat.MMMd().add_jm().format(ping.createdAt)}',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: SepColors.blueGray),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: SepColors.blueGray),
            ],
          ),
        ),
      ),
    );
  }
}
