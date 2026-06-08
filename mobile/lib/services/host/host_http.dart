import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Helpers HTTP partagés par les handlers du Mode Hôte (serveur `dart:io`).
///
/// Le téléphone hôte ré-implémente en Dart les endpoints que le client mobile
/// appelle déjà (cf. [[linkup_tel_to_tel]]). Ces utilitaires centralisent
/// l'écriture des réponses JSON et la lecture du corps pour éviter la
/// duplication entre découverte, appairage et transfert.

/// Écrit [body] en JSON avec le [status] donné et ferme la réponse.
Future<void> writeJson(HttpRequest req, Object body, {int status = 200}) async {
  final res = req.response;
  res.statusCode = status;
  res.headers.contentType = ContentType.json;
  res.write(jsonEncode(body));
  await res.close();
}

/// Réponse vide avec un simple code de statut (404, 401, 204…).
Future<void> writeStatus(HttpRequest req, int status) async {
  req.response.statusCode = status;
  await req.response.close();
}

/// Lit le corps de la requête comme un objet JSON. Renvoie une map vide si le
/// corps est vide ; throw [FormatException] si ce n'est pas un objet JSON.
Future<Map<String, dynamic>> readJsonBody(HttpRequest req) async {
  final raw = await utf8.decoder.bind(req).join();
  if (raw.isEmpty) return <String, dynamic>{};
  final decoded = jsonDecode(raw);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Corps JSON attendu (objet).');
  }
  return decoded;
}

/// Lit le corps brut de la requête (chunk binaire d'un transfert).
Future<List<int>> readRawBody(HttpRequest req) async {
  final builder = BytesBuilder(copy: false);
  await for (final chunk in req) {
    builder.add(chunk);
  }
  return builder.takeBytes();
}
