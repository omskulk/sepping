import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/ping.dart';
import '../../services/ping_service.dart';
import '../../theme/app_theme.dart';

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

  Future<void> _submitProof(Ping p) async {
    final picker = ImagePicker();
    // gallery is more reliable on web than camera mode; on mobile the user can still
    // take a photo via the OS picker if their browser supports it.
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
      await context.read<PingService>().submitProof(
            ping: p,
            photoBytes: bytes,
            contentType: picked.mimeType ?? 'image/jpeg',
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Proof submitted. +1 to your count.')),
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
    final pings = context.read<PingService>();
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
          final completed = p.status == PingStatus.completed;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(completed ? Icons.check_circle : Icons.location_on,
                              color: completed ? SepColors.success : SepColors.navy),
                          const SizedBox(width: 8),
                          Text(p.status.label,
                              style: Theme.of(context).textTheme.titleMedium),
                          const Spacer(),
                          Chip(label: Text('${p.creditCost} cr')),
                        ],
                      ),
                      const Divider(height: 24),
                      Text('TASK',
                          style: Theme.of(context)
                              .textTheme
                              .labelLarge
                              ?.copyWith(color: SepColors.blueGray)),
                      const SizedBox(height: 4),
                      Text(p.taskDescription,
                          style: Theme.of(context).textTheme.bodyLarge),
                      const SizedBox(height: 16),
                      Text('FROM',
                          style: Theme.of(context)
                              .textTheme
                              .labelLarge
                              ?.copyWith(color: SepColors.blueGray)),
                      const SizedBox(height: 4),
                      Text(p.createdByName),
                      const SizedBox(height: 16),
                      Text('LOCATION',
                          style: Theme.of(context)
                              .textTheme
                              .labelLarge
                              ?.copyWith(color: SepColors.blueGray)),
                      const SizedBox(height: 4),
                      Text('${p.lat.toStringAsFixed(5)}, ${p.lng.toStringAsFixed(5)}'),
                      const SizedBox(height: 16),
                      Text('CREATED',
                          style: Theme.of(context)
                              .textTheme
                              .labelLarge
                              ?.copyWith(color: SepColors.blueGray)),
                      const SizedBox(height: 4),
                      Text(DateFormat.yMMMd().add_jm().format(p.createdAt)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _openInMaps(p),
                      icon: const Icon(Icons.map_outlined),
                      label: const Text('OPEN IN MAPS'),
                    ),
                  ),
                  if (!completed) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _busy ? null : () => _submitProof(p),
                        icon: _busy
                            ? const SizedBox(
                                height: 16,
                                width: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: SepColors.light))
                            : const Icon(Icons.photo_camera_outlined),
                        label: const Text('SUBMIT PROOF'),
                      ),
                    ),
                  ],
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: SepColors.danger)),
              ],
              if (completed && p.photoUrl != null) ...[
                const SizedBox(height: 24),
                Text('YOUR PROOF',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(p.photoUrl!),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
