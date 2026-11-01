import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static ThemeData _calmWorkspace(ThemeData theme) {
    final dark = theme.brightness == Brightness.dark;
    final surface = dark ? const Color(0xFF142033) : Colors.white;
    final outline = dark ? const Color(0xFF34445C) : const Color(0xFFE2E5EA);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
    );
    return theme.copyWith(
      scaffoldBackgroundColor: dark
          ? const Color(0xFF0B1320)
          : const Color(0xFFF6F7F9),
      colorScheme: theme.colorScheme.copyWith(
        surface: surface,
        outlineVariant: outline,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: outline),
        ),
      ),
      dividerTheme: DividerThemeData(color: outline, thickness: 1, space: 1),
      appBarTheme: theme.appBarTheme.copyWith(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      inputDecorationTheme: theme.inputDecorationTheme.copyWith(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: theme.colorScheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: theme.colorScheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: theme.colorScheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: theme.colorScheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: theme.colorScheme.error, width: 2),
        ),
        errorMaxLines: 3,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: theme.colorScheme.primary,
        selectionColor: theme.colorScheme.primary.withValues(alpha: .24),
        selectionHandleColor: theme.colorScheme.primary,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: shape,
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: theme.elevatedButtonTheme.style?.copyWith(
          shape: WidgetStatePropertyAll(shape),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 0,
        shape: shape,
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
      ),
      chipTheme: theme.chipTheme.copyWith(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  static bool _fontLicenseRegistered = false;
  static const List<String> _fontFallbacks = <String>[
    'Noto Sans',
    'Segoe UI Emoji',
    'Segoe UI Symbol',
    'Arial',
  ];

  static TextStyle? _withFallback(TextStyle? style) {
    return style?.copyWith(fontFamilyFallback: _fontFallbacks);
  }

  static TextTheme _textThemeWithFallback(TextTheme theme) {
    return theme.copyWith(
      displayLarge: _withFallback(theme.displayLarge),
      displayMedium: _withFallback(theme.displayMedium),
      displaySmall: _withFallback(theme.displaySmall),
      headlineLarge: _withFallback(theme.headlineLarge),
      headlineMedium: _withFallback(theme.headlineMedium),
      headlineSmall: _withFallback(theme.headlineSmall),
      titleLarge: _withFallback(theme.titleLarge),
      titleMedium: _withFallback(theme.titleMedium),
      titleSmall: _withFallback(theme.titleSmall),
      bodyLarge: _withFallback(theme.bodyLarge),
      bodyMedium: _withFallback(theme.bodyMedium),
      bodySmall: _withFallback(theme.bodySmall),
      labelLarge: _withFallback(theme.labelLarge),
      labelMedium: _withFallback(theme.labelMedium),
      labelSmall: _withFallback(theme.labelSmall),
    );
  }

  static void _requireBundledFonts() {
    GoogleFonts.config.allowRuntimeFetching = false;
    if (_fontLicenseRegistered) {
      return;
    }
    LicenseRegistry.addLicense(() async* {
      final license = await rootBundle.loadString('assets/fonts/Inter-OFL.txt');
      yield LicenseEntryWithLineBreaks(<String>['Inter'], license);
      final sourceLicense = await rootBundle.loadString(
        'assets/fonts/SourceSans3-OFL.txt',
      );
      yield LicenseEntryWithLineBreaks(<String>[
        'Source Sans 3',
      ], sourceLicense);
    });
    _fontLicenseRegistered = true;
  }

  static ThemeData light({TargetPlatform? platform}) {
    _requireBundledFonts();
    const primaryColor = Color(0xFF1E5BF1);
    const backgroundColor = Color(0xFFF5F7FE);
    final base = ThemeData(
      useMaterial3: true,
      platform: platform,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        primary: primaryColor,
        brightness: Brightness.light,
        surface: backgroundColor,
      ),
      scaffoldBackgroundColor: backgroundColor,
      textTheme: ThemeData.light().textTheme.apply(fontFamily: 'Source Sans 3'),
    );

    return _calmWorkspace(
      base.copyWith(
        textTheme: _textThemeWithFallback(
          base.textTheme
              .apply(fontFamily: 'Source Sans 3')
              .copyWith(
                displayLarge: TextStyle(
                  fontFamily: 'Source Sans 3',
                  fontWeight: FontWeight.w700,
                  fontSize: 56,
                  color: const Color(0xFF0F172A),
                ),
                headlineMedium: TextStyle(
                  fontFamily: 'Source Sans 3',
                  fontWeight: FontWeight.w600,
                  fontSize: 32,
                  color: const Color(0xFF0F172A),
                ),
                titleLarge: TextStyle(
                  fontFamily: 'Source Sans 3',
                  fontWeight: FontWeight.w600,
                  fontSize: 20,
                  color: const Color(0xFF0F172A),
                ),
                bodyLarge: TextStyle(
                  fontFamily: 'Source Sans 3',
                  fontSize: 16,
                  height: 1.5,
                  color: const Color(0xFF334155),
                ),
                bodyMedium: TextStyle(
                  fontFamily: 'Source Sans 3',
                  fontSize: 14,
                  height: 1.6,
                  color: const Color(0xFF475569),
                ),
                labelLarge: TextStyle(
                  fontFamily: 'Source Sans 3',
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
        ),
        chipTheme: base.chipTheme.copyWith(
          backgroundColor: const Color(0xFFE8EDFF),
          labelStyle: TextStyle(
            fontFamily: 'Source Sans 3',
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF1E5BF1),
          ).copyWith(fontFamilyFallback: _fontFallbacks),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          side: BorderSide.none,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          hintStyle: TextStyle(
            fontFamily: 'Source Sans 3',
            color: const Color(0xFF64748B),
          ).copyWith(fontFamilyFallback: _fontFallbacks),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: primaryColor, width: 1.2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFEF4444)),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFEF4444)),
          ),
          contentPadding: const EdgeInsets.symmetric(
            vertical: 18,
            horizontal: 20,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryColor,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 18),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: TextStyle(
              fontFamily: 'Source Sans 3',
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ).copyWith(fontFamilyFallback: _fontFallbacks),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: primaryColor,
            side: const BorderSide(color: Color(0xFFCBD5F5)),
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
            textStyle: TextStyle(
              fontFamily: 'Source Sans 3',
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ).copyWith(fontFamilyFallback: _fontFallbacks),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF1E5BF1),
            textStyle: TextStyle(
              fontFamily: 'Source Sans 3',
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ).copyWith(fontFamilyFallback: _fontFallbacks),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF0F172A),
          surfaceTintColor: Colors.white,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
        ),
      ),
    );
  }

  static ThemeData dark({TargetPlatform? platform}) {
    _requireBundledFonts();
    const primaryColor = Color(0xFFA9C7FF);
    const scaffoldColor = Color(0xFF0B1220);
    final base = ThemeData(
      useMaterial3: true,
      platform: platform,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        primary: primaryColor,
        brightness: Brightness.dark,
        surface: scaffoldColor,
      ),
      scaffoldBackgroundColor: scaffoldColor,
      textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'Source Sans 3'),
    );

    return _calmWorkspace(
      base.copyWith(
        scaffoldBackgroundColor: scaffoldColor,
        colorScheme: base.colorScheme.copyWith(
          surface: const Color(0xFF152034),
          surfaceContainerHighest: const Color(0xFF1F2A3F),
        ),
        textTheme: _textThemeWithFallback(
          base.textTheme
              .apply(fontFamily: 'Source Sans 3')
              .copyWith(
                displayLarge: TextStyle(
                  fontFamily: 'Source Sans 3',
                  fontWeight: FontWeight.w700,
                  fontSize: 56,
                  color: Colors.white,
                ),
                headlineMedium: TextStyle(
                  fontFamily: 'Source Sans 3',
                  fontWeight: FontWeight.w600,
                  fontSize: 32,
                  color: Colors.white,
                ),
                titleLarge: TextStyle(
                  fontFamily: 'Source Sans 3',
                  fontWeight: FontWeight.w600,
                  fontSize: 20,
                  color: Colors.white,
                ),
                bodyLarge: TextStyle(
                  fontFamily: 'Source Sans 3',
                  fontSize: 16,
                  height: 1.5,
                  color: const Color(0xFFD1D5DB),
                ),
                bodyMedium: TextStyle(
                  fontFamily: 'Source Sans 3',
                  fontSize: 14,
                  height: 1.6,
                  color: const Color(0xFFCBD5F5),
                ),
                labelLarge: TextStyle(
                  fontFamily: 'Source Sans 3',
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
        ),
        chipTheme: base.chipTheme.copyWith(
          backgroundColor: const Color(0x332B3A55),
          labelStyle: TextStyle(
            fontFamily: 'Source Sans 3',
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: const Color(0xFFA9C7FF),
          ).copyWith(fontFamilyFallback: _fontFallbacks),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          side: BorderSide.none,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF1E293B),
          hintStyle: TextStyle(
            fontFamily: 'Source Sans 3',
            color: const Color(0xFF94A3B8),
          ).copyWith(fontFamilyFallback: _fontFallbacks),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFF334155)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFF334155)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: primaryColor, width: 1.2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFEF4444)),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFEF4444)),
          ),
          contentPadding: const EdgeInsets.symmetric(
            vertical: 18,
            horizontal: 20,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryColor,
            foregroundColor: Colors.black,
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 18),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: TextStyle(
              fontFamily: 'Source Sans 3',
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ).copyWith(fontFamilyFallback: _fontFallbacks),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: primaryColor,
            side: const BorderSide(color: Color(0xFF475569)),
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
            textStyle: TextStyle(
              fontFamily: 'Source Sans 3',
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ).copyWith(fontFamilyFallback: _fontFallbacks),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFFA9C7FF),
            textStyle: TextStyle(
              fontFamily: 'Source Sans 3',
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ).copyWith(fontFamilyFallback: _fontFallbacks),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0F172A),
          foregroundColor: Colors.white,
          surfaceTintColor: Color(0xFF0F172A),
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF152034),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
        ),
      ),
    );
  }
}
