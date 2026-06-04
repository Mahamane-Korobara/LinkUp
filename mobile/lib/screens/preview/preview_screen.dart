import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/pairing/paired_device_store.dart';
import '../../services/preview/preview_client.dart';

/// Écran Dev Preview (S14) : liste les projets web que le PC a exposés (depuis
/// son dashboard) et les ouvre dans le navigateur du téléphone.
///
/// La première fois, il faut installer le **certificat Linkup** (bouton dédié) :
/// les projets sont servis en HTTPS, et sans ce certificat le navigateur affiche
/// un avertissement de sécurité et bloque caméra / PWA.
class PreviewScreen extends StatefulWidget {
  final PairedDevice device;
  final PreviewClient? client;

  const PreviewScreen({super.key, required this.device, this.client});

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  late final PreviewClient _client;
  late final bool _ownsClient;

  PreviewListing? _listing;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _client = widget.client ?? PreviewClient();
    _ownsClient = widget.client == null;
    _load();
  }

  @override
  void dispose() {
    if (_ownsClient) _client.close();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final listing = await _client.projects(widget.device);
      if (!mounted) return;
      setState(() => _listing = listing);
    } on PreviewException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Erreur inattendue : $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(Uri uri) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Impossible d\'ouvrir $uri')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Dev Preview — ${widget.device.pcName}'),
        actions: [
          IconButton(
            tooltip: 'Recharger',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _certificateCard(),
            const SizedBox(height: 16),
            ..._buildContent(),
          ],
        ),
      ),
    );
  }

  Widget _certificateCard() {
    return Card(
      color: Colors.amber.shade50,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.verified_user_outlined, color: Colors.amber.shade800),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Certificat Linkup',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'À installer une seule fois : les projets sont servis en HTTPS. '
              'Sans ce certificat, le navigateur affiche un avertissement et '
              'bloque caméra / PWA.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => _open(_client.caCertificateUri(widget.device)),
                icon: const Icon(Icons.download),
                label: const Text('Installer le certificat'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildContent() {
    if (_loading && _listing == null) {
      return const [
        Padding(
          padding: EdgeInsets.only(top: 48),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (_error != null) {
      return [
        _emptyOrError(
          icon: Icons.error_outline,
          title: 'Impossible de charger',
          subtitle: _error!,
        ),
      ];
    }
    final projects = _listing?.projects ?? const <PreviewProject>[];
    if (projects.isEmpty) {
      return [
        _emptyOrError(
          icon: Icons.public_off,
          title: 'Aucun projet exposé',
          subtitle: 'Sur le PC, ouvre le dashboard Linkup → Dev Preview, et '
              'clique « Exposer » sur le serveur à tester.',
        ),
      ];
    }
    return projects.map(_projectTile).toList();
  }

  Widget _projectTile(PreviewProject p) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.dns_outlined),
        title: Text('Port ${p.targetPort}'),
        subtitle: const Text('Exposé en HTTPS'),
        trailing: FilledButton.icon(
          onPressed: () =>
              _open(_client.projectUri(widget.device, _listing!, p)),
          icon: const Icon(Icons.open_in_new),
          label: const Text('Ouvrir'),
        ),
      ),
    );
  }

  Widget _emptyOrError({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 48),
      child: Column(
        children: [
          Icon(icon, size: 48, color: Colors.grey),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
