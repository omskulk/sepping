import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/app_user.dart';
import '../../models/strike_request.dart';
import '../../services/strike_service.dart';
import '../../theme/app_theme.dart';

/// NME-only inbox of pending strike requests. Each request shows its PNMs as
/// checkboxes so the NME can partially approve (e.g. accept 3 of the 5 named).
/// Denial is one-tap with an optional explanation.
class StrikeApprovalsScreen extends StatelessWidget {
  const StrikeApprovalsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AppUser>();
    if (!user.isNme) {
      return Scaffold(
        appBar: AppBar(title: const Text('APPROVALS')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('Only the NME can review strike requests.'),
          ),
        ),
      );
    }

    final strikes = context.read<StrikeService>();
    return Scaffold(
      appBar: AppBar(title: const Text('STRIKE APPROVALS')),
      body: StreamBuilder<List<StrikeRequest>>(
        stream: strikes.watchPendingRequests(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final list = snap.data ?? const <StrikeRequest>[];
          if (list.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Inbox zero. No pending requests.',
                  style: TextStyle(color: SepColors.blueGray),
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _RequestCard(request: list[i], nme: user),
          );
        },
      ),
    );
  }
}

class _RequestCard extends StatefulWidget {
  const _RequestCard({required this.request, required this.nme});
  final StrikeRequest request;
  final AppUser nme;

  @override
  State<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends State<_RequestCard> {
  late final Set<String> _approved =
      Set<String>.from(widget.request.pnmUids); // default: all selected
  bool _busy = false;
  String? _error;

  Future<void> _approve() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<StrikeService>().approveRequest(
            request: widget.request,
            nme: widget.nme,
            approvedPnmUids: _approved,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Approved ${_approved.length} strike(s).')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deny() async {
    // Resolve the service synchronously before opening the dialog so we don't
    // need to use `context` again after the await gap.
    final service = context.read<StrikeService>();
    final note = await showDialog<String?>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController();
        return AlertDialog(
          title: const Text('Deny request?'),
          content: TextField(
            controller: ctrl,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Optional explanation (visible to issuer)',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('CANCEL'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(ctrl.text),
              child: const Text('DENY'),
            ),
          ],
        );
      },
    );
    if (note == null) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await service.denyRequest(
        request: widget.request,
        nme: widget.nme,
        denyReason: note,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    final dateStr = DateFormat.MMMd().add_jm().format(r.createdAt);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: SepColors.danger, size: 20),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('From ${r.issuedByName}',
                      style: Theme.of(context).textTheme.titleSmall),
                ),
                Text(dateStr,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: SepColors.blueGray)),
              ],
            ),
            const SizedBox(height: 8),
            Text('REASON',
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(color: SepColors.blueGray)),
            const SizedBox(height: 4),
            Text(r.reason),
            const Divider(height: 24),
            Text('PNMs (${r.pnmUids.length})',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            ...List.generate(r.pnmUids.length, (i) {
              final uid = r.pnmUids[i];
              final name = i < r.pnmNames.length ? r.pnmNames[i] : uid;
              final selected = _approved.contains(uid);
              return CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: selected,
                onChanged: (v) => setState(() {
                  if (v == true) {
                    _approved.add(uid);
                  } else {
                    _approved.remove(uid);
                  }
                }),
                title: Text(name),
              );
            }),
            if (_error != null) ...[
              const SizedBox(height: 6),
              Text(_error!,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: SepColors.danger)),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : _deny,
                    child: const Text('DENY'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed:
                        (_busy || _approved.isEmpty) ? null : _approve,
                    child: _busy
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: SepColors.light),
                          )
                        : Text('APPROVE ${_approved.length}'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
