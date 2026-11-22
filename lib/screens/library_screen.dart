import 'dart:io';

import 'package:flutter/material.dart';

import '../services/download_location.dart';
import '../services/download_location_scope.dart';
import '../services/local_files.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../utils/paths.dart';
import '../widgets/dialogs.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  Directory? _root;
  Directory? _current;
  List<FileSystemEntity> _entries = const [];
  List<File> _cacheFiles = const [];
  int _cacheBytes = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      await _loadLibrary();
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _toast(friendlyError(error));
    }
  }

  Future<void> _loadLibrary() async {
    final root = await downloadDirectory();
    final current = _current;
    final directory =
        current == null || !localPathContains(root.path, current.path)
        ? root
        : current;
    if (!await directory.exists()) await directory.create(recursive: true);
    final entries = await directory.list(followLinks: false).toList();
    entries.sort((a, b) {
      final aDir = a is Directory;
      final bDir = b is Directory;
      if (aDir != bDir) return aDir ? -1 : 1;
      return localBaseName(
        a.path,
      ).toLowerCase().compareTo(localBaseName(b.path).toLowerCase());
    });
    final cache = await cacheDirectory();
    final cacheFiles = <File>[];
    var cacheBytes = 0;
    await for (final entity in cache.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File || entity.path.endsWith('.part')) continue;
      cacheFiles.add(entity);
      cacheBytes += await entity.length();
    }
    cacheFiles.sort(
      (a, b) => localBaseName(
        a.path,
      ).toLowerCase().compareTo(localBaseName(b.path).toLowerCase()),
    );
    if (!mounted) return;
    setState(() {
      _root = root;
      _current = directory;
      _entries = entries;
      _cacheFiles = cacheFiles;
      _cacheBytes = cacheBytes;
      _loading = false;
    });
  }

  void _toast(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _createFolder() async {
    final current = _current;
    if (current == null) return;
    final name = await showNameDialog(
      context: context,
      title: '新建文件夹',
      confirm: '创建',
      hint: '文件夹名称',
    );
    if (name == null || !mounted) return;
    final error = validateEntryName(name);
    if (error != null) {
      _toast(error);
      return;
    }
    try {
      await Directory('${current.path}/$name').create(recursive: true);
      await _reload();
    } catch (error) {
      if (mounted) _toast(friendlyError(error));
    }
  }

  Future<void> _openFile(File file) async {
    final message = await openLocalFile(file);
    if (message != null && mounted) _toast(message);
  }

  Future<void> _rename(FileSystemEntity entity) async {
    final name = await showNameDialog(
      context: context,
      title: '重命名',
      confirm: '保存',
      initial: localBaseName(entity.path),
    );
    if (name == null || name == localBaseName(entity.path) || !mounted) return;
    final error = validateEntryName(name);
    if (error != null) {
      _toast(error);
      return;
    }
    final parent = entity.parent.path;
    final next = '$parent${Platform.pathSeparator}$name';
    if (await FileSystemEntity.type(next) != FileSystemEntityType.notFound) {
      _toast('这个名称已经有文件了');
      return;
    }
    try {
      await entity.rename(next);
      await _reload();
    } catch (error) {
      if (mounted) _toast(friendlyError(error));
    }
  }

  Future<void> _delete(FileSystemEntity entity) async {
    final folder = entity is Directory;
    final confirmed = await showConfirmDialog(
      context: context,
      title: folder ? '删除文件夹' : '删除文件',
      message: folder
          ? '删除「${localBaseName(entity.path)}」及其里面的内容？'
          : '删除「${localBaseName(entity.path)}」？',
      confirm: '删除',
      danger: true,
    );
    if (!confirmed) return;
    try {
      await entity.delete(recursive: folder);
      await _reload();
    } catch (error) {
      if (mounted) _toast(friendlyError(error));
    }
  }

  Future<void> _move(FileSystemEntity entity) async {
    final root = _root;
    if (root == null) return;
    final folders = <Directory>[root];
    try {
      await for (final item in root.list(recursive: true, followLinks: false)) {
        if (item is Directory) folders.add(item);
      }
    } catch (error) {
      if (mounted) _toast(friendlyError(error));
      return;
    }
    if (!mounted) return;
    final target = await showModalBottomSheet<Directory>(
      context: context,
      backgroundColor: AppPalette.of(context).card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(title: Text('移动到')),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.55,
                ),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final folder in folders)
                      if (entity is! Directory ||
                          !localPathContains(entity.path, folder.path))
                        ListTile(
                          leading: const Icon(Icons.folder_rounded),
                          title: Text(_folderLabel(root, folder)),
                          onTap: () => Navigator.pop(context, folder),
                        ),
                    ListTile(
                      leading: const Icon(Icons.create_new_folder_rounded),
                      title: const Text('新建文件夹并移入'),
                      onTap: () async {
                        final name = await showNameDialog(
                          context: context,
                          title: '新建文件夹',
                          confirm: '创建',
                          hint: '文件夹名称',
                        );
                        if (name == null || !context.mounted) return;
                        final error = validateEntryName(name);
                        if (error != null) return;
                        final created = await Directory(
                          '${root.path}/$name',
                        ).create(recursive: true);
                        if (context.mounted) Navigator.pop(context, created);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
    if (target == null || !mounted) return;
    if (entity.parent.path == target.path) return;
    final name = localBaseName(entity.path);
    final direct = '${target.path}${Platform.pathSeparator}$name';
    try {
      if (await FileSystemEntity.type(direct) !=
          FileSystemEntityType.notFound) {
        final unique = await uniqueLocalFile(target, name);
        await entity.rename(unique.path);
      } else {
        await entity.rename(direct);
      }
      await _reload();
    } catch (error) {
      if (mounted) _toast(friendlyError(error));
    }
  }

  String _folderLabel(Directory root, Directory folder) {
    if (folder.path == root.path) return '下载';
    final relative = folder.path
        .substring(root.path.length)
        .replaceAll('\\', '/');
    return relative.startsWith('/') ? relative.substring(1) : relative;
  }

  Future<void> _clearCache() async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: '清理缓存',
      message: '删除预览和播放留下的临时文件。已经下载的文件会保留。',
      confirm: '清理',
    );
    if (!confirmed) return;
    try {
      await clearCache();
      await _reload();
      if (mounted) _toast('缓存已清理');
    } catch (error) {
      if (mounted) _toast(friendlyError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('本地文件'),
          bottom: const TabBar(
            tabs: [
              Tab(text: '下载'),
              Tab(text: '缓存'),
            ],
          ),
          actions: [
            IconButton(
              tooltip: '新建文件夹',
              onPressed: _createFolder,
              icon: const Icon(Icons.create_new_folder_rounded),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(children: [_downloadTab(palette), _cacheTab(palette)]),
      ),
    );
  }

  Widget _locationBanner(AppPalette palette) {
    final store = DownloadLocationScope.of(context);
    final external = store.mode != DownloadLocation.private;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: palette.accentSoft,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(
            external
                ? Icons.folder_shared_rounded
                : Icons.phone_android_rounded,
            color: palette.accent,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '当前下载位置：${store.mode.label}',
                  style: TextStyle(
                    color: palette.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (external)
                  Text(
                    '新文件保存在系统文件夹，用手机的文件管理器查看。',
                    style: TextStyle(color: palette.muted, fontSize: 12),
                  ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => showDownloadLocationSheet(context),
            child: const Text('更改'),
          ),
        ],
      ),
    );
  }

  Widget _downloadTab(AppPalette palette) {
    final root = _root;
    final current = _current;
    final nested = root != null && current != null && current.path != root.path;
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _locationBanner(palette),
          const SizedBox(height: 12),
          Text(
            '这里是你点「下载到本地」保存的文件，可以打开、重命名、移动和删除。',
            style: TextStyle(color: palette.muted, height: 1.4),
          ),
          if (nested)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.arrow_upward_rounded),
              title: const Text('上一级'),
              onTap: () {
                setState(() => _current = current.parent);
                _reload();
              },
            ),
          if (_entries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: Text('这个文件夹是空的', style: TextStyle(color: palette.muted)),
              ),
            ),
          for (final entity in _entries)
            _EntryTile(
              entity: entity,
              onOpen: entity is File
                  ? () => _openFile(entity)
                  : () {
                      setState(() => _current = entity as Directory);
                      _reload();
                    },
              onRename: () => _rename(entity),
              onMove: () => _move(entity),
              onDelete: () => _delete(entity),
            ),
        ],
      ),
    );
  }

  Widget _cacheTab(AppPalette palette) {
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(
            '预览图片、文本，以及无法直接播放时下载的视频会放在这里。超过 3 天或 512 MB 会自动删掉。你指定下载的文件不受影响。',
            style: TextStyle(color: palette.muted, height: 1.4),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _cacheFiles.isEmpty ? null : _clearCache,
            child: Text('清理缓存 · ${formatBytes(_cacheBytes)}'),
          ),
          const SizedBox(height: 12),
          if (_cacheFiles.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: Text('没有缓存', style: TextStyle(color: palette.muted)),
              ),
            ),
          for (final file in _cacheFiles)
            _EntryTile(
              entity: file,
              onOpen: () => _openFile(file),
              onDelete: () => _delete(file),
            ),
        ],
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.entity,
    required this.onOpen,
    required this.onDelete,
    this.onRename,
    this.onMove,
  });

  final FileSystemEntity entity;
  final VoidCallback onOpen;
  final VoidCallback onDelete;
  final VoidCallback? onRename;
  final VoidCallback? onMove;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final folder = entity is Directory;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: palette.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: palette.line),
      ),
      child: ListTile(
        onTap: onOpen,
        leading: Icon(
          folder ? Icons.folder_rounded : Icons.insert_drive_file_rounded,
          color: folder ? palette.accent : palette.ink,
        ),
        title: Text(
          localBaseName(entity.path),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: folder
            ? const Text('文件夹')
            : FutureBuilder<FileStat>(
                future: entity.stat(),
                builder: (context, snapshot) {
                  final stat = snapshot.data;
                  if (stat == null) return const Text('文件');
                  return Text(
                    '${formatBytes(stat.size)} · ${formatDate(stat.modified)}',
                  );
                },
              ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            switch (value) {
              case 'rename':
                onRename?.call();
              case 'move':
                onMove?.call();
              case 'delete':
                onDelete();
            }
          },
          itemBuilder: (context) => [
            if (onRename != null)
              const PopupMenuItem(value: 'rename', child: Text('重命名')),
            if (onMove != null)
              const PopupMenuItem(value: 'move', child: Text('移动')),
            PopupMenuItem(
              value: 'delete',
              child: Text('删除', style: TextStyle(color: palette.danger)),
            ),
          ],
        ),
      ),
    );
  }
}
