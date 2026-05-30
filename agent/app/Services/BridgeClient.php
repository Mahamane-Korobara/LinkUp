<?php

namespace App\Services;

use Illuminate\Http\Client\ConnectionException;
use Illuminate\Http\Client\Factory as HttpFactory;
use Illuminate\Http\Client\PendingRequest;
use Illuminate\Http\Client\RequestException;
use RuntimeException;

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
            throw new BridgeUnavailableException(
                "Bridge a répondu en erreur ({$e->response->status()}) pour {$path}.",
                previous: $e,
            );
        }
    }

    private function request(): PendingRequest
    {
        return $this->http
            ->baseUrl($this->baseUrl())
            ->acceptJson()
            ->withToken((string) config('services.linkup_bridge.token'))
            ->timeout((int) config('services.linkup_bridge.timeout_seconds', 2));
    }

    private function baseUrl(): string
    {
        return rtrim((string) config('services.linkup_bridge.base_url'), '/');
    }
}

/**
 * Levée quand le bridge Python ne répond pas. Les controllers/routes la
 * traduisent en HTTP 503 (Service Unavailable) au lieu d'une stacktrace.
 */
class BridgeUnavailableException extends RuntimeException
{
}
