import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/pairing/paired_device_store.dart';
import '../../services/preview/preview_client.dart';
import '../../theme/app_colors.dart';
import 'certificate_screen.dart';
import 'preview_webview_screen.dart';

/// Écran Dev Preview (S14) : liste les projets web que le PC a exposés (depuis
/// son dashboard) et les ouvre sur le téléphone.
///
/// Voie PRINCIPALE : « Ouvrir » rend le projet dans une WebView in-app qui épingle
/// le certificat du PC → HTTPS de confiance SANS installer la CA. Voie de SECOURS :
/// « Ouvrir dans Chrome » (pour PWA-install / Web Push / DevTools) nécessite, elle,
/// d'installer le **certificat Linkup** (carte repliable en bas).
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

  /// Voie principale : rendre le projet dans la WebView in-app (cert épinglé).
  /// Sans empreinte (PC trop ancien), on bascule sur le navigateur externe.
  void _openInApp(PreviewProject p) {
    final uri = _client.projectUri(widget.device, _listing!, p);
    final certSha256 = _listing!.certSha256;
    if (certSha256 == null) {
      _open(uri); // pas de pin possible → repli navigateur (avec install CA)
      return;
    }
    // Map port d'origine → port d'écoute du bridge, pour TOUS les projets exposés :
    // on recrée chacun à l'identique sur le 127.0.0.1 du tél (même port) → l'app
    // tourne comme sur le PC (localhost:3001 ↔ localhost:8001, cross-origin natif).
    final portToListen = {
      for (final proj in _listing!.projects) proj.targetPort: proj.listenPort,
    };
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PreviewWebViewScreen(
          url: uri,
          certSha256: certSha256,
          frontPort: p.targetPort,
          portToListen: portToListen,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Dev Preview — ${widget.device.pcName}'),
        // Recharger retiré : le pull-to-refresh du corps le couvre. On garde
        // seulement l'accès au certificat (action sans équivalent gestuel).
        actions: [
          IconButton(
            tooltip: 'Certificat (pour Chrome)',
            onPressed: _openCertificate,
            icon: const Icon(Icons.verified_user_outlined),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: _buildContent(),
        ),
      ),
    );
  }

  /// Ouvre la page dédiée au certificat (accès direct depuis l'AppBar).
  void _openCertificate() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CertificateScreen(
          caCertificateUri: _client.caCertificateUri(widget.device),
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
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Ouvrir dans Chrome (PWA / DevTools)',
              onPressed: () =>
                  _open(_client.projectUri(widget.device, _listing!, p)),
              icon: const Icon(Icons.open_in_browser),
            ),
            const SizedBox(width: 4),
            FilledButton.icon(
              onPressed: () => _openInApp(p),
              icon: const Icon(Icons.open_in_new),
              label: const Text('Ouvrir'),
            ),
          ],
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
          Icon(icon, size: 48, color: AppColors.faint),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}
