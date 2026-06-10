import 'dart:io';
import 'dart:typed_data';

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
import 'package:linkup_mobile/services/transfer/incoming_receiver.dart';
import 'package:linkup_mobile/services/transfer/received_saver.dart';
import 'package:linkup_mobile/services/transfer/transfer_client.dart';

import 'host_test_support.dart';

class _FakeSaver extends ReceivedFileSaver {
  String? filename;
  Uint8List? bytes;
  @override
  Future<SaveResult> save(String filename, Uint8List bytes) async {
    this.filename = filename;
    this.bytes = bytes;
    return const SaveResult(SaveKind.document, location: 'LinkupReçus');
  }
}

class _Host {
  final HostServer server;
  final HostTransfer transfer;
  final HostDeviceStore devices;
  final int port;
  _Host(this.server, this.transfer, this.devices, this.port);
}

Future<_Host> _startHost(int port) async {
  final storage = MemoryStorage();
  final keys = KeyManager(storage: storage);
  final identity = HostIdentity(storage: storage, keys: keys, deviceName: 'Hôte');
  final devices = HostDeviceStore(storage: storage);
  final pairing = HostPairing(identity: identity, devices: devices, keys: keys);
  final staging = await Directory.systemTemp.createTemp('linkup_outbox_test_');
  final transfer = HostTransfer(
    pairing: pairing,
    saver: _FakeSaver(),
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
  return _Host(server, transfer, devices, port);
}

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
  test('hôte→pair : le pair récupère le fichier déposé (vrai IncomingReceiver)',
      () async {
    final port = await freePort();
    final host = await _startHost(port);
    addTearDown(host.server.stop);
    final peer = await _approvedPeer(host);

    final input = Uint8List.fromList(List<int>.generate(5000, (i) => i % 256));
    await host.transfer.enqueueOutgoing(
      deviceId: peer.deviceId,
      filename: 'rapport.pdf',
      bytes: input,
    );

    final saver = _FakeSaver();
    final receiver = IncomingReceiver(transfers: TransferClient(), saver: saver);
    final res = await receiver.run(peer);

    expect(res.saved, 1);
    expect(saver.filename, 'rapport.pdf');
    expect(saver.bytes, equals(input));

    // Après récupération, plus rien d'entrant (marqué delivered).
    final res2 = await receiver.run(peer);
    expect(res2.isEmpty, isTrue);
  });
}
