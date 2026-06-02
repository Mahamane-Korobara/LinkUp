# Fichiers d'installation — hébergés sur le VPS

Les deux installeurs sont servis en **téléchargement direct** (un clic, sans
détour par GitHub) depuis le **VPS sahelstack.tech**, pas par Vercel — les
fichiers sont trop lourds pour un static host et changent à chaque release.

Liens (définis dans `src/lib/site.js`) :

| URL | Pour | Source locale |
|---|---|---|
| `https://linkup.sahelstack.tech/dl/linkup.apk` | Téléphone (Android) | `mobile/build/app/outputs/flutter-apk/app-release.apk` |
| `https://linkup.sahelstack.tech/dl/linkup-pc.tar.gz` | Ordinateur (Linux) | `dist/linkup-linux.tar.gz` |

## Publier / mettre à jour une version

```bash
# 1. (re)builder l'APK release + le bundle PC, puis pousser sur le VPS :
rsync -az --partial mobile/build/app/outputs/flutter-apk/app-release.apk \
  root@72.61.194.76:/var/www/linkup-dl/linkup.apk
rsync -az --partial dist/linkup-linux.tar.gz \
  root@72.61.194.76:/var/www/linkup-dl/linkup-pc.tar.gz
ssh root@72.61.194.76 'chown www-data:www-data /var/www/linkup-dl/*'
```

## Config Apache (VPS)

Servi par le vhost `linkup.sahelstack.tech` (`/etc/apache2/sites-available/linkup-le-ssl.conf`) :
`Alias /dl /var/www/linkup-dl`, exclu du proxy tunnel via `ProxyPass /dl !`,
avec `Content-Disposition: attachment` (force le téléchargement) et CORS ouvert.

> Ce dossier `public/downloads/` ne contient donc **aucun binaire** : tout passe
> par le VPS.
