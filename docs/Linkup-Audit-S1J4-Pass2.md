# 🔍 Rapport d'Audit #2 — Linkup (post-fixes S1.J4)

**Date :** 2026-05-30
**Périmètre :** code modifié depuis le commit `c96a19f` (refactor P1+P2 du premier audit)
**Stack :** Laravel 12 + FastAPI + Flutter 3.41 + Kotlin Android
**Lignes de code (sources métier) :** ~1 900 LOC
**Problèmes nouveaux trouvés :** 20 (🔴 3 critiques • 🟠 9 importants • 🟡 8 mineurs)
**Estimation dette :** ~4 à 5 heures de nettoyage

Le premier audit a corrigé 27 problèmes (4 P0 + 14 P1 + 9 P2). Cette seconde passe se concentre sur :
1. Ce qui a été introduit par le refactor
2. Les angles morts du premier audit
3. Les subtilités d'architecture qui méritent une seconde lecture

---

## 📊 Résumé exécutif

### Top 3 critiques

1. **🔴 PSR-4 violation** : `BridgeUnavailableException` co-located dans `BridgeClient.php`. Marche aujourd'hui par autoload-by-side-effect, fragile.
2. **🔴 Bug `bridgeHealthUri`** : utilise `bridgePort` du modèle qui peut prendre la valeur `srv.port` (= port Reverb 8080) en fallback. Le `health` partirait vers Reverb au lieu du bridge.
3. **🔴 `_safe_username()` défini après son usage** dans `bridge/main.py` : Python l'autorise mais c'est un code smell qui dégrade la lisibilité.

### Santé par catégorie

| Catégorie | 🔴 | 🟠 | 🟡 |
|---|---|---|---|
| Architecture / PSR / structure | 1 | 4 | 1 |
| Bug latent | 2 | 1 | 1 |
| Tests manquants | 0 | 2 | 3 |
| Sécurité | 0 | 2 | 0 |
| Style / consistance | 0 | 0 | 3 |
| **Total** | **3** | **9** | **8** |

### Hot spots

| Fichier | Problèmes |
|---|---|
| `agent/app/Services/BridgeClient.php` | 3 |
| `mobile/lib/models/linkup_agent.dart` | 3 |
| `mobile/lib/screens/agent_picker/manual_agent_dialog.dart` | 3 |
| `bridge/app/main.py` | 3 |
| `mobile/lib/services/linkup_discovery.dart` | 2 |

---

## 🗂️ Problèmes détaillés

### 1) `agent/app/Services/BridgeClient.php` (86 lignes)

#### 🔴 PSR-4 violation — `BridgeClient.php:84`
**Catégorie :** Architecture / dette technique
**Problème :** `BridgeUnavailableException` est définie dans le même fichier que `BridgeClient`. Le standard PSR-4 dit : une classe par fichier, fichier nommé comme la classe. Composer accepte la situation actuelle (`composer dump-autoload` voit la classe via la classmap optimisée), mais c'est fragile :
- Si un autre fichier fait `use App\Services\BridgeUnavailableException;` SANS aussi importer `BridgeClient`, Composer ne sait pas où trouver la classe.
- En mode dev avec `--no-classmap-authoritative`, ça peut planter.
- Si quelqu'un déplace l'exception, l'autre référence casse silencieusement.

**Avant :**
```php
class BridgeClient { ... }

class BridgeUnavailableException extends RuntimeException { }
```
**Après :** créer un fichier dédié `agent/app/Services/BridgeUnavailableException.php` :
```php
<?php

namespace App\Services;

use RuntimeException;

class BridgeUnavailableException extends RuntimeException
{
}
```
Et retirer la classe du fichier `BridgeClient.php`.

