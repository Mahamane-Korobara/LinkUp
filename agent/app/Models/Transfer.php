<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * S4.J2 — un transfert de fichier orchestré côté Laravel.
 *
 * @property string $id
 * @property string $device_id
 * @property string $filename
 * @property int $size
 * @property string|null $sha256
 * @property string $direction
 * @property string $status
 * @property int|null $total_chunks
 * @property \Illuminate\Support\Carbon|null $completed_at
 */
class Transfer extends Model
{
    use HasUuids;

    // Directions
    public const TO_PC = 'to_pc';
    public const TO_PHONE = 'to_phone';

    // Statuts
    public const PENDING = 'pending';
    public const UPLOADING = 'uploading';
    public const COMPLETED = 'completed';
    public const FAILED = 'failed';
    public const CANCELLED = 'cancelled';

    protected $fillable = [
        'device_id',
        'filename',
        'stored_name',
        'size',
        'sha256',
        'direction',
        'status',
        'total_chunks',
        'completed_at',
    ];

    protected $casts = [
        'size' => 'integer',
        'total_chunks' => 'integer',
        'completed_at' => 'datetime',
    ];

    public function device(): BelongsTo
    {
        return $this->belongsTo(Device::class);
    }

    public function isTerminal(): bool
    {
        return in_array($this->status, [self::COMPLETED, self::FAILED, self::CANCELLED], true);
    }
}
