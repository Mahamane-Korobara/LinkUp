<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * S6 — un média (photo/vidéo) indexé depuis la galerie d'un téléphone.
 *
 * Ne contient QUE des métadonnées + le flag `has_thumb` ; l'original reste sur
 * le tél jusqu'à un import explicite (qui passe par le module transfert S4).
 *
 * @property string $id
 * @property string $device_id
 * @property string $media_id   identifiant MediaStore côté tél
 * @property string $mime
 * @property int $size
 * @property \Illuminate\Support\Carbon|null $taken_at
 * @property int|null $width
 * @property int|null $height
 * @property bool $has_thumb
 */
class GalleryItem extends Model
{
    use HasUuids;

    protected $fillable = [
        'device_id',
        'media_id',
        'mime',
        'size',
        'taken_at',
        'width',
        'height',
        'has_thumb',
    ];

    protected $casts = [
        'size' => 'integer',
        'taken_at' => 'datetime',
        'width' => 'integer',
        'height' => 'integer',
        'has_thumb' => 'boolean',
    ];

    public function device(): BelongsTo
    {
        return $this->belongsTo(Device::class);
    }

    public function isVideo(): bool
    {
        return str_starts_with($this->mime, 'video/');
    }
}
