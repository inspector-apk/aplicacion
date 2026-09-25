import 'package:flutter/material.dart';

/// Paleta de colores de Inspector con los colores corporativos de
/// Servialco: azul (#0070C0) y verde (#70C050), sobre fondo oscuro.
class AppColors {
  AppColors._();

  static const Color background = Color(0xFF000000);
  static const Color surface = Color(0xFF121212);
  static const Color surfaceVariant = Color(0xFF1C1C1E);
  static const Color border = Color(0xFF2E2E30);

  /// Azul corporativo: botones, bordes, rellenos y selecciones.
  static const Color accent = Color(0xFF0070C0);
  static const Color accentDim = Color(0xFF00589A);

  /// Versión más clara del azul corporativo para texto e íconos pequeños
  /// sobre fondo oscuro (el azul exacto no alcanza buen contraste ahí).
  static const Color accentText = Color(0xFF4DA6E8);

  /// Color del texto/ícono que va encima de un relleno `accent`.
  static const Color onAccent = Color(0xFFFFFFFF);

  /// Verde corporativo.
  static const Color secondary = Color(0xFF70C050);

  static const Color textPrimary = Color(0xFFF5F5F5);
  static const Color textSecondary = Color(0xFFA0A0A3);
  static const Color textMuted = Color(0xFF6E6E72);

  static const Color success = secondary;
  static const Color error = Color(0xFFFF5C5C);
}
