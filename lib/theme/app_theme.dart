import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'design_tokens.dart';

ThemeData conexiaTheme({Brightness brightness = Brightness.light}) {
  final dark = brightness == Brightness.dark;
  GoogleFonts.config.allowRuntimeFetching = false;
  final scheme = ColorScheme.fromSeed(
    seedColor: ConexiaColors.brand,
    brightness: brightness,
    primary: dark ? const Color(0xFFA6D9C3) : ConexiaColors.brand,
    onPrimary: dark ? const Color(0xFF12382B) : Colors.white,
    surface: dark ? const Color(0xFF111916) : ConexiaColors.canvas,
    onSurface: dark ? const Color(0xFFE5EFE9) : ConexiaColors.ink,
    surfaceContainer: dark ? const Color(0xFF1B2620) : Colors.white,
    primaryContainer: dark ? const Color(0xFF293D32) : ConexiaColors.lavender,
    onPrimaryContainer: dark ? const Color(0xFFD5E9DB) : ConexiaColors.ink,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: brightness,
  );
  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    splashFactory: InkSparkle.splashFactory,
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      thickness: 1,
      space: 1,
    ),
    iconTheme: IconThemeData(color: scheme.onSurface, size: 22),
    pageTransitionsTheme: PageTransitionsTheme(
      builders: {
        ...PageTransitionsTheme().builders,
        TargetPlatform.android: const _ConexiaTransitions(),
        TargetPlatform.windows: const _ConexiaTransitions(),
        TargetPlatform.linux: const _ConexiaTransitions(),
      },
    ),
    listTileTheme: ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      iconColor: scheme.primary,
      minVerticalPadding: 12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.primary,
      strokeWidth: 2.5,
    ),
    appBarTheme: AppBarTheme(
      centerTitle: true,
      backgroundColor: scheme.surfaceContainer,
      toolbarHeight: 64,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    inputDecorationTheme: InputDecorationTheme(
      labelStyle: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14),
      hintStyle: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14),
      prefixIconColor: scheme.onSurfaceVariant,
      suffixIconColor: scheme.onSurfaceVariant,
      filled: true,
      fillColor: scheme.surfaceContainer,
      contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: scheme.primary, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: scheme.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: scheme.error, width: 1.6),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainer,
      elevation: 1,
      shadowColor: Color(0x101C2940),
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        textStyle: GoogleFonts.lato(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          letterSpacing: .15,
        ),
        padding: EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        elevation: 0,
        animationDuration: Duration(milliseconds: 160),
        minimumSize: Size(48, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: Size(48, 50),
        foregroundColor: scheme.onSurface,
        side: BorderSide(color: scheme.outlineVariant),
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        textStyle: GoogleFonts.lato(fontSize: 14, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: Size(48, 44),
        foregroundColor: scheme.primary,
        textStyle: GoogleFonts.lato(fontSize: 13, fontWeight: FontWeight.w700),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      elevation: 0,
      hoverElevation: 1,
      focusElevation: 1,
      highlightElevation: 0,
      shape: const CircleBorder(),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 76,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      backgroundColor: scheme.surfaceContainer,
      indicatorColor: scheme.primary.withValues(alpha: .10),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => GoogleFonts.lato(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w400,
          color: states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.onSurfaceVariant,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 23,
          color: states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.onSurfaceVariant,
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.onSurface,
      contentTextStyle: TextStyle(
        fontSize: 14,
        color: scheme.surface,
        height: 1.45,
      ),
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    textTheme: GoogleFonts.latoTextTheme(base.textTheme).copyWith(
      bodyLarge: GoogleFonts.lato(
        fontSize: 16,
        height: 1.5,
        color: scheme.onSurface,
      ),
      bodyMedium: GoogleFonts.lato(
        fontSize: 14,
        height: 1.5,
        color: scheme.onSurface,
      ),
      bodySmall: GoogleFonts.lato(
        fontSize: 12,
        height: 1.5,
        color: scheme.onSurfaceVariant,
      ),
      headlineSmall: GoogleFonts.lato(
        fontSize: 24,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: -.65,
        color: scheme.onSurface,
      ),
      titleMedium: GoogleFonts.lato(
        fontSize: 16,
        height: 1.3,
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
      headlineMedium: GoogleFonts.lato(
        fontSize: 28,
        fontWeight: FontWeight.w900,
        color: scheme.onSurface,
      ),
      titleLarge: GoogleFonts.lato(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
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
        position: eased.drive(Tween(begin: Offset(.035, 0), end: Offset.zero)),
        child: child,
      ),
    );
  }
}
