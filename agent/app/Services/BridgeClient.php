<?php

namespace App\Services;

use Illuminate\Http\Client\ConnectionException;
use Illuminate\Http\Client\Factory as HttpFactory;
use Illuminate\Http\Client\PendingRequest;
use Illuminate\Http\Client\RequestException;

/**
 * Client HTTP local vers le bridge Python (`bridge/app/...`).
 *
 * Laravel orchestre, le bridge touche l'OS — toute interaction métier qui doit
 * passer par le bridge (mDNS, clipboard, terminal, transfert) passe par ce
 * client. Pas d'appel direct depuis controllers/routes.
 *
 * Anciennement nommé MdnsAnnouncer (cf. audit S1.J4 : naming trompeur, ne fait
 * pas d'annonce mDNS, juste lit l'état du bridge local).
 */
class BridgeClient
{
    public function __construct(
        private readonly HttpFactory $http,
    ) {
    }

    /**
     * Retourne les infos mDNS de l'agent local (cette machine).
     *
     * @throws BridgeUnavailableException si le bridge ne répond pas
     */
    public function localInfo(): array
    {
        return $this->safeGet('/mdns/info');
    }

    /**
     * Retourne la liste des autres agents Linkup détectés sur le LAN.
     *
     * @throws BridgeUnavailableException si le bridge ne répond pas
     */
    public function discoveredServices(): array
    {
        return $this->safeGet('/mdns/services');
    }

    /**
     * Demande au bridge d'ouvrir un fichier de l'inbox dans l'app par défaut
     * du PC (S4 — « Ouvrir sur le PC »).
     *
     * @throws BridgeUnavailableException
     */
    public function openInbox(string $filename): array
    {
        try {
            return $this->request()
                // L'ouverture lance une appli GUI : le bridge bloque brièvement
                // pour détecter un échec immédiat (cf. _LAUNCH_DETECT_SECONDS).
                // Timeout dédié plus large que le défaut (2 s) pour absorber un
                // démarrage à froid d'appli lourde sans afficher « injoignable ».
                ->timeout(5)
                // UNE seule tentative : ouvrir n'est pas idempotent. Un retry
                // relancerait xdg-open → 2-3 activations D-Bus rapprochées de la
                // même appli (Evince), course qui peut n'ouvrir AUCUNE fenêtre.
                ->retry(1)
                ->withHeaders(['X-Filename' => $filename])
                ->post('/transfer/open')
                ->throw()
                ->json();
        } catch (ConnectionException $e) {
            throw new BridgeUnavailableException(
                "Bridge Python injoignable sur {$this->baseUrl()}. Est-il démarré ?",
                previous: $e,
            );
        } catch (RequestException $e) {
            throw new BridgeUnavailableException(
                "Le PC n'a pas pu ouvrir le fichier ({$e->response->status()}).",
                previous: $e,
            );
        }
    }

    /**
     * Écrit un texte dans le presse-papier du PC (S5).
     *
     * @throws BridgeUnavailableException
     */
    public function writeClipboard(string $text): array
    {
        return $this->safePost('/clipboard/write', ['text' => $text]);
    }

    /**
     * Lit le presse-papier courant du PC (S5).
     *
     * @throws BridgeUnavailableException
     */
    public function readClipboard(): array
    {
        return $this->safeGet('/clipboard/read');
    }

    /**
     * Ouvre un lien (http/https) dans le navigateur par défaut du PC (S5).
     *
     * @throws BridgeUnavailableException
     */
    public function openLink(string $url): array
    {
        return $this->safePost('/link/open', ['url' => $url]);
    }

    /**
     * Dev Preview (S14) — serveurs de dev qui écoutent sur le PC.
     *
     * @throws BridgeUnavailableException
     */
    public function previewPorts(): array
    {
        return $this->safeGet('/preview/ports');
    }

    /**
     * Dev Preview — projets actuellement exposés au LAN (+ hosts/scheme).
     *
     * @throws BridgeUnavailableException
     */
    public function exposedPreviews(): array
    {
        return $this->safeGet('/preview/exposed');
    }

    /**
     * Dev Preview — ouvre un proxy HTTPS vers `127.0.0.1:<port>`.
     *
     * @throws BridgeUnavailableException si rien n'écoute derrière le port (404)
     */
    public function exposePreview(int $port): array
    {
        return $this->safePost('/preview/expose', ['port' => $port]);
    }

    /**
     * Dev Preview — ferme le proxy d'un projet.
     *
     * @throws BridgeUnavailableException
     */
    public function unexposePreview(int $port): array
    {
        return $this->safePost('/preview/unexpose', ['port' => $port]);
    }

    /**
     * Dev Preview — certificat PUBLIC de la CA Linkup (PEM brut), à relayer au
     * tél pour qu'il l'installe. Pas de `->json()` : c'est du texte, pas du JSON.
     *
     * @throws BridgeUnavailableException
     */
    public function previewCaCertificate(): string
    {
        try {
            return $this->request()->get('/preview/ca.crt')->throw()->body();
        } catch (ConnectionException $e) {
            throw new BridgeUnavailableException(
                "Bridge Python injoignable sur {$this->baseUrl()}. Est-il démarré ?",
                previous: $e,
            );
        } catch (RequestException $e) {
            throw $this->bridgeError($e, '/preview/ca.crt');
        }
    }

    private function safeGet(string $path): array
    {
        try {
            return $this->request()->get($path)->throw()->json();
        } catch (ConnectionException $e) {
            throw new BridgeUnavailableException(
                "Bridge Python injoignable sur {$this->baseUrl()}. Est-il démarré ?",
                previous: $e,
            );
        } catch (RequestException $e) {
            throw $this->bridgeError($e, $path);
        }
    }

    /**
     * @param array<string, mixed> $json
     *
     * @throws BridgeUnavailableException
     */
    private function safePost(string $path, array $json): array
    {
        try {
            return $this->request()->post($path, $json)->throw()->json();
        } catch (ConnectionException $e) {
            throw new BridgeUnavailableException(
                "Bridge Python injoignable sur {$this->baseUrl()}. Est-il démarré ?",
                previous: $e,
            );
        } catch (RequestException $e) {
            throw $this->bridgeError($e, $path);
        }
    }

    /**
     * Traduit une erreur HTTP du bridge en BridgeUnavailableException, en
     * remontant le `detail` du bridge (ex. « installe wl-clipboard ») quand il
     * est présent, plutôt qu'un code brut — message bien plus utile au tél.
     */
    private function bridgeError(RequestException $e, string $path): BridgeUnavailableException
    {
        $detail = $e->response->json('detail');
        $message = is_string($detail) && trim($detail) !== ''
            ? $detail
            : "Bridge a répondu en erreur ({$e->response->status()}) pour {$path}.";

        return new BridgeUnavailableException($message, previous: $e);
    }

    private function request(): PendingRequest
    {
        return $this->http
            ->baseUrl($this->baseUrl())
            ->acceptJson()
            ->withToken((string) config('services.linkup_bridge.token'))
            ->timeout((int) config('services.linkup_bridge.timeout_seconds', 2))
            // Le bridge peut être lent à démarrer (mDNS init + zeroconf setup).
            // 2 retries avec 100 ms de backoff évitent un 503 sur un boot léger
            // sans masquer un vrai down.
            ->retry(2, 100, throw: false);
    }

    private function baseUrl(): string
    {
        return rtrim((string) config('services.linkup_bridge.base_url'), '/');
    }
}
