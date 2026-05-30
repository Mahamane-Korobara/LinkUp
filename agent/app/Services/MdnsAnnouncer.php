<?php

namespace App\Services;

use Illuminate\Http\Client\Factory as HttpFactory;
use Illuminate\Http\Client\PendingRequest;

class MdnsAnnouncer
{
    public function __construct(
        private readonly HttpFactory $http,
    ) {
    }

    public function bridgeHealth(): array
    {
        return $this->request()
            ->get('/health')
            ->throw()
            ->json();
    }

    public function localInfo(): array
    {
        return $this->request()
            ->get('/mdns/info')
            ->throw()
            ->json();
    }

    public function discoveredServices(): array
    {
        return $this->request()
            ->get('/mdns/services')
            ->throw()
            ->json();
    }

    private function request(): PendingRequest
    {
        return $this->http
            ->baseUrl(rtrim((string) config('services.linkup_bridge.base_url'), '/'))
            ->acceptJson()
            ->withToken((string) config('services.linkup_bridge.token'))
            ->timeout((int) config('services.linkup_bridge.timeout_seconds', 2));
    }
}
