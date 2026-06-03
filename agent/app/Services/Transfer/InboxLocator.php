<?php

namespace App\Services\Transfer;

/**
 * Localise un fichier reçu (tél→PC) sous l'inbox, de façon sûre.
 *
 * Depuis S6.6 le bridge range les fichiers finalisés par catégorie
 * (`photos/`, `video/`, `fichiers/`) et renvoie un chemin RELATIF que Laravel
 * stocke comme `stored_name`. Ce localisateur re-résout ce chemin, en cherchant
 * dans plusieurs racines (la nouvelle `Transfert/`, puis l'ancienne `Inbox/`
 * plate — pour que les fichiers reçus AVANT la migration restent ouvrables).
 *
 * Pour chaque racine :
 *   1. essai du chemin relatif tel quel (sous-dossier inclus) ;
 *   2. fallback par basename à la racine + dans chaque catégorie.
 *
 * Anti-traversal : tout chemin résolu HORS de la racine (via `../`) est rejeté.
 */
class InboxLocator
{
    private const CATEGORIES = ['photos', 'video', 'fichiers'];

    /** @var string[] */
    private readonly array $roots;

    /** @param string|string[] $roots une ou plusieurs racines d'inbox à fouiller */
    public function __construct(string|array $roots)
    {
        $this->roots = array_values(array_filter(
            is_array($roots) ? $roots : [$roots],
            static fn ($r) => is_string($r) && $r !== '',
        ));
    }

    /** Construit le locator depuis la config (inbox courante + legacy). */
    public static function fromConfig(): self
    {
        return new self([
            (string) config('services.linkup.inbox'),
            (string) config('services.linkup.inbox_legacy'),
        ]);
    }

    /** Chemin absolu réel du fichier, ou null si introuvable/hors inbox. */
    public function locate(?string $storedName): ?string
    {
        $name = trim((string) $storedName);
        if ($name === '') {
            return null;
        }

        foreach ($this->roots as $root) {
            $base = realpath($root);
            if ($base === false) {
                continue;
            }

            // 1) chemin relatif fourni (ex. « photos/IMG.jpg »).
            $hit = $this->within($base, $base.DIRECTORY_SEPARATOR.ltrim($name, '/\\'));
            if ($hit !== null) {
                return $hit;
            }

            // 2) fallback : basename à la racine puis dans chaque catégorie.
            $basename = basename($name);
            foreach (array_merge([''], self::CATEGORIES) as $sub) {
                $prefix = $sub === '' ? '' : $sub.DIRECTORY_SEPARATOR;
                $hit = $this->within($base, $base.DIRECTORY_SEPARATOR.$prefix.$basename);
                if ($hit !== null) {
                    return $hit;
                }
            }
        }

        return null;
    }

    /** Valide qu'un chemin résolu reste STRICTEMENT dans la racine et est un fichier. */
    private function within(string $base, string $path): ?string
    {
        $real = realpath($path);

        return ($real !== false
            && str_starts_with($real, $base.DIRECTORY_SEPARATOR)
            && is_file($real)) ? $real : null;
    }
}
