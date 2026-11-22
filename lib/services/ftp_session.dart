import 'dart:async';
import 'dart:io';

import 'package:ftpconnect/ftpconnect.dart';
// Passive data sockets are not exposed for ranged reads.
// ignore: implementation_imports
import 'package:ftpconnect/src/ftp_socket.dart';
// ignore: implementation_imports
import 'package:ftpconnect/src/utils.dart';

import '../models/models.dart';
import '../utils/paths.dart';
import 'protocol_plan.dart';
import 'remote_session.dart';

class FtpSession extends RemoteSession {
  FtpSession._(
    this._ftp,
    super.account,
    this._root,
    this.resolvedMode,
    this.transportLabel,
  );

  final FTPConnect _ftp;
  final String _root;
  String _cwd = '';
  int _listStage = 0;

  @override
  final ConnectionMode resolvedMode;

  @override
  final String transportLabel;

  @override
  String get rootPath => _root;

  static Future<FtpSession> open(SavedAccount account) async {
    final plan = ftpPlan(account.mode, account.port);
    Object? last;
    final tried = <String>[];
    for (final security in plan) {
      tried.add(security.label);
      final ftp = FTPConnect(
        account.host,
        port: ftpPort(security, account.port),
        user: account.username.isEmpty ? 'anonymous' : account.username,
        pass: account.password,
        timeout: 12,
        securityType: switch (security) {
          FtpSecurity.plain => SecurityType.ftp,
          FtpSecurity.explicitTls => SecurityType.ftpes,
          FtpSecurity.implicitTls => SecurityType.ftps,
        },
      );
      ftp.transferMode = TransferMode.passive;
      try {
        final connected = await ftp.connect();
        if (!connected) throw Exception('登录失败');
        try {
          await ftp.setTransferType(TransferType.binary);
        } catch (_) {}
        ftp.listCommand = ListCommand.list;
        var root = '/';
        try {
          root = normalizeRemote(await ftp.currentDirectory());
        } catch (_) {}
        return FtpSession._(ftp, account, root, security.mode, security.label);
      } catch (error) {
        last = error;
        try {
          await ftp.disconnect();
        } catch (_) {}
        if (isAuthenticationFailure(error)) {
          throw NegotiateFailure(error, tried);
        }
      }
    }
    throw NegotiateFailure(last ?? Exception('图片设备登录失败'), tried);
  }

  Future<void> _use(String path) async {
    final target = normalizeRemote(path.isEmpty ? rootPath : path);
    if (target == _cwd) return;
    final moved = await _ftp.changeDirectory(target);
    if (!moved) {
      throw Exception('无法打开目录');
    }
    _cwd = target;
  }

  Future<List<FTPEntry>> _entries() async {
    while (true) {
      try {
        return await _ftp.listDirectoryContent();
      } catch (_) {
        if (_listStage >= 2) rethrow;
        _listStage++;
        _ftp.listCommand = switch (_listStage) {
          1 => ListCommand.mlsd,
          _ => ListCommand.nlst,
        };
      }
    }
  }

  @override
  Future<List<RemoteEntry>> list(String path) {
    return queue.run(() async {
      final directory = normalizeRemote(path.isEmpty ? rootPath : path);
      await _use(directory);
      final entries = await _entries();
      return entries
          .where(
            (entry) =>
                entry.name.isNotEmpty &&
                entry.name != '.' &&
                entry.name != '..',
          )
          .map((entry) {
            return RemoteEntry(
              name: entry.name,
              path: joinRemote(directory, entry.name),
              kind: switch (entry.type) {
                FTPEntryType.dir => EntryKind.directory,
                FTPEntryType.file => EntryKind.file,
                FTPEntryType.link || FTPEntryType.unknown => EntryKind.unknown,
              },
              size: entry.size ?? 0,
              modified: entry.modifyTime,
            );
          })
          .toList();
    });
  }

  @override
  Future<void> createFolder(String path) {
    return queue.run(() async {
      final directory = parentRemote(path);
      final parent = directory.length < rootPath.length ? rootPath : directory;
      await _use(parent);
      final created = await _ftp.makeDirectory(path.split('/').last);
      if (!created) throw Exception('文件夹没有创建成功');
    });
  }

  @override
  Future<void> delete(RemoteEntry entry) {
    return queue.run(() async {
      await _use(parentRemote(entry.path));
      if (entry.kind == EntryKind.directory) {
        final removed = await _ftp.deleteDirectory(entry.name);
        _cwd = '';
        if (!removed) throw Exception('文件夹没有删除');
        return;
      }
      final removed = await _ftp.deleteFile(entry.name);
      if (removed) return;
      if (entry.kind == EntryKind.unknown) {
        final removedDir = await _ftp.deleteDirectory(entry.name);
        _cwd = '';
        if (removedDir) return;
      }
      throw Exception('文件没有删除');
    });
  }

  @override
  Future<void> rename(RemoteEntry entry, String newName) {
    return queue.run(() async {
      await _use(parentRemote(entry.path));
      final renamed = await _ftp.rename(entry.name, newName);
      if (!renamed) throw Exception('重命名没有成功');
    });
  }

  @override
  Future<void> download(
    RemoteEntry entry,
    File destination,
    TransferProgress? onProgress, {
    bool Function()? isCancelled,
  }) {
    return queue.run(() async {
      if (isCancelled?.call() ?? false) throw const TransferCancelled();
      await _use(parentRemote(entry.path));
      final saved = await _ftp.downloadFile(
        entry.name,
        destination,
        onProgress: (progress, received, total) {
          if (isCancelled?.call() ?? false) throw const TransferCancelled();
          onProgress?.call(received, total > 0 ? total : entry.size);
        },
      );
      if (isCancelled?.call() ?? false) throw const TransferCancelled();
      if (!saved) throw Exception('下载没有完成');
    });
  }

