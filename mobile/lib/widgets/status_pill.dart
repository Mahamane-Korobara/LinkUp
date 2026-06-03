import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

enum PillTone { brand, success, warn, danger, neutral }

/// Petite pastille « point + libellé » colorée selon le ton — pour les statuts
/// (appairé, en attente, hors ligne…). Reprend le langage de la vitrine.
class StatusPill extends StatelessWidget {
  final String label;
  final PillTone tone;
  final IconData? icon;
  final bool pulse;

  const StatusPill({
    super.key,
    required this.label,
    this.tone = PillTone.neutral,
    this.icon,
    this.pulse = false,
  });

  ({Color fg, Color bg}) get _palette => switch (tone) {
        PillTone.brand => (fg: AppColors.brandDark, bg: AppColors.brandSoft),
        PillTone.success => (fg: AppColors.success, bg: AppColors.successSoft),
        PillTone.warn => (fg: AppColors.warn, bg: AppColors.warnSoft),
        PillTone.danger => (fg: AppColors.danger, bg: AppColors.dangerSoft),
        PillTone.neutral => (fg: AppColors.muted, bg: Color(0xFFF4F4F5)),
      };

  @override
  Widget build(BuildContext context) {
    final p = _palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: p.bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null)
            Icon(icon, size: 13, color: p.fg)
          else
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: p.fg, shape: BoxShape.circle),
            ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: p.fg,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
