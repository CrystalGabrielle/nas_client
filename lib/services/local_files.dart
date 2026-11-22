import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../models/models.dart';
import '../utils/cache_policy.dart';

enum FileFamily {
  folder,
  image,
  video,
  audio,
  text,
  pdf,
  archive,
  document,
  other,
}

FileFamily familyOf(RemoteEntry entry) {
  if (entry.isDirectory) return FileFamily.folder;
  return familyOfName(entry.name);
}

FileFamily familyOfName(String name) {
  final dot = name.lastIndexOf('.');
  final ext = dot <= 0 ? '' : name.substring(dot + 1).toLowerCase();
  const images = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic', 'heif'};
  const videos = {'mp4', 'mov', 'mkv', 'avi', 'webm', '3gp', 'm4v'};
  const audios = {'mp3', 'wav', 'flac', 'aac', 'ogg', 'm4a', 'wma'};
  const texts = {
    'txt',
    'md',
    'json',
    'xml',
    'csv',
    'log',
    'yaml',
    'yml',
    'ini',
    'conf',
    'dart',
    'py',
    'js',
    'ts',
    'html',
    'css',
    'sh',
    'bat',
    'properties',
  };
  const archives = {'zip', 'rar', '7z', 'tar', 'gz', 'bz2'};
  const documents = {'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'rtf'};
  if (images.contains(ext)) return FileFamily.image;
  if (videos.contains(ext)) return FileFamily.video;
  if (audios.contains(ext)) return FileFamily.audio;
  if (ext == 'pdf') return FileFamily.pdf;
  if (texts.contains(ext)) return FileFamily.text;
  if (archives.contains(ext)) return FileFamily.archive;
  if (documents.contains(ext)) return FileFamily.document;
  return FileFamily.other;
}

String familyLabel(FileFamily family) {
  return switch (family) {
    FileFamily.folder => '文件夹',
    FileFamily.image => '图片',
    FileFamily.video => '视频',
    FileFamily.audio => '音频',
    FileFamily.text => '文本',
    FileFamily.pdf => 'PDF',
    FileFamily.archive => '压缩包',
    FileFamily.document => '文档',
    FileFamily.other => '文件',
  };
}

String? mimeOf(String name) {
  return switch (familyOfName(name)) {
    FileFamily.image => _imageMime(name),
    FileFamily.video => 'video/*',
    FileFamily.audio => 'audio/*',
    FileFamily.text => 'text/plain',
    FileFamily.pdf => 'application/pdf',
    FileFamily.folder ||
    FileFamily.archive ||
    FileFamily.document ||
    FileFamily.other => null,
  };
}

String videoMime(String name) {
  final ext = _extension(name);
  return switch (ext) {
    'webm' => 'video/webm',
    'mov' => 'video/quicktime',
    'mkv' => 'video/x-matroska',
    'avi' => 'video/x-msvideo',
    '3gp' => 'video/3gpp',
    _ => 'video/mp4',
  };
}

String _extension(String name) {
  final dot = name.lastIndexOf('.');
  if (dot <= 0 || dot == name.length - 1) return '';
  return name.substring(dot + 1).toLowerCase();
}

String _imageMime(String name) {
  final ext = name.split('.').last.toLowerCase();
  return switch (ext) {
    'png' => 'image/png',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    'bmp' => 'image/bmp',
    'heic' || 'heif' => 'image/heic',
    _ => 'image/jpeg',
  };
}

Future<Directory> downloadDirectory() async {
  final docs = await getApplicationDocumentsDirectory();
  final directory = Directory('${docs.path}/下载');
  if (!await directory.exists()) {
    await directory.create(recursive: true);
  }
  return directory;
}

Future<Directory> cacheDirectory() async {
  final root = await getApplicationCacheDirectory();
  final directory = Directory('${root.path}/预览缓存');
  if (!await directory.exists()) {
    await directory.create(recursive: true);
  }
  return directory;
}

Future<Directory> previewDirectory() => cacheDirectory();

String localBaseName(String path) {
  final normalized = path.replaceAll('\\', '/');
  final index = normalized.lastIndexOf('/');
  if (index < 0 || index == normalized.length - 1) return normalized;
  return normalized.substring(index + 1);
}

bool localPathContains(String parent, String child) {
  final base = parent.replaceAll('\\', '/');
  final nested = child.replaceAll('\\', '/');
  if (nested == base) return true;
  final prefix = base.endsWith('/') ? base : '$base/';
  return nested.startsWith(prefix);
}

Future<File> downloadCompletely({
  required File destination,
  required Future<void> Function(File partial) write,
}) async {
  final partial = File('${destination.path}.part');
  if (await partial.exists()) await partial.delete();
  try {
    await write(partial);
    if (await destination.exists()) await destination.delete();
    return await partial.rename(destination.path);
  } catch (_) {
    if (await partial.exists()) {
      await partial.delete();
    }
    rethrow;
  }
}

Future<void> tidyLocalFiles({
  DateTime? now,
  int maxBytes = defaultCacheBudget,
  Duration maxAge = defaultCacheAge,
}) async {
  await _deleteLegacyPreview();
  await _deletePartFiles(await downloadDirectory());
  final cache = await cacheDirectory();
  await _deletePartFiles(cache);
  final files = <File>[];
  await for (final entity in cache.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final length = await entity.length();
    if (length == 0) {
      await entity.delete();
      continue;
    }
    files.add(entity);
  }
  final entries = <CacheEntry>[];
  for (final file in files) {
    final stat = await file.stat();
    entries.add(
      CacheEntry(id: file.path, bytes: stat.size, modified: stat.modified),
    );
  }
  final victims = cacheVictims(
    entries,
    now: now ?? DateTime.now(),
    maxBytes: maxBytes,
    maxAge: maxAge,
  );
  for (final path in victims) {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}

Future<void> clearCache() async {
  final cache = await cacheDirectory();
  await for (final entity in cache.list(followLinks: false)) {
    await entity.delete(recursive: true);
  }
}

Future<int> cacheSize() async {
  final cache = await cacheDirectory();
  var total = 0;
  await for (final entity in cache.list(recursive: true, followLinks: false)) {
    if (entity is File) total += await entity.length();
  }
  return total;
}

Future<void> _deleteLegacyPreview() async {
  final temp = await getTemporaryDirectory();
  final legacy = Directory('${temp.path}/samba_preview');
  if (await legacy.exists()) {
    await legacy.delete(recursive: true);
  }
}

Future<void> _deletePartFiles(Directory directory) async {
  if (!await directory.exists()) return;
  await for (final entity in directory.list(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is File && entity.path.endsWith('.part')) {
      await entity.delete();
    }
  }
}

Future<File> uniqueLocalFile(Directory directory, String name) async {
  final safe = _safeName(name);
  final direct = File('${directory.path}/$safe');
  if (!await direct.exists()) return direct;
  final dot = safe.lastIndexOf('.');
  final stem = dot > 0 ? safe.substring(0, dot) : safe;
  final ext = dot > 0 ? safe.substring(dot) : '';
  for (var index = 1; index < 1000; index++) {
    final candidate = File('${directory.path}/$stem ($index)$ext');
    if (!await candidate.exists()) return candidate;
  }
  return direct;
}

File previewFile(Directory directory, RemoteEntry entry) {
  final stamp = entry.modified?.millisecondsSinceEpoch ?? 0;
  return File(
    '${directory.path}/${entry.size}_${stamp}_${_safeName(entry.name)}',
  );
}

String _safeName(String name) {
  final cleaned = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  return cleaned.isEmpty ? '未命名' : cleaned;
}

Future<File> materializePickedFile(PlatformFile file) async {
  final path = file.path;
  if (path != null && path.isNotEmpty) return File(path);
  final temp = await getTemporaryDirectory();
  final out = File('${temp.path}/${_safeName(file.name)}');
  final sink = out.openWrite();
  await sink.addStream(file.readAsByteStream());
  await sink.close();
  return out;
}

Future<String?> openLocalFile(File file) async {
  final result = await OpenFilex.open(
    file.path,
    type: mimeOf(file.uri.pathSegments.last),
  );
  return switch (result.type) {
    ResultType.done => null,
    ResultType.noAppToOpen => '手机里没有能打开这种文件的应用',
    ResultType.fileNotFound => '本地文件不见了',
    ResultType.permissionDenied => '没有权限打开这个文件',
    ResultType.error => result.message,
  };
}