#### 🟠 Pas de retry sur appels HTTP — `BridgeClient.php:51`
**Catégorie :** Robustesse
**Problème :** Le bridge peut être lent à démarrer (mDNS init + zeroconf setup ~1-2s). Un seul appel `/mdns/info` qui timeout = 503 instantané pour l'utilisateur, alors qu'un retry de 1 seconde aurait suffit.
**Action :**
```php
private function request(): PendingRequest
{
    return $this->http
        ->baseUrl($this->baseUrl())
        ->acceptJson()
        ->withToken((string) config('services.linkup_bridge.token'))
        ->timeout((int) config('services.linkup_bridge.timeout_seconds', 2))
        ->retry(2, 100, throw: false);  // ← 2 retries, 100ms backoff
}
```

#### 🟠 Branche `ConnectionException` jamais testée — `BridgeClient.php:52`
**Catégorie :** Couverture tests
**Problème :** Le test `BridgeClientTest::"returns 503 when bridge is down"` simule un HTTP 500 (donc `RequestException`), pas une `ConnectionException` (bridge totalement injoignable). La branche du catch ligne 52-56 n'est pas couverte.
**Action :** ajouter un test qui simule une connexion refusée :
```php
it('returns 503 when bridge connection refused', function () {
    Http::fake(function () {
        throw new ConnectionException('Connection refused');
    });
    $this->getJson('/api/agent/info')->assertStatus(503);
});
```

---

### 2) `agent/routes/api.php` (62 lignes)

#### 🟠 Toujours en closures avec injection de dépendance — `api.php:18, 36, 44`
**Catégorie :** Architecture Laravel
**Problème :** Mentionné dans l'audit #1 (P1), pas encore corrigé. À S2 (pairing), la route `/api/agent/info` va grossir (ajout de fingerprint complet, statut pairing, etc.) et ne tiendra plus dans une closure.
**Action :** créer `app/Http/Controllers/AgentInfoController.php` et `PingController.php` avant de toucher à S2.

#### 🟠 `/api/health` Laravel asymétrique avec `/health` bridge — `api.php:9-16`
**Catégorie :** Cohérence API
**Problème :** Le bridge `/health` retourne `agent_id`, `host`, `user`. Laravel `/api/health` retourne juste `status`/`service`/`version`/`time`. Le LAN sweep côté Flutter ne peut donc PAS découvrir Laravel directement (port 8000) — il vise toujours le bridge (port 8765). C'est intentionnel selon ADR-002, mais à acter par un commentaire ou un test.
**Action :** soit ajouter les champs dans Laravel `/api/health`, soit ajouter un commentaire dans la route :
```php
// Laravel /api/health est minimal par design — le LAN sweep des clients tape
// directement /health du bridge Python qui a tous les champs riches.
```

---

### 3) `bridge/app/main.py` (182 lignes)

#### 🔴 `_safe_username()` défini APRÈS son usage — `main.py:144 vs :151`
**Catégorie :** Code smell / lisibilité
**Problème :** `health()` ligne 128 appelle `_safe_username()` ligne 144 — mais cette fonction est déclarée ligne 151, plus bas. Python autorise (résolution au runtime), mais c'est confusant : à la lecture top-down, on tombe sur un appel à une fonction non encore définie.
**Avant :**
```python
@app.get("/health")
def health(request: Request) -> dict:
    ...
    "user": _safe_username(),  # défini... plus loin ??
    ...

def _safe_username() -> str:  # ← ici
    ...
```
**Après :** déplacer `_safe_username()` AVANT `health()`.

#### 🟡 Ancien style de commentaires de section — `main.py:21, 71, 86, 95, 122, 164`
**Catégorie :** Consistance
**Problème :** Après le nettoyage de l'audit #1, les imports sont propres mais les blocs `# =========================` SECTION `# =========================` partout sont une relique. Style inconsistant.
**Action :** soit les supprimer tous (suggéré, FastAPI a un ordre logique évident), soit les remplacer par des docstrings de section. Réduire le bruit.

