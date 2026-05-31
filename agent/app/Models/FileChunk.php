<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * S4.J2 — un chunk validé d'un transfert (pour la reprise).
 *
 * @property string $id
 * @property string $transfer_id
 * @property int $chunk_index
 * @property string $sha256
 * @property \Illuminate\Support\Carbon $received_at
 */
class FileChunk extends Model
{
    use HasUuids;

    public const UPDATED_AT = null;
    public const CREATED_AT = null;

    protected $fillable = [
        'transfer_id',
        'chunk_index',
        'sha256',
        'received_at',
    ];

    protected $casts = [
        'chunk_index' => 'integer',
        'received_at' => 'datetime',
    ];

    public function transfer(): BelongsTo
    {
        return $this->belongsTo(Transfer::class);
    }
}
