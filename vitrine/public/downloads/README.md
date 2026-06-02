# Fichiers d'installation (téléchargement direct)

La vitrine sert ces deux fichiers en **téléchargement direct** (un clic, sans
détour par GitHub), via les liens définis dans `src/lib/site.js` :

| Fichier | Pour | Source |
|---|---|---|
| `linkup.apk` | Téléphone (Android) | `mobile/build/app/outputs/flutter-apk/app-release.apk` |
| `linkup-pc.tar.gz` | Ordinateur (Linux) | `dist/linkup-linux.tar.gz` |

Ils sont **hors git** (trop lourds : 65 Mo + 141 Mo). Pour les régénérer :

```bash
# depuis la racine du repo
cp mobile/build/app/outputs/flutter-apk/app-release.apk vitrine/public/downloads/linkup.apk
cp dist/linkup-linux.tar.gz                              vitrine/public/downloads/linkup-pc.tar.gz
```

## Déploiement

Vercel déploie le contenu de `public/`. Comme ces binaires sont gitignorés, il
faut soit :
- les copier avant un déploiement CLI (`vercel deploy`), soit
- les héberger sur le VPS sahelstack.tech et pointer `src/lib/site.js` dessus
  (recommandé si le bundle de 141 Mo dépasse les limites de fichier Vercel).
