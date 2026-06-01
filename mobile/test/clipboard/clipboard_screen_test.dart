import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:linkup_mobile/screens/clipboard/clipboard_screen.dart';
import 'package:linkup_mobile/services/clipboard/clipboard_client.dart';
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
    expect(find.text('Ouvrir sur PC'), findsOneWidget); // sur l'item URL
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
}
