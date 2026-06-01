<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * S6.J4 — demande d'import d'un original, déclenchée depuis le dashboard et
 * honorée par le tél (qui uploade via le module transfert S4).
 *
 * @property string $id
 * @property string $device_id
 * @property string $gallery_item_id
 * @property string $media_id
 * @property string $status
 * @property string|null $transfer_id
 */
class GalleryImportRequest extends Model
{
    use HasUuids;

    public const REQUESTED = 'requested';
    public const DONE = 'done';
    public const FAILED = 'failed';

    protected $fillable = [
        'device_id',
        'gallery_item_id',
        'media_id',
        'status',
        'transfer_id',
    ];

    public function item(): BelongsTo
    {
        return $this->belongsTo(GalleryItem::class, 'gallery_item_id');
    }

    public function device(): BelongsTo
    {
        return $this->belongsTo(Device::class);
    }
}
