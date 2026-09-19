import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:librecamera/src/utils/preferences.dart';

class ThemeProvider extends ChangeNotifier {
  CustomThemeMode? _themeMode;

  CustomThemeMode themeMode() {
    _themeMode = Preferences.getThemeMode().isNotEmpty
        ? CustomThemeMode.values.byName(Preferences.getThemeMode())
        : CustomThemeMode.system;
    return _themeMode!;
  }

  ThemeData theme({required ColorScheme colorScheme}) {
    final isBlack = themeMode() == CustomThemeMode.black;

    return ThemeData(
      colorScheme: isBlack
          ? colorScheme
              .copyWith(surface: Colors.black)
              .harmonized()
          : colorScheme,
      useMaterial3: true, // 强制启用Material 3
      scaffoldBackgroundColor: isBlack ? Colors.black : null,
      // 添加Material 3专用配置
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 3,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
      ),
      // Flutter 3.22+ expects CardThemeData here
      cardTheme: CardThemeData(
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        height: 64,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
        elevation: 3,
        highlightElevation: 6,
      ),
    );
  }

  ThemeMode getMaterialThemeMode() {
    switch (themeMode()) {
      case CustomThemeMode.system:
        return ThemeMode.system;
      case CustomThemeMode.light:
        return ThemeMode.light;
      case CustomThemeMode.dark:
      case CustomThemeMode.black:
        return ThemeMode.dark;
    }
  }

  void setTheme(CustomThemeMode theme) {
    Preferences.setThemeMode(theme.name);
    _themeMode = theme;
    notifyListeners();
  }
}

enum CustomThemeMode {
  system,
  light,
  dark,
  black,
}
