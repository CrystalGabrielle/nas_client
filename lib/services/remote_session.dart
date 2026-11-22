import 'dart:async';
import 'dart:io';

import '../models/models.dart';
import 'ftp_session.dart';
import 'smb_session.dart';

typedef TransferProgress = void Function(int transferred, int total);

/// The user left a download or upload before it finished.
class TransferCancelled implements Exception {
  const TransferCancelled();
}

/// Reads one remote file in ranges. Implementations must allow [copy] to stop
/// when [onBytes] throws, so a player can seek without finishing the earlier
/// request.
abstract class RangeReader {
  Future<void> copy({
    required int start,
    int? endExclusive,
    required void Function(List<int> bytes) onBytes,
  });

  Future<void> close();
}

class OpQueue {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() action) {
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
}

abstract class RemoteSession {
  RemoteSession(this.account);

  final SavedAccount account;
  final OpQueue queue = OpQueue();

  RemoteProtocol get protocol => account.protocol;

  ConnectionMode get resolvedMode;

  String get transportLabel;

  String get rootPath;

  bool canMutate(String path) {
    if (protocol == RemoteProtocol.smb && (path.isEmpty || path == '/')) {
      return false;
    }
    return true;
  }

  Future<List<RemoteEntry>> list(String path);

  Future<void> createFolder(String path);

  Future<void> delete(RemoteEntry entry);

  Future<void> rename(RemoteEntry entry, String newName);

  Future<void> download(
    RemoteEntry entry,
    File destination,
    TransferProgress? onProgress, {
    bool Function()? isCancelled,
  });

  /// Opens a reader that can fetch byte ranges without saving the whole file.
  Future<RangeReader> openRange(RemoteEntry entry);

  Future<void> upload(
    File local,
    String directory,
    String remoteName,
    TransferProgress? onProgress, {
    bool Function()? isCancelled,
  });

  Future<void> close();

  static Future<RemoteSession> open(SavedAccount account) {
    return switch (account.protocol) {
      RemoteProtocol.smb => SmbSession.open(account),
      RemoteProtocol.ftp => FtpSession.open(account),
    };
  }
}
