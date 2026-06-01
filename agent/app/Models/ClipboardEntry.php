<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * S5 — une entrée du presse-papier synchronisé (table `clipboard_log`).
 *
 * @property string $id
 * @property string|null $device_id
 * @property string $content
 * @property string $hash         sha256 du contenu
 * @property string $origin       phone | pc
 * @property \Illuminate\Support\Carbon $created_at
 */
class ClipboardEntry extends Model
{
    use HasUuids;

    protected $table = 'clipboard_log';

    /** Un item de presse-papier est immuable : pas de updated_at. */
    public const UPDATED_AT = null;

    protected $fillable = [
        'device_id',
        'content',
        'hash',
        'origin',
    ];

    protected $casts = [
        'created_at' => 'datetime',
    ];
}
