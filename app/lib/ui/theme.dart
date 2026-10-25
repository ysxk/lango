import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../app_scope.dart';

@immutable
class LangoColors extends ThemeExtension<LangoColors> {
  const LangoColors({
    required this.canvas,
    required this.surface,
    required this.raised,
    required this.sunken,
    required this.ink,
    required this.secondary,
    required this.faint,
    required this.line,
    required this.teal,
    required this.onTeal,
    required this.mint,
    required this.mintInk,
    required this.danger,
    required this.dangerWash,
    required this.warm,
    required this.isDark,
  });

  final Color canvas;
  final Color surface;
  final Color raised;
  final Color sunken;
  final Color ink;
  final Color secondary;
  final Color faint;
  final Color line;
  final Color teal;
  final Color onTeal;
  final Color mint;
  final Color mintInk;
  final Color danger;
  final Color dangerWash;
  final Color warm;
  final bool isDark;

  static const light = LangoColors(
    canvas: Color(0xFFF4F2ED),
    surface: Color(0xFFFCFBF8),
    raised: Color(0xFFFFFFFF),
    sunken: Color(0xFFECEAE4),
    ink: Color(0xFF252C29),
    secondary: Color(0xFF6F7771),
    faint: Color(0xFF969C96),
    line: Color(0xFFE5E1D9),
    teal: Color(0xFF285E52),
    onTeal: Color(0xFFF5FBF7),
    mint: Color(0xFFDCEAE2),
    mintInk: Color(0xFF245247),
    danger: Color(0xFFA44136),
    dangerWash: Color(0xFFF5E7E4),
    warm: Color(0xFFEFE7D8),
    isDark: false,
  );

  static const dark = LangoColors(
    canvas: Color(0xFF191E1B),
    surface: Color(0xFF222925),
    raised: Color(0xFF2B342E),
    sunken: Color(0xFF141815),
    ink: Color(0xFFEEEFE7),
    secondary: Color(0xFFA7B0A9),
    faint: Color(0xFF7B857E),
    line: Color(0xFF343D37),
    teal: Color(0xFFA8D1BD),
    onTeal: Color(0xFF132019),
    mint: Color(0xFF263B31),
    mintInk: Color(0xFFC3E0D0),
    danger: Color(0xFFE3A096),
    dangerWash: Color(0xFF3A2622),
    warm: Color(0xFF3A3529),
    isDark: true,
  );

  @override
  LangoColors copyWith({
    Color? canvas,
    Color? surface,
    Color? raised,
    Color? sunken,
    Color? ink,
    Color? secondary,
    Color? faint,
    Color? line,
    Color? teal,
    Color? onTeal,
    Color? mint,
    Color? mintInk,
    Color? danger,
    Color? dangerWash,
    Color? warm,
    bool? isDark,
  }) {
    return LangoColors(
      canvas: canvas ?? this.canvas,
      surface: surface ?? this.surface,
      raised: raised ?? this.raised,
      sunken: sunken ?? this.sunken,
      ink: ink ?? this.ink,
      secondary: secondary ?? this.secondary,
      faint: faint ?? this.faint,
      line: line ?? this.line,
      teal: teal ?? this.teal,
      onTeal: onTeal ?? this.onTeal,
      mint: mint ?? this.mint,
      mintInk: mintInk ?? this.mintInk,
      danger: danger ?? this.danger,
      dangerWash: dangerWash ?? this.dangerWash,
      warm: warm ?? this.warm,
      isDark: isDark ?? this.isDark,
    );
  }

