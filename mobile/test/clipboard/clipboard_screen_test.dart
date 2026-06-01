import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:linkup_mobile/screens/clipboard/clipboard_screen.dart';
import 'package:linkup_mobile/services/clipboard/clipboard_client.dart';
import 'package:linkup_mobile/services/clipboard/clipboard_watcher.dart';
import 'package:linkup_mobile/services/pairing/paired_device_store.dart';

const _device = PairedDevice(
  deviceId: 'dev-1',
  host: '192.168.1.50',
  port: 8000,
  token: 'device-token',
  pcPublicKey: 'pk',
  pcFingerprint: 'fp',
  pcName: 'mon-pc',
);

/// Watcher injectable : on déclenche `fire()` pour simuler une copie sur le tél.
class _FakeWatcher implements ClipboardWatcher {
  final StreamController<void> _c = StreamController<void>.broadcast();
  bool started = false;

  @override
  Stream<void> get onChanged => _c.stream;

  @override
  Future<void> start() async => started = true;

  @override
  Future<void> stop() async {}

  void fire() => _c.add(null);
}

MockClient _backend({
  List<Map<String, dynamic>>? items,
  void Function()? onPush,
  void Function()? onOpenLink,
  String pcText = 'PC clip',
}) {
  return MockClient((req) async {
    final path = req.url.path;
    if (req.method == 'GET' && path == '/api/clipboard') {
      return http.Response(jsonEncode({'items': items ?? []}), 200);
    }
    if (req.method == 'POST' && path == '/api/clipboard') {
      onPush?.call();
      return http.Response('{"ok":true}', 200);
    }
    if (req.method == 'GET' && path == '/api/clipboard/pc') {
      return http.Response(jsonEncode({'text': pcText}), 200);
    }
    if (req.method == 'POST' && path == '/api/link/open') {
      onOpenLink?.call();
      return http.Response('{"ok":true}', 200);
    }
    return http.Response('nf', 404);
  });
}

ClipboardScreen _screen(
  MockClient mock, {
  Future<String?> Function()? read,
  Future<void> Function(String)? write,
}) =>
    ClipboardScreen(
      device: _device,
      client: ClipboardClient(httpClient: mock),
      readPhoneClipboard: read ?? () async => '',
      writePhoneClipboard: write ?? (_) async {},
    );

void main() {
  testWidgets('lists clipboard history with origin + URL affordance', (tester) async {
    final client = _screen(_backend(items: [
      {'id': '1', 'content': 'hello from phone', 'origin': 'phone'},
      {'id': '2', 'content': 'https://example.com', 'origin': 'pc'},
    ]));

    await tester.pumpWidget(MaterialApp(home: client));
    await tester.pumpAndSettle();

    expect(find.text('hello from phone'), findsOneWidget);
    expect(find.text('https://example.com'), findsOneWidget);
    expect(find.text('Ouvrir sur PC'), findsOneWidget);
  });

  testWidgets('« Envoyer » pushes the phone clipboard to the PC', (tester) async {
    var pushed = false;
    await tester.pumpWidget(MaterialApp(
      home: _screen(_backend(onPush: () => pushed = true), read: () async => 'copied text'),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Envoyer'));
    await tester.pumpAndSettle();

    expect(pushed, isTrue);
  });

  testWidgets('« Envoyer » with an empty clipboard hints and does not push', (tester) async {
    var pushed = false;
    await tester.pumpWidget(MaterialApp(
      home: _screen(_backend(onPush: () => pushed = true), read: () async => '   '),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Envoyer'));
    await tester.pumpAndSettle();

    expect(pushed, isFalse);
    expect(find.textContaining('vide'), findsOneWidget);
  });

  testWidgets('« Coller depuis le PC » writes the PC clipboard to the phone', (tester) async {
    String? written;
    await tester.pumpWidget(MaterialApp(
      home: _screen(_backend(pcText: 'from PC clipboard'), write: (t) async => written = t),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Coller depuis le PC'));
    await tester.pumpAndSettle();

    expect(written, 'from PC clipboard');
  });

  testWidgets('tapping an item copies it to the phone clipboard', (tester) async {
    String? written;
    await tester.pumpWidget(MaterialApp(
      home: _screen(
        _backend(items: [
          {'id': '1', 'content': 'recopie-moi', 'origin': 'pc'},
        ]),
        write: (t) async => written = t,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('recopie-moi'));
    await tester.pumpAndSettle();

    expect(written, 'recopie-moi');
  });

  testWidgets('« Ouvrir sur PC » on a URL item calls the open-link endpoint', (tester) async {
    var opened = false;
    await tester.pumpWidget(MaterialApp(
      home: _screen(_backend(
        items: [
          {'id': '2', 'content': 'https://x.com', 'origin': 'phone'},
        ],
        onOpenLink: () => opened = true,
      )),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ouvrir sur PC'));
    await tester.pumpAndSettle();

    expect(opened, isTrue);
  });

  testWidgets('shows the server error message when the PC write fails', (tester) async {
    final mock = MockClient((req) async {
      if (req.method == 'GET' && req.url.path == '/api/clipboard') {
        return http.Response(jsonEncode({'items': []}), 200);
      }
      // Le PC n'a pas d'outil presse-papier → 503 avec le message utile.
      return http.Response(
        jsonEncode({'message': 'Aucun outil presse-papier trouvé. Installe wl-clipboard.'}),
        503,
      );
    });
    await tester.pumpWidget(MaterialApp(
      home: ClipboardScreen(
        device: _device,
        client: ClipboardClient(httpClient: mock),
        readPhoneClipboard: () async => 'du texte',
        writePhoneClipboard: (_) async {},
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Envoyer'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Installe wl-clipboard'), findsOneWidget);
  });

  testWidgets('auto mode pushes to the PC on a phone clipboard change', (tester) async {
    var pushed = false;
    final watcher = _FakeWatcher();
    await tester.pumpWidget(MaterialApp(
      home: ClipboardScreen(
        device: _device,
        client: ClipboardClient(httpClient: _backend(onPush: () => pushed = true)),
        watcher: watcher,
        readPhoneClipboard: () async => 'auto copied',
        writePhoneClipboard: (_) async {},
        // Intervalle volontairement long : le timer périodique ne se déclenche
        // pas pendant le test (on teste le push sur événement, pas le poll).
        autoPollInterval: const Duration(minutes: 5),
      ),
    ));
    await tester.pumpAndSettle();

    // Active le mode auto (abonne le watcher).
    await tester.tap(find.text('Sync auto'));
    await tester.pumpAndSettle();
    expect(watcher.started, isTrue);

    // Simule une copie sur le téléphone → push auto.
    watcher.fire();
    await tester.pumpAndSettle();
    expect(pushed, isTrue);

    // Dispose l'écran pour annuler le timer périodique (sinon « pending timer »).
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