#### 🟡 `_started_at` non remis à zéro lors d'un hot reload uvicorn — `main.py:90`
**Catégorie :** Robustesse dev
**Problème :** `_started_at = time.monotonic()` est calculé à l'import. Si on lance `uvicorn --reload`, le module est rechargé mais `_started_at` peut garder l'ancienne valeur dans certains scénarios de réimport (cas rare mais documentable).
**Action :** déplacer dans le `lifespan()` :
```python
@asynccontextmanager
async def lifespan(app: FastAPI):
    app.state.started_at = time.monotonic()
    ...
```
Et lire `request.app.state.started_at` dans `health()`.

---

### 4) `bridge/app/config.py` (37 lignes)

#### 🟡 Token validator ne vérifie pas l'entropie — `config.py:25-33`
**Catégorie :** Sécurité légère
**Problème :** Le validator refuse uniquement la valeur placeholder exacte. Un user qui utilise `abcdefghijklmnop` (16 chars, pas le placeholder) passe. Mais ce token est devinable.
**Action :** ajouter une heuristique simple :
```python
@field_validator("agent_token")
@classmethod
def _validate_token(cls, value: str) -> str:
    if value.strip() == _PLACEHOLDER_TOKEN:
        raise ValueError("placeholder token interdit, voir docstring")
    if len(set(value)) < 8:
        raise ValueError("token trop pauvre en caractères distincts")
    return value
```

---

### 5) `bridge/tests/test_config.py` (47 lignes — après ruff)

#### 🟡 Test couple à un nom de token précis — `test_config.py:31`
**Catégorie :** Fragilité tests
**Problème :** Le test contient `"change-me-to-a-random-32-bytes-base64"` en dur. Si on renomme la sentinelle dans `config.py`, le test casse silencieusement (il continue de passer mais ne teste plus le bon truc).
**Action :** importer la constante :
```python
from app.config import _PLACEHOLDER_TOKEN  # noqa
```
ou exposer une fonction `is_placeholder(token) -> bool` qu'on importe ici.

---

### 6) `mobile/lib/models/linkup_agent.dart` (118 lignes)

#### 🔴 Bug `bridgeHealthUri` quand TXT manque `bridge_port` — `linkup_agent.dart:65` + `linkup_discovery.dart:144`
**Catégorie :** Bug latent
**Problème :**
- Dans `_resolve()` (linkup_discovery.dart:144) : `final bridgePort = int.tryParse(bridgePortRaw ?? '') ?? srv.port;`
- Si le TXT mDNS n'a pas `bridge_port`, on retombe sur `srv.port` qui est le **port Reverb annoncé** (8080).
- L'agent stocke alors `bridgePort = 8080`.
- `agent.bridgeHealthUri` calcule `http://addr:8080/health` → frappe Reverb, pas le bridge !

**Cas concret :** si un user lance un bridge sans le TXT `bridge_port`, le hover/check côté Flutter va échouer en `Connection refused` sur Reverb (qui ne répond pas à HTTP /health).

**Avant :**
```dart
final bridgePort = int.tryParse(bridgePortRaw ?? '') ?? srv.port;
```
**Après :**
```dart
// Sans TXT bridge_port explicite, on utilise la convention par défaut.
// srv.port est le port Reverb annoncé en mDNS, PAS le port HTTP du bridge.
final bridgePort = int.tryParse(bridgePortRaw ?? '') ?? LinkupPorts.bridge;
```

#### 🟠 `bridgeHealthUri` n'utilise pas `LinkupPorts.bridge` quand `bridgePort` est manquant
Lié au point précédent. Le champ `bridgePort` est `required` donc toujours présent au type Dart, mais peut être faussé par le bug ci-dessus.

#### 🟡 `toString()` répète l'info — `linkup_agent.dart:107-108`
**Catégorie :** Style mineur
**Problème :** Le toString affiche `LinkupAgent(linkup-xyz, 192.168.1.10:8765, source=...)` où `linkup-xyz` est l'`agentId` qui SERT de `uniqueKey`, et `192.168.1.10:8765` est aussi quasi le `uniqueKey` quand `agentId` est null. Redondant.
**Action :** simplifier :
```dart
@override
String toString() => 'LinkupAgent($uniqueKey, source=$source)';
```

