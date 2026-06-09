import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Carte « Stripe/Notion » : surface blanche, coins doux, **ombre diffuse**
/// (au lieu d'une bordure 1px sèche) + une hairline à peine visible. Gère le tap
/// avec un ripple propre clippé aux coins.
///
/// Remplace progressivement les `Card()` Material plats du projet pour un rendu
/// plus premium et aéré.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final double radius;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.onTap,
    this.radius = 18,
  });

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: shape,
        border: Border.all(color: AppColors.hairline),
        boxShadow: AppColors.cardShadow,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: shape,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}
