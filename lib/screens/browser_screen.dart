import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../models/models.dart';
import '../services/local_files.dart';
import '../services/remote_session.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import '../utils/format.dart';
import '../utils/paths.dart';
import '../widgets/dialogs.dart';
import '../widgets/file_glyph.dart';
import 'library_screen.dart';
import 'preview_screen.dart';

enum _SortMode { name, modified, size }

class BrowserScreen extends StatefulWidget {
  const BrowserScreen({
    super.key,
    required this.session,
    required this.account,
    this.ownsSession = true,
    this.onSwitchServer,
  });

  final RemoteSession session;
  final SavedAccount account;
  final bool ownsSession;
  final VoidCallback? onSwitchServer;

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  late String _path = widget.session.rootPath;
  List<RemoteEntry> _entries = const [];
  var _loadGeneration = 0;
  bool _loading = true;
  String? _error;
  bool _grid = false;
  bool _searching = false;
  _SortMode _sort = _SortMode.name;
  final TextEditingController _query = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load(_path);
  }

  @override
  void dispose() {
    _query.dispose();
    if (widget.ownsSession) {
      widget.session.close().catchError((Object _) {});
    }
    super.dispose();
  }

  List<RemoteEntry> get _visible {
    final keyword = _query.text.trim().toLowerCase();
    final filtered = keyword.isEmpty
        ? _entries
        : _entries
              .where((entry) => entry.name.toLowerCase().contains(keyword))
              .toList();
    final sorted = [...filtered];
    sorted.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return switch (_sort) {
        _SortMode.name => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        _SortMode.modified =>
          (b.modified ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
            a.modified ?? DateTime.fromMillisecondsSinceEpoch(0),
          ),
        _SortMode.size => b.size.compareTo(a.size),
      };
    });
    return sorted;
  }

  Future<void> _load(String path) async {
    final generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _error = null;
      if (normalizeRemote(path) != _path) _entries = const [];
    });
    try {
      final entries = await widget.session.list(path);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _path = normalizeRemote(path);
        _entries = entries;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loading = false;
        _error = friendlyError(error);
      });
    }
  }

  String _parentOf(String path) {
    final parent = parentRemote(path);
    final root = widget.session.rootPath;
    if (root != '/' && parent.length < root.length) return root;
    return parent;
  }

  Future<void> _goUp() async {
    if (_path == widget.session.rootPath) {
      final switchServer = widget.onSwitchServer;
      if (switchServer != null) {
        switchServer();
        return;
      }
      if (context.mounted) Navigator.pop(context);
      return;
    }
    await _load(_parentOf(_path));
  }

  void _switchServer() {
    widget.onSwitchServer?.call();
  }

  void _openLibrary() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const LibraryScreen()));
  }

  void _toast(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  bool _guardWrite() {
    if (widget.session.canMutate(_path)) return true;
    _toast('请先进入一个共享，再新建、上传或发送图片。');
    return false;
  }

  Future<void> _open(RemoteEntry entry) async {
    if (entry.kind == EntryKind.file) {
      await _preview(entry);
      return;
    }
    if (entry.kind == EntryKind.directory) {
      await _load(entry.path);
      return;
    }
    setState(() => _loading = true);
    try {
      final children = await widget.session.list(entry.path);
      if (!mounted) return;
      setState(() {
        _path = normalizeRemote(entry.path);
        _entries = children;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      await _preview(entry);
    }
  }

  Future<void> _preview(RemoteEntry entry) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PreviewScreen(session: widget.session, entry: entry),
      ),
    );
  }

  Future<void> _createFolder() async {
    if (!_guardWrite()) return;
    final name = await showNameDialog(
      context: context,
      title: '新建文件夹',
      confirm: '创建',
      hint: '文件夹名称',
    );
    if (name == null || !mounted) return;
    try {
      await showProgressTask(
        context: context,
        title: '正在创建',
        task: (_, _) => widget.session.createFolder(joinRemote(_path, name)),
      );
      await _load(_path);
    } catch (error) {
      if (mounted) _toast(friendlyError(error));
    }
  }

  Future<void> _rename(RemoteEntry entry) async {
    final name = await showNameDialog(
      context: context,
      title: '重命名',
      confirm: '保存',
      initial: entry.name,
    );
    if (name == null || name == entry.name || !mounted) return;
    try {
      await showProgressTask(
        context: context,
        title: '正在重命名',
        task: (_, _) => widget.session.rename(entry, name),
      );
      await _load(_path);
    } catch (error) {
      if (mounted) _toast(friendlyError(error));
    }
  }

  Future<void> _delete(RemoteEntry entry) async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: entry.isDirectory ? '删除文件夹' : '删除文件',
      message: entry.isDirectory
          ? '删除「${entry.name}」及其里面的内容？此操作无法撤销。'
          : '删除「${entry.name}」？此操作无法撤销。',
      confirm: '删除',
      danger: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await showProgressTask(
        context: context,
        title: '正在删除',
        task: (_, _) => widget.session.delete(entry),
      );
      await _load(_path);
    } catch (error) {
      if (mounted) _toast(friendlyError(error));
    }
  }

  Future<void> _download(RemoteEntry entry) async {
    try {
      // system/custom destinations need a one-time SAF grant first.
      if (!await ensureDownloadLocation(context)) return;
      if (!mounted) return;

      // Always stage in the app-private folder, then deliver to the target.
      final directory = await downloadDirectory();
      final destination = await uniqueLocalFile(directory, entry.name);
      if (!mounted) return;
      await showProgressTask(
        context: context,
        title: '正在下载',
        cancellable: true,
        task: (onProgress, isCancelled) => downloadCompletely(
          destination: destination,
          write: (partial) => widget.session.download(
            entry,
            partial,
            onProgress,
            isCancelled: isCancelled,
          ),
        ),
      );
      if (!mounted) return;

      final delivered = await deliverDownloadedFile(
        context: context,
        stagingFile: destination,
        displayName: entry.name,
      );
      if (!mounted) return;
      final openTarget = delivered == null ? destination : File(delivered);
      final location = delivered == null ? '应用私有目录' : '已授权的文件夹';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已保存到$location'),
          action: delivered == null
              ? SnackBarAction(
                  label: '打开',
                  onPressed: () async {
                    final message = await openLocalFile(openTarget);
                    if (message != null && mounted) _toast(message);
                  },
                )
              : null,
        ),
      );
    } on TransferCancelled {
      return;
    } catch (error) {
      if (mounted) _toast(friendlyError(error));
    }
  }

  Future<void> _uploadFiles(List<File> files, List<String> names) async {
    Object? failure;
    try {
      for (var index = 0; index < files.length; index++) {
        if (!mounted) return;
        final name = names[index];
        await showProgressTask(
          context: context,
          title: files.length == 1
              ? '正在上传 $name'
              : '正在上传 ${index + 1}/${files.length}',
          cancellable: true,
          task: (onProgress, isCancelled) => widget.session.upload(
            files[index],
            _path,
            name,
            onProgress,
            isCancelled: isCancelled,
          ),
        );
      }
    } on TransferCancelled {
      if (mounted) await _load(_path);
      return;
    } catch (error) {
      failure = error;
    }
    if (mounted) await _load(_path);
    if (failure != null) throw failure;
  }

  Future<void> _pickFiles() async {
    if (!_guardWrite()) return;
    try {
      final picked = await FilePicker.pickFiles(dialogTitle: '选择要上传的文件');
      if (picked.isEmpty || !mounted) return;
      final files = <File>[];
      final names = <String>[];
      for (final item in picked) {
        files.add(await materializePickedFile(item));
        names.add(item.name);
      }
      await _uploadFiles(files, names);
    } catch (error) {
      if (mounted) _toast(friendlyError(error));
    }
  }

  Future<void> _sendImages() async {
    if (!_guardWrite()) return;
    final source = await showModalBottomSheet<ImageSource>(
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
              ListTile(
                leading: const Icon(Icons.photo_library_rounded),
                title: const Text('从相册选择'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_rounded),
                title: const Text('拍照'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
            ],
          ),
        );
      },
    );
    if (source == null || !mounted) return;
    try {
      final picker = ImagePicker();
      final images = source == ImageSource.gallery
          ? await picker.pickMultiImage(imageQuality: 92)
          : [
              ?await picker.pickImage(
                source: ImageSource.camera,
                imageQuality: 92,
              ),
            ];
      if (images.isEmpty || !mounted) return;
      await _uploadFiles(
        images.map((image) => File(image.path)).toList(),
        images.map((image) => image.name).toList(),
      );
    } catch (error) {
      if (mounted) _toast(friendlyError(error));
    }
  }

  Future<void> _showActions(RemoteEntry entry) async {
    final palette = AppPalette.of(context);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: palette.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: FileGlyph(entry: entry, size: 42),
                title: Text(
                  entry.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(_meta(entry)),
              ),
              ListTile(
                leading: const Icon(Icons.open_in_new_rounded),
                title: const Text('打开'),
                onTap: () {
                  Navigator.pop(context);
                  _open(entry);
                },
              ),
              if (!entry.isDirectory && !entry.isShare)
                ListTile(
                  leading: const Icon(Icons.download_rounded),
                  title: const Text('下载到本地'),
                  onTap: () {
                    Navigator.pop(context);
                    _download(entry);
                  },
                ),
              if (!entry.isShare)
                ListTile(
                  leading: const Icon(Icons.drive_file_rename_outline_rounded),
                  title: const Text('重命名'),
                  onTap: () {
                    Navigator.pop(context);
                    _rename(entry);
                  },
                ),
              if (!entry.isShare)
                ListTile(
                  leading: Icon(
                    Icons.delete_outline_rounded,
                    color: palette.danger,
                  ),
                  title: Text('删除', style: TextStyle(color: palette.danger)),
                  onTap: () {
                    Navigator.pop(context);
                    _delete(entry);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.info_outline_rounded),
                title: const Text('详情'),
                onTap: () {
                  Navigator.pop(context);
                  _details(entry);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _details(RemoteEntry entry) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('详情'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _detailLine('名称', entry.name),
              _detailLine(
                '类型',
                entry.isShare ? '共享' : familyLabel(familyOf(entry)),
              ),
              _detailLine(
                '大小',
                entry.isDirectory ? '—' : formatBytes(entry.size),
              ),
              _detailLine('修改时间', formatDate(entry.modified)),
              _detailLine('路径', entry.path),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: entry.path));
                if (context.mounted) Navigator.pop(context);
                if (mounted) _toast('路径已复制');
              },
              child: const Text('复制路径'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final entries = _visible;
    return PopScope(
      canPop: _path == widget.session.rootPath,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goUp();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip:
                _path == widget.session.rootPath &&
                    widget.onSwitchServer != null
                ? '切换服务器'
                : '返回',
            onPressed:
                _path == widget.session.rootPath &&
                    widget.onSwitchServer != null
                ? _switchServer
                : _goUp,
            icon: Icon(
              _path == widget.session.rootPath && widget.onSwitchServer != null
                  ? Icons.dns_rounded
                  : Icons.arrow_back_rounded,
            ),
          ),
          toolbarHeight: 72,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.account.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                '${widget.session.transportLabel} · ${widget.account.host}',
                style: TextStyle(
                  color: palette.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          actions: [
            PopupMenuButton<String>(
              tooltip: '更多',
              onSelected: (value) {
                switch (value) {
                  case 'server':
                    _switchServer();
                  case 'library':
                    _openLibrary();
                  case 'location':
                    showDownloadLocationSheet(context);
                  case 'theme-system':
                  case 'theme-light':
                  case 'theme-dark':
                    applyThemeChoice(context, value);
                }
              },
              itemBuilder: (context) => [
                if (widget.onSwitchServer != null)
                  const PopupMenuItem(value: 'server', child: Text('切换服务器')),
                const PopupMenuItem(value: 'library', child: Text('本地文件')),
                const PopupMenuItem(value: 'location', child: Text('下载位置')),
                ...themeMenuItems(ThemeScope.of(context).mode),
              ],
            ),
            IconButton(
              tooltip: '搜索',
              onPressed: () => setState(() => _searching = !_searching),
              icon: Icon(
                _searching ? Icons.search_off_rounded : Icons.search_rounded,
              ),
            ),
            PopupMenuButton<_SortMode>(
              tooltip: '排序',
              initialValue: _sort,
              onSelected: (mode) => setState(() => _sort = mode),
              itemBuilder: (context) => const [
                PopupMenuItem(value: _SortMode.name, child: Text('按名称')),
                PopupMenuItem(value: _SortMode.modified, child: Text('按修改时间')),
                PopupMenuItem(value: _SortMode.size, child: Text('按大小')),
              ],
              icon: const Icon(Icons.sort_rounded),
            ),
            IconButton(
              tooltip: _grid ? '列表' : '宫格',
              onPressed: () => setState(() => _grid = !_grid),
              icon: Icon(
                _grid ? Icons.view_list_rounded : Icons.grid_view_rounded,
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            if (_searching)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  controller: _query,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: '筛选当前文件夹',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            SizedBox(
              height: 42,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final crumb in breadcrumbs(
                    widget.session.rootPath,
                    _path,
                  ))
                    TextButton(
                      onPressed: crumb.path == _path
                          ? null
                          : () => _load(crumb.path),
                      child: Text(crumb.label),
                    ),
                ],
              ),
            ),
            Expanded(child: _body(palette, entries)),
          ],
        ),
        bottomNavigationBar: Material(
          color: palette.card,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  _BarAction(
                    icon: Icons.create_new_folder_rounded,
                    label: '新建',
                    onTap: _createFolder,
                  ),
                  _BarAction(
                    icon: Icons.upload_file_rounded,
                    label: '上传',
                    onTap: _pickFiles,
                  ),
                  _BarAction(
                    icon: Icons.add_photo_alternate_rounded,
                    label: '发送图片',
                    onTap: _sendImages,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(AppPalette palette, List<RemoteEntry> entries) {
    if (_loading && _entries.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => _load(_path),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    if (entries.isEmpty) {
      return Center(
        child: Text(
          _query.text.trim().isEmpty ? '这个文件夹是空的' : '没有匹配的文件',
          style: TextStyle(color: palette.muted),
        ),
      );
    }
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final list = _grid
        ? GridView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: MediaQuery.sizeOf(context).width > 700 ? 4 : 3,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              mainAxisExtent: 168 * textScale.clamp(1, 1.35),
            ),
            itemCount: entries.length,
            itemBuilder: (context, index) => _GridTile(
              entry: entries[index],
              onTap: () => _open(entries[index]),
              onLongPress: () => _showActions(entries[index]),
            ),
          )
        : ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            itemCount: entries.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) => _ListTile(
              entry: entries[index],
              meta: _meta(entries[index]),
              onTap: () => _open(entries[index]),
              onMore: () => _showActions(entries[index]),
            ),
          );
    return RefreshIndicator(onRefresh: () => _load(_path), child: list);
  }

  String _meta(RemoteEntry entry) {
    if (entry.isShare) return '共享';
    if (entry.isDirectory) {
      return entry.modified == null
          ? '文件夹'
          : '文件夹 · ${formatDate(entry.modified)}';
    }
    final size = entry.size > 0
        ? formatBytes(entry.size)
        : familyLabel(familyOf(entry));
    if (entry.modified == null) return size;
    return '$size · ${formatDate(entry.modified)}';
  }

  Widget _detailLine(String label, String value) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: palette.muted, fontSize: 12)),
          const SizedBox(height: 2),
          Text(value),
        ],
      ),
    );
  }
}

class _BarAction extends StatelessWidget {
  const _BarAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: palette.accent),
              const SizedBox(height: 4),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ListTile extends StatelessWidget {
  const _ListTile({
    required this.entry,
    required this.meta,
    required this.onTap,
    required this.onMore,
  });

  final RemoteEntry entry;
  final String meta;
  final VoidCallback onTap;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Material(
      color: palette.card,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        onLongPress: onMore,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: palette.line),
          ),
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          child: Row(
            children: [
              FileGlyph(entry: entry),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: palette.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onMore,
                icon: const Icon(Icons.more_horiz_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GridTile extends StatelessWidget {
  const _GridTile({
    required this.entry,
    required this.onTap,
    required this.onLongPress,
  });

  final RemoteEntry entry;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Material(
      color: palette.card,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: palette.line),
          ),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FileGlyph(entry: entry, size: 48),
              const Spacer(),
              Text(
                entry.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  height: 1.15,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                entry.isDirectory
                    ? (entry.isShare ? '共享' : '文件夹')
                    : (entry.size > 0
                          ? formatBytes(entry.size)
                          : familyLabel(familyOf(entry))),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.muted,
                  fontSize: 11,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
