import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Intitulé de section discret (petites capitales douces) — aligné sur le rendu
/// « Stripe/Notion ». Remplace les gros titres pour aérer et structurer un écran
/// sans le surcharger. Utilisé en tête de chaque groupe de cartes.
class SectionLabel extends StatelessWidget {
  final String text;

  const SectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.4,
        color: AppColors.faint,
      ),
    );
  }
}
