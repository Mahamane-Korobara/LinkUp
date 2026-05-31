import 'package:flutter/material.dart';

import '../../services/crypto/key_manager.dart';
import '../../services/pairing/device_metadata.dart';
import '../../services/pairing/paired_device_store.dart';
import '../../services/pairing/pairing_handshake_client.dart';
import '../../services/pairing/pairing_poll_client.dart';
import '../../services/pairing/pairing_url.dart';
import 'scan_qr_screen.dart';

/// Orchestre le flow de pairing complet (T2.10 → T2.14) :
///   1. Lance ScanQrScreen
///   2. Reçoit le PairingUrl scanné
///   3. Lance le handshake HTTP vers Laravel
///   4. Affiche le résultat (en attente d'approbation côté PC, ou erreur)
class PairingFlowScreen extends StatefulWidget {
  final KeyManager? keyManager;
  final PairingHandshakeClient? handshakeClient;
  final PairingPollClient? pollClient;
  final PairedDeviceStore? deviceStore;

  const PairingFlowScreen({
    super.key,
    this.keyManager,
    this.handshakeClient,
    this.pollClient,
    this.deviceStore,
  });

  @override
  State<PairingFlowScreen> createState() => _PairingFlowScreenState();
}

class _PairingFlowScreenState extends State<PairingFlowScreen> {
  late final KeyManager _keyManager;
  late final PairingHandshakeClient _client;
  late final PairingPollClient _pollClient;
  late final PairedDeviceStore _store;
  late final bool _ownsClient;
  late final bool _ownsPollClient;

  _PairingState _state = _PairingState.idle;
  String? _errorMessage;
  HandshakeResult? _result;

  @override
  void initState() {
    super.initState();
    _keyManager = widget.keyManager ?? KeyManager();
    _ownsClient = widget.handshakeClient == null;
    _client = widget.handshakeClient ??
        PairingHandshakeClient(keyManager: _keyManager);
    _ownsPollClient = widget.pollClient == null;
    _pollClient =
        widget.pollClient ?? PairingPollClient(keyManager: _keyManager);
    _store = widget.deviceStore ?? PairedDeviceStore();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startScan());
  }

  @override
  void dispose() {
    if (_ownsClient) _client.close();
    if (_ownsPollClient) _pollClient.close();
    super.dispose();
  }

  Future<void> _startScan() async {
    if (!mounted) return;
    setState(() => _state = _PairingState.scanning);
    final scanned = await Navigator.of(context).push<PairingUrl>(
      MaterialPageRoute(builder: (_) => const ScanQrScreen()),
    );
    if (!mounted) return;
    if (scanned == null) {
      // L'user a annulé le scan
      setState(() => _state = _PairingState.idle);
      return;
    }
    await _runHandshake(scanned);
  }

  Future<void> _runHandshake(PairingUrl pairing) async {
    setState(() {
      _state = _PairingState.handshaking;
      _errorMessage = null;
    });
    try {
      // Métadonnées d'affichage du tél (modèle, OS) pour le dashboard PC.
      // collect() ne lève jamais ; au pire un fallback neutre.
      final metadata = await DeviceMetadata.collect();
      final result = await _client.handshake(pairing, metadata: metadata);
      if (!mounted) return;
      _result = result;
      // Le handshake n'approuve pas : le PC doit valider l'empreinte. On passe
      // en attente et on poll jusqu'à approbation / refus (S2.J5).
      setState(() => _state = _PairingState.waitingApproval);
      await _waitForApproval(pairing, result);
    } on HandshakeRejected catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _PairingState.error;
        _errorMessage = '${e.reasonCode} — ${e.message}';
      });
    } on HandshakeNetworkException catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _PairingState.error;
        _errorMessage = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _PairingState.error;
        _errorMessage = 'Erreur inattendue : $e';
      });
    }
  }

  /// Poll le PC jusqu'à approbation / refus, puis persiste le device approuvé.
  Future<void> _waitForApproval(
    PairingUrl pairing,
    HandshakeResult handshake,
  ) async {
    try {
      // Légèrement au-delà des 120s serveur pour observer le « rejected »
      // automatique plutôt que de timeout côté tel.
      final poll = await _pollClient.waitForResolution(
        pairing.laravelBaseUri,
        handshake.deviceId,
        timeout: const Duration(seconds: 150),
      );
      if (!mounted) return;

      if (poll.status == PollStatus.rejected) {
        setState(() {
          _state = _PairingState.rejected;
          _errorMessage = 'Le PC a refusé cet appareil.';
        });
        return;
      }

      // Approuvé : on persiste le device (avec son token) pour la reconnexion
      // auto. Le token n'est livré qu'une fois ; s'il est absent (re-pairing
      // d'un device déjà connu) on garde ce qu'on avait.
      if (poll.token != null && poll.token!.isNotEmpty) {
        await _store.save(PairedDevice(
          deviceId: handshake.deviceId,
          host: pairing.host,
          port: pairing.port,
          token: poll.token!,
          pcPublicKey: handshake.pcPublicKey,
          pcFingerprint: handshake.pcFingerprint,
          pcName: handshake.pcName,
        ));
      }
      if (!mounted) return;
      setState(() => _state = _PairingState.success);
    } on PollNetworkException catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _PairingState.error;
        _errorMessage = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Appairer le PC')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _buildContent(),
        ),
      ),
    );
  }

  Widget _buildContent() {
    switch (_state) {
      case _PairingState.idle:
        return _IdleView(onScan: _startScan);
      case _PairingState.scanning:
        return const _ProgressView(text: 'Scanner en cours…');
      case _PairingState.handshaking:
        return const _ProgressView(text: 'Connexion sécurisée au PC…');
      case _PairingState.waitingApproval:
        return _ProgressView(
          text: 'En attente d\'approbation sur le PC…',
          subtitle: _result != null
              ? 'Empreinte à vérifier sur le PC : ${_result!.deviceFingerprint}'
              : null,
        );
      case _PairingState.success:
        return _SuccessView(result: _result!, onDone: () => Navigator.of(context).pop());
      case _PairingState.rejected:
        return _ErrorView(
          message: _errorMessage ?? 'Appareil refusé par le PC.',
          onRetry: _startScan,
          onCancel: () => Navigator.of(context).pop(),
        );
      case _PairingState.error:
        return _ErrorView(
          message: _errorMessage ?? 'Erreur inconnue',
          onRetry: _startScan,
          onCancel: () => Navigator.of(context).pop(),
        );
    }
  }
}

