import 'package:flutter/material.dart';
import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:google_fonts/google_fonts.dart';

import 'design_tokens.dart';

ThemeData conexiaTheme() {
  GoogleFonts.config.allowRuntimeFetching = false;
  final scheme = ColorScheme.fromSeed(
    seedColor: ConexiaColors.brand,
    primary: ConexiaColors.brand,
    onPrimary: Colors.white,
    primaryContainer: ConexiaColors.lavender,
    onPrimaryContainer: ConexiaColors.ink,
    secondary: ConexiaColors.green,
    onSecondary: Colors.white,
    secondaryContainer: ConexiaColors.mint,
    onSecondaryContainer: ConexiaColors.green,
    error: ConexiaColors.danger,
    surface: ConexiaColors.canvas,
  );
  final base = FlexThemeData.light(
    useMaterial3: true,
    colorScheme: scheme,
    subThemesData: const FlexSubThemesData(
      defaultRadius: 16,
      inputDecoratorIsFilled: true,
      navigationBarHeight: 72,
    ),
  );
  return base.copyWith(
    scaffoldBackgroundColor: ConexiaColors.canvas,
    splashFactory: InkSparkle.splashFactory,
    dividerTheme: const DividerThemeData(
      color: ConexiaColors.line,
      thickness: 1,
      space: 1,
    ),
    iconTheme: const IconThemeData(color: ConexiaColors.ink, size: 22),
    pageTransitionsTheme: PageTransitionsTheme(
      builders: {
        ...const PageTransitionsTheme().builders,
        TargetPlatform.android: const _ConexiaTransitions(),
        TargetPlatform.windows: const _ConexiaTransitions(),
        TargetPlatform.linux: const _ConexiaTransitions(),
      },
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      iconColor: ConexiaColors.brand,
      minVerticalPadding: 12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: ConexiaColors.brand,
      strokeWidth: 2.5,
    ),
    appBarTheme: const AppBarTheme(
      centerTitle: true,
      backgroundColor: Colors.white,
      toolbarHeight: 64,
      foregroundColor: ConexiaColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    inputDecorationTheme: InputDecorationTheme(
      labelStyle: const TextStyle(color: ConexiaColors.muted, fontSize: 14),
      hintStyle: const TextStyle(color: ConexiaColors.muted, fontSize: 14),
      prefixIconColor: ConexiaColors.muted,
      suffixIconColor: ConexiaColors.muted,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: ConexiaColors.brand, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: ConexiaColors.danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: ConexiaColors.danger, width: 1.6),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFE4E8F3)),
      ),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 1,
      shadowColor: const Color(0x101C2940),
      surfaceTintColor: Colors.transparent,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: Color(0xFFE4E8F3)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: ConexiaColors.brand,
        foregroundColor: Colors.white,
        textStyle: GoogleFonts.lato(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          letterSpacing: .15,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        elevation: 0,
        animationDuration: const Duration(milliseconds: 160),
        minimumSize: const Size(48, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 50),
        foregroundColor: ConexiaColors.ink,
        side: const BorderSide(color: ConexiaColors.line),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        textStyle: GoogleFonts.lato(fontSize: 14, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 44),
        foregroundColor: ConexiaColors.brand,
        textStyle: GoogleFonts.lato(fontSize: 13, fontWeight: FontWeight.w700),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 76,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      backgroundColor: Colors.white,
      indicatorColor: scheme.primary.withValues(alpha: .10),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => GoogleFonts.lato(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w400,
          color: states.contains(WidgetState.selected)
              ? scheme.primary
              : ConexiaColors.muted,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 23,
          color: states.contains(WidgetState.selected)
              ? scheme.primary
              : ConexiaColors.muted,
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: ConexiaColors.ink,
      contentTextStyle: const TextStyle(
        fontSize: 14,
        color: Colors.white,
        height: 1.45,
      ),
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    textTheme: GoogleFonts.latoTextTheme(base.textTheme).copyWith(
      bodyLarge: GoogleFonts.lato(
        fontSize: 16,
        height: 1.5,
        color: ConexiaColors.ink,
      ),
      bodyMedium: GoogleFonts.lato(
        fontSize: 14,
        height: 1.5,
        color: ConexiaColors.ink,
      ),
      bodySmall: GoogleFonts.lato(
        fontSize: 12,
        height: 1.5,
        color: ConexiaColors.muted,
      ),
      headlineSmall: GoogleFonts.lato(
        fontSize: 24,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: -.65,
        color: ConexiaColors.ink,
      ),
      titleMedium: GoogleFonts.lato(
        fontSize: 16,
        height: 1.3,
        fontWeight: FontWeight.w700,
        color: ConexiaColors.ink,
      ),
      headlineMedium: GoogleFonts.lato(
        fontSize: 28,
        fontWeight: FontWeight.w900,
        color: ConexiaColors.ink,
      ),
      titleLarge: GoogleFonts.lato(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: ConexiaColors.ink,
      ),
    ),
  );
}

class _ConexiaTransitions extends PageTransitionsBuilder {
  const _ConexiaTransitions();
  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final eased = animation.drive(CurveTween(curve: Curves.easeOutCubic));
    return FadeTransition(
      opacity: eased,
      child: SlideTransition(
        position: eased.drive(
          Tween(begin: const Offset(.035, 0), end: Offset.zero),
        ),
        child: child,
      ),
    );
  }
}
