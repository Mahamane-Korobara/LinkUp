import 'package:flutter/material.dart';

import '../../services/crypto/key_manager.dart';
import '../../services/pairing/pairing_handshake_client.dart';
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

  const PairingFlowScreen({
    super.key,
    this.keyManager,
    this.handshakeClient,
  });

  @override
  State<PairingFlowScreen> createState() => _PairingFlowScreenState();
}

class _PairingFlowScreenState extends State<PairingFlowScreen> {
  late final KeyManager _keyManager;
  late final PairingHandshakeClient _client;
  late final bool _ownsClient;

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
    WidgetsBinding.instance.addPostFrameCallback((_) => _startScan());
  }

  @override
  void dispose() {
    if (_ownsClient) _client.close();
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
      final result = await _client.handshake(pairing);
      if (!mounted) return;
      setState(() {
        _state = _PairingState.success;
        _result = result;
      });
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
      case _PairingState.success:
        return _SuccessView(result: _result!, onDone: () => Navigator.of(context).pop());
      case _PairingState.error:
        return _ErrorView(
          message: _errorMessage ?? 'Erreur inconnue',
          onRetry: _startScan,
          onCancel: () => Navigator.of(context).pop(),
        );
    }
  }
}

enum _PairingState { idle, scanning, handshaking, success, error }

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
  const _ProgressView({required this.text});

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
        Text(text, style: const TextStyle(fontSize: 16)),
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
        Text(
          result.isApproved
              ? 'Pairing réussi'
              : 'En attente d\'approbation côté PC',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'PC : ${result.pcName}',
          style: TextStyle(color: Colors.grey.shade700),
        ),
        const SizedBox(height: 4),
        Text(
          'Empreinte : ${result.pcFingerprint}',
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
