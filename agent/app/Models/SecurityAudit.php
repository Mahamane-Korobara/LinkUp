<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * Entrée du journal d'audit sécurité (S3.J3).
 *
 * @property string $id
 * @property string|null $device_id
 * @property string $event
 * @property array|null $payload
 * @property string|null $ip
 * @property \Illuminate\Support\Carbon $created_at
 */
class SecurityAudit extends Model
{
    use HasUuids;

    protected $table = 'security_audit';

    /** Pas de updated_at : une entrée d'audit est immuable. */
    public const UPDATED_AT = null;

    protected $fillable = [
        'device_id',
        'event',
        'payload',
        'ip',
    ];

    protected $casts = [
        'payload' => 'array',
        'created_at' => 'datetime',
    ];
}
