import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

ThemeMode themeModeFromName(String? raw) {
  return switch (raw?.trim()) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };
}

String themeModeName(ThemeMode mode) {
  return switch (mode) {
    ThemeMode.light => 'light',
    ThemeMode.dark => 'dark',
    ThemeMode.system => 'system',
  };
}

class ThemeController extends ChangeNotifier {
  ThemeMode _mode = ThemeMode.system;

  ThemeMode get mode => _mode;

  Future<void> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return;
      _mode = themeModeFromName(await file.readAsString());
      notifyListeners();
    } catch (_) {}
  }

  Future<void> setMode(ThemeMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
    try {
      final file = await _file();
      await file.writeAsString(themeModeName(mode));
    } catch (_) {}
  }

  Future<File> _file() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}/theme_mode.txt');
  }
}

class ThemeScope extends InheritedNotifier<ThemeController> {
  const ThemeScope({
    required ThemeController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static ThemeController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ThemeScope>();
    return scope!.notifier!;
  }
}

List<PopupMenuEntry<String>> themeMenuItems(ThemeMode mode) {
  String label(String text, ThemeMode value) {
    return mode == value ? '$text  ✓' : text;
  }

  return [
    PopupMenuItem(
      value: 'theme-system',
      child: Text(label('跟随系统', ThemeMode.system)),
    ),
    PopupMenuItem(
      value: 'theme-light',
      child: Text(label('白天模式', ThemeMode.light)),
    ),
    PopupMenuItem(
      value: 'theme-dark',
      child: Text(label('夜间模式', ThemeMode.dark)),
    ),
  ];
}

void applyThemeChoice(BuildContext context, String value) {
  final mode = switch (value) {
    'theme-light' => ThemeMode.light,
    'theme-dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };
  ThemeScope.of(context).setMode(mode);
}
