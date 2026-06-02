import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linkup_mobile/screens/gallery/gallery_send_screen.dart';
import 'package:linkup_mobile/services/gallery/gallery_sender.dart';
import 'package:linkup_mobile/services/gallery/gallery_source.dart';
import 'package:linkup_mobile/services/pairing/paired_device_store.dart';
import 'package:linkup_mobile/services/transfer/transfer_client.dart';

const _device = PairedDevice(
  deviceId: 'dev-1',
  host: '192.168.1.50',
  port: 8000,
  token: 'device-token',
  pcPublicKey: 'pk',
  pcFingerprint: 'fp',
  pcName: 'mon-pc',
);

final _pixel = Uint8List.fromList([
  // 1x1 transparent PNG (assez pour Image.memory en test).
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

class _FakeSource implements GalleryAssetSource {
  final bool granted;
  _FakeSource({this.granted = true});

  @override
  Future<bool> requestPermission() async => granted;

  @override
  Future<List<GalleryAsset>> list({int page = 0, int size = 100}) async => page == 0
      ? [
          GalleryAsset(
            meta: const GalleryMeta(mediaId: 'a', mime: 'image/jpeg'),
            loadThumbnail: () async => _pixel,
          ),
          GalleryAsset(
            meta: const GalleryMeta(mediaId: 'b', mime: 'image/jpeg'),
            loadThumbnail: () async => _pixel,
          ),
        ]
      : const [];

  @override
  Future<GalleryOriginal?> loadOriginal(String mediaId) async =>
      GalleryOriginal(bytes: Uint8List.fromList([1, 2, 3]), filename: '$mediaId.jpg');
}

/// Faux sender : ne touche pas au réseau, renvoie un bilan déterministe.
class _FakeSender extends GallerySender {
  _FakeSender() : super(source: _FakeSource(), transfers: TransferClient());

  @override
  Future<GallerySendResult> send(
    PairedDevice device,
    List<String> mediaIds, {
    void Function(GallerySendProgress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    onProgress?.call(GallerySendProgress(
      done: 0,
      total: mediaIds.length,
      currentName: '${mediaIds.first}.jpg',
      fileFraction: 0.5,
    ));
    return GallerySendResult(sent: mediaIds.length, failed: 0);
  }
}

void main() {
  testWidgets('selects photos and shows a success summary after sending', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: GallerySendScreen(device: _device, source: _FakeSource(), sender: _FakeSender()),
    ));
    await tester.pumpAndSettle();

    // Grille chargée : le bouton invite à sélectionner.
    expect(find.text('Sélectionne des médias'), findsOneWidget);

    // Sélectionne la première vignette (on tape l'image du tile, pas le filtre).
    await tester.tap(find.byType(Image).first);
    await tester.pumpAndSettle();
    expect(find.text('Envoyer 1 élément(s) au PC'), findsOneWidget);

    // Envoie.
    await tester.tap(find.text('Envoyer 1 élément(s) au PC'));
    await tester.pumpAndSettle();

    expect(find.text('Envoi terminé'), findsOneWidget);
    expect(find.textContaining('1 photo(s) envoyée(s)'), findsOneWidget);
  });

  testWidgets('shows an error when the permission is denied', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: GallerySendScreen(device: _device, source: _FakeSource(granted: false), sender: _FakeSender()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Impossible'), findsOneWidget);
    expect(find.textContaining('Permission'), findsOneWidget);
  });
}
