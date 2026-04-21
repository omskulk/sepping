import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/app_user.dart';
import '../../models/ping.dart';
import '../../services/ping_service.dart';
import '../../theme/app_theme.dart';
import '../shared/app_scaffold.dart';
import 'ping_detail_screen.dart';

const _defaultCamera = CameraPosition(
  target: LatLng(34.4140, -119.8489),
  zoom: 15,
);

/// PNM landing page. Completely rebuilt around the capacity model:
/// pings are no longer assigned to a specific uid. Instead each PNM sees a
/// shared pool filtered to what they're eligible for, and picks slots on a
/// first-come basis.
class PnmHome extends StatelessWidget {
  const PnmHome({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AppUser>();
    final pings = context.read<PingService>();
    return AppScaffold(
      title: 'PNM · ${user.displayName}',
      subtitle: 'Tap a pin on the map or a card in the sidebar to accept it.',
      body: StreamBuilder<List<Ping>>(
        stream: pings.watchAvailablePingsForPnm(user.uid),
        builder: (context, availSnap) {
          final available = availSnap.data ?? const <Ping>[];
          return StreamBuilder<List<Ping>>(
            stream: pings.watchMyClaimedPings(user.uid),
            builder: (context, mineSnap) {
              final mine = mineSnap.data ?? const <Ping>[];
              return LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 980;
                  final map = _PnmMap(pings: available, me: user);
                  final sidebar = _PnmSidebar(
                    available: available,
                    mine: mine,
                    meUid: user.uid,
                  );
                  if (wide) {
                    return Row(
                      children: [
                        Expanded(flex: 3, child: map),
                        const VerticalDivider(width: 1),
                        SizedBox(width: 380, child: sidebar),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      SizedBox(height: 320, child: map),
                      const Divider(height: 1),
                      Expanded(child: sidebar),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

/// Hue mapping specific to the PNM view. Violet is reserved for "specific"
/// pings (the "just for you" bucket) so they visually pop. Green means the
/// PNM already has a claim on that ping, so it still shows but looks distinct.
double _pnmHueFor(Ping p, String meUid) {
  if (p.hasClaimFrom(meUid)) return BitmapDescriptor.hueGreen;
  if (p.visibility == PingVisibility.specific) return BitmapDescriptor.hueViolet;
  return BitmapDescriptor.hueAzure;
}

class _PnmMap extends StatelessWidget {
  const _PnmMap({required this.pings, required this.me});
  final List<Ping> pings;
  final AppUser me;

  @override
  Widget build(BuildContext context) {
    final markers = <Marker>{
      for (final p in pings)
        Marker(
          markerId: MarkerId(p.id),
          position: LatLng(p.lat, p.lng),
          icon: BitmapDescriptor.defaultMarkerWithHue(_pnmHueFor(p, me.uid)),
          infoWindow: InfoWindow(
            title: p.taskDescription,
            snippet: '${p.claims.length}/${p.capacity} slots · '
                '${p.creditCostPer} cr',
            onTap: () => _open(context, p),
          ),
          onTap: () => _open(context, p),
        ),
    };
    return GoogleMap(
      initialCameraPosition: _defaultCamera,
      onMapCreated: (_) {},
      markers: markers,
      mapToolbarEnabled: false,
      zoomControlsEnabled: true,
    );
  }

  void _open(BuildContext context, Ping p) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Provider<AppUser>.value(
          value: me,
          child: PingDetailScreen(pingId: p.id),
        ),
      ),
    );
  }
}

class _PnmSidebar extends StatelessWidget {
  const _PnmSidebar({
    required this.available,
    required this.mine,
    required this.meUid,
  });
  final List<Ping> available;
  final List<Ping> mine;
  final String meUid;

  @override
  Widget build(BuildContext context) {
    final justForMe = available
        .where((p) =>
            p.visibility == PingVisibility.specific && !p.hasClaimFrom(meUid))
        .toList();
    final chapterWide = available
        .where(
            (p) => p.visibility == PingVisibility.all && !p.hasClaimFrom(meUid))
        .toList();
    // Completed pings (status==completed OR my claim has photoUrl) move to
    // the History screen. The "in progress" lane only shows live work.
    final inProgress = mine.where((p) {
      if (p.status == PingStatus.completed) return false;
      final myClaim = p.claimFor(meUid);
      return myClaim != null && !myClaim.isCompleted;
    }).toList();

    return Container(
      color: SepColors.light,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          _SectionHeader(
            label: 'JUST FOR YOU',
            icon: Icons.star_outline,
            count: justForMe.length,
          ),
          if (justForMe.isEmpty)
            const _EmptyHint('Nothing targeted at you right now.')
          else
            ...justForMe.map((p) => _PingRow(ping: p)),
          const SizedBox(height: 16),
          _SectionHeader(
            label: 'CHAPTER-WIDE',
            icon: Icons.groups_outlined,
            count: chapterWide.length,
          ),
          if (chapterWide.isEmpty)
            const _EmptyHint('No open chapter-wide pings.')
          else
            ...chapterWide.map((p) => _PingRow(ping: p)),
          const SizedBox(height: 16),
          _SectionHeader(
            label: 'IN PROGRESS',
            icon: Icons.hourglass_top,
            count: inProgress.length,
          ),
          if (inProgress.isEmpty)
            const _EmptyHint('Accept a ping to start.')
          else
            ...inProgress.map((p) => _PingRow(ping: p, mineUid: meUid)),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(
      {required this.label, required this.icon, required this.count});
  final String label;
  final IconData icon;
  final int count;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: SepColors.navy),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.titleSmall),
          const Spacer(),
          Chip(
            visualDensity: VisualDensity.compact,
            label: Text('$count'),
          ),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Text(text,
          style: const TextStyle(color: SepColors.blueGray, fontSize: 12)),
    );
  }
}

class _PingRow extends StatelessWidget {
  const _PingRow({required this.ping, this.mineUid});
  final Ping ping;

  /// Provided when rendering this row in the "in-progress / completed" lane so
  /// we know the PNM already has a claim and can tailor the subtitle.
  final String? mineUid;

  @override
  Widget build(BuildContext context) {
    final claim = mineUid == null ? null : ping.claimFor(mineUid!);
    final isMine = claim != null;
    final completed = claim?.isCompleted ?? false;
    final subtitle = isMine
        ? (completed
            ? 'Completed ${DateFormat.MMMd().add_jm().format(claim.completedAt!)}'
            : 'Accepted ${DateFormat.MMMd().add_jm().format(claim.acceptedAt)} — submit proof')
        : 'From ${ping.createdByName} · ${ping.claims.length}/${ping.capacity} slots · ${ping.creditCostPer} cr';
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => Provider<AppUser>.value(
              value: context.read<AppUser>(),
              child: PingDetailScreen(pingId: ping.id),
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(
                completed
                    ? Icons.check_circle
                    : (isMine ? Icons.photo_camera_outlined : Icons.location_on),
                color: completed
                    ? SepColors.success
                    : (isMine ? SepColors.navy : SepColors.navy),
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(ping.taskDescription,
                        style: Theme.of(context).textTheme.titleSmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: SepColors.blueGray)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: SepColors.blueGray),
            ],
          ),
        ),
      ),
    );
  }
}
