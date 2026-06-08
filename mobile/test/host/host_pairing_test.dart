import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:linkup_mobile/services/crypto/key_manager.dart';
import 'package:linkup_mobile/services/host/host_advertise.dart';
import 'package:linkup_mobile/services/host/host_device_store.dart';
import 'package:linkup_mobile/services/host/host_identity.dart';
import 'package:linkup_mobile/services/host/host_pairing.dart';
import 'package:linkup_mobile/services/host/host_router.dart';
import 'package:linkup_mobile/services/host/host_server.dart';
import 'package:linkup_mobile/services/pairing/paired_device_store.dart';
import 'package:linkup_mobile/services/pairing/pairing_handshake_client.dart';
import 'package:linkup_mobile/services/pairing/pairing_poll_client.dart';
import 'package:linkup_mobile/services/pairing/pairing_url.dart';
import 'package:linkup_mobile/services/pairing/pairing_verifier.dart';

import 'host_test_support.dart';

/// Démarre un hôte complet (découverte + appairage) et renvoie le serveur,
/// l'objet pairing, le device store et l'URL d'appairage parsée.
class _Host {
  final HostServer server;
  final HostPairing pairing;
  final HostDeviceStore devices;
  final PairingUrl url;
  _Host(this.server, this.pairing, this.devices, this.url);
}

Future<_Host> _startHost(int port) async {
  final storage = MemoryStorage();
  final keys = KeyManager(storage: storage);
  final identity = HostIdentity(storage: storage, keys: keys, deviceName: 'Mon Hôte');
  final devices = HostDeviceStore(storage: storage);
  final pairing = HostPairing(identity: identity, devices: devices, keys: keys);
  final server = HostServer(
    router: HostRouter(
      advertise: HostAdvertise(identity: identity, listenPort: port),
      pairing: pairing,
    ),
    address: InternetAddress.loopbackIPv4,
    port: port,
  );
  await server.start();
  final urlStr = await pairing.pairingUrl('127.0.0.1', port);
  return _Host(server, pairing, devices, PairingUrl.parse(urlStr));
}

void main() {
  test('handshake + approbation + poll + /api/me : flux complet avec les vrais clients',
      () async {
    final port = await freePort();
    final host = await _startHost(port);
    addTearDown(host.server.stop);

    // --- Le pair (son propre keypair) fait le handshake ---
    final peerKeys = KeyManager(storage: MemoryStorage());
    final handshake = PairingHandshakeClient(keyManager: peerKeys);
    final result = await handshake.handshake(host.url);

    expect(result.isPending, isTrue);
    expect(result.deviceId, isNotEmpty);
    expect(result.pcName, 'Mon Hôte');
    expect(result.pcPublicKey, host.url.pcPublicKey); // anti-MITM OK

    // --- Poll avant approbation → pending ---
    final poll = PairingPollClient(keyManager: peerKeys);
    final before = await poll.pollOnce(host.url.laravelBaseUri, result.deviceId);
    expect(before.status, PollStatus.pending);

    // --- L'hôte approuve (action manuelle de l'utilisateur) ---
    await host.devices.approve(result.deviceId);

    // --- Poll après → approved + token (livré une seule fois) ---
    final after = await poll.pollOnce(host.url.laravelBaseUri, result.deviceId);
    expect(after.status, PollStatus.approved);
    expect(after.token, isNotNull);

    final again = await poll.pollOnce(host.url.laravelBaseUri, result.deviceId);
    expect(again.status, PollStatus.approved);
    expect(again.token, isNull, reason: 'le token n\'est livré qu\'une fois');

    // --- /api/me valide le token via le vrai vérificateur ---
    final device = PairedDevice(
      deviceId: result.deviceId,
      host: '127.0.0.1',
      port: port,
      token: after.token!,
      pcPublicKey: result.pcPublicKey,
      pcFingerprint: result.pcFingerprint,
      pcName: result.pcName,
    );
    final verifier = HttpPairingVerifier();
    expect(await verifier.verify(device), PairingValidity.valid);

    // --- Un mauvais token → stale (401) ---
    final bogus = PairedDevice(
      deviceId: result.deviceId,
      host: '127.0.0.1',
      port: port,
      token: 'mauvais-token',
      pcPublicKey: result.pcPublicKey,
      pcFingerprint: result.pcFingerprint,
      pcName: result.pcName,
    );
    expect(await verifier.verify(bogus), PairingValidity.stale);
  });

  test('OTP incorrect → handshake refusé (422)', () async {
    final port = await freePort();
    final host = await _startHost(port);
    addTearDown(host.server.stop);

    final badUrl = PairingUrl(
      host: host.url.host,
      port: host.url.port,
      pcPublicKey: host.url.pcPublicKey,
      otp: 'mauvais-otp',
      version: 1,
    );
    final handshake = PairingHandshakeClient(keyManager: KeyManager(storage: MemoryStorage()));

    expect(
      () => handshake.handshake(badUrl),
      throwsA(isA<HandshakeRejected>()),
    );
  });

  test('poll avec un device inconnu → 404 remonté en erreur réseau', () async {
    final port = await freePort();
    final host = await _startHost(port);
    addTearDown(host.server.stop);

    final poll = PairingPollClient(keyManager: KeyManager(storage: MemoryStorage()));
    expect(
      () => poll.pollOnce(host.url.laravelBaseUri, 'device-fantome'),
      throwsA(isA<PollNetworkException>()),
    );
  });
}
