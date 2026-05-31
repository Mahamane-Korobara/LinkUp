<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Token persistant d'un device approuvé (S2.J4 T2.19).
 *
 * @property string $id
 * @property string $device_id
 * @property string $token_hash  argon2id
 * @property \Illuminate\Support\Carbon|null $last_used_at
 */
class DeviceToken extends Model
{
    use HasUuids;

    protected $fillable = [
        'device_id',
        'token_hash',
        'last_used_at',
    ];

    protected $casts = [
        'last_used_at' => 'datetime',
    ];

    public function device(): BelongsTo
    {
        return $this->belongsTo(Device::class);
    }
}