  @override
  Future<void> upload(
    File local,
    String directory,
    String remoteName,
    TransferProgress? onProgress, {
    bool Function()? isCancelled,
  }) {
    return queue.run(() async {
      if (isCancelled?.call() ?? false) throw const TransferCancelled();
      await _use(directory);
      final saved = await _ftp.uploadFile(
        local,
        sRemoteName: remoteName,
        onProgress: (progress, sent, total) {
          if (isCancelled?.call() ?? false) throw const TransferCancelled();
          onProgress?.call(sent, total);
        },
      );
      if (isCancelled?.call() ?? false) throw const TransferCancelled();
      if (!saved) throw Exception('上传没有完成');
    });
  }

  @override
  Future<RangeReader> openRange(RemoteEntry entry) {
    return _FtpRangeReader.connect(
      account: account,
      mode: resolvedMode,
      directory: parentRemote(entry.path),
      fileName: entry.name,
    );
  }

  @override
  Future<void> close() {
    return queue.run(() async {
      try {
        await _ftp.disconnect();
      } catch (_) {}
    });
  }
}

class _FtpRangeReader implements RangeReader {
  _FtpRangeReader(this._account, this._mode, this._directory, this._fileName);

  final SavedAccount _account;
  final ConnectionMode _mode;
  final String _directory;
  final String _fileName;
  FTPSocket? _control;
  Socket? _data;
  var _closed = false;
  Future<void> _tail = Future<void>.value();

  static Future<_FtpRangeReader> connect({
    required SavedAccount account,
    required ConnectionMode mode,
    required String directory,
    required String fileName,
  }) async {
    final reader = _FtpRangeReader(account, mode, directory, fileName);
    await reader._ensure();
    return reader;
  }

  SecurityType get _security {
    return switch (_mode) {
      ConnectionMode.ftpes => SecurityType.ftpes,
      ConnectionMode.ftps => SecurityType.ftps,
      _ => SecurityType.ftp,
    };
  }

  Future<T> _sync<T>(Future<T> Function() action) {
    final gate = _tail;
    final done = Completer<void>();
    _tail = done.future;
    return () async {
      await gate;
      try {
        return await action();
      } finally {
        if (!done.isCompleted) done.complete();
      }
    }();
  }

  Future<void> _ensure() async {
    if (_control != null) return;
    final socket = FTPSocket(
      _account.host,
      _account.port,
      _security,
      Logger(isEnabled: false),
      20,
    );
    final user = _account.username.isEmpty ? 'anonymous' : _account.username;
    final connected = await socket.connect(user, _account.password);
    if (!connected) {
      throw Exception('视频连接没有建立');
    }
    await socket.setTransferType(TransferType.binary);
    if (_directory.isNotEmpty && _directory != '/') {
      final reply = await socket.sendCommand('CWD $_directory');
      if (!reply.isSuccessCode()) {
        try {
          await socket.disconnect();
        } catch (_) {}
        throw Exception('无法打开视频所在目录');
      }
    }
    _control = socket;
  }

  Future<void> _dropControl() async {
    final socket = _control;
    _control = null;
    if (socket == null) return;
    try {
      await socket.disconnect();
    } catch (_) {}
  }

  @override
  Future<void> copy({
    required int start,
    int? endExclusive,
    required void Function(List<int> bytes) onBytes,
  }) {
    return _sync(() async {
      if (_closed) return;
      await _ensure();
      final control = _control;
      if (control == null) return;
      var synced = false;
      var transferStarted = false;
      try {
        final passive = await control.sendCommand('PASV');
        if (!passive.isSuccessCode()) {
          throw Exception('服务器没有打开数据端口');
        }
        if (start > 0) {
          final rest = await control.sendCommand('REST $start');
          if (!rest.isSuccessCode() && rest.code != 350) {
            throw Exception('服务器不支持从中间读取视频');
          }
        }
        final port = Utils.parsePort(passive.message, false);
        final data = await Socket.connect(
          _account.host,
          port,
          timeout: const Duration(seconds: 12),
        );
        try {
          data.setOption(SocketOption.tcpNoDelay, true);
        } catch (_) {}
        _data = data;
        control.sendCommandWithoutWaitingResponse('RETR $_fileName');
        transferStarted = true;
        final opened = await control.readResponse();
        final accepted =
            opened.code == 150 || opened.code == 125 || opened.isSuccessCode();
        if (!accepted) {
          throw Exception('视频没有开始传输');
        }
        synced = opened.code == 226 || opened.message.contains('226');
        var remaining = endExclusive == null ? null : endExclusive - start;
        await for (final chunk in data) {
          if (_closed || remaining == 0) break;
          if (remaining == null || chunk.length <= remaining) {
            onBytes(chunk);
            if (remaining != null) remaining -= chunk.length;
          } else {
            onBytes(chunk.sublist(0, remaining));
            remaining = 0;
          }
          if (remaining == 0) break;
        }
      } catch (_) {
        await _dropControl();
        rethrow;
      } finally {
        final data = _data;
        _data = null;
        try {
          await data?.close();
        } catch (_) {}
        if (transferStarted && !synced && _control != null) {
          try {
            await _control!.readResponse();
          } catch (_) {
            await _dropControl();
          }
        }
      }
    });
  }

  @override
  Future<void> close() async {
    _closed = true;
    try {
      _data?.destroy();
    } catch (_) {}
    _data = null;
    await _dropControl();
  }
}
