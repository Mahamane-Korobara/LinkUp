import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/preview/local_proxy.dart';

/// Rend un projet de dev exposé par le PC dans une WebView in-app (S14).
///
/// Voie PRINCIPALE du Dev Preview. Pour reproduire **fidèlement** l'environnement
/// du PC, on lance **un proxy local par port exposé**, chacun sur le MÊME port que
/// le serveur de dev d'origine (`127.0.0.1:3001`, `127.0.0.1:8001`, …). La WebView
/// charge `http://localhost:3001` ; l'app y appelle `localhost:8001` exactement
/// comme sur le PC (cross-origin natif, mêmes cookies, même CORS) — sans réécriture
/// d'URL ni préfixe. Chaque proxy parle TLS au bridge en épinglant son certificat
/// (zéro install CA). `localhost` (et non 127.0.0.1) car Next dev n'autorise son
/// WebSocket HMR que depuis sa propre origine.
///
/// Ce que la WebView NE fait pas (install PWA écran d'accueil, Web Push, DevTools)
/// reste accessible via « Ouvrir dans Chrome ».
class PreviewWebViewScreen extends StatefulWidget {
  /// URL HTTPS du projet sur le PC (`https://<ip>:<listen>`) — pour joindre le PC
  /// (hôte) et pour le repli « Ouvrir dans Chrome ».
  final Uri url;

  /// Empreinte SHA-256 (hex) du cert serveur du bridge, à épingler. Null → pas de
  /// pin possible (on n'ouvre pas en in-app).
  final String? certSha256;

  /// Port d'origine du projet ouvert (ex. 3001) : la WebView charge `localhost:<frontPort>`.
  final int frontPort;

  /// Tous les projets exposés : port d'origine → port d'écoute du bridge. On ouvre
  /// un proxy local par entrée, lié au même port d'origine sur 127.0.0.1 du tél.
  final Map<int, int> portToListen;

  const PreviewWebViewScreen({
    super.key,
    required this.url,
    required this.certSha256,
    required this.frontPort,
    required this.portToListen,
  });

  @override
  State<PreviewWebViewScreen> createState() => _PreviewWebViewScreenState();
}

class _PreviewWebViewScreenState extends State<PreviewWebViewScreen> {
  InAppWebViewController? _controller;
  final List<LocalPreviewProxy> _proxies = [];
  double _progress = 0;

  /// URL locale à charger une fois les proxies démarrés : `http://localhost:<frontPort>`.
  String? _localUrl;

  /// Renseigné si un proxy ne démarre pas / le cert ne correspond pas au pin.
  String? _error;

  @override
  void initState() {
    super.initState();
    // Inspectable depuis `chrome://inspect` du PC (console + réseau).
    if (Platform.isAndroid) {
      InAppWebViewController.setWebContentsDebuggingEnabled(true);
    }
    _startProxies();
  }

  Future<void> _startProxies() async {
    if (widget.certSha256 == null) {
      setState(() => _error =
          'Le PC ne fournit pas d\'empreinte de certificat à épingler. '
          'Mets Linkup à jour côté PC, ou utilise « Ouvrir dans Chrome ».');
      return;
    }
    int? frontBound;
    try {
      for (final entry in widget.portToListen.entries) {
        final proxy = LocalPreviewProxy(
          pcHost: widget.url.host,
          targetListenPort: entry.value,
          certSha256: widget.certSha256,
          preferredListenPort: entry.key,
          onUpstreamFailure: (_) {
            if (mounted) {
              setState(() => _error =
                  'Le certificat du PC ne correspond pas à celui attendu (ou le PC '
                  'est injoignable). Connexion refusée par sécurité — recharge la '
                  'liste sur l\'écran précédent puis rouvre le projet.');
            }
          },
        );
        final bound = await proxy.start();
        _proxies.add(proxy);
        if (entry.key == widget.frontPort) frontBound = bound;
        // Un back doit écouter sur SON port exact (sinon `localhost:<port>` de
        // l'app ne le joindra pas) ; on le signale sans bloquer.
        if (bound != entry.key) {
          debugPrint('[local-proxy] ⚠ port ${entry.key} déjà pris sur le tél → '
              'ouvert sur $bound (les appels localhost:${entry.key} échoueront).');
        }
      }
    } catch (e) {
      await _stopProxies();
      if (mounted) setState(() => _error = 'Impossible de démarrer le proxy local : $e');
      return;
    }
    if (!mounted) {
      await _stopProxies();
      return;
    }
    setState(() => _localUrl = 'http://localhost:${frontBound ?? widget.frontPort}');
  }

  Future<void> _stopProxies() async {
    for (final p in _proxies) {
      await p.stop();
    }
    _proxies.clear();
  }

  @override
  void dispose() {
    _stopProxies();
    super.dispose();
  }

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
        title: Text('Preview — port ${widget.frontPort}'),
        actions: [
          IconButton(
            tooltip: 'Recharger',
            onPressed: _controller == null ? null : () => _controller?.reload(),
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Ouvrir dans Chrome (PWA / DevTools)',
            onPressed: _openInBrowser,
            icon: const Icon(Icons.open_in_browser),
          ),
        ],
        bottom: _progress < 1.0 && _error == null && _localUrl != null
            ? PreferredSize(
                preferredSize: const Size.fromHeight(3),
                child: LinearProgressIndicator(value: _progress),
              )
            : null,
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_error != null) return _errorView();
    if (_localUrl == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return _webView(_localUrl!);
  }

  Widget _webView(String localUrl) {
    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(localUrl)),
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
      onConsoleMessage: (controller, msg) {
        debugPrint('[WebView:${msg.messageLevel}] ${msg.message}');
      },
      onReceivedError: (controller, request, error) {
        debugPrint('[WebView:error] ${request.url} → ${error.type} ${error.description}');
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

  Widget _errorView() {
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
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
