import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/app_user.dart';
import '../../models/ping.dart';
import '../../services/ping_service.dart';
import '../../theme/app_theme.dart';
import '../pnm/ping_detail_screen.dart';
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
  LatLng? _pendingTap;

  Future<void> _onTap(LatLng pos) async {
    setState(() => _pendingTap = pos);
    final active = context.read<AppUser>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) =>
          DropPingDialog(active: active, lat: pos.latitude, lng: pos.longitude),
    );
    if (!mounted) return;
    setState(() => _pendingTap = null);
    if (ok == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Draft saved to bulletin.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AppUser>();
    final pingService = context.read<PingService>();
    return AppScaffold(
      title: 'Active · ${user.displayName}',
      subtitle:
          'Tap the map to drop a draft. Publish from the bulletin to send it to PNMs.',
      body: StreamBuilder<List<Ping>>(
        stream: pingService.watchAllPings(),
        builder: (context, snap) {
          final all = snap.data ?? const <Ping>[];
          // Completed pings live on the History screen — they shouldn't
          // clutter the live map or sidebars.
          final live = all
              .where((p) => p.status != PingStatus.completed &&
                  p.status != PingStatus.cancelled)
              .toList();
          return LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 980;
              final dialogOpen = _pendingTap != null;
              final map = _MapPanel(
                pendingTap: _pendingTap,
                pings: live,
                onTap: dialogOpen ? null : _onTap,
                onMarkerTap: (p) => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => Provider<AppUser>.value(
                      value: user,
                      child: PingDetailScreen(pingId: p.id),
                    ),
                  ),
                ),
              );
              // Chapter-wide transparency: every active sees every
              // published ping, not just their own. Prevents a creator
              // from publishing something inappropriate that only PNMs
              // would ever see. Drafts moved to BulletinScreen so this
              // pane has full vertical room.
              final activity = _PublishedPane(
                pings: live.where((p) => !p.isDraft).toList(),
                meUid: user.uid,
              );

              if (wide) {
                return Row(
                  children: [
                    Expanded(flex: 3, child: map),
                    const VerticalDivider(width: 1),
                    SizedBox(width: 380, child: activity),
                  ],
                );
              }
              return Column(
                children: [
                  SizedBox(height: 320, child: map),
                  const Divider(height: 1),
                  Expanded(child: activity),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

/// Color-encodes status onto markers. Default Google hues are coarse but free —
/// custom bitmaps require a build-time asset and an `await` on plugin init.
double _hueFor(Ping p) {
  if (p.status == PingStatus.completed) return BitmapDescriptor.hueGreen;
  if (p.status == PingStatus.full) return BitmapDescriptor.hueYellow;
  if (p.isDraft) return BitmapDescriptor.hueViolet;
  return BitmapDescriptor.hueAzure; // open + published
}

class _MapPanel extends StatelessWidget {
  const _MapPanel({
    required this.pendingTap,
    required this.pings,
    required this.onTap,
    required this.onMarkerTap,
  });

  final LatLng? pendingTap;
  final List<Ping> pings;
  final void Function(LatLng)? onTap;
  final void Function(Ping) onMarkerTap;

  @override
  Widget build(BuildContext context) {
    final markers = <Marker>{
      for (final p in pings)
        Marker(
          markerId: MarkerId(p.id),
          position: LatLng(p.lat, p.lng),
          icon: BitmapDescriptor.defaultMarkerWithHue(_hueFor(p)),
          infoWindow: InfoWindow(
            title: p.taskDescription,
            snippet:
                '${p.visibility.name} · ${p.claims.length}/${p.capacity} slots',
            onTap: () => onMarkerTap(p),
          ),
          onTap: () => onMarkerTap(p),
        ),
      if (pendingTap != null)
        Marker(
          markerId: const MarkerId('pending'),
          position: pendingTap!,
          icon: BitmapDescriptor.defaultMarker,
          infoWindow: const InfoWindow(title: 'New pin'),
        ),
    };
    return GoogleMap(
      initialCameraPosition: _defaultCamera,
      onMapCreated: (_) {},
      onTap: onTap,
      markers: markers,
      mapToolbarEnabled: false,
      zoomControlsEnabled: true,
    );
  }
}

class _PublishedPane extends StatelessWidget {
  const _PublishedPane({required this.pings, required this.meUid});
  final List<Ping> pings;
  final String meUid;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: SepColors.light,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                const Icon(Icons.public, size: 18, color: SepColors.navy),
                const SizedBox(width: 6),
                Text('PUBLISHED (CHAPTER)',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text('${pings.length}'),
                ),
              ],
            ),
          ),
          Expanded(
            child: pings.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No published pings yet.',
                      style: TextStyle(color: SepColors.blueGray),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                    itemCount: pings.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (_, i) =>
                        _PublishedRow(ping: pings[i], meUid: meUid),
                  ),
          ),
        ],
      ),
    );
  }
}

class _PublishedRow extends StatelessWidget {
  const _PublishedRow({required this.ping, required this.meUid});
  final Ping ping;
  final String meUid;
  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat.MMMd().add_jm().format(ping.createdAt);
    final mine = ping.createdBy == meUid;
    return Card(
      child: ListTile(
        leading: Icon(_iconFor(ping.status), color: _colorFor(ping.status)),
        title: Row(
          children: [
            Expanded(
              child: Text(ping.taskDescription,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall),
            ),
            if (mine)
              const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text('MINE'),
                ),
              ),
          ],
        ),
        subtitle: Text(
          'by ${ping.createdByName} · ${ping.status.label} · '
          '${ping.claims.length}/${ping.capacity} · '
          '${ping.visibility.name} · $dateStr',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: SepColors.blueGray),
        ),
        trailing: const Icon(Icons.chevron_right, color: SepColors.blueGray),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => Provider<AppUser>.value(
              value: context.read<AppUser>(),
              child: PingDetailScreen(pingId: ping.id),
            ),
          ),
        ),
      ),
    );
  }

  IconData _iconFor(PingStatus s) => switch (s) {
        PingStatus.completed => Icons.check_circle,
        PingStatus.full => Icons.lock_clock,
        PingStatus.cancelled => Icons.cancel_outlined,
        PingStatus.open => Icons.location_on,
      };

  Color _colorFor(PingStatus s) => switch (s) {
        PingStatus.completed => SepColors.success,
        PingStatus.full => SepColors.darkNavy,
        PingStatus.cancelled => SepColors.blueGray,
        PingStatus.open => SepColors.navy,
      };
}
