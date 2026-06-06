import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Page dédiée au certificat Linkup (S14, Lot F).
///
/// La WebView in-app n'a **pas** besoin de ce certificat (elle épingle le cert du
/// PC). Il ne sert QUE si on ouvre un projet dans **Chrome** (pour installer une
/// PWA sur l'écran d'accueil, le Web Push ou les DevTools du navigateur) : sans la
/// CA Linkup dans le magasin du téléphone, Chrome affiche un avertissement TLS.
///
/// Cette page rassemble, au même endroit et accessible directement, le téléchargement
/// du certificat + le pas-à-pas d'installation Android.
class CertificateScreen extends StatelessWidget {
  /// URL du certificat de la CA Linkup (`…/api/preview/ca.crt`).
  final Uri caCertificateUri;

  const CertificateScreen({super.key, required this.caCertificateUri});

  Future<void> _install(BuildContext context) async {
    final ok = await launchUrl(caCertificateUri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible d\'ouvrir le certificat.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Certificat Linkup')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: Colors.blue.shade50,
            child: const Padding(
              padding: EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Inutile pour « Ouvrir » : la WebView intégrée gère le HTTPS '
                      'toute seule. N\'installe ce certificat que si tu utilises '
                      '« Ouvrir dans Chrome » (PWA, Web Push, DevTools).',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Installation (une seule fois)',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 8),
          ..._steps.asMap().entries.map((e) => _StepTile(index: e.key + 1, text: e.value)),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => _install(context),
            icon: const Icon(Icons.download),
            label: const Text('Télécharger le certificat'),
          ),
          const SizedBox(height: 12),
          const Text(
            'Astuce : si Android demande à quoi sert le certificat, choisis '
            '« CA » (autorité de certification). Un verrou/PIN d\'écran peut être '
            'exigé par le système.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  static const List<String> _steps = [
    'Touche « Télécharger le certificat » ci-dessous.',
    'Ouvre le fichier .crt téléchargé (ou Réglages → Sécurité → Installer un certificat → Certificat CA).',
    'Confirme l\'installation comme autorité de certification (CA).',
    'Reviens dans Linkup et ouvre le projet « dans Chrome » : plus d\'avertissement.',
  ];
}

class _StepTile extends StatelessWidget {
  final int index;
  final String text;

  const _StepTile({required this.index, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: Theme.of(context).colorScheme.primary,
            child: Text(
              '$index',
              style: const TextStyle(fontSize: 12, color: Colors.white),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }
}
