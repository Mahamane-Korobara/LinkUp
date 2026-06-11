import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme/app_colors.dart';

/// Page de la vitrine (front) où télécharger l'app PC (Windows/Linux).
const _vitrineUrl = 'https://linkup-landing.sahelstack.tech';

/// Empty state du picker. Pendant l'auto-scan : radar « Recherche en cours… ».
/// Sinon (aucun PC trouvé) : on EXPLIQUE qu'il faut ouvrir l'app LinkUp sur le
/// PC (même Wi-Fi) — le tél le détecte tout seul — et on propose de l'installer
/// via la vitrine. (Un PC ne peut être vu que si un service LinkUp y tourne.)
class EmptyState extends StatelessWidget {
  final bool scanning;
  final VoidCallback onRetry;

  const EmptyState({
    super.key,
    required this.scanning,
    required this.onRetry,
  });

  Future<void> _openPcDownload(BuildContext context) async {
    try {
      await launchUrl(Uri.parse(_vitrineUrl),
          mode: LaunchMode.externalApplication);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossible d\'ouvrir le lien.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (scanning) return const _Scanning();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: const BoxDecoration(
              color: Color(0xFFF4F4F5),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.wifi_find_rounded,
                size: 40, color: AppColors.faint),
          ),
          const SizedBox(height: 20),
          const Text(
            'Aucun PC détecté',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Pour échanger avec ton ordinateur, l\'app LinkUp doit y être '
            'ouverte (même Wi-Fi). Le téléphone le détecte ensuite tout seul.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 20),
          // Étapes guidées.
          const _Step(
            n: '1',
            text: 'Ouvre l\'app LinkUp sur ton PC (Windows ou Linux).',
          ),
          const SizedBox(height: 10),
          const _Step(
            n: '2',
            text: 'Reviens ici : ton PC apparaît automatiquement.',
          ),
          const SizedBox(height: 24),
          // Action principale : installer l'app PC depuis la vitrine.
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _openPcDownload(context),
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('Installer LinkUp sur PC'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.brand,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Action secondaire : relancer la découverte.
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('J\'ai ouvert l\'app PC — rescanner'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Une étape numérotée (pastille violette + texte).
class _Step extends StatelessWidget {
  final String n;
  final String text;

  const _Step({required this.n, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: AppColors.brandSoft,
            shape: BoxShape.circle,
          ),
          child: Text(
            n,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: AppColors.brand,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(
              text,
              style: const TextStyle(
                  color: AppColors.body, fontSize: 13.5, height: 1.4),
            ),
          ),
        ),
      ],
    );
  }
}

/// État « scan en cours » : radar pulsant + libellé.
class _Scanning extends StatelessWidget {
  const _Scanning();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ScanPulse(),
            SizedBox(height: 24),
            Text(
              'Recherche en cours…',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
                letterSpacing: -0.3,
              ),
            ),
            SizedBox(height: 10),
            Text(
              'On scanne le Wi-Fi pour trouver ton PC.\nÇa peut prendre quelques secondes.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, fontSize: 14, height: 1.5),
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
