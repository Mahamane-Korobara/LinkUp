import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../config/linkup_ports.dart';
import '../crypto/key_manager.dart';
import '../pairing/device_metadata.dart';
import '../transfer/received_saver.dart';
import 'host_advertise.dart';
import 'host_device_store.dart';
import 'host_foreground.dart';
import 'host_identity.dart';
import 'host_network.dart';
import 'host_pairing.dart';
import 'host_router.dart';
import 'host_server.dart';
import 'host_transfer.dart';

/// Orchestre le Mode Hôte pour l'UI : démarre/arrête le serveur embarqué, gère
/// l'OTP/QR, l'approbation des pairs et l'envoi de fichiers hôte→pair.
///
/// Un seul [HostController] par écran hôte. Le serveur tourne dans l'isolate
/// principal, gardé vivant par [HostForeground].
class HostController extends ChangeNotifier {
  final HostDeviceStore devices = HostDeviceStore();

  HostServer? _server;
  HostTransfer? _transfer;
  String? _pairingUrl;
  String? _ip;
  bool _starting = false;
  String? _error;

  List<HostDevice> _pending = const [];
  List<HostDevice> _approved = const [];

  bool get isHosting => _server != null;
  bool get isStarting => _starting;
  String? get pairingUrl => _pairingUrl;
  String? get ip => _ip;
  String? get error => _error;
  List<HostDevice> get pending => _pending;
  List<HostDevice> get approved => _approved;
  int get port => LinkupPorts.bridge;

  Future<void> startHosting() async {
    if (isHosting || _starting) return;
    _starting = true;
    _error = null;
    notifyListeners();
    try {
      final ip = await HostNetwork.lanIpv4();
      if (ip == null) {
        _error = 'Aucun réseau Wi-Fi détecté. Connecte les deux téléphones au '
            'même réseau, ou active le partage de connexion sur celui-ci.';
        return;
      }

      final keys = KeyManager();
      String? name;
      try {
        name = (await DeviceMetadata.collect()).name;
      } catch (_) {/* nom système en repli */}

      final identity = HostIdentity(keys: keys, deviceName: name);
      final pairing = HostPairing(identity: identity, devices: devices, keys: keys);
      final staging = Directory(
        '${(await getTemporaryDirectory()).path}/linkup_host',
      );
      final transfer = HostTransfer(
        pairing: pairing,
        saver: DeviceFileSaver(),
        stagingRoot: staging,
        listenPort: LinkupPorts.bridge,
      );
      final server = HostServer(
        router: HostRouter(
          advertise: HostAdvertise(identity: identity, listenPort: LinkupPorts.bridge),
          pairing: pairing,
          transfer: transfer,
        ),
      );
      await server.start();

      _server = server;
      _transfer = transfer;
      _ip = ip;
      pairing.rotateOtp();
      _pairingUrl = await pairing.pairingUrl(ip, LinkupPorts.bridge);
      await _refresh();
      await HostForeground.start(_approved.length);
    } on SocketException {
      _error = 'Le port ${LinkupPorts.bridge} est déjà occupé '
          '(un autre service LinkUp tourne sur ce téléphone ?).';
    } catch (e) {
      _error = 'Démarrage impossible : $e';
    } finally {
      _starting = false;
      notifyListeners();
    }
  }

  Future<void> stopHosting() async {
    await _server?.stop();
    _server = null;
    _transfer = null;
    _pairingUrl = null;
    await HostForeground.stop();
    notifyListeners();
  }

  /// Recharge pending/approved (à appeler périodiquement : un pair qui scanne
  /// crée un device pending côté serveur, qu'on veut faire remonter à l'écran).
  Future<void> refresh() => _refresh();

  Future<void> _refresh() async {
    _pending = await devices.listPending();
    _approved = await devices.listApproved();
    await HostForeground.update(_approved.length);
    notifyListeners();
  }

  Future<void> approve(String deviceId) async {
    await devices.approve(deviceId);
    await _refresh();
  }

  Future<void> reject(String deviceId) async {
    await devices.reject(deviceId);
    await _refresh();
  }

  /// Dépose un fichier pour un pair approuvé (il le récupère ensuite côté pair).
  Future<void> sendToPeer({
    required String deviceId,
    required String filename,
    required List<int> bytes,
  }) async {
    await _transfer?.enqueueOutgoing(
      deviceId: deviceId,
      filename: filename,
      bytes: bytes,
    );
  }

  @override
  void dispose() {
    // Best-effort : on coupe le serveur si l'écran disparaît.
    _server?.stop();
    HostForeground.stop();
    super.dispose();
  }
}