---

### 7) `mobile/lib/services/linkup_discovery.dart` (290 lignes)

#### 🟠 `addManualAgent` n'utilise pas `_mergeAgent` — `linkup_discovery.dart:229`
**Catégorie :** Cohérence
**Problème :** Quand l'utilisateur saisit manuellement une IP qui est ensuite découverte par mDNS, le `_resolve` appelle `_mergeAgent` qui préserve les champs. Mais `addManualAgent` fait directement `_agents[uniqueKey] = agent` — donc le manuel écrase tout, incluant un éventuel agent venu du sweep avec `user`/`hostname` riches.
**Avant :**
```dart
_agents[agent.uniqueKey] = agent;
_emit();
```
**Après :**
```dart
_mergeAgent(agent);
```

#### 🟡 `developer.log` spam si rescan répété — `linkup_discovery.dart:90, 113`
**Catégorie :** UX dev
**Problème :** Chaque clic sur "Rescanner" qui échoue produit 2 lignes de log. 5 clics = 10 lignes pour la même cause. Pas grave en dev, mais pollue logcat.
**Action :** dédupliquer avec un cache de la dernière erreur :
```dart
Object? _lastLoggedError;

void _logIfNew(String msg, Object e, StackTrace stack) {
  if (_lastLoggedError == e) return;
  _lastLoggedError = e;
  developer.log(msg, name: 'linkup.discovery', error: e, stackTrace: stack);
}
```

---

### 8) `mobile/lib/services/lan_sweep.dart` (126 lignes)

#### 🟠 Sélection arbitraire de la première interface IPv4 — `lan_sweep.dart:107-111`
**Catégorie :** Robustesse / bug latent
**Problème :** `_localIPv4()` retourne la première IP RFC1918 trouvée dans l'itération. Sur un tel avec Wi-Fi ET cellular ET VPN, cet ordre n'est pas garanti — on peut tomber sur l'IP cellular et scanner le sous-réseau 10.x.x.x du carrier (inutile, va échouer 254 fois en 600ms = 2-3s perdues).
**Action :** prioriser explicitement les interfaces Wi-Fi :
```dart
Future<String?> _localIPv4() async {
  final interfaces = await NetworkInterface.list(...);
  // Sur Android, les interfaces Wi-Fi commencent par 'wlan' ou 'swlan'.
  // Tri custom pour les mettre en premier.
  interfaces.sort((a, b) {
    final aWifi = a.name.startsWith('wlan') || a.name.startsWith('swlan');
    final bWifi = b.name.startsWith('wlan') || b.name.startsWith('swlan');
    if (aWifi != bWifi) return aWifi ? -1 : 1;
    return 0;
  });
  // ... reste pareil
}
```

#### 🟡 `_subnet24` ne valide pas les octets — `lan_sweep.dart:119-123`
**Catégorie :** Mineur (cas pratique impossible)
**Problème :** `_subnet24("999.1.1.1")` retourne `"999.1.1"`. Aucun appel direct n'envoie de bête comme ça (vient de NetworkInterface), mais c'est une fonction qui ne fait pas ce que son nom suggère.
**Action :** vérifier chaque partie :
```dart
String? _subnet24(String ip) {
  final parts = ip.split('.');
  if (parts.length != 4) return null;
  for (final p in parts) {
    final n = int.tryParse(p);
    if (n == null || n < 0 || n > 255) return null;
  }
  return '${parts[0]}.${parts[1]}.${parts[2]}';
}
```

---

### 9) `mobile/lib/screens/agent_picker/manual_agent_dialog.dart` (113 lignes)

#### 🟠 Validateurs privés, non testables — `manual_agent_dialog.dart:98-113`
**Catégorie :** Couverture tests
**Problème :** `_validateAddress` et `_validatePort` sont des fonctions top-level privées (`_`) du fichier. Aucun unit test ne peut les appeler directement → la regex IPv4 stricte (4 chiffres × 4 octets) peut casser silencieusement.
**Action :** soit les déplacer dans `lib/utils/address_validators.dart` (public), soit créer un widget test qui couvre tous les cas.

