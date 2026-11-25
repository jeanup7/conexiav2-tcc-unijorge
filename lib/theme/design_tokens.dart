import 'package:flutter/material.dart';

abstract final class ConexiaColors {
  static const brand = Color(0xFF236754);
  static const ink = Color(0xFF162E2A);
  static const muted = Color(0xFF596860);
  static const canvas = Color(0xFFF8F6EF);
  static const line = Color(0xFFDADFD2);
  static const lavender = Color(0xFFEDF0DC);
  static const mint = Color(0xFFE7F5EF);
  static const green = Color(0xFF206B56);
  static const danger = Color(0xFFB83C55);
  static const hero = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFEDF0DC), Color(0xFFF8F6EF), Color(0xFFE8F5F0)],
  );
  static const shadow = [
    BoxShadow(color: Color(0x091C2940), blurRadius: 24, offset: Offset(0, 8)),
  ];
}

abstract final class ConexiaMotion {
  static Duration duration(BuildContext context, [int milliseconds = 200]) =>
      MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : Duration(milliseconds: milliseconds);
}

class ConexiaPalette {
  ConexiaPalette.of(BuildContext context)
    : scheme = Theme.of(context).colorScheme;
  final ColorScheme scheme;
  Color get background => scheme.surface;
  Color get surface => scheme.surfaceContainer;
  Color get text => scheme.onSurface;
  Color get muted => scheme.onSurfaceVariant;
  Color get primary => scheme.primary;
  Color get line => scheme.outlineVariant;
  Color get tinted => scheme.primaryContainer;
  Color get positive => scheme.tertiary;
  Color get positiveSurface => scheme.tertiaryContainer;
  Color get danger => scheme.error;
  Gradient get hero =>
      LinearGradient(colors: [scheme.primaryContainer, scheme.surface]);
}
