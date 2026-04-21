import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:provider/provider.dart';

import '../../models/app_user.dart';
import '../../services/ping_service.dart';
import '../../theme/app_theme.dart';

/// Active-side draft editor. PNM selection / broadcast targeting is **not**
/// in this dialog — that decision moves to [PublishPingDialog]. Here the
/// active just shapes the task and decides how many slots it has.
///
/// Cost = `costPer × capacity` is debited immediately on submit (per the user's
/// debit-at-drop decision, 2026-04-20). The active can still bump capacity up
/// or down on the bulletin before publishing — credits will true-up.
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
  int _capacity = 1;
  int _costPer = 1;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _task.dispose();
    super.dispose();
  }

  int get _total => _capacity * _costPer;

  Future<void> _submit() async {
    if (_task.text.trim().isEmpty) {
      setState(() => _error = 'Enter a task.');
      return;
    }
    if (widget.active.pingCredits < _total) {
      setState(() =>
          _error = 'Need $_total credits; you have ${widget.active.pingCredits}.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<PingService>().dropPing(
            active: widget.active,
            lat: widget.lat,
            lng: widget.lng,
            taskDescription: _task.text.trim(),
            creditCostPer: _costPer,
            capacity: _capacity,
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
    // PointerInterceptor blocks click leak-through to the GoogleMap
    // HtmlElementView underneath on Flutter web (see docs/PIN_BUG_FIX.md).
    return PointerInterceptor(
      child: AlertDialog(
        title: const Text('Drop a draft ping'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
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
                const SizedBox(height: 4),
                const Text(
                  'Drafts go to the chapter bulletin. PNMs will not see this until you publish it.',
                  style:
                      TextStyle(color: SepColors.blueGray, fontSize: 12),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _task,
                  decoration: const InputDecoration(
                    labelText: 'Task',
                    hintText: 'e.g. Pick up the log near the SRC',
                  ),
                  maxLines: 3,
                  minLines: 2,
                ),
                const SizedBox(height: 16),
                _Stepper(
                  label: 'Slots (capacity)',
                  value: _capacity,
                  min: 1,
                  max: 20,
                  onChanged: (v) => setState(() => _capacity = v),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('Cost per slot:'),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Slider(
                        value: _costPer.toDouble(),
                        min: 1,
                        max: 5,
                        divisions: 4,
                        label: '$_costPer credits',
                        onChanged: (v) =>
                            setState(() => _costPer = v.round()),
                      ),
                    ),
                    Text('$_costPer cr'),
                  ],
                ),
                _CostRecap(
                  costPer: _costPer,
                  capacity: _capacity,
                  total: _total,
                  available: widget.active.pingCredits,
                ),
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
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: SepColors.light),
                  )
                : const Text('DROP DRAFT'),
          ),
        ],
      ),
    );
  }
}

/// Tiny +/- stepper. We don't use a Slider for capacity because the chapter's
/// PNM count is small enough that exact numeric control matters more than a
/// visual sweep, and a Slider costs vertical space we'd rather use for the
/// task field.
class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });
  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        IconButton(
          onPressed: value > min ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove_circle_outline),
        ),
        SizedBox(
          width: 40,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        IconButton(
          onPressed: value < max ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    );
  }
}

class _CostRecap extends StatelessWidget {
  const _CostRecap({
    required this.costPer,
    required this.capacity,
    required this.total,
    required this.available,
  });
  final int costPer;
  final int capacity;
  final int total;
  final int available;

  @override
  Widget build(BuildContext context) {
    final short = available < total;
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: short ? SepColors.danger : SepColors.blueGray,
          fontWeight: short ? FontWeight.w600 : null,
        );
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        '$costPer cr × $capacity slot${capacity == 1 ? '' : 's'} = '
        '$total cr total · you have $available',
        style: style,
      ),
    );
  }
}
