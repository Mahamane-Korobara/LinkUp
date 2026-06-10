<?php

namespace App\Http\Controllers;

use App\Http\Middleware\AuthenticateDevice;
use App\Models\Device;
use Illuminate\Http\Request;

abstract class Controller
{
    /**
     * Device authentifié par le middleware `auth.device` (X-Device-Id + Bearer),
     * exposé sur la requête. Centralisé ici pour les controllers qui en ont
     * besoin (transfert, presse-papier) plutôt que dupliqué dans chacun.
     */
    protected function device(Request $request): Device
    {
        return $request->attributes->get(AuthenticateDevice::ATTRIBUTE);
    }
}
