import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/app_user.dart';
import '../../models/ping.dart';
import '../../services/ping_service.dart';
import '../../theme/app_theme.dart';
import '../shared/app_scaffold.dart';
import 'drop_ping_dialog.dart';

/// UCSB campus default. Picked because Om is a UCSB student; once the user taps
/// a location the drop dialog uses the tapped coords, not this.
const _defaultCamera = CameraPosition(
  target: LatLng(34.4140, -119.8489),
  zoom: 15,
);

class ActiveHome extends StatefulWidget {
  const ActiveHome({super.key});

  @override
  State<ActiveHome> createState() => _ActiveHomeState();
}

class _ActiveHomeState extends State<ActiveHome> {
  GoogleMapController? _mapController;
  LatLng? _pendingTap;

  Future<void> _onTap(LatLng pos) async {
    setState(() => _pendingTap = pos);
    final active = context.read<AppUser>();
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => DropPingDialog(active: active, lat: pos.latitude, lng: pos.longitude),
    );
    if (!mounted) return;
    setState(() => _pendingTap = null);
    if (result == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ping dropped.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AppUser>();
    return AppScaffold(
      title: 'Active · ${user.displayName}',
      subtitle: 'Tap the map to drop a pin and assign a task.',
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          final map = _MapPanel(
            pendingTap: _pendingTap,
            onMapCreated: (c) => _mapController = c,
            onTap: _onTap,
          );
          final list = _MyPingsList(activeUid: user.uid);
          if (wide) {
            return Row(
              children: [
                Expanded(flex: 3, child: map),
                const VerticalDivider(width: 1),
                SizedBox(width: 380, child: list),
              ],
            );
          }
          return Column(
            children: [
              SizedBox(height: 360, child: map),
              const Divider(height: 1),
              Expanded(child: list),
            ],
          );
        },
      ),
    );
  }
}

class _MapPanel extends StatelessWidget {
  const _MapPanel({
    required this.pendingTap,
    required this.onMapCreated,
    required this.onTap,
  });

  final LatLng? pendingTap;
  final void Function(GoogleMapController) onMapCreated;
  final void Function(LatLng) onTap;

  @override
  Widget build(BuildContext context) {
    return GoogleMap(
      initialCameraPosition: _defaultCamera,
      onMapCreated: onMapCreated,
      onTap: onTap,
      markers: {
        if (pendingTap != null)
          Marker(
            markerId: const MarkerId('pending'),
            position: pendingTap!,
            infoWindow: const InfoWindow(title: 'New pin'),
          ),
      },
      mapToolbarEnabled: false,
      zoomControlsEnabled: true,
    );
  }
}

class _MyPingsList extends StatelessWidget {
  const _MyPingsList({required this.activeUid});
  final String activeUid;

  @override
  Widget build(BuildContext context) {
    final pings = context.read<PingService>();
    return Container(
      color: SepColors.light,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('MY PINGS', style: Theme.of(context).textTheme.titleMedium),
          ),
          Expanded(
            child: StreamBuilder<List<Ping>>(
              stream: pings.watchPingsCreatedBy(activeUid),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final list = snap.data ?? const [];
                if (list.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No pings yet. Tap the map to drop one.',
                      style: TextStyle(color: SepColors.blueGray),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (_, i) => _PingTile(ping: list[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PingTile extends StatelessWidget {
  const _PingTile({required this.ping});
  final Ping ping;

  @override
  Widget build(BuildContext context) {
    final completed = ping.status == PingStatus.completed;
    final dateStr = DateFormat.MMMd().add_jm().format(ping.createdAt);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  completed ? Icons.check_circle : Icons.pending_actions,
                  size: 18,
                  color: completed ? SepColors.success : SepColors.blueGray,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    ping.assignedToName,
                    style: Theme.of(context).textTheme.titleSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(dateStr,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: SepColors.blueGray)),
              ],
            ),
            const SizedBox(height: 6),
            Text(ping.taskDescription, maxLines: 3, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 8),
            Row(
              children: [
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text('${ping.creditCost} cr'),
                ),
                const SizedBox(width: 6),
                Chip(
                  visualDensity: VisualDensity.compact,
                  backgroundColor: completed ? SepColors.success.withValues(alpha: .15) : null,
                  label: Text(ping.status.label),
                ),
                const Spacer(),
                if (completed && ping.photoUrl != null)
                  TextButton.icon(
                    onPressed: () => _showPhoto(context, ping.photoUrl!),
                    icon: const Icon(Icons.photo_outlined, size: 18),
                    label: const Text('View proof'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showPhoto(BuildContext context, String url) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        child: InteractiveViewer(child: Image.network(url)),
      ),
    );
  }
}

