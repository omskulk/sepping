import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/app_user.dart';
import '../../services/strike_service.dart';
import '../../services/user_service.dart';
import '../../theme/app_theme.dart';

/// Multi-PNM strike request form. Any active can open this; the request lands
/// in the NME's approvals inbox where it may be approved (in whole or part) or
/// denied.
///
/// Selection and filter state live in [ValueNotifier]s so a checkbox toggle
/// only rebuilds the list (not the whole Scaffold + StreamBuilder + reason
/// field + submit button). The previous setState-per-toggle caused a full
/// screen rerender on every click.
class StrikeRequestForm extends StatefulWidget {
  const StrikeRequestForm({super.key});

  @override
  State<StrikeRequestForm> createState() => _StrikeRequestFormState();
}

class _StrikeRequestFormState extends State<StrikeRequestForm> {
  final _reason = TextEditingController();
  final _filter = TextEditingController();
  final _selection = ValueNotifier<Set<String>>(<String>{});
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Make filter changes observable to ValueListenableBuilder without
    // rebuilding the top-level widget.
    _filter.addListener(_onFilterChanged);
  }

  final _filterText = ValueNotifier<String>('');
  void _onFilterChanged() => _filterText.value = _filter.text;

  @override
  void dispose() {
    _filter.removeListener(_onFilterChanged);
    _reason.dispose();
    _filter.dispose();
    _selection.dispose();
    _filterText.dispose();
    super.dispose();
  }

  Future<void> _submit(List<AppUser> allPnms) async {
    final selected =
        allPnms.where((p) => _selection.value.contains(p.uid)).toList();
    if (selected.isEmpty) {
      setState(() => _error = 'Pick at least one PNM.');
      return;
    }
    if (_reason.text.trim().isEmpty) {
      setState(() => _error = 'Enter a reason.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<StrikeService>().submitRequest(
            issuer: context.read<AppUser>(),
            pnms: selected,
            reason: _reason.text,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Request filed for ${selected.length} PNM(s).')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toggle(String uid, bool on) {
    final next = Set<String>.from(_selection.value);
    if (on) {
      next.add(uid);
    } else {
      next.remove(uid);
    }
    _selection.value = next;
  }

  @override
  Widget build(BuildContext context) {
    final users = context.read<UserService>();
    return Scaffold(
      appBar: AppBar(title: const Text('SUBMIT STRIKE')),
      body: StreamBuilder<List<AppUser>>(
        stream: users.watchPnms(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final pnms = snap.data ?? const <AppUser>[];
          if (pnms.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('No PNMs to strike.'),
              ),
            );
          }
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _filter,
                      decoration: const InputDecoration(
                        labelText: 'Filter PNMs',
                        prefixIcon: Icon(Icons.search),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Only this Text rebuilds when selection changes.
                    ValueListenableBuilder<Set<String>>(
                      valueListenable: _selection,
                      builder: (_, sel, _) => Text(
                        '${sel.length} of ${pnms.length} selected',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: SepColors.blueGray,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: _PnmList(
                  pnms: pnms,
                  filterText: _filterText,
                  selection: _selection,
                  onToggle: _toggle,
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _reason,
                      maxLines: 3,
                      minLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Reason (shared by all selected PNMs)',
                        hintText: 'e.g. Late to mandatory event without notice',
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(_error!,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: SepColors.danger)),
                    ],
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _busy ? null : () => _submit(pnms),
                      child: _busy
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: SepColors.light),
                            )
                          : const Text('SUBMIT FOR NME REVIEW'),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Pulled out so selection / filter changes only rebuild this subtree. Nested
/// ValueListenableBuilders give us fine-grained invalidation: the outer one
/// refires when the filter text changes (list re-filters); the inner one
/// refires when selection changes (checkboxes flip). Neither touches the
/// parent Scaffold.
class _PnmList extends StatelessWidget {
  const _PnmList({
    required this.pnms,
    required this.filterText,
    required this.selection,
    required this.onToggle,
  });

  final List<AppUser> pnms;
  final ValueNotifier<String> filterText;
  final ValueNotifier<Set<String>> selection;
  final void Function(String uid, bool on) onToggle;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: filterText,
      builder: (_, raw, _) {
        final q = raw.trim().toLowerCase();
        final visible = q.isEmpty
            ? pnms
            : pnms
                .where((p) =>
                    p.displayName.toLowerCase().contains(q) ||
                    p.email.toLowerCase().contains(q))
                .toList();
        return ValueListenableBuilder<Set<String>>(
          valueListenable: selection,
          builder: (_, sel, _) {
            return ListView.builder(
              itemCount: visible.length,
              itemBuilder: (_, i) {
                final p = visible[i];
                return CheckboxListTile(
                  key: ValueKey(p.uid),
                  value: sel.contains(p.uid),
                  onChanged: (v) => onToggle(p.uid, v ?? false),
                  title: Text(p.displayName),
                  subtitle: Text(
                    p.email,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: SepColors.blueGray),
                  ),
                  secondary: p.strikes > 0
                      ? Chip(
                          backgroundColor:
                              SepColors.danger.withValues(alpha: .15),
                          label: Text('${p.strikes}'),
                        )
                      : null,
                );
              },
            );
          },
        );
      },
    );
  }
}
