import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Where downloaded files are saved.
///
/// - [system]: the public Downloads folder, accessed through a SAF directory
///   the user grants once. Requires a persisted grant on Android 11+.
/// - [private]: the app-private `下载/` folder (legacy behaviour, always works).
/// - [custom]: a user-chosen folder, also backed by a persisted SAF grant.
enum DownloadLocation { system, private, custom }

extension DownloadLocationLabel on DownloadLocation {
  String get label => switch (this) {
    DownloadLocation.system => '系统下载文件夹',
    DownloadLocation.private => '应用私有目录',
    DownloadLocation.custom => '自定义目录',
  };

  String get description => switch (this) {
    DownloadLocation.system => '保存到手机的「下载」文件夹，文件管理器可见',
    DownloadLocation.private => '仅在本应用内可见，卸载后清除',
    DownloadLocation.custom => '保存到你指定的文件夹',
  };
}

/// Result of picking a directory through the platform SAF dialog.
class PickedDownloadDirectory {
  const PickedDownloadDirectory({required this.uri, required this.displayName});

  final String uri;
  final String displayName;
}

/// Platform bridge for SAF directory grants and writes.
///
/// Kept as an abstract interface so unit tests can inject a fake. The real
/// implementation talks to a MethodChannel handled by MainActivity.kt.
abstract class DownloadLocationPlatform {
  Future<PickedDownloadDirectory?> pickDirectory();

  /// Copies [source] into the granted [directoryUri] as [displayName].
  /// Returns the resolved path when available, otherwise null on failure.
  Future<String?> writeFile({
    required String directoryUri,
    required String source,
    required String displayName,
  });

  /// Whether a persisted write grant is still valid for [directoryUri].
  Future<bool> hasPermission(String directoryUri);

  Future<void> releaseDirectory(String directoryUri);
}

class MethodChannelDownloadLocation implements DownloadLocationPlatform {
  static const MethodChannel _channel = MethodChannel(
    'com.nasclient.app/download',
  );

  @override
  Future<PickedDownloadDirectory?> pickDirectory() async {
    final result = await _channel.invokeMapMethod<String, Object>(
      'pickDirectory',
    );
    if (result == null) return null;
    final uri = result['uri'] as String?;
    if (uri == null || uri.isEmpty) return null;
    return PickedDownloadDirectory(
      uri: uri,
      displayName: result['displayName'] as String? ?? '下载文件夹',
    );
  }

  @override
  Future<String?> writeFile({
    required String directoryUri,
    required String source,
    required String displayName,
  }) {
    return _channel.invokeMethod<String>('writeFile', {
      'uri': directoryUri,
      'source': source,
      'displayName': displayName,
    });
  }

  @override
  Future<bool> hasPermission(String directoryUri) async {
    final value = await _channel.invokeMethod<bool>('hasPermission', {
      'uri': directoryUri,
    });
    return value ?? false;
  }

  @override
  Future<void> releaseDirectory(String directoryUri) {
    return _channel.invokeMethod<void>('releaseDirectory', {
      'uri': directoryUri,
    });
  }
}

/// Persisted preferences + orchestration for download destinations.
class DownloadLocationStore extends ChangeNotifier {
  DownloadLocationStore({
    DownloadLocationPlatform? platform,
    Future<Directory> Function()? supportDirectory,
  }) : _platform = platform ?? MethodChannelDownloadLocation(),
       _supportDirectory = supportDirectory ?? getApplicationSupportDirectory;

  final DownloadLocationPlatform _platform;
  final Future<Directory> Function() _supportDirectory;

  DownloadLocation _mode = DownloadLocation.system;
  String? _directoryUri;
  String? _directoryName;

  DownloadLocation get mode => _mode;
  String? get directoryUri => _directoryUri;
  String? get directoryName => _directoryName;

  bool get needsGrant =>
      (_mode == DownloadLocation.system || _mode == DownloadLocation.custom) &&
      (_directoryUri == null || _directoryUri!.isEmpty);

  Future<File> _file() async {
    final directory = await _supportDirectory();
    return File('${directory.path}/download_location.json');
  }

  Future<void> load() async {
    try {
      final raw = await (await _file()).readAsString();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      _mode = DownloadLocation.values.firstWhere(
        (value) => value.name == decoded['mode'],
        orElse: () => DownloadLocation.system,
      );
      _directoryUri = decoded['uri'] as String?;
      _directoryName = decoded['displayName'] as String?;
      notifyListeners();
    } catch (_) {
      // Corrupt or missing preferences: keep the safe default.
    }
  }

  Future<void> _persist() async {
    try {
      await (await _file()).writeAsString(
        jsonEncode({
          'mode': _mode.name,
          'uri': _directoryUri,
          'displayName': _directoryName,
        }),
      );
    } catch (_) {
      // Preferences are best-effort; downloads must still work.
    }
  }

  /// Sets the mode without (re)granting a directory.
  Future<void> setMode(DownloadLocation mode) async {
    _mode = mode;
    await _persist();
    notifyListeners();
  }

  /// Opens the SAF picker and stores the granted directory as the active
  /// destination for [mode] (defaults to the current mode).
  Future<PickedDownloadDirectory?> chooseDirectory({
    DownloadLocation? mode,
  }) async {
    final picked = await _platform.pickDirectory();
    if (picked == null) return null;
    _mode = mode ?? _mode;
    _directoryUri = picked.uri;
    _directoryName = picked.displayName;
    await _persist();
    notifyListeners();
    return picked;
  }

  /// Clears the stored grant (e.g. when switching to private mode).
  Future<void> clearDirectory() async {
    final uri = _directoryUri;
    if (uri != null && uri.isNotEmpty) {
      try {
        await _platform.releaseDirectory(uri);
      } catch (_) {}
    }
    _directoryUri = null;
    _directoryName = null;
    await _persist();
    notifyListeners();
  }

  /// Validates the current grant. Returns false when a grant is missing or
  /// has been revoked, so callers can prompt the user to re-authorise.
  Future<bool> hasValidGrant() async {
    final uri = _directoryUri;
    if (uri == null || uri.isEmpty) return false;
    return _platform.hasPermission(uri);
  }

  /// Delivers a fully-written local file to the configured destination.
  ///
  /// Returns the final path for a snackbar / open action, or null when the
  /// caller should fall back to the private directory.
  Future<String?> deliver({
    required File source,
    required String displayName,
    required Future<Directory> Function() privateDirectory,
  }) async {
    if (_mode == DownloadLocation.private) return null;
    final uri = _directoryUri;
    if (uri == null || uri.isEmpty) return null;

    final written = await _platform.writeFile(
      directoryUri: uri,
      source: source.path,
      displayName: displayName,
    );
    if (written == null) return null;
    // The SAF copy is independent; remove the staging file to avoid duplicates.
    try {
      if (await source.exists()) await source.delete();
    } catch (_) {}
    return written;
  }
}
