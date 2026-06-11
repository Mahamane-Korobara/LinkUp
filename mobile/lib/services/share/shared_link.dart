/// Extrait la première URL http(s) d'un texte partagé.
///
/// Quand on partage un lien depuis TikTok / YouTube / Insta, le texte reçu est
/// soit l'URL seule, soit une phrase qui la contient (« Regarde ça https://… »).
/// On isole le lien pour le passer au téléchargeur. Renvoie `null` si aucun lien.
String? firstHttpUrl(String text) {
  final match = RegExp(r'https?://[^\s]+').firstMatch(text);
  return match?.group(0)?.trim();
}
