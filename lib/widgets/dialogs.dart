import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../services/download_location.dart';
import '../services/download_location_scope.dart';
import '../services/local_files.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../utils/paths.dart';

Future<bool> showConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  String confirm = '确定',
  bool danger = false,
}) async {
  final palette = AppPalette.of(context);
  final result = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: danger
                ? FilledButton.styleFrom(
                    backgroundColor: palette.danger,
                    foregroundColor: Colors.white,
                  )
                : null,
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirm),
          ),
        ],
      );
    },
  );
  return result ?? false;
}

Future<String?> showNameDialog({
  required BuildContext context,
  required String title,
  required String confirm,
  String initial = '',
  String hint = '名称',
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _NameDialog(
      title: title,
      confirm: confirm,
      initial: initial,
      hint: hint,
    ),
  );
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.confirm,
    required this.initial,
    required this.hint,
  });

  final String title;
  final String confirm;
  final String initial;
  final String hint;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final error = validateEntryName(_controller.text);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(context, _controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(hintText: widget.hint, errorText: _error),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.confirm)),
      ],
    );
  }
}

Future<T> showProgressTask<T>({
  required BuildContext context,
  required String title,
  bool cancellable = false,
  required Future<T> Function(
    void Function(int transferred, int total) onProgress,
    bool Function() isCancelled,
  )
  task,
}) async {
  final progress = ValueNotifier<(int, int)>((0, 0));
  final cancelFlag = ValueNotifier(false);
  final shown = Completer<BuildContext>();
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      if (!shown.isCompleted) shown.complete(dialogContext);
      return PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text(title),
          content: ValueListenableBuilder<(int, int)>(
            valueListenable: progress,
            builder: (context, value, _) {
              final total = value.$2;
              final ratio = total > 0
                  ? (value.$1 / total).clamp(0.0, 1.0)
                  : null;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(value: ratio),
                  const SizedBox(height: 12),
                  ValueListenableBuilder<bool>(
                    valueListenable: cancelFlag,
                    builder: (context, cancelled, _) {
                      return Text(
                        cancelled
                            ? '正在取消'
                            : total > 0
                            ? '${formatBytes(value.$1)} / ${formatBytes(total)}'
                            : '正在处理',
                      );
                    },
                  ),
                ],
              );
            },
          ),
          actions: [
            if (cancellable)
              ValueListenableBuilder<bool>(
                valueListenable: cancelFlag,
                builder: (context, cancelled, _) {
                  return TextButton(
                    onPressed: cancelled ? null : () => cancelFlag.value = true,
                    child: const Text('取消'),
                  );
                },
              ),
          ],
        ),
      );
    },
  );
  final dialogContext = await shown.future;
  try {
    return await task(
      (transferred, total) => progress.value = (transferred, total),
      () => cancelFlag.value,
    );
  } finally {
    if (dialogContext.mounted) Navigator.of(dialogContext).pop();
    await WidgetsBinding.instance.endOfFrame;
    progress.dispose();
    cancelFlag.dispose();
  }
}

/// Ensures a writable destination is configured before a download starts.
///
/// For system/custom modes without a valid SAF grant, explains why a one-time
/// folder choice is needed and opens the system folder picker. Returns true
/// when downloading may proceed, false when the user cancelled.
Future<bool> ensureDownloadLocation(BuildContext context) async {
  final store = DownloadLocationScope.of(context);
  if (store.mode == DownloadLocation.private) return true;
  if (await store.hasValidGrant()) return true;
  if (!context.mounted) return false;

  final understood = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(
        store.mode == DownloadLocation.system ? '选择「下载」文件夹' : '选择保存位置',
      ),
      content: Text(
        store.mode == DownloadLocation.system
            ? 'Android 不允许应用直接写入系统下载文件夹。请在接下来的系统窗口中选中「Download / 下载」文件夹并允许访问，只需授权一次。'
            : '请在接下来的系统窗口中选择一个用于保存下载文件的文件夹并允许访问，只需授权一次。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('去选择'),
        ),
      ],
    ),
  );
  if (understood != true) return false;
  if (!context.mounted) return false;
  final picked = await store.chooseDirectory(mode: store.mode);
  return picked != null;
}

/// Bottom sheet for choosing the default download location.
Future<void> showDownloadLocationSheet(BuildContext context) async {
  final store = DownloadLocationScope.of(context);
  final palette = AppPalette.of(context);
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '下载位置',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: palette.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '新下载的文件会保存到这里。部分 Android 版本需要授权一次文件夹访问。',
              style: TextStyle(color: palette.muted, height: 1.4),
            ),
            const SizedBox(height: 16),
            for (final mode in DownloadLocation.values)
              _LocationTile(
                mode: mode,
                selected: store.mode == mode,
                subtitle:
                    mode == DownloadLocation.custom &&
                        store.directoryName != null
                    ? '${store.directoryName}'
                    : null,
                onTap: () async {
                  if (mode == DownloadLocation.private) {
                    await store.setMode(mode);
                  } else {
                    final haveGrant =
                        store.mode == mode && await store.hasValidGrant();
                    if (!haveGrant) {
                      final picked = await store.chooseDirectory(mode: mode);
                      if (picked == null) return;
                    } else {
                      await store.setMode(mode);
                    }
                  }
                  if (context.mounted) Navigator.pop(context);
                },
              ),
          ],
        ),
      ),
    ),
  );
}

class _LocationTile extends StatelessWidget {
  const _LocationTile({
    required this.mode,
    required this.selected,
    required this.onTap,
    this.subtitle,
  });

  final DownloadLocation mode;
  final bool selected;
  final VoidCallback onTap;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(switch (mode) {
        DownloadLocation.system => Icons.download_rounded,
        DownloadLocation.private => Icons.phone_android_rounded,
        DownloadLocation.custom => Icons.folder_open_rounded,
      }, color: selected ? palette.accent : palette.muted),
      title: Text(
        mode.label,
        style: TextStyle(
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: palette.ink,
        ),
      ),
      subtitle: Text(
        [mode.description, ?subtitle].join(' · '),
        style: TextStyle(color: palette.muted, fontSize: 12),
      ),
      trailing: selected
          ? Icon(Icons.check_circle_rounded, color: palette.accent)
          : null,
      onTap: onTap,
    );
  }
}

/// Delivers a downloaded staging file to the configured destination.
///
/// Returns the path to report to the user, or null if delivery failed (in
/// which case the file stays in the private folder).
Future<String?> deliverDownloadedFile({
  required BuildContext context,
  required File stagingFile,
  required String displayName,
}) async {
  final store = DownloadLocationScope.of(context);
  if (store.mode == DownloadLocation.private) return null;
  if (!await store.hasValidGrant()) return null;
  return store.deliver(
    source: stagingFile,
    displayName: displayName,
    privateDirectory: downloadDirectory,
  );
}
