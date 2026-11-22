import 'dart:io';

import 'package:smb_connect/smb_connect.dart';
// The public constructor stops negotiation at SMB 2.1.
// ignore: implementation_imports
import 'package:smb_connect/src/connect/impl/base_configuration.dart';
// ignore: implementation_imports
import 'package:smb_connect/src/dialect_version.dart';
// ignore: implementation_imports
import 'package:smb_connect/src/smb/ntlm_password_authenticator.dart';

import '../models/models.dart';
import '../utils/format.dart';
import '../utils/paths.dart';
import 'protocol_plan.dart';
import 'remote_session.dart';
import 'smb_io.dart';

class SmbSession extends RemoteSession {
  SmbSession._(
    this._smb,
    super.account,
    this.resolvedMode,
    this.transportLabel,
  );

  final SmbConnect _smb;

  @override
  final ConnectionMode resolvedMode;

  @override
  final String transportLabel;

  @override
  String get rootPath => '/';

  static Future<SmbSession> open(SavedAccount account) async {
    final plan = smbPlan(account.mode);
    Object? last;
    final tried = <String>[];
    for (final dialect in plan) {
      tried.add(dialect.label);
      try {
        final smb = await _connect(account, dialect);
        return SmbSession._(smb, account, dialect.mode, _label(smb, dialect));
      } catch (error) {
        last = error;
        if (isAuthenticationFailure(error)) {
          throw NegotiateFailure(error, tried);
        }
      }
    }
    throw NegotiateFailure(last ?? Exception('Samba 登录失败'), tried);
  }

  static Future<SmbConnect> _connect(SavedAccount account, SmbDialect dialect) {
    final credentials = NtlmPasswordAuthenticator(
      domain: account.domain,
      username: account.username,
      password: account.password,
    );
    return SmbConnect.connect(
      BaseConfiguration(
        credentials: credentials,
        username: account.username,
        password: account.password,
        domain: account.domain,
        bufferCacheSize: 0x1FFF,
        forceSmb1: dialect == SmbDialect.smb1,
        minimumVersion: dialect == SmbDialect.smb1
            ? DialectVersion.SMB1
            : DialectVersion.SMB202,
        maximumVersion: switch (dialect) {
          SmbDialect.smb3 => DialectVersion.SMB311,
          SmbDialect.smb2 => DialectVersion.SMB210,
          SmbDialect.smb1 => DialectVersion.SMB1,
        },
      ),
      account.host,
    );
  }

  static String _label(SmbConnect smb, SmbDialect dialect) {
    final name = smb.transport
        .getNegotiatedResponse()
        ?.getSelectedDialect()
        ?.name;
    return switch (name) {
      'SMB311' => 'SMB 3.1.1',
      'SMB302' => 'SMB 3.0.2',
      'SMB300' => 'SMB 3.0',
      'SMB210' => 'SMB 2.1',
      'SMB202' => 'SMB 2.0.2',
      'SMB1' => 'SMB 1',
      _ => dialect.label,
    };
  }

  @override
  Future<List<RemoteEntry>> list(String path) {
    return queue.run(() async {
      final normalized = normalizeRemote(path);
      if (normalized == '/') return _shares();
      final folder = await _smb.file(normalized);
      final files = await _smb.listFiles(folder);
      return files
          .where(
            (file) =>
                file.name.isNotEmpty && file.name != '.' && file.name != '..',
          )
          .map(
            (file) => RemoteEntry(
              name: file.name,
              path: normalizeRemote(file.path),
              kind: file.isDirectory() ? EntryKind.directory : EntryKind.file,
              size: file.size,
              modified: smbTimestamp(file.lastModified),
            ),
          )
          .toList();
    });
  }

  Future<List<RemoteEntry>> _shares() async {
    final shares = await _smb.listShares();
    return shares
        .where((share) => share.name.isNotEmpty && !share.name.endsWith(r'$'))
        .map((share) {
          final path = normalizeRemote(share.path);
          return RemoteEntry(
            name: share.name,
            path: path == '/' ? '/${share.name}' : path,
            kind: EntryKind.directory,
            size: 0,
            modified: smbTimestamp(share.lastModified),
            isShare: true,
          );
        })
        .toList();
  }

  @override
  Future<void> createFolder(String path) {
    return queue.run(() async {
      await _smb.createFolder(normalizeRemote(path));
    });
  }

  @override
  Future<void> delete(RemoteEntry entry) {
    return queue.run(() async {
      final file = await _smb.file(entry.path);
      await _smb.delete(file);
    });
  }

  @override
  Future<void> rename(RemoteEntry entry, String newName) {
    return queue.run(() async {
      final file = await _smb.file(entry.path);
      await _smb.rename(file, joinRemote(parentRemote(entry.path), newName));
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
      final file = await _smb.file(entry.path);
      final sink = destination.openWrite();
      var transferred = 0;
      var stopped = false;
      try {
        await readRemote(
          smb: _smb,
          file: file,
          start: 0,
          endExclusive: entry.size > 0 ? entry.size : null,
          knownSize: entry.size,
          isCancelled: () {
            stopped = isCancelled?.call() ?? false;
            return stopped;
          },
          onBytes: (chunk) {
            sink.add(chunk);
            transferred += chunk.length;
            onProgress?.call(transferred, entry.size);
          },
        );
        await sink.flush();
      } finally {
        await sink.close();
      }
      if (stopped) throw const TransferCancelled();
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
      final remote = await _smb.createFile(joinRemote(directory, remoteName));
      final sink = await _smb.openWrite(remote);
      final total = await local.length();
      var transferred = 0;
      try {
        await for (final chunk in fileBlocks(local, smbWriteChunk)) {
          if (isCancelled?.call() ?? false) throw const TransferCancelled();
          sink.add(chunk);
          transferred += chunk.length;
          onProgress?.call(transferred, total);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
    });
  }

  @override
  Future<RangeReader> openRange(RemoteEntry entry) async {
    return _SmbRangeReader(this, entry);
  }

  @override
  Future<void> close() {
    return queue.run(_smb.close);
  }
}

class _SmbRangeReader implements RangeReader {
  _SmbRangeReader(this._session, this._entry);

  final SmbSession _session;
  final RemoteEntry _entry;
  var _closed = false;

  @override
  Future<void> copy({
    required int start,
    int? endExclusive,
    required void Function(List<int> bytes) onBytes,
  }) {
    return _session.queue.run(() async {
      if (_closed) return;
      final file = await _session._smb.file(_entry.path);
      await readRemote(
        smb: _session._smb,
        file: file,
        start: start,
        endExclusive: endExclusive,
        knownSize: _entry.size,
        isCancelled: () => _closed,
        onBytes: onBytes,
      );
    });
  }

  @override
  Future<void> close() async {
    _closed = true;
  }
}
