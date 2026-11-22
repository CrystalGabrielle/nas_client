import 'dart:ui';

import 'package:flutter/material.dart';

import 'screens/shell_screen.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = FlutterError.presentError;
  PlatformDispatcher.instance.onError = (error, stack) {
    FlutterError.presentError(
      FlutterErrorDetails(exception: error, stack: stack),
    );
    return true;
  };
  ErrorWidget.builder = (details) {
    return const Material(
      color: Color(0xFFF3EEE6),
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Text('这一页没有显示出来，返回后再打开一次。', textAlign: TextAlign.center),
        ),
      ),
    );
  };
  runApp(const NasClientApp());
}

class NasClientApp extends StatefulWidget {
  const NasClientApp({super.key});

  @override
  State<NasClientApp> createState() => _NasClientAppState();
}

class _NasClientAppState extends State<NasClientApp> {
  final ThemeController _theme = ThemeController();

  @override
  void initState() {
    super.initState();
    _theme.addListener(_onTheme);
    _theme.load();
  }

  void _onTheme() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _theme.removeListener(_onTheme);
    _theme.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ThemeScope(
      controller: _theme,
      child: MaterialApp(
        title: '近邻盘',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: _theme.mode,
        home: const ShellScreen(),
      ),
    );
  }
}
