import 'package:flutter/material.dart';

/// Palette de marque Linkup — alignée sur la vitrine et le dashboard web
/// (base neutre zinc + accent violet). Centralisée ici pour éviter les
/// `Colors.deepPurple`/`Colors.grey` éparpillés.
abstract final class AppColors {
  // Accent (violet)
  static const brand = Color(0xFF7C3AED); // violet-600
  static const brandDark = Color(0xFF6D28D9); // violet-700
  static const brandSoft = Color(0xFFF3F0FF); // violet-50/100
  static const brandSoftBorder = Color(0xFFE5DEFF);

  // Neutres (zinc)
  static const ink = Color(0xFF18181B); // zinc-900 — texte fort
  static const body = Color(0xFF3F3F46); // zinc-700 — texte courant
  static const muted = Color(0xFF71717A); // zinc-500 — texte secondaire
  static const faint = Color(0xFFA1A1AA); // zinc-400
  static const line = Color(0xFFE4E4E7); // zinc-200 — bordures visibles (champs)
  static const hairline = Color(0xFFF0F0F2); // bordure quasi invisible des cartes
  static const surface = Color(0xFFFFFFFF);
  static const bg = Color(0xFFF7F7F8); // fond d'écran (off-white doux, type Notion)

  // Ombre douce « Stripe/Notion » : une couche serrée + une couche large et
  // diffuse, teinte ardoise (pas du noir pur) → profondeur sans lourdeur.
  static const cardShadow = <BoxShadow>[
    BoxShadow(color: Color(0x0D1A2433), blurRadius: 2, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x141A2433), blurRadius: 16, offset: Offset(0, 8)),
  ];

  // États
  static const success = Color(0xFF059669); // emerald-600
  static const successSoft = Color(0xFFD1FAE5);
  static const warn = Color(0xFFD97706); // amber-600
  static const warnSoft = Color(0xFFFEF3C7);
  static const danger = Color(0xFFDC2626); // red-600
  static const dangerSoft = Color(0xFFFEE2E2);
}
