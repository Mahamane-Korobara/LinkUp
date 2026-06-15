import 'package:flutter/material.dart';

import '../../services/pairing/paired_device_store.dart';
import '../gallery/gallery_send_screen.dart';
import 'incoming_screen.dart';
import 'transfers_screen.dart';

/// Hub des transferts tél ↔ PC (S6) : un seul point d'entrée regroupant
///   - Galerie : envoyer photos/vidéos (avec filtre photos/vidéos),
///   - Fichier : historique des envois + envoyer un document (PDF, archive…),
///   - Reçus du PC : récupérer ce que le PC a envoyé (filtre image/vidéo/doc).
class TransferHubScreen extends StatelessWidget {
  final PairedDevice device;

  /// `true` en tél↔tél (Mode Hôte) : le pair est un téléphone, pas un PC —
  /// les libellés s'adaptent (« Reçus » au lieu de « Reçus du PC », etc.).
  final bool isHost;

  const TransferHubScreen({
    super.key,
    required this.device,
    this.isHost = false,
  });

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Transfert — ${device.pcName}'),
          bottom: TabBar(
            tabs: [
              const Tab(icon: Icon(Icons.photo_library), text: 'Galerie'),
              const Tab(icon: Icon(Icons.description), text: 'Fichier'),
              Tab(
                icon: const Icon(Icons.move_to_inbox),
                text: isHost ? 'Reçus' : 'Reçus du PC',
              ),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            GallerySendScreen(device: device, embedded: true, isHost: isHost),
            TransfersScreen(device: device, embedded: true, isHost: isHost),
            IncomingScreen(device: device, embedded: true, isHost: isHost),
          ],
        ),
      ),
    );
  }
}
