import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:provider/provider.dart';

import '../../models/app_user.dart';
import '../../models/ping.dart';
import '../../services/ping_service.dart';
import '../../services/user_service.dart';
import '../../theme/app_theme.dart';

/// Creator-only dialog: turns a draft into a published ping by picking a
/// visibility (`all` PNMs or `specific` ones). Capacity and cost are read-only
/// here — they were locked at drop and could only have been edited through
/// the bulletin's edit affordance before this point.
enum _Audience { all, specific }

class PublishPingDialog extends StatefulWidget {
  const PublishPingDialog({super.key, required this.ping});
  final Ping ping;

  @override
  State<PublishPingDialog> createState() => _PublishPingDialogState();
}

class _PublishPingDialogState extends State<PublishPingDialog> {
  _Audience _audience = _Audience.all;
  final Set<String> _picked = {};
  bool _busy = false;
  String? _error;

  Future<void> _publish() async {
    if (_audience == _Audience.specific && _picked.isEmpty) {
      setState(() => _error = 'Pick at least one PNM, or switch to All PNMs.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<PingService>().publishPing(
            ping: widget.ping,
            eligiblePnmUids:
                _audience == _Audience.all ? const [] : _picked.toList(),
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final users = context.read<UserService>();
    final p = widget.ping;
    return PointerInterceptor(
      child: AlertDialog(
        title: const Text('Publish ping'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _LockedRow(label: 'Task', value: p.taskDescription),
                _LockedRow(
                  label: 'Slots',
                  value: '${p.capacity} '
                      '(${p.creditCostPer} cr × ${p.capacity} = ${p.totalCost} cr)',
                ),
                const SizedBox(height: 12),
                SegmentedButton<_Audience>(
                  segments: const [
                    ButtonSegment(
                      value: _Audience.all,
                      label: Text('All PNMs'),
                      icon: Icon(Icons.groups_outlined),
                    ),
                    ButtonSegment(
                      value: _Audience.specific,
                      label: Text('Select'),
                      icon: Icon(Icons.checklist),
                    ),
                  ],
                  selected: {_audience},
                  onSelectionChanged: (s) => setState(() => _audience = s.first),
                ),
                const SizedBox(height: 12),
                if (_audience == _Audience.specific)
                  _PnmPicker(
                    usersService: users,
                    selected: _picked,
                    onToggle: (uid, on) => setState(() {
                      if (on) {
                        _picked.add(uid);
                      } else {
                        _picked.remove(uid);
                      }
                    }),
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: SepColors.danger)),
                ],
                const SizedBox(height: 8),
                Text(
                  _audience == _Audience.all
                      ? 'Visible to every PNM. Capacity caps how many can finish; cost is fixed.'
                      : 'Only the picked PNMs will see this in their "Just for you" sidebar.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: SepColors.blueGray),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(false),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: _busy ? null : _publish,
            child: _busy
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: SepColors.light),
                  )
                : const Text('PUBLISH'),
          ),
        ],
      ),
    );
  }
}

class _LockedRow extends StatelessWidget {
  const _LockedRow({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text(label,
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(color: SepColors.blueGray)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _PnmPicker extends StatelessWidget {
  const _PnmPicker({
    required this.usersService,
    required this.selected,
    required this.onToggle,
  });

  final UserService usersService;
  final Set<String> selected;
  final void Function(String uid, bool on) onToggle;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AppUser>>(
      stream: usersService.watchPnms(),
      builder: (context, snap) {
        final pnms = snap.data ?? const <AppUser>[];
        if (snap.connectionState == ConnectionState.waiting) {
          return const SizedBox(
              height: 120, child: Center(child: CircularProgressIndicator()));
        }
        if (pnms.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(12),
            child: Text('No PNMs in the directory yet.'),
          );
        }
        return Container(
          decoration: BoxDecoration(
            border: Border.all(color: SepColors.lightBlue),
            borderRadius: BorderRadius.circular(8),
          ),
          constraints: const BoxConstraints(maxHeight: 220),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: pnms.length,
            itemBuilder: (_, i) {
              final u = pnms[i];
              final on = selected.contains(u.uid);
              return CheckboxListTile(
                dense: true,
                value: on,
                onChanged: (v) => onToggle(u.uid, v ?? false),
                title: Text(u.displayName),
                subtitle: Text(u.email,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: SepColors.blueGray)),
                controlAffinity: ListTileControlAffinity.leading,
              );
            },
          ),
        );
      },
    );
  }
}
