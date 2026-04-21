import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/app_user.dart';
import '../../models/strike.dart';
import '../../services/strike_service.dart';
import '../../theme/app_theme.dart';

/// PNM-facing read-only view of strikes against them this cycle. Removed
/// strikes are hidden (not their concern); only the live count + reasons show.
class MyStrikesScreen extends StatelessWidget {
  const MyStrikesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AppUser>();
    final strikes = context.read<StrikeService>();
    return Scaffold(
      appBar: AppBar(title: const Text('MY STRIKES')),
      body: StreamBuilder<List<Strike>>(
        stream: strikes.watchStrikesForPnm(user.uid),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final list = (snap.data ?? const <Strike>[])
              .where((s) => !s.removed)
              .toList();
          return Column(
            children: [
              Container(
                width: double.infinity,
                color: list.isEmpty
                    ? SepColors.success.withValues(alpha: .15)
                    : SepColors.danger.withValues(alpha: .15),
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Text(
                      list.isEmpty ? 'CLEAN SLATE' : '${list.length} STRIKE(S)',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      list.isEmpty
                          ? 'No strikes against you this cycle. Keep it that way.'
                          : 'Approved by the NME. Talk to them if you think any are unfair.',
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: list.isEmpty
                    ? const SizedBox.shrink()
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: list.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (_, i) => _StrikeCard(strike: list[i]),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StrikeCard extends StatelessWidget {
  const _StrikeCard({required this.strike});
  final Strike strike;

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat.yMMMd().add_jm().format(strike.createdAt);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: SepColors.danger),
                const SizedBox(width: 6),
                Text('STRIKE',
                    style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                Text(dateStr,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: SepColors.blueGray)),
              ],
            ),
            const SizedBox(height: 8),
            Text(strike.effectiveReason,
                style: Theme.of(context).textTheme.bodyLarge),
            if (strike.isAmended) ...[
              const SizedBox(height: 4),
              Text('(amended)',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: SepColors.blueGray)),
            ],
          ],
        ),
      ),
    );
  }
}
