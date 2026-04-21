import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/app_user.dart';
import '../../models/ping.dart';
import '../../services/ping_service.dart';
import '../../services/user_service.dart';
import '../../theme/app_theme.dart';

/// Shared detail screen for both roles. Behavior branches on the viewer's
/// role + their relationship to this ping:
///
/// - Active creator / non-creator: read-only detail + claims list.
/// - PNM, not claimed, slots available & eligible: ACCEPT button.
/// - PNM, not claimed, full: disabled "Full" chip.
/// - PNM, claimed, not yet completed: SUBMIT PROOF button.
/// - PNM, claimed, completed: passive "Completed" badge + their photo.
class PingDetailScreen extends StatefulWidget {
  const PingDetailScreen({super.key, required this.pingId});
  final String pingId;

  @override
  State<PingDetailScreen> createState() => _PingDetailScreenState();
}

class _PingDetailScreenState extends State<PingDetailScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _openInMaps(Ping p) async {
    final uri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=${p.lat},${p.lng}');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _accept(Ping p) async {
    final pings = context.read<PingService>();
    final me = context.read<AppUser>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await pings.acceptPing(ping: p, pnm: me);
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Slot claimed.')));
    } on CannotAcceptPingException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.reason);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitProof(Ping p) async {
    final pings = context.read<PingService>();
    final me = context.read<AppUser>();
    final messenger = ScaffoldMessenger.of(context);
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1600,
    );
    if (picked == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bytes = await picked.readAsBytes();
      await pings.submitProof(
        ping: p,
        pnm: me,
        photoBytes: bytes,
        contentType: picked.mimeType ?? 'image/jpeg',
      );
      if (!mounted) return;
      messenger.showSnackBar(
          const SnackBar(content: Text('Proof submitted. +1 to your count.')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pings = context.read<PingService>();
    final me = context.watch<AppUser>();
    return Scaffold(
      appBar: AppBar(title: const Text('PING DETAIL')),
      body: StreamBuilder<Ping?>(
        stream: pings.watchPing(widget.pingId),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final p = snap.data;
          if (p == null) return const Center(child: Text('Ping not found.'));
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _Header(p: p),
              const SizedBox(height: 16),
              _Meta(p: p),
              const SizedBox(height: 16),
              _ActionBar(
                p: p,
                me: me,
                busy: _busy,
                error: _error,
                onOpenMaps: () => _openInMaps(p),
                onAccept: () => _accept(p),
                onSubmitProof: () => _submitProof(p),
              ),
              const SizedBox(height: 24),
              _ClaimsList(p: p, meUid: me.uid),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.p});
  final Ping p;
  @override
  Widget build(BuildContext context) {
    final color = switch (p.status) {
      PingStatus.completed => SepColors.success,
      PingStatus.full => SepColors.darkNavy,
      PingStatus.cancelled => SepColors.blueGray,
      PingStatus.open => SepColors.navy,
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.location_on, color: color),
                const SizedBox(width: 8),
                Text(p.status.label,
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                Chip(label: Text('${p.creditCostPer} cr/slot')),
              ],
            ),
            const Divider(height: 24),
            Text(p.taskDescription,
                style: Theme.of(context).textTheme.bodyLarge),
          ],
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.p});
  final Ping p;
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Row(label: 'FROM', value: p.createdByName),
            const SizedBox(height: 12),
            _Row(
              label: 'LOCATION',
              value: '${p.lat.toStringAsFixed(5)}, ${p.lng.toStringAsFixed(5)}',
            ),
            const SizedBox(height: 12),
            _Row(
              label: 'SLOTS',
              value: '${p.claims.length} of ${p.capacity} claimed · '
                  '${p.slotsRemaining} still open',
            ),
            const SizedBox(height: 12),
            _AudienceRow(p: p),
            const SizedBox(height: 12),
            _Row(
              label: 'CREATED',
              value: DateFormat.yMMMd().add_jm().format(p.createdAt),
            ),
            if (p.publishedAt != null) ...[
              const SizedBox(height: 12),
              _Row(
                label: 'PUBLISHED',
                value: DateFormat.yMMMd().add_jm().format(p.publishedAt!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Replaces the cryptic `visibility: specific` string with a human-readable
/// audience: either "Every PNM", a comma-separated list of selected PNM
/// names, or a draft notice. Streams the user directory to resolve uids to
/// names; falls back to a uid prefix if a user record vanishes.
class _AudienceRow extends StatelessWidget {
  const _AudienceRow({required this.p});
  final Ping p;

  @override
  Widget build(BuildContext context) {
    if (p.isDraft) {
      return const _Row(
        label: 'AVAILABLE TO',
        value: 'Nobody yet — still a draft on the bulletin.',
      );
    }
    if (p.visibility == PingVisibility.all) {
      return const _Row(label: 'AVAILABLE TO', value: 'Every PNM');
    }
    // visibility == specific: resolve names from the user directory.
    return StreamBuilder<List<AppUser>>(
      stream: context.read<UserService>().watchPnms(),
      builder: (context, snap) {
        final pnms = snap.data ?? const <AppUser>[];
        final byUid = {for (final u in pnms) u.uid: u.displayName};
        final claimed = p.claims.map((c) => c.pnmUid).toSet();
        final eligibleNotClaimed = p.eligiblePnmUids
            .where((uid) => !claimed.contains(uid))
            .map((uid) => byUid[uid] ?? '(${uid.substring(0, 6)})')
            .toList()
          ..sort();
        final value = eligibleNotClaimed.isEmpty
            ? 'All targeted PNMs have already claimed.'
            : eligibleNotClaimed.join(', ');
        return _Row(
          label: 'AVAILABLE TO (${eligibleNotClaimed.length} of '
              '${p.eligiblePnmUids.length} unclaimed)',
          value: value,
        );
      },
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(color: SepColors.blueGray)),
        const SizedBox(height: 4),
        Text(value, style: Theme.of(context).textTheme.bodyLarge),
      ],
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.p,
    required this.me,
    required this.busy,
    required this.error,
    required this.onOpenMaps,
    required this.onAccept,
    required this.onSubmitProof,
  });

  final Ping p;
  final AppUser me;
  final bool busy;
  final String? error;
  final VoidCallback onOpenMaps;
  final VoidCallback onAccept;
  final VoidCallback onSubmitProof;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onOpenMaps,
                icon: const Icon(Icons.map_outlined),
                label: const Text('OPEN IN MAPS'),
              ),
            ),
            if (_pnmActionVisible) ...[
              const SizedBox(width: 12),
              Expanded(child: _pnmButton(context)),
            ],
          ],
        ),
        if (error != null) ...[
          const SizedBox(height: 10),
          Text(error!,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: SepColors.danger)),
        ],
      ],
    );
  }

  bool get _pnmActionVisible {
    if (!me.isPnm) return false;
    if (p.isDraft) return false;
    return true;
  }

  Widget _pnmButton(BuildContext context) {
    final claim = p.claimFor(me.uid);
    if (claim != null && !claim.isCompleted) {
      return ElevatedButton.icon(
        onPressed: busy ? null : onSubmitProof,
        icon: busy
            ? const SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: SepColors.light),
              )
            : const Icon(Icons.photo_camera_outlined),
        label: const Text('SUBMIT PROOF'),
      );
    }
    if (claim != null && claim.isCompleted) {
      return const ElevatedButton(
        onPressed: null,
        child: Text('COMPLETED'),
      );
    }
    if (!p.isEligibleForPnm(me.uid)) {
      return const ElevatedButton(
        onPressed: null,
        child: Text('NOT ELIGIBLE'),
      );
    }
    if (p.slotsRemaining == 0) {
      return const ElevatedButton(
        onPressed: null,
        child: Text('FULL'),
      );
    }
    return ElevatedButton.icon(
      onPressed: busy ? null : onAccept,
      icon: busy
          ? const SizedBox(
              height: 16,
              width: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: SepColors.light),
            )
          : const Icon(Icons.bolt_outlined),
      label: Text('ACCEPT (${p.slotsRemaining}/${p.capacity} free)'),
    );
  }
}

class _ClaimsList extends StatelessWidget {
  const _ClaimsList({required this.p, required this.meUid});
  final Ping p;
  final String meUid;
  @override
  Widget build(BuildContext context) {
    if (p.claims.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('CLAIMS (${p.claims.length}/${p.capacity})',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...p.claims.map((c) {
              final mine = c.pnmUid == meUid;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      c.isCompleted
                          ? Icons.check_circle
                          : Icons.hourglass_top,
                      size: 18,
                      color: c.isCompleted
                          ? SepColors.success
                          : SepColors.blueGray,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            mine ? '${c.pnmName}  · YOU' : c.pnmName,
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                          Text(
                            c.isCompleted
                                ? 'Completed ${DateFormat.MMMd().add_jm().format(c.completedAt!)}'
                                : 'Accepted ${DateFormat.MMMd().add_jm().format(c.acceptedAt)}',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: SepColors.blueGray),
                          ),
                          if (mine && c.photoUrl != null) ...[
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(c.photoUrl!,
                                  height: 200, fit: BoxFit.cover),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
