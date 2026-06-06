/// Shim réseau injecté dans la WebView du Dev Preview (S14, Lot F).
///
/// Problème : un front exposé appelle souvent son back en dur via
/// `http://localhost:8000` (ou `ws://localhost:6001`…). Sur le téléphone,
/// `localhost` = le téléphone lui-même → l'appel échoue. On ne peut pas non plus
/// pointer vers `https://<ip-PC>:<autre-port>` : ce serait une autre origine →
/// CORS + mixed-content.
///
/// Solution single-origin : le bridge route, sur CHAQUE listener, un préfixe
/// `/__linkup/<port>/…` vers `127.0.0.1:<port>`. Ce shim, injecté au tout début du
/// document, monkeypatche les primitives réseau pour réécrire à la volée tout appel
/// vers `localhost|127.0.0.1|0.0.0.0:<port>` (pour un `<port>` **exposé**) en
/// `<origine courante>/__linkup/<port>/…`. Résultat : **même origine** que le front
/// → zéro CORS, zéro mixed-content, et ça marche pour n'importe quel stack
/// (axios, socket.io, Livewire, EventSource…) sans toucher au code du projet.
///
/// Limite : couvre les appels réseau JS (fetch / XHR / WebSocket / EventSource),
/// pas les URLs `localhost:<port>` codées en dur dans le HTML/CSS statique
/// (`<img src>`…). C'est « la communication » qui est visée, pas les assets.
library;

/// Construit le code source JS du shim pour les [exposedPorts] donnés.
///
/// Fonction pure (testable sans WebView). Idempotente côté JS (drapeau
/// `window.__linkupShimInstalled`). Si [exposedPorts] est vide, le shim s'installe
/// mais ne réécrit rien (no-op).
String buildNetworkShim(List<int> exposedPorts) {
  final portsLiteral = '[${exposedPorts.join(', ')}]';
  return _shimTemplate.replaceFirst('__LINKUP_PORTS__', portsLiteral);
}

// Raw string : préserve les backslashes des regex JS (\/, \., \d) tels quels.
const String _shimTemplate = r'''
(function () {
  if (window.__linkupShimInstalled) return;
  window.__linkupShimInstalled = true;

  var ports = __LINKUP_PORTS__;
  var exposed = {};
  for (var i = 0; i < ports.length; i++) exposed[String(ports[i])] = true;

  var httpBase = location.origin;                        // https://<ip>:<listen>
  var wsBase = location.origin.replace(/^http/, 'ws');   // wss://<ip>:<listen>
  var LOCAL = /^(https?|wss?):\/\/(localhost|127\.0\.0\.1|0\.0\.0\.0):(\d+)(\/.*)?$/i;

  // Réécrit une URL absolue localhost:<port exposé> → origine courante + préfixe.
  // Toute autre URL (relative, distante, port non exposé) est laissée intacte.
  function rewrite(url) {
    try {
      if (typeof url !== 'string') return url;
      var m = url.match(LOCAL);
      if (!m) return url;
      if (!exposed[m[3]]) return url;
      var rest = m[4] || '/';
      var isWs = m[1].toLowerCase().indexOf('ws') === 0;
      return (isWs ? wsBase : httpBase) + '/__linkup/' + m[3] + rest;
    } catch (e) {
      return url;
    }
  }

  // fetch(input, init) : input peut être une string ou un Request.
  if (window.fetch) {
    var _fetch = window.fetch;
    window.fetch = function (input, init) {
      try {
        if (typeof input === 'string') {
          input = rewrite(input);
        } else if (input && input.url) {
          var u = rewrite(input.url);
          if (u !== input.url) input = new Request(u, input);
        }
      } catch (e) {}
      return _fetch.call(this, input, init);
    };
  }

  // XMLHttpRequest.open(method, url, ...)
  if (window.XMLHttpRequest) {
    var _open = XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.open = function () {
      if (arguments.length > 1) arguments[1] = rewrite(arguments[1]);
      return _open.apply(this, arguments);
    };
  }

  // Wrappe un constructeur (WebSocket/EventSource) pour réécrire son 1ᵉʳ argument.
  function wrapCtor(Original, statics) {
    function Wrapped(url, opt) {
      return opt === undefined ? new Original(rewrite(url)) : new Original(rewrite(url), opt);
    }
    Wrapped.prototype = Original.prototype;
    for (var i = 0; i < statics.length; i++) {
      var k = statics[i];
      if (k in Original) Wrapped[k] = Original[k];
    }
    return Wrapped;
  }

  if (window.WebSocket) {
    window.WebSocket = wrapCtor(window.WebSocket, ['CONNECTING', 'OPEN', 'CLOSING', 'CLOSED']);
  }
  if (window.EventSource) {
    window.EventSource = wrapCtor(window.EventSource, ['CONNECTING', 'OPEN', 'CLOSED']);
  }
})();
''';