Exemple de tests à ajouter :
```dart
test('rejects IP with octet > 255', () {
  expect(validateAddress('256.1.1.1'), isNotNull);
});

test('accepts IP 0.0.0.0', () {
  expect(validateAddress('0.0.0.0'), isNull);
});

test('accepts pc.local hostname', () {
  expect(validateAddress('pc.local'), isNull);
});

test('rejects empty', () {
  expect(validateAddress(''), 'Adresse requise');
});
```

#### 🟠 Hostname regex accepte `pc` sans suffixe — `manual_agent_dialog.dart:96`
**Catégorie :** Robustesse
**Problème :** La regex `^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}(\.local)?$` accepte juste `pc`. Mais sur un LAN moderne, le résolveur DNS lookup `pc` interrogera le DNS public en cas d'échec local, ce qui peut être un timeout long ou un résultat surprenant (fournisseur DNS qui redirige les NXDOMAIN).
**Action :** rendre `.local` obligatoire pour les hostnames :
```dart
final _hostnameRegex = RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}\.local$');
```

#### 🟡 Regex IPv4 cas limite 0 — déjà OK
Trick : `[1-9]?\d` matche 0-99, et `2[0-4]\d|25[0-5]` matche 200-255. Le `0.0.0.0` est techniquement valide pour le formulaire mais pas pour cibler un agent (route IP non-routable). Acceptable pour validation côté UI.

---

### 10) `bridge/app/services/mdns.py` (439 lignes)

#### 🟠 God class `LinkupBrowser` (déjà signalé audit #1)
Toujours valable, post-S3. Pas d'action immédiate.

---

### 11) `mobile/lib/screens/agent_picker_screen.dart` (210 lignes)

#### 🟡 Hard-coded i18n strings
Déjà signalé audit #1. Toujours valable. À traiter à S24 (i18n FR+EN).

---

### 12) Tests manquants (cross-cutting)

#### 🟠 Pas de test unitaire pour `_mergeAgent`
**Catégorie :** Couverture
**Problème :** Le fix critique #3 du premier audit (merge sweep/mDNS) est testé indirectement via les widget tests + le test de dispose. Mais il n'existe pas de test unitaire qui isolent le comportement de fusion (« mDNS avec moins de champs ne doit pas écraser sweep avec plus de champs »).
**Action :** ajouter dans `linkup_discovery_test.dart` :
```dart
test('mergeAgent preserves user/hostname when mDNS arrives later', () async {
  final discovery = LinkupDiscovery(...);
  // émettre via sweep avec user=mahamane
  // émettre via mDNS avec user=null
  // assert : agent.user == 'mahamane'
});
```

#### 🟡 Pas de test du cas « sweep ne trouve rien »
Cas typique d'un user sans LAN actif. Pas de test.

#### 🟡 Pas de test direct des regex IP/hostname validators
Voir point 9.

---

### 13) Sécurité (signaux légers)

#### 🟠 `usesCleartextTraffic="true"` global — `mobile/.../AndroidManifest.xml`
**Catégorie :** Sécurité Android
**Problème :** Autorise HTTP cleartext **pour tout domaine**, y compris linkup.sahelstack.tech (futur). En prod (alpha S6.5), un MITM sur le LAN peut intercepter ou injecter les requêtes.
**Action :** créer `res/xml/network_security_config.xml` qui restreint HTTP aux RFC1918 :
```xml
<network-security-config>
  <base-config cleartextTrafficPermitted="false"/>
  <domain-config cleartextTrafficPermitted="true">
    <domain includeSubdomains="false">192.168.0.0</domain>
    <!-- Le pattern domain ne supporte pas les CIDR en réalité.
         Alternative : utiliser un base-config qui interdit puis
         override par interface dans les sockets (pas trivial). -->
  </domain-config>
</network-security-config>
```
**Note :** Android `network-security-config` est limité — les patterns domain ne supportent pas CIDR. La vraie sécurité passe par TLS sur le bridge (S2+ avec pairing crypto). Pour l'instant, accepter la limitation et la documenter dans ADR-002.

