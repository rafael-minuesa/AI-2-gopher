import 'package:flutter/material.dart';

// The dark colors of the browser extension's reader (extension/src/reader.css).
const _background = Color(0xFF171B19);
const _panel = Color(0xFF232925);
const _text = Color(0xFFE7ECE6);
const _muted = Color(0xFFADB7AB);
const _line = Color(0xFF465047);
const _accent = Color(0xFFA9D5BD);

const _scheme = ColorScheme.dark(
  primary: _accent,
  onPrimary: _background,
  primaryContainer: _panel,
  onPrimaryContainer: _accent,
  secondary: _accent,
  onSecondary: _background,
  secondaryContainer: _panel,
  onSecondaryContainer: _accent,
  surface: _background,
  onSurface: _text,
  onSurfaceVariant: _muted,
  surfaceContainerLowest: _background,
  surfaceContainerLow: _background,
  surfaceContainer: _panel,
  surfaceContainerHigh: _panel,
  surfaceContainerHighest: _panel,
  outline: _line,
  outlineVariant: _line,
);

/// The app is always dark, in the same monospace look as the reader.
final readerTheme = ThemeData(
  useMaterial3: true,
  colorScheme: _scheme,
  scaffoldBackgroundColor: _background,
  fontFamily: 'monospace',
  appBarTheme: const AppBarTheme(
    backgroundColor: _background,
    foregroundColor: _text,
    surfaceTintColor: Colors.transparent,
    shape: Border(bottom: BorderSide(color: _line)),
  ),
  navigationBarTheme: const NavigationBarThemeData(
    backgroundColor: _background,
    indicatorColor: _panel,
    surfaceTintColor: Colors.transparent,
  ),
  dividerTheme: const DividerThemeData(color: _line),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: _panel,
      foregroundColor: _accent,
      side: const BorderSide(color: _line),
    ),
  ),
);
