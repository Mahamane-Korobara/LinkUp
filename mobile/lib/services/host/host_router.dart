import 'dart:io';

import 'host_advertise.dart';
import 'host_http.dart';
import 'host_pairing.dart';
import 'host_transfer.dart';

/// Routeur du serveur Mode Hôte : associe (méthode, chemin) à un handler.
///
/// Découverte + appairage + transfert. Tout chemin non reconnu → 404. Les
/// briques optionnelles (null) permettent des configurations partielles en test.
class HostRouter {
  final HostAdvertise advertise;
  final HostPairing? pairing;
  final HostTransfer? transfer;

  HostRouter({required this.advertise, this.pairing, this.transfer});

  Future<void> dispatch(HttpRequest req) async {
    final method = req.method;
    final path = req.uri.path;
    final segs = req.uri.pathSegments; // ex. ['transfer', '<id>', 'status']

    // --- Découverte (sonde du LAN sweep du pair) ---
    if (method == 'GET' && path == '/health') {
      return writeJson(req, await advertise.health());
    }
    if (method == 'GET' && (path == '/api/agent/info' || path == '/agent/info')) {
      return writeJson(req, await advertise.agentInfo());
    }

    // --- Appairage ---
    final p = pairing;
    if (p != null) {
      if (method == 'POST' && path == '/api/pairing/handshake') {
        return p.handleHandshake(req);
      }
      if (method == 'POST' && path == '/api/pairing/poll') {
        return p.handlePoll(req);
      }
      if (method == 'GET' && path == '/api/me') {
        return p.handleMe(req);
      }
    }

    // --- Transfert (agent /api/transfers* + bridge /transfer/*) ---
    final t = transfer;
    if (t != null) {
      if (method == 'POST' && path == '/api/transfers') return t.handleInitiate(req);
      if (method == 'GET' && path == '/api/transfers') return t.handleList(req);
      if (method == 'GET' && path == '/api/transfers/incoming') {
        return t.handleIncoming(req);
      }
      // /api/transfers/{id}/{complete|download|delivered}
      if (segs.length == 4 && segs[0] == 'api' && segs[1] == 'transfers') {
        final id = segs[2];
        if (method == 'POST' && segs[3] == 'complete') return t.handleComplete(req, id);
        if (method == 'GET' && segs[3] == 'download') return t.handleDownload(req, id);
        if (method == 'POST' && segs[3] == 'delivered') return t.handleDelivered(req, id);
      }
      if (method == 'POST' && path == '/transfer/upload') return t.handleUpload(req);
      // GET /transfer/{id}/status
      if (method == 'GET' &&
          segs.length == 3 &&
          segs[0] == 'transfer' &&
          segs[2] == 'status') {
        return t.handleStatus(req, segs[1]);
      }
      // POST /transfer/{id}/finalize
      if (method == 'POST' &&
          segs.length == 3 &&
          segs[0] == 'transfer' &&
          segs[2] == 'finalize') {
        return t.handleFinalize(req, segs[1]);
      }
    }

    return writeStatus(req, HttpStatus.notFound);
  }
}
