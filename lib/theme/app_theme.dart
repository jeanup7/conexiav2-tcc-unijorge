import 'package:flutter/material.dart';

ThemeData conexiaTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF4965E8), secondary: const Color(0xFF237B68), surface: const Color(0xFFF7F8FC));
  return ThemeData(useMaterial3: true, colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: const AppBarTheme(centerTitle: false, backgroundColor: Color(0xFFF7F8FC), surfaceTintColor: Colors.transparent),
    inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16))),
    cardTheme: CardThemeData(color: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Color(0xFFE4E8F3)))),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(minimumSize: const Size(48, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)))),
    textTheme: const TextTheme(headlineMedium: TextStyle(fontWeight: FontWeight.w800), titleLarge: TextStyle(fontWeight: FontWeight.w700)));
}
