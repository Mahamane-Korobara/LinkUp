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

  const TransferHubScreen({super.key, required this.device});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Transfert — ${device.pcName}'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.photo_library), text: 'Galerie'),
              Tab(icon: Icon(Icons.description), text: 'Fichier'),
              Tab(icon: Icon(Icons.move_to_inbox), text: 'Reçus du PC'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            GallerySendScreen(device: device, embedded: true),
            TransfersScreen(device: device, embedded: true),
            IncomingScreen(device: device, embedded: true),
          ],
        ),
      ),
    );
  }
}
