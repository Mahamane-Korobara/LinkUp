import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// Empty state du picker : affiche un loader « Recherche en cours… » pendant
/// l'auto-scan, sinon le hint « Aucun PC détecté » + bouton « Rescanner ».
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
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            scanning
                ? const _ScanPulse()
                : Container(
                    width: 96,
                    height: 96,
                    decoration: const BoxDecoration(
                      color: Color(0xFFF4F4F5),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.wifi_find_rounded,
                        size: 44, color: AppColors.faint),
                  ),
            const SizedBox(height: 24),
            Text(
              scanning ? 'Recherche en cours…' : 'Aucun PC détecté',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              scanning
                  ? 'On scanne le Wi-Fi pour trouver ton PC.\nÇa peut prendre quelques secondes.'
                  : 'Vérifie que ton PC est sur le même Wi-Fi et que Linkup tourne.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            OutlinedButton.icon(
              onPressed: scanning ? null : onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Rescanner'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cercle violet avec deux anneaux qui pulsent — évoque un radar de découverte.
class _ScanPulse extends StatefulWidget {
  const _ScanPulse();

  @override
  State<_ScanPulse> createState() => _ScanPulseState();
}

class _ScanPulseState extends State<_ScanPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 2))
        ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120,
      height: 120,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          return Stack(
            alignment: Alignment.center,
            children: [
              _ring(_c.value),
              _ring((_c.value + 0.5) % 1.0),
              child!,
            ],
          );
        },
        child: Container(
          width: 64,
          height: 64,
          decoration: const BoxDecoration(
            color: AppColors.brand,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.wifi_tethering_rounded,
              color: Colors.white, size: 30),
        ),
      ),
    );
  }

  Widget _ring(double t) {
    final size = 64 + t * 56;
    return Opacity(
      opacity: (1 - t) * 0.5,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.brand, width: 2),
        ),
      ),
    );
  }
}
