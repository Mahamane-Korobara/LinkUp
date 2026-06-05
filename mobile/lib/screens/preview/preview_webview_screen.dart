import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/preview/preview_client.dart';

/// Rend un projet de dev exposé par le PC dans une WebView in-app (S14).
///
/// Voie PRINCIPALE du Dev Preview : au lieu de faire installer la CA Linkup dans
/// l'OS (PIN forcé + avertissement permanent côté Android), on **épingle** ici le
/// cert serveur du bridge ([certMatchesPin]) → HTTPS de confiance sans aucune
/// install. La WebView gère caméra/micro/géoloc via les permissions runtime.
///
/// Ce que la WebView NE fait pas (install PWA sur l'écran d'accueil, Web Push,
/// DevTools du navigateur) reste accessible via « Ouvrir dans Chrome ».
class PreviewWebViewScreen extends StatefulWidget {
  /// URL du projet : `https://<ip-LAN>:<listen_port>`.
  final Uri url;

  /// Empreinte SHA-256 (hex) du cert serveur, annoncée par le bridge. Null si le
  /// PC est trop ancien pour la fournir → on n'ouvre pas en in-app (pas de pin).
  final String? certSha256;

  /// Port d'origine du serveur de dev (ex. 5173), pour le titre.
  final int targetPort;

  const PreviewWebViewScreen({
    super.key,
    required this.url,
    required this.certSha256,
    required this.targetPort,
  });

  @override
  State<PreviewWebViewScreen> createState() => _PreviewWebViewScreenState();
}

class _PreviewWebViewScreenState extends State<PreviewWebViewScreen> {
  InAppWebViewController? _controller;
  double _progress = 0;

  /// Renseigné si le cert présenté ne correspond pas au pin : on refuse de rendre
  /// la moindre page (anti-MITM) et on affiche une erreur explicite à la place.
  String? _pinError;

  Future<void> _openInBrowser() async {
    await launchUrl(widget.url, mode: LaunchMode.externalApplication);
  }

  /// Map une ressource web demandée vers les permissions Android à obtenir.
  List<Permission> _permissionsFor(PermissionResourceType r) {
    if (r == PermissionResourceType.CAMERA) return [Permission.camera];
    if (r == PermissionResourceType.MICROPHONE) return [Permission.microphone];
    if (r == PermissionResourceType.CAMERA_AND_MICROPHONE) {
      return [Permission.camera, Permission.microphone];
    }
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Preview — port ${widget.targetPort}'),
        actions: [
          IconButton(
            tooltip: 'Recharger',
            onPressed: () => _controller?.reload(),
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Ouvrir dans Chrome (PWA / DevTools)',
            onPressed: _openInBrowser,
            icon: const Icon(Icons.open_in_browser),
          ),
        ],
        bottom: _progress < 1.0 && _pinError == null
            ? PreferredSize(
                preferredSize: const Size.fromHeight(3),
                child: LinearProgressIndicator(value: _progress),
              )
            : null,
      ),
      body: _pinError != null ? _pinErrorView() : _webView(),
    );
  }

  Widget _webView() {
    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(widget.url.toString())),
      initialSettings: InAppWebViewSettings(
        // getUserMedia (caméra/micro) sans exiger un geste utilisateur préalable.
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
        geolocationEnabled: true,
      ),
      onWebViewCreated: (c) => _controller = c,
      onProgressChanged: (c, p) {
        if (mounted) setState(() => _progress = p / 100.0);
      },

      // ----- Cœur sécurité : on n'accepte QUE le cert épinglé -----
      onReceivedServerTrustAuthRequest: (controller, challenge) async {
        final der =
            challenge.protectionSpace.sslCertificate?.x509Certificate?.encoded;
        if (der != null && await certMatchesPin(der, widget.certSha256)) {
          return ServerTrustAuthResponse(
            action: ServerTrustAuthResponseAction.PROCEED,
          );
        }
        if (mounted) {
          setState(() => _pinError =
              "Le certificat du PC ne correspond pas à celui attendu. "
              "Connexion refusée par sécurité.");
        }
        return ServerTrustAuthResponse(
          action: ServerTrustAuthResponseAction.CANCEL,
        );
      },

      // ----- Permissions caméra / micro demandées par la page web -----
      onPermissionRequest: (controller, request) async {
        final granted = <PermissionResourceType>[];
        for (final resource in request.resources) {
          final perms = _permissionsFor(resource);
          if (perms.isEmpty) continue;
          var allOk = true;
          for (final p in perms) {
            final status = await p.request();
            if (!status.isGranted) allOk = false;
          }
          if (allOk) granted.add(resource);
        }
        return PermissionResponse(
          resources: granted,
          action: granted.isEmpty
              ? PermissionResponseAction.DENY
              : PermissionResponseAction.GRANT,
        );
      },

      // ----- Permission géolocalisation demandée par la page web -----
      onGeolocationPermissionsShowPrompt: (controller, origin) async {
        final status = await Permission.location.request();
        return GeolocationPermissionShowPromptResponse(
          origin: origin,
          allow: status.isGranted,
          retain: true,
        );
      },
    );
  }

  Widget _pinErrorView() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.gpp_bad_outlined, size: 56, color: Colors.red),
          const SizedBox(height: 16),
          const Text(
            'Connexion non sécurisée',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            _pinError!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 8),
          const Text(
            'Recharge la liste sur l\'écran précédent (le PC a peut-être '
            'redémarré), puis rouvre le projet.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
