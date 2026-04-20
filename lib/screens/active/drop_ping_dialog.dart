import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/app_user.dart';
import '../../services/ping_service.dart';
import '../../services/user_service.dart';
import '../../theme/app_theme.dart';

class DropPingDialog extends StatefulWidget {
  const DropPingDialog({
    super.key,
    required this.active,
    required this.lat,
    required this.lng,
  });

  final AppUser active;
  final double lat;
  final double lng;

  @override
  State<DropPingDialog> createState() => _DropPingDialogState();
}

class _DropPingDialogState extends State<DropPingDialog> {
  final _task = TextEditingController();
  // Key the dropdown by uid; AppUser objects are rebuilt on each Firestore snapshot,
  // so object-identity equality would break dropdown selection across rebuilds.
  String? _selectedUid;
  int _cost = 1;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _task.dispose();
    super.dispose();
  }

  Future<void> _submit(List<AppUser> pnms) async {
    final assignee = pnms.firstWhere(
      (u) => u.uid == _selectedUid,
      orElse: () => pnms.first,
    );
    if (_task.text.trim().isEmpty) {
      setState(() => _error = 'Enter a task.');
      return;
    }
    if (widget.active.pingCredits < _cost) {
      setState(() => _error = 'Not enough credits.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<PingService>().dropPing(
            active: widget.active,
            assignee: assignee,
            lat: widget.lat,
            lng: widget.lng,
            taskDescription: _task.text.trim(),
            creditCost: _cost,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on InsufficientCreditsException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
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
    return StreamBuilder<List<AppUser>>(
      stream: users.watchPnms(),
      builder: (context, snap) {
        final pnms = snap.data ?? const <AppUser>[];
        final loading = snap.connectionState == ConnectionState.waiting;

        if (pnms.isNotEmpty &&
            (_selectedUid == null || pnms.every((u) => u.uid != _selectedUid))) {
          _selectedUid = pnms.first.uid;
        }

        return AlertDialog(
          title: const Text('Drop a ping'),
          content: SizedBox(
            width: 420,
            child: loading
                ? const SizedBox(
                    height: 160, child: Center(child: CircularProgressIndicator()))
                : pnms.isEmpty
                    ? const Text('No PNMs have signed up yet.')
                    : SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Location: ${widget.lat.toStringAsFixed(5)}, ${widget.lng.toStringAsFixed(5)}',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: SepColors.blueGray),
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              initialValue: _selectedUid,
                              decoration:
                                  const InputDecoration(labelText: 'Assign to PNM'),
                              items: pnms
                                  .map((u) => DropdownMenuItem(
                                        value: u.uid,
                                        child: Text(u.displayName),
                                      ))
                                  .toList(),
                              onChanged: (v) => setState(() => _selectedUid = v),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _task,
                              decoration: const InputDecoration(
                                labelText: 'Task',
                                hintText:
                                    'e.g. Take a selfie in front of the library',
                              ),
                              maxLines: 3,
                              minLines: 2,
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                const Text('Cost:'),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Slider(
                                    value: _cost.toDouble(),
                                    min: 1,
                                    max: 5,
                                    divisions: 4,
                                    label: '$_cost credits',
                                    onChanged: (v) =>
                                        setState(() => _cost = v.round()),
                                  ),
                                ),
                                Text('$_cost cr'),
                              ],
                            ),
                            Text('You have ${widget.active.pingCredits} credits.',
                                style: Theme.of(context).textTheme.bodySmall),
                            if (_error != null) ...[
                              const SizedBox(height: 10),
                              Text(_error!,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: SepColors.danger)),
                            ],
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
              onPressed: (_busy || pnms.isEmpty) ? null : () => _submit(pnms),
              child: _busy
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: SepColors.light))
                  : const Text('DROP PIN'),
            ),
          ],
        );
      },
    );
  }
}