enum _PairingState {
  idle,
  scanning,
  handshaking,
  waitingApproval,
  success,
  rejected,
  error,
}

class _IdleView extends StatelessWidget {
  final VoidCallback onScan;
  const _IdleView({required this.onScan});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.qr_code_scanner, size: 96, color: Colors.deepPurple.shade300),
        const SizedBox(height: 24),
        const Text(
          'Scanne le QR du dashboard de ton PC',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Sur ton PC, ouvre http://localhost:3000/pair',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade600),
        ),
        const SizedBox(height: 32),
        FilledButton.icon(
          onPressed: onScan,
          icon: const Icon(Icons.qr_code_scanner),
          label: const Text('Lancer le scan'),
        ),
      ],
    );
  }
}

class _ProgressView extends StatelessWidget {
  final String text;
  final String? subtitle;
  const _ProgressView({required this.text, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(
          width: 64,
          height: 64,
          child: CircularProgressIndicator(strokeWidth: 4),
        ),
        const SizedBox(height: 24),
        Text(text, style: const TextStyle(fontSize: 16), textAlign: TextAlign.center),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          Text(
            subtitle!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: Colors.grey),
          ),
        ],
      ],
    );
  }
}

class _SuccessView extends StatelessWidget {
  final HandshakeResult result;
  final VoidCallback onDone;
  const _SuccessView({required this.result, required this.onDone});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.check_circle, size: 96, color: Colors.green.shade500),
        const SizedBox(height: 16),
        const Text(
          'Appareil approuvé 🎉',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Connecté à : ${result.pcName}',
          style: TextStyle(color: Colors.grey.shade700),
        ),
        const SizedBox(height: 4),
        // On affiche l'empreinte du PC (son identité Ed25519), la MÊME que celle
        // de l'écran de détail de l'agent. C'est elle qu'on a appairée : afficher
        // l'empreinte du téléphone ici créait une incohérence visuelle.
        Text(
          'Empreinte du PC : ${result.pcFingerprint}',
          style: const TextStyle(
            fontFamily: 'monospace',
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 32),
        FilledButton(onPressed: onDone, child: const Text('Terminer')),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onCancel;
  const _ErrorView({
    required this.message,
    required this.onRetry,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.error_outline, size: 96, color: Colors.red.shade400),
        const SizedBox(height: 16),
        const Text(
          'Pairing échoué',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton(onPressed: onCancel, child: const Text('Annuler')),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      ],
    );
  }
}