  @override
  LangoColors lerp(ThemeExtension<LangoColors>? other, double t) {
    if (other is! LangoColors) return this;
    return LangoColors(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      raised: Color.lerp(raised, other.raised, t)!,
      sunken: Color.lerp(sunken, other.sunken, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      secondary: Color.lerp(secondary, other.secondary, t)!,
      faint: Color.lerp(faint, other.faint, t)!,
      line: Color.lerp(line, other.line, t)!,
      teal: Color.lerp(teal, other.teal, t)!,
      onTeal: Color.lerp(onTeal, other.onTeal, t)!,
      mint: Color.lerp(mint, other.mint, t)!,
      mintInk: Color.lerp(mintInk, other.mintInk, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerWash: Color.lerp(dangerWash, other.dangerWash, t)!,
      warm: Color.lerp(warm, other.warm, t)!,
      isDark: t < 0.5 ? isDark : other.isDark,
    );
  }
}

class LangoTheme {
  static const displayFamily = 'serif';
  static const double maxContent = 1120;

  static const _displayFallback = <String>[
    'Noto Serif CJK SC',
    'Noto Serif',
    'Songti SC',
    'Georgia',
  ];

  static TextStyle display(double size, {FontWeight? weight, double? height}) {
    return TextStyle(
      fontFamily: displayFamily,
      fontFamilyFallback: _displayFallback,
      fontSize: size,
      height: height,
      letterSpacing: size > 28 ? -0.8 : -0.2,
      fontWeight: weight ?? FontWeight.w500,
    );
  }

  static ThemeData build({required LangoColors c}) {
    final ink = c.ink;
    final base = c.isDark ? ThemeData.dark(useMaterial3: true) : ThemeData.light(useMaterial3: true);
    final bodyWeight = c.isDark ? FontWeight.w300 : FontWeight.w400;
    final mediumWeight = c.isDark ? FontWeight.w400 : FontWeight.w500;
    final strongWeight = c.isDark ? FontWeight.w500 : FontWeight.w600;

    final text = TextTheme(
      displayLarge: display(52, weight: FontWeight.w500, height: 1.04).copyWith(color: ink),
      displayMedium: display(42, weight: FontWeight.w500, height: 1.06).copyWith(color: ink),
      displaySmall: display(34, weight: FontWeight.w500, height: 1.1).copyWith(color: ink),
      headlineLarge: display(30, weight: FontWeight.w500, height: 1.16).copyWith(color: ink),
      headlineMedium: display(26, weight: FontWeight.w500, height: 1.2).copyWith(color: ink),
      headlineSmall: display(22, weight: FontWeight.w500, height: 1.24).copyWith(color: ink),
      titleLarge: TextStyle(fontSize: 20, height: 1.35, fontWeight: strongWeight, letterSpacing: -0.1, color: ink),
      titleMedium: TextStyle(fontSize: 16, height: 1.4, fontWeight: mediumWeight, color: ink),
      titleSmall: TextStyle(fontSize: 14, height: 1.4, fontWeight: strongWeight, color: ink),
      bodyLarge: TextStyle(fontSize: 16, height: 1.65, fontWeight: bodyWeight, color: ink),
      bodyMedium: TextStyle(fontSize: 14, height: 1.6, fontWeight: bodyWeight, color: ink),
      bodySmall: TextStyle(fontSize: 12.5, height: 1.55, fontWeight: bodyWeight, color: c.secondary),
      labelLarge: TextStyle(fontSize: 14, height: 1.2, fontWeight: strongWeight, letterSpacing: 0.1, color: ink),
      labelMedium: TextStyle(fontSize: 12.5, height: 1.2, fontWeight: mediumWeight, letterSpacing: 0.2, color: c.secondary),
      labelSmall: TextStyle(fontSize: 11.5, height: 1.2, fontWeight: mediumWeight, letterSpacing: 0.5, color: c.faint),
    );

    final scheme = ColorScheme(
      brightness: c.isDark ? Brightness.dark : Brightness.light,
      primary: c.teal,
      onPrimary: c.onTeal,
      primaryContainer: c.mint,
      onPrimaryContainer: c.mintInk,
      secondary: c.teal,
      onSecondary: c.onTeal,
      secondaryContainer: c.mint,
      onSecondaryContainer: c.mintInk,
      tertiary: c.warm,
      onTertiary: ink,
      error: c.danger,
      onError: c.isDark ? const Color(0xFF20100D) : const Color(0xFFFFF8F6),
      errorContainer: c.dangerWash,
      onErrorContainer: c.danger,
      surface: c.surface,
      onSurface: ink,
      onSurfaceVariant: c.secondary,
      outline: c.line,
      outlineVariant: c.line,
      shadow: const Color(0x33000000),
      scrim: const Color(0x66000000),
      inverseSurface: ink,
      onInverseSurface: c.canvas,
      inversePrimary: c.isDark ? LangoColors.light.teal : LangoColors.dark.teal,
      surfaceTint: Colors.transparent,
    );

    final rounded = RoundedRectangleBorder(borderRadius: BorderRadius.circular(999));
    final buttonLabel = TextStyle(fontSize: 14.5, height: 1.2, fontWeight: strongWeight, letterSpacing: 0.1);

    final fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide.none,
    );

    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: c.canvas,
      canvasColor: c.canvas,
      textTheme: text,
      extensions: [c],
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      dividerColor: c.line,
      focusColor: c.teal.withValues(alpha: 0.12),
      hoverColor: c.ink.withValues(alpha: 0.035),
      highlightColor: c.ink.withValues(alpha: 0.05),
      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          TargetPlatform.android: const FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: const CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: const CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: const FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.windows: const FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.fuchsia: const FadeUpwardsPageTransitionsBuilder(),
        },
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: c.teal,
        selectionColor: c.mint,
        selectionHandleColor: c.teal,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 22, vertical: 12)),
          shape: WidgetStatePropertyAll(rounded),
          elevation: const WidgetStatePropertyAll(0),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) return c.ink.withValues(alpha: 0.08);
            if (states.contains(WidgetState.pressed)) return Color.lerp(c.teal, ink, 0.16);
            if (states.contains(WidgetState.hovered)) return Color.lerp(c.teal, ink, 0.08);
            return c.teal;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) return c.faint;
            return c.onTeal;
          }),
          overlayColor: WidgetStatePropertyAll(c.onTeal.withValues(alpha: 0.08)),
          textStyle: WidgetStatePropertyAll(buttonLabel),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
          shape: WidgetStatePropertyAll(rounded),
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.focused)) return BorderSide(color: c.teal.withValues(alpha: 0.55));
            return BorderSide(color: c.line);
          }),
          foregroundColor: WidgetStatePropertyAll(ink),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.hovered)) return c.raised;
            return Colors.transparent;
          }),
          overlayColor: WidgetStatePropertyAll(c.ink.withValues(alpha: 0.03)),
          textStyle: WidgetStatePropertyAll(buttonLabel),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(0, 40)),
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 14, vertical: 8)),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          foregroundColor: WidgetStatePropertyAll(c.teal),
          overlayColor: WidgetStatePropertyAll(c.teal.withValues(alpha: 0.07)),
          textStyle: WidgetStatePropertyAll(buttonLabel.copyWith(fontSize: 13.5)),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(44, 44)),
          foregroundColor: WidgetStatePropertyAll(c.secondary),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
          overlayColor: WidgetStatePropertyAll(c.ink.withValues(alpha: 0.05)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: false,
        border: fieldBorder,
        enabledBorder: fieldBorder,
        focusedBorder: fieldBorder,
        errorBorder: fieldBorder,
        focusedErrorBorder: fieldBorder,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        hintStyle: TextStyle(color: c.faint, fontSize: 14.5, fontWeight: bodyWeight),
        errorStyle: TextStyle(color: c.danger, fontSize: 12.5, height: 1.4),
        isDense: true,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: c.teal,
        inactiveTrackColor: c.line,
        thumbColor: c.teal,
        overlayColor: c.teal.withValues(alpha: 0.08),
        trackHeight: 3,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
        valueIndicatorColor: c.ink,
        valueIndicatorTextStyle: TextStyle(color: c.canvas, fontWeight: strongWeight, fontSize: 12),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.onTeal : c.surface),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.teal : c.sunken),
        trackOutlineColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.transparent : c.line),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.isDark ? c.raised : c.ink,
        contentTextStyle: TextStyle(color: c.isDark ? c.ink : c.canvas, fontSize: 14, height: 1.4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        insetPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        elevation: 0,
        actionTextColor: c.isDark ? c.teal : LangoColors.dark.teal,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: text.headlineSmall,
        contentTextStyle: text.bodyMedium?.copyWith(color: c.secondary),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        modalBarrierColor: c.isDark ? const Color(0x99000000) : const Color(0x33252C29),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        showDragHandle: true,
        dragHandleColor: c.line,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: c.mint,
        height: 68,
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11.5,
            fontWeight: selected ? strongWeight : bodyWeight,
            color: selected ? c.mintInk : c.secondary,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(size: 22, color: selected ? c.mintInk : c.secondary);
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: Colors.transparent,
        indicatorColor: c.mint,
        selectedIconTheme: IconThemeData(color: c.mintInk, size: 22),
        unselectedIconTheme: IconThemeData(color: c.secondary, size: 22),
        selectedLabelTextStyle: TextStyle(color: c.mintInk, fontSize: 12.5, fontWeight: strongWeight),
        unselectedLabelTextStyle: TextStyle(color: c.secondary, fontSize: 12.5, fontWeight: bodyWeight),
        useIndicator: true,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: c.ink, borderRadius: BorderRadius.circular(10)),
        textStyle: TextStyle(color: c.canvas, fontSize: 12.5, height: 1.35),
        waitDuration: const Duration(milliseconds: 500),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: c.teal, linearTrackColor: c.line),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(c.ink.withValues(alpha: 0.18)),
        radius: const Radius.circular(99),
        thickness: const WidgetStatePropertyAll(6),
      ),
    );
  }
}

extension LangoContext on BuildContext {
  LangoColors get colors => Theme.of(this).extension<LangoColors>() ?? LangoColors.light;
  TextTheme get texts => Theme.of(this).textTheme;

  bool get reduceMotion {
    final media = MediaQuery.maybeOf(this);
    final app = AppScope.maybeOf(this);
    return (media?.disableAnimations ?? false) || (app?.reduceMotion ?? false);
  }

  Duration motion(int milliseconds) =>
      reduceMotion ? Duration.zero : Duration(milliseconds: milliseconds);

  Curve get entranceCurve => reduceMotion ? Curves.linear : const Cubic(0.16, 1, 0.3, 1);
}

TextStyle tabular(TextStyle? style) =>
    (style ?? const TextStyle()).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
