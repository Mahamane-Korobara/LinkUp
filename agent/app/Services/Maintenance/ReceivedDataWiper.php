<?php

namespace App\Services\Maintenance;

use App\Models\ClipboardEntry;
use App\Models\Device;
use App\Models\DeviceToken;
use App\Models\Transfer;
use App\Services\Transfer\InboxLocator;
use Illuminate\Support\Facades\DB;

/**
 * Efface TOUT ce que les téléphones ont laissé sur ce PC : fichiers reçus (sur
 * le disque), transferts, historique du presse-papier, ET les données de
 * pairing (devices + tokens + OTP). Remet l'agent à un état « usine ».
 *
 * Le geste est destructeur et irréversible : le dashboard l'entoure d'une
 * confirmation explicite + d'un délai d'annulation de 5 s AVANT d'appeler le
 * endpoint. Côté serveur la suppression est immédiate (pas de soft-delete).
 */
class ReceivedDataWiper
{
    public function __construct(private readonly InboxLocator $inbox)
    {
    }

    public static function fromConfig(): self
    {
        return new self(InboxLocator::fromConfig());
    }

    /**
     * Aperçu de ce qui sera supprimé, pour l'écran de confirmation du dashboard.
     *
     * @return array{files:int, bytes:int, clipboard:int, devices:int}
     */
    public function summary(): array
    {
        $received = fn () => Transfer::query()
            ->where('direction', Transfer::TO_PC)
            ->where('status', Transfer::COMPLETED);

        return [
            'files' => $received()->count(),
            'bytes' => (int) $received()->sum('size'),
            'clipboard' => ClipboardEntry::query()->count(),
            'devices' => Device::query()->count(),
        ];
    }

    /**
     * Supprime tout. Renvoie le compte de ce qui a été effacé (mesuré AVANT la
     * purge, pour le message de confirmation final).
     *
     * @return array{files:int, bytes:int, clipboard:int, devices:int}
     */
    public function wipe(): array
    {
        $summary = $this->summary();

        // 1) Fichiers sur le disque AVANT la purge SQL : on a encore besoin des
        //    `stored_name` pour les localiser (inbox reçus + outbox envoyés).
        $this->deleteFiles();

        // 2) Lignes SQL, dans un ordre qui ne dépend pas du cascade FK :
        //    transferts → tokens → devices → presse-papier → OTP de pairing.
        DB::transaction(function () {
            Transfer::query()->delete();
            DeviceToken::query()->delete();
            Device::query()->delete();
            ClipboardEntry::query()->delete();
            DB::table('pairing_otps')->delete();
        });

        return $summary;
    }

    /** Unlink des fichiers reçus (inbox) et envoyés (outbox) référencés en base. */
    private function deleteFiles(): void
    {
        // Reçus tél→PC : localisés par l'InboxLocator (anti-traversal intégré).
        Transfer::query()
            ->where('direction', Transfer::TO_PC)
            ->orderBy('id')
            ->each(function (Transfer $t) {
                $path = $this->inbox->locate($t->stored_name ?: $t->filename);
                if ($path !== null && is_file($path)) {
                    @unlink($path);
                }
            });

        // Envoyés PC→tél : déposés à plat dans l'outbox sous leur `stored_name`.
        $outbox = rtrim((string) config('services.linkup.outbox'), DIRECTORY_SEPARATOR);
        if ($outbox !== '') {
            Transfer::query()
                ->where('direction', Transfer::TO_PHONE)
                ->whereNotNull('stored_name')
                ->orderBy('id')
                ->each(function (Transfer $t) use ($outbox) {
                    $path = $outbox . DIRECTORY_SEPARATOR . basename((string) $t->stored_name);
                    if (is_file($path)) {
                        @unlink($path);
                    }
                });
        }
    }
}
