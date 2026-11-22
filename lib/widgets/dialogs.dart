import 'dart:async';

import 'package:flutter/material.dart';

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