#### 🟠 `/health` bridge expose `user` et `host` côté LAN
**Catégorie :** Fingerprinting
**Problème :** Sur un Wi-Fi partagé (café, hotel), n'importe qui peut connaître ton nom user et hostname Linux en frappant 254 IPs. C'est ce que fait notre propre LAN sweep — d'autres peuvent le faire aussi.
**Action :** envisager un mode privacy où `/health` ne retourne que `service` et `agent_id` (8 chars hex sans info perso). À documenter dans ADR sécurité quand on aura un security-audit complet.

---

### 14) `.env` versionnement — OK

Vérifié : `.gitignore` ligne 19 exclut `.env`, `git ls-files | grep env` ne montre que les `.env.example`. **Aucun problème.**

---

## ✅ Plan d'action recommandé

### 🔴 P0 — Faire avant de coder S2 (~1h)

- [ ] Extraire `BridgeUnavailableException` dans son propre fichier (PSR-4)
- [ ] Fix bug `bridgeHealthUri` → fallback sur `LinkupPorts.bridge` au lieu de `srv.port`
- [ ] Déplacer `_safe_username()` AVANT `health()` dans `bridge/main.py`

### 🟠 P1 — Sprint S2-S3 (~2-3h)

- [ ] Retry HTTP sur `BridgeClient` (`.retry(2, 100)`)
- [ ] Test `ConnectionException` dans `BridgeClientTest`
- [ ] Transformer les closures `api.php` en controllers (`AgentInfoController`, `PingController`)
- [ ] `addManualAgent` doit utiliser `_mergeAgent`
- [ ] Priorisation interfaces Wi-Fi dans `_localIPv4()`
- [ ] Exposer + tester `_validateAddress` / `_validatePort` (`lib/utils/address_validators.dart`)
- [ ] Hostname regex : `.local` obligatoire
- [ ] Test unitaire pour `_mergeAgent`
- [ ] Décider scope `usesCleartextTraffic` (ADR ou config XML)

### 🟡 P2 — Backlog

- [ ] Nettoyer commentaires `# ===` dans `bridge/main.py`
- [ ] Déplacer `_started_at` dans `lifespan()`
- [ ] Token validator : check entropie minimale
- [ ] Test cas « sweep ne trouve rien »
- [ ] `_subnet24` valide chaque octet
- [ ] `_logIfNew` rate-limit des `developer.log`
- [ ] Importer `_PLACEHOLDER_TOKEN` dans `test_config.py`
- [ ] Simplifier `LinkupAgent.toString()`
- [ ] Cohérence `/api/health` Laravel : ajouter commentaire ou aligner sur bridge

---

## 📌 Synthèse

L'audit #2 trouve **20 nouveaux problèmes** dont **3 critiques**. La majorité sont des subtilités liées au refactor récent (PSR-4, ordre de déclaration, fallback fragile) — pas du code mort ni des bugs grossiers. Le code est globalement **bien structuré** après l'audit #1, mais quelques pièges restent :

- Le **PSR-4 violation** est le plus important — facile à corriger, prévient un futur bug obscur
- Le **bug `bridgeHealthUri` → port Reverb** est le plus subtil — invisible jusqu'à ce qu'un user lance un bridge sans TXT `bridge_port`
- Le reste est **dette préventive** : tests à ajouter, validation à durcir, robustesse réseau

**Estimation P0+P1 : 3-4 heures.** À planifier avant S2 (pairing) qui ajoutera beaucoup de surface API et amplifierait ces problèmes.

> Critères pour audit #3 : refaire après S2-S3 complets. Le modèle de données (15 tables SQLite) et les controllers vont introduire une nouvelle vague de patterns à surveiller (N+1, mass assignment, validation).
