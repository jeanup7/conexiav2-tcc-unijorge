import 'package:flutter/material.dart';

abstract final class ConexiaColors {
  static const brand = Color(0xFF4D5BD5);
  static const ink = Color(0xFF1C2940);
  static const muted = Color(0xFF59677C);
  static const canvas = Color(0xFFF5F7FB);
  static const line = Color(0xFFE1E7F0);
  static const lavender = Color(0xFFEEF0FF);
  static const mint = Color(0xFFE7F5EF);
  static const green = Color(0xFF206B56);
  static const danger = Color(0xFFB83C55);
  static const hero = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFE9EDFF), Color(0xFFF6F8FF), Color(0xFFE8F5F0)],
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
