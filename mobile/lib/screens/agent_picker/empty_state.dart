import 'package:flutter/material.dart';

/// Empty state du picker : affiche un loader « Recherche en cours… » pendant
/// l'auto-scan, sinon le hint « Aucun agent détecté » avec le bouton manuel.
class EmptyState extends StatelessWidget {
  final bool scanning;
  final VoidCallback onRetry;

  const EmptyState({
    super.key,
    required this.scanning,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            scanning
                ? const SizedBox(
                    width: 64,
                    height: 64,
                    child: CircularProgressIndicator(strokeWidth: 4),
                  )
                : Icon(Icons.search_off, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              scanning ? 'Recherche en cours…' : 'Aucun agent détecté',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              scanning
                  ? 'On scanne le Wi-Fi pour trouver ton PC.\nCa peut prendre quelques secondes.'
                  : 'Vérifie que ton PC est sur le même Wi-Fi et que Linkup tourne.\n'
                      'Si le multicast est bloqué, utilise « Saisie manuelle ».',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: scanning ? null : onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Rescanner'),
            ),
          ],
        ),
      ),
    );
  }
}
