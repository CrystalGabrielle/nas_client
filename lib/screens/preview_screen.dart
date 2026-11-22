import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/models.dart';
import '../services/local_files.dart';
import '../services/media_proxy.dart';
import '../services/remote_session.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/file_glyph.dart';

class PreviewScreen extends StatefulWidget {
  const PreviewScreen({super.key, required this.session, required this.entry});

  final RemoteSession session;
  final RemoteEntry entry;

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen>
    with WidgetsBindingObserver {
  File? _file;
  String? _text;
  String? _error;
  bool _loading = false;
  int _transferred = 0;
  int _total = 0;
  MediaProxy? _proxy;
  VideoPlayerController? _controller;
  bool _playing = false;
  bool _buffering = false;
  var _videoGeneration = 0;

  FileFamily get _family => familyOf(widget.entry);

  bool get _canRenderHere =>
      _family == FileFamily.image || _family == FileFamily.text;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_family == FileFamily.video) {
      _openVideo();
    } else if (_canRenderHere) {
      _download();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      final controller = _controller;
      if (controller != null && controller.value.isPlaying) {
        controller.pause();
      }
    }
  }

  @override
  void dispose() {
    _videoGeneration++;
    WidgetsBinding.instance.removeObserver(this);
    final controller = _controller;
    final proxy = _proxy;
    _controller = null;
    _proxy = null;
    if (controller != null) {
      controller.removeListener(_onVideo);
      controller.dispose();
    }
    proxy?.close();
    super.dispose();
  }

  Future<File?> _download() async {
    if (_file != null) return _file;
    setState(() {
      _loading = true;
      _error = null;
      _transferred = 0;
      _total = widget.entry.size;
    });
    try {
      final directory = await previewDirectory();
      final destination = previewFile(directory, widget.entry);
      if (!await destination.exists() || await destination.length() == 0) {
        await downloadCompletely(
          destination: destination,
          write: (partial) => widget.session.download(widget.entry, partial, (
            transferred,
            total,
          ) {
            if (!mounted) return;
            setState(() {
              _transferred = transferred;
              _total = total;
            });
          }),
        );
      }
      try {
        await destination.setLastModified(DateTime.now());
      } catch (_) {}
      String? text;
      if (_family == FileFamily.text) {
        text = await _readTextPreview(destination);
      }
      if (!mounted) return destination;
      setState(() {
        _file = destination;
        _text = text;
        _loading = false;
      });
      return destination;
    } catch (error) {
      if (!mounted) return null;
      setState(() {
        _loading = false;
        _error = friendlyError(error);
      });
      return null;
    }
  }

  Future<String> _readTextPreview(File file) async {
    const limit = 512 * 1024;
    final length = await file.length();
    final input = await file.open();
    try {
      final bytes = await input.read(length > limit ? limit : length);
      String text;
      try {
        text = utf8.decode(bytes);
      } catch (_) {
        text = latin1.decode(bytes);
      }
      if (length > limit) {
        text = '$text\n\n（后面的内容太长，没有全部显示）';
      }
      return text;
    } finally {
      await input.close();
    }
  }

  Future<void> _releaseVideo(
    VideoPlayerController? controller,
    MediaProxy? proxy,
  ) async {
    if (controller != null) {
      controller.removeListener(_onVideo);
      try {
        await controller.dispose();
      } catch (_) {}
    }
    try {
      await proxy?.close();
    } catch (_) {}
  }

  Future<void> _openVideo() async {
    final generation = ++_videoGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });
    MediaProxy? proxy;
    VideoPlayerController? controller;
    try {
      proxy = MediaProxy(session: widget.session, entry: widget.entry);
      final uri = await proxy.start();
      if (!mounted || generation != _videoGeneration) {
        await _releaseVideo(null, proxy);
        return;
      }
      controller = VideoPlayerController.networkUrl(uri);
      await controller.initialize().timeout(const Duration(seconds: 20));
      if (!mounted || generation != _videoGeneration) {
        await _releaseVideo(controller, proxy);
        return;
      }
      controller.addListener(_onVideo);
      await controller.play();
      if (!mounted || generation != _videoGeneration) {
        await _releaseVideo(controller, proxy);
        return;
      }
      setState(() {
        _proxy = proxy;
        _controller = controller;
        _loading = false;
        _playing = true;
        _buffering = controller!.value.isBuffering;
      });
    } on TimeoutException {
      await _releaseVideo(controller, proxy);
      if (!mounted || generation != _videoGeneration) return;
      setState(() {
        _loading = false;
        _proxy = null;
        _controller = null;
        _error = '这个视频没法直接播放';
      });
    } catch (error) {
      await _releaseVideo(controller, proxy);
      if (!mounted || generation != _videoGeneration) return;
      setState(() {
        _loading = false;
        _proxy = null;
        _controller = null;
        _error = friendlyError(error);
      });
    }
  }

  void _onVideo() {
    final controller = _controller;
    if (controller == null || !mounted) return;
    final value = controller.value;
    final playing = value.isPlaying;
    final buffering = value.isBuffering;
    final failed = value.hasError;
    if (playing == _playing &&
        buffering == _buffering &&
        (!failed || _error != null)) {
      return;
    }
    if (failed) controller.pause();
    setState(() {
      _playing = playing;
      _buffering = buffering;
      if (failed) _error = '这个视频没法直接播放';
    });
  }

  Future<void> _openExternal() async {
    final file = _file ?? await _download();
    if (file == null || !mounted) return;
    final message = await openLocalFile(file);
    if (message != null && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final darkViewer =
        (_family == FileFamily.image && _file != null) ||
        (_family == FileFamily.video && _controller != null);
    return Scaffold(
      backgroundColor: darkViewer ? const Color(0xFF100E0C) : palette.paper,
      appBar: AppBar(
        backgroundColor: darkViewer ? const Color(0xFF100E0C) : palette.paper,
        foregroundColor: darkViewer ? Colors.white : palette.ink,
        leading: TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            '关闭',
            style: TextStyle(color: darkViewer ? Colors.white : palette.ink),
          ),
        ),
        leadingWidth: 72,
        title: Text(
          widget.entry.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: _family == FileFamily.video ? '下载并用其他应用打开' : '用其他应用打开',
            onPressed: _loading ? null : _openExternal,
            icon: const Icon(Icons.open_in_new_rounded),
          ),
        ],
      ),
      body: _buildBody(palette, darkViewer),
    );
  }

  Widget _buildBody(AppPalette palette, bool darkViewer) {
    final controller = _controller;
    if (_error != null && _family == FileFamily.video) {
      return _message(palette, _error!, '下载并用其他应用打开', _openExternal);
    }
    if (_family == FileFamily.video && controller != null) {
      return _videoBody(controller);
    }
    if (_loading) {
      final ratio = _total > 0 ? (_transferred / _total).clamp(0.0, 1.0) : null;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FileGlyph(entry: widget.entry, size: 72),
              const SizedBox(height: 20),
              Text(
                _family == FileFamily.video
                    ? '正在连接 ${widget.entry.name}'
                    : '正在打开 ${widget.entry.name}',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: _family == FileFamily.video ? null : ratio,
              ),
              const SizedBox(height: 8),
              Text(
                _family == FileFamily.video
                    ? '边缓冲边播放，不会先下完整份视频'
                    : _total > 0
                    ? '${formatBytes(_transferred)} / ${formatBytes(_total)}'
                    : '请稍候',
                style: TextStyle(color: palette.muted),
              ),
            ],
          ),
        ),
      );
    }
    if (_error != null) {
      return _message(
        palette,
        _error!,
        _family == FileFamily.video ? '下载并用其他应用打开' : '重试',
        _family == FileFamily.video ? _openExternal : _download,
      );
    }
    if (_family == FileFamily.image && _file != null) {
      return InteractiveViewer(
        minScale: 0.8,
        maxScale: 4,
        child: Center(
          child: Image.file(
            _file!,
            fit: BoxFit.contain,
            cacheWidth:
                (MediaQuery.sizeOf(context).width *
                        MediaQuery.devicePixelRatioOf(context))
                    .round()
                    .clamp(720, 2400),
            errorBuilder: (context, error, stack) {
              return _message(
                palette,
                '这张图无法在应用内显示',
                '用其他应用打开',
                _openExternal,
                onDark: true,
              );
            },
          ),
        ),
      );
    }
    if (_family == FileFamily.text && _text != null) {
      return Scrollbar(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: SelectableText(
            _text!,
            style: const TextStyle(
              fontSize: 15,
              height: 1.5,
              fontFamily: 'monospace',
            ),
          ),
        ),
      );
    }
    return _message(
      palette,
      '${familyLabel(_family)}会交给手机里对应的应用打开，看完后回到这里点关闭。',
      '打开',
      _openExternal,
    );
  }

  Widget _videoBody(VideoPlayerController controller) {
    final aspect = controller.value.aspectRatio;
    final ratio = aspect.isFinite && aspect > 0 ? aspect : 16 / 9;
    final position = controller.value.position;
    final duration = controller.value.duration;
    return Column(
      children: [
        Expanded(
          child: Stack(
            alignment: Alignment.center,
            children: [
              Center(
                child: AspectRatio(
                  aspectRatio: ratio,
                  child: VideoPlayer(controller),
                ),
              ),
              if (_buffering)
                const CircularProgressIndicator(color: Colors.white),
            ],
          ),
        ),
        ColoredBox(
          color: const Color(0xFF1A1613),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    color: Colors.white,
                    onPressed: () {
                      if (controller.value.isPlaying) {
                        controller.pause();
                      } else {
                        controller.play();
                      }
                    },
                    icon: Icon(
                      _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    ),
                  ),
                  Text(
                    _clock(position),
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  Expanded(
                    child: VideoProgressIndicator(
                      controller,
                      allowScrubbing: true,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      colors: const VideoProgressColors(
                        playedColor: Color(0xFFFF8A5B),
                        bufferedColor: Color(0x66FFFFFF),
                        backgroundColor: Color(0x33FFFFFF),
                      ),
                    ),
                  ),
                  Text(
                    _clock(duration),
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _clock(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) return '$hours:$minutes:$seconds';
    return '$minutes:$seconds';
  }

  Widget _message(
    AppPalette palette,
    String text,
    String action,
    VoidCallback onPressed, {
    bool onDark = false,
  }) {
    final color = onDark ? Colors.white : palette.ink;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FileGlyph(entry: widget.entry, size: 84),
            const SizedBox(height: 18),
            Text(
              widget.entry.name,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: color,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${familyLabel(_family)} · ${widget.entry.size > 0 ? formatBytes(widget.entry.size) : '大小未知'}',
              style: TextStyle(color: onDark ? Colors.white70 : palette.muted),
            ),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(color: color, height: 1.4),
            ),
            const SizedBox(height: 18),
            FilledButton(onPressed: onPressed, child: Text(action)),
          ],
        ),
      ),
    );
  }
}
