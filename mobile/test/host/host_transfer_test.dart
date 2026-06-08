import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:linkup_mobile/services/crypto/key_manager.dart';
import 'package:linkup_mobile/services/host/host_advertise.dart';
import 'package:linkup_mobile/services/host/host_device_store.dart';
import 'package:linkup_mobile/services/host/host_identity.dart';
import 'package:linkup_mobile/services/host/host_pairing.dart';
import 'package:linkup_mobile/services/host/host_router.dart';
import 'package:linkup_mobile/services/host/host_server.dart';
import 'package:linkup_mobile/services/host/host_transfer.dart';
import 'package:linkup_mobile/services/pairing/paired_device_store.dart';
import 'package:linkup_mobile/services/transfer/received_saver.dart';
import 'package:linkup_mobile/services/transfer/transfer_client.dart';

import 'host_test_support.dart';

/// Saver factice : enregistre en mémoire le dernier fichier rangé.
class _FakeSaver implements ReceivedFileSaver {
  String? filename;
  Uint8List? bytes;

  @override
  Future<SaveResult> save(String filename, Uint8List bytes) async {
    this.filename = filename;
    this.bytes = bytes;
    return const SaveResult(SaveKind.gallery, location: 'galerie');
  }
}

class _Host {
  final HostServer server;
  final HostDeviceStore devices;
  final _FakeSaver saver;
  final int port;
  _Host(this.server, this.devices, this.saver, this.port);
}

Future<_Host> _startHost(int port) async {
  final storage = MemoryStorage();
  final keys = KeyManager(storage: storage);
  final identity = HostIdentity(storage: storage, keys: keys, deviceName: 'Hôte');
  final devices = HostDeviceStore(storage: storage);
  final pairing = HostPairing(identity: identity, devices: devices, keys: keys);
  final saver = _FakeSaver();
  final staging = await Directory.systemTemp.createTemp('linkup_host_test_');
  final transfer = HostTransfer(
    pairing: pairing,
    saver: saver,
    stagingRoot: staging,
    listenPort: port,
  );
  final server = HostServer(
    router: HostRouter(
      advertise: HostAdvertise(identity: identity, listenPort: port),
      pairing: pairing,
      transfer: transfer,
    ),
    address: InternetAddress.loopbackIPv4,
    port: port,
  );
  await server.start();
  return _Host(server, devices, saver, port);
}

/// Crée et approuve un pair directement (le transfert n'authentifie que par
/// token, pas par signature → inutile de rejouer le handshake ici).
Future<PairedDevice> _approvedPeer(_Host host, {String id = 'peer-1'}) async {
  await host.devices.upsertPending(HostDevice(
    deviceId: id,
    telPublicKey: 'x',
    name: 'Galaxy',
    model: '',
    platform: 'Android',
    osVersion: '',
    status: HostDeviceStatus.pending,
  ));
  final approved = await host.devices.approve(id);
  return PairedDevice(
    deviceId: id,
    host: '127.0.0.1',
    port: host.port,
    token: approved!.token!,
    pcPublicKey: '',
    pcFingerprint: '',
    pcName: 'Hôte',
  );
}

void main() {
  test('upload multi-chunk pair→hôte : le fichier arrive intact (vrai TransferClient)',
      () async {
    final port = await freePort();
    final host = await _startHost(port);
    addTearDown(host.server.stop);
    final peer = await _approvedPeer(host);

    // ~300 Ko aléatoires → plusieurs chunks avec un chunkSize réduit.
    final rnd = Random(42);
    final input = Uint8List.fromList(
      List<int>.generate(300 * 1024, (_) => rnd.nextInt(256)),
    );
    final expectedSha = crypto.sha256.convert(input).toString();

    final client = TransferClient(chunkSize: 64 * 1024);
    final transferId = await client.uploadBytes(
      device: peer,
      filename: 'photo.jpg',
      bytes: input,
    );
    client.close();

    expect(transferId, isNotEmpty);
    expect(host.saver.filename, 'photo.jpg');
    expect(host.saver.bytes, isNotNull);
    expect(host.saver.bytes!.length, input.length);
    expect(crypto.sha256.convert(host.saver.bytes!).toString(), expectedSha);

    // L'historique du pair reflète le transfert terminé.
    final history = await TransferClient().listTransfers(peer);
    expect(history, hasLength(1));
    expect(history.first.filename, 'photo.jpg');
    expect(history.first.isCompleted, isTrue);
  });

  test('initiate sans token valide → 401 (TransferException)', () async {
    final port = await freePort();
    final host = await _startHost(port);
    addTearDown(host.server.stop);

    final bogus = PairedDevice(
      deviceId: 'inconnu',
      host: '127.0.0.1',
      port: port,
      token: 'mauvais',
      pcPublicKey: '',
      pcFingerprint: '',
      pcName: 'Hôte',
    );

    expect(
      () => TransferClient().uploadBytes(
        device: bogus,
        filename: 'x.bin',
        bytes: Uint8List.fromList([1, 2, 3]),
      ),
      throwsA(isA<TransferException>()),
    );
  });
}
