import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/app_user.dart';
import '../../models/strike.dart';
import '../../services/strike_service.dart';
import '../../theme/app_theme.dart';

/// NME-only screen for amending or removing already-approved strikes. Lists
/// every strike (most recent first), grouped by status (active vs removed),
/// and lets the NME open an edit dialog or soft-delete.
///
/// Intentionally minimal — this is the "task page" placeholder Om asked for;
/// expand it later if you want a richer audit/review UI.
class StrikeAmendmentsScreen extends StatelessWidget {
  const StrikeAmendmentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AppUser>();
    if (!user.isNme) {
      return Scaffold(
        appBar: AppBar(title: const Text('AMENDMENTS')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('Only the NME can amend or remove strikes.'),
          ),
        ),
      );
    }

    final strikes = context.read<StrikeService>();
    return Scaffold(
      appBar: AppBar(title: const Text('STRIKE AMENDMENTS')),
      body: StreamBuilder<List<Strike>>(
        stream: strikes.watchAllStrikes(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final all = snap.data ?? const <Strike>[];
          if (all.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No approved strikes yet.',
                  style: TextStyle(color: SepColors.blueGray),
                ),
              ),
            );
          }
          final active = all.where((s) => !s.removed).toList();
          final removed = all.where((s) => s.removed).toList();
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (active.isNotEmpty) ...[
                Text('ACTIVE',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                ...active.map((s) => _StrikeRow(strike: s, nme: user)),
                const SizedBox(height: 24),
              ],
              if (removed.isNotEmpty) ...[
                Text('REMOVED',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                ...removed.map((s) => _StrikeRow(strike: s, nme: user)),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _StrikeRow extends StatelessWidget {
  const _StrikeRow({required this.strike, required this.nme});
  final Strike strike;
  final AppUser nme;

  Future<void> _amend(BuildContext context) async {
    // Capture context-bound objects synchronously before the first await so
    // the analyzer can prove we don't reuse `context` across an async gap.
    final service = context.read<StrikeService>();
    final messenger = ScaffoldMessenger.of(context);
    final ctrl = TextEditingController(text: strike.effectiveReason);
    final newReason = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Amend strike'),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'New reason'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text),
            child: const Text('SAVE'),
          ),
        ],
      ),
    );
    if (newReason == null) return;
    try {
      await service.amendStrike(strike: strike, nme: nme, newReason: newReason);
      messenger.showSnackBar(
        const SnackBar(content: Text('Amendment saved.')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _remove(BuildContext context) async {
    final service = context.read<StrikeService>();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove strike?'),
        content: Text(
            'This will decrement ${strike.pnmName}\'s strike count. The audit record stays.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('REMOVE'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await service.removeStrike(strike: strike, nme: nme);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat.MMMd().add_jm().format(strike.createdAt);
    final faded = strike.removed;
    return Card(
      color: faded ? SepColors.gray.withValues(alpha: .3) : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    strike.pnmName,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          decoration:
                              faded ? TextDecoration.lineThrough : null,
                        ),
                  ),
                ),
                Text(dateStr,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: SepColors.blueGray)),
              ],
            ),
            const SizedBox(height: 4),
            Text(strike.effectiveReason),
            if (strike.isAmended) ...[
              const SizedBox(height: 4),
              Text(
                'Amended (was: ${strike.reason})',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: SepColors.blueGray),
              ),
            ],
            const SizedBox(height: 4),
            Text(
              'Filed by ${strike.issuedByName} · approved by ${strike.approvedByName}',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: SepColors.blueGray),
            ),
            if (!faded) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () => _amend(context),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('AMEND'),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () => _remove(context),
                    icon: const Icon(Icons.delete_outline,
                        size: 18, color: SepColors.danger),
                    label: const Text('REMOVE',
                        style: TextStyle(color: SepColors.danger)),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
