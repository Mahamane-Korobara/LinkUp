<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * @property string $id          UUID
 * @property string|null $name
 * @property string|null $model       ex. Google Pixel 7
 * @property string|null $platform    Android / iOS
 * @property string|null $os_version  ex. Android 14
 * @property string $public_key  base64 Ed25519
 * @property string $fingerprint_sha256
 * @property bool $approved
 * @property \Illuminate\Support\Carbon|null $paired_at
 * @property \Illuminate\Support\Carbon|null $approved_at
 * @property \Illuminate\Support\Carbon|null $revoked_at
 */
class Device extends Model
{
    use HasUuids;

    protected $fillable = [
        'name',
        'model',
        'platform',
        'os_version',
        'public_key',
        'fingerprint_sha256',
        'approved',
        'paired_at',
        'approved_at',
        'revoked_at',
    ];

    protected $casts = [
        'approved' => 'boolean',
        'paired_at' => 'datetime',
        'approved_at' => 'datetime',
        'revoked_at' => 'datetime',
    ];

    public function isActive(): bool
    {
        return $this->approved && $this->revoked_at === null;
    }

    public function tokens(): HasMany
    {
        return $this->hasMany(DeviceToken::class);
    }

    /**
     * Statut lisible utilisé par le dashboard et la poll du tel.
     */
    public function status(): string
    {
        if ($this->revoked_at !== null) {
            return 'rejected';
        }
        return $this->approved ? 'approved' : 'pending';
    }
}
