/// Generates README screenshots from synthetic data only.
///
/// This generator never touches real accounts, real hosts or real files. All
/// addresses are documentation-only RFC5737-style examples. It is an optional
/// doc tool, NOT part of `flutter test` (it lives under `tool/`). Run with:
///
///   flutter test --update-goldens tool/docs_screenshots.dart
///   python tools/prepare_screenshots.py
///
/// Golden PNGs land in `test/goldens/` and are downscaled into
/// `docs/screenshots/` by `tools/prepare_screenshots.py`.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_client/models/models.dart';
import 'package:nas_client/screens/browser_screen.dart';
import 'package:nas_client/screens/home_screen.dart';
import 'package:nas_client/services/remote_session.dart';
import 'package:nas_client/theme/app_theme.dart';
import 'package:nas_client/theme/theme_controller.dart';

// --------------------------------------------------------------- fake font ---
Future<void> _loadCjkFont() async {
  final candidates = <String>[
    'C:/Windows/Fonts/simhei.ttf',
    '/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc',
  ];
  for (final path in candidates) {
    final file = File(path);
    if (!await file.exists()) continue;
    final bytes = await file.readAsBytes();
    final loader = FontLoader('DocCjk');
    loader.addFont(
      Future.value(ByteData.sublistView(Uint8List.fromList(bytes))),
    );
    await loader.load();
    break;
  }
  // Material Icons: golden tests default to the Ahem font, which turns every
  // icon glyph into a tofu box. Load the real font so icons render correctly.
  const iconFonts = <String>[
    '/c/src/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
  ];
  for (final path in iconFonts) {
    final file = File(path);
    if (!await file.exists()) continue;
    final bytes = await file.readAsBytes();
    final loader = FontLoader('MaterialIcons');
    loader.addFont(
      Future.value(ByteData.sublistView(Uint8List.fromList(bytes))),
    );
    await loader.load();
    break;
  }
}

// -------------------------------------------------------------- fake data ---
const _exampleIp = '192.168.1.10';

SavedAccount _demoAccount() => SavedAccount(
  id: 'demo',
  protocol: RemoteProtocol.smb,
  host: _exampleIp,
  port: 445,
  username: 'demo',
  password: '',
  domain: '',
  alias: '客厅 NAS',
  anonymous: true,
  updatedAt: DateTime(2026, 1, 1),
);

class _FakeReader implements RangeReader {
  @override
  Future<void> copy({
    required int start,
    int? endExclusive,
    required void Function(List<int> bytes) onBytes,
  }) async {}

  @override
  Future<void> close() async {}
}

/// A session backed entirely by in-memory example entries.
class _DemoSession extends RemoteSession {
  _DemoSession(super.account);

  @override
  ConnectionMode get resolvedMode => ConnectionMode.smb3;

  @override
  String get transportLabel => 'SMB 3';

  @override
  String get rootPath => '/';

  static final List<RemoteEntry> entries = [
    RemoteEntry(
      name: '照片',
      path: '/照片',
      kind: EntryKind.directory,
      size: 0,
      modified: DateTime(2026, 1, 1),
      isShare: true,
    ),
    RemoteEntry(
      name: '影音',
      path: '/影音',
      kind: EntryKind.directory,
      size: 0,
      modified: DateTime(2026, 1, 1),
      isShare: true,
    ),
    RemoteEntry(
      name: '文档',
      path: '/文档',
      kind: EntryKind.directory,
      size: 0,
      modified: DateTime(2026, 1, 1),
    ),
    RemoteEntry(
      name: ' backups',
      path: '/ backups',
      kind: EntryKind.directory,
      size: 0,
      modified: DateTime(2026, 1, 1),
    ),
    RemoteEntry(
      name: '旅行vlog.mp4',
      path: '/旅行vlog.mp4',
      kind: EntryKind.file,
      size: 824 * 1024 * 1024,
      modified: DateTime(2026, 1, 1),
    ),
    RemoteEntry(
      name: '家庭合照.jpg',
      path: '/家庭合照.jpg',
      kind: EntryKind.file,
      size: 4 * 1024 * 1024,
      modified: DateTime(2026, 1, 1),
    ),
    RemoteEntry(
      name: '项目说明.pdf',
      path: '/项目说明.pdf',
      kind: EntryKind.file,
      size: 1 * 1024 * 1024,
      modified: DateTime(2026, 1, 1),
    ),
    RemoteEntry(
      name: 'readme.txt',
      path: '/readme.txt',
      kind: EntryKind.file,
      size: 2048,
      modified: DateTime(2026, 1, 1),
    ),
  ];

  @override
  Future<List<RemoteEntry>> list(String path) async => entries;

  @override
  Future<void> createFolder(String path) async {}

  @override
  Future<void> delete(RemoteEntry entry) async {}

  @override
  Future<void> rename(RemoteEntry entry, String newName) async {}

  @override
  Future<void> download(
    RemoteEntry entry,
    File destination,
    TransferProgress? onProgress, {
    bool Function()? isCancelled,
  }) async {}

  @override
  Future<RangeReader> openRange(RemoteEntry entry) async => _FakeReader();

  @override
  Future<void> upload(
    File local,
    String directory,
    String remoteName,
    TransferProgress? onProgress, {
    bool Function()? isCancelled,
  }) async {}

  @override
  Future<void> close() async {}
}

// ------------------------------------------------------------------ harness ---
Widget _harness({required Widget child, ThemeMode mode = ThemeMode.light}) {
  final controller = ThemeController();
  // ignore: invalid_use_of_protected_member
  controller.setMode(mode);
  final base = AppTheme.light();
  final theme = base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: 'DocCjk'),
    primaryTextTheme: base.primaryTextTheme.apply(fontFamily: 'DocCjk'),
  );
  return ThemeScope(
    controller: controller,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: child,
    ),
  );
}

Future<void> _shot(
  WidgetTester tester,
  String name, {
  required Widget child,
}) async {
  await tester.binding.setSurfaceSize(const Size(1080, 1920));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(_harness(child: child));
  // Let async init (path_provider, secure storage, directory listing) settle.
  for (var i = 0; i < 12; i++) {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('goldens/$name.png'),
  );
}

void main() {
  setUp(_loadCjkFont);

  testWidgets('screenshot home', (tester) async {
    await _shot(tester, 'screenshot_home', child: const HomeScreen());
  });

  testWidgets('screenshot browser', (tester) async {
    final account = _demoAccount();
    await _shot(
      tester,
      'screenshot_browser',
      child: BrowserScreen(session: _DemoSession(account), account: account),
    );
  });
}
