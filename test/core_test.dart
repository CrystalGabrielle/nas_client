import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_client/models/models.dart';
import 'package:nas_client/services/byte_range.dart';
import 'package:nas_client/services/media_proxy.dart';
import 'package:nas_client/services/protocol_plan.dart';
import 'package:nas_client/services/remote_session.dart';
import 'package:flutter/material.dart';
import 'package:nas_client/theme/theme_controller.dart';
import 'package:nas_client/utils/cache_policy.dart';
import 'package:nas_client/utils/format.dart';
import 'package:nas_client/utils/lan.dart';
import 'package:nas_client/utils/paths.dart';

void main() {
  test('slash24 excludes self, network and broadcast', () {
    final hosts = hostsInSlash24('192.168.1.10');
    expect(hosts.length, 253);
    expect(hosts, isNot(contains('192.168.1.10')));
    expect(hosts, isNot(contains('192.168.1.0')));
    expect(hosts, contains('192.168.1.1'));
    expect(hosts, contains('192.168.1.254'));
  });

  test('private addresses stay inside lan ranges', () {
    expect(isPrivateIpv4('10.1.2.3'), isTrue);
    expect(isPrivateIpv4('192.168.0.1'), isTrue);
    expect(isPrivateIpv4('172.16.0.1'), isTrue);
    expect(isPrivateIpv4('172.32.0.1'), isFalse);
    expect(isPrivateIpv4('8.8.8.8'), isFalse);
    expect(isValidIpv4('192.168.001.1'), isFalse);
  });

  test('remote paths and breadcrumbs', () {
    expect(joinRemote('/photos', 'a.jpg'), '/photos/a.jpg');
    expect(joinRemote('/', 'share'), '/share');
    expect(parentRemote('/photos/a.jpg'), '/photos');
    expect(validateEntryName('a/b'), isNotNull);
    expect(validateEntryName('假期'), isNull);

    final crumbs = breadcrumbs('/home/user', '/home/user/相册/2026');
    expect(crumbs.map((item) => item.label).toList(), ['根目录', '相册', '2026']);
    expect(crumbs.last.path, '/home/user/相册/2026');
  });

  test('byte and smb time formatting', () {
    expect(formatBytes(512), '512 B');
    expect(formatBytes(1536), '1.5 KB');
    expect(formatBytes(5 * 1024 * 1024), '5 MB');
    expect(smbTimestamp(0), isNull);
    expect(
      smbTimestamp(DateTime.utc(2024, 1, 2).millisecondsSinceEpoch)?.year,
      2024,
    );
  });

  test('saved account roundtrip hides nothing but keeps the password', () {
    final account = SavedAccount(
      id: 'smb|192.168.1.8|445|ada',
      protocol: RemoteProtocol.smb,
      host: '192.168.1.8',
      port: 445,
      username: 'ada',
      password: 'secret',
      domain: '',
      alias: '客厅',
      anonymous: false,
      updatedAt: DateTime.utc(2026, 10, 20),
    );
    final restored = SavedAccount.fromJson(
      Map<String, Object?>.from(
        jsonDecode(jsonEncode(account.toJson())) as Map,
      ),
    );
    expect(restored.password, 'secret');
    expect(restored.title, '客厅');
    expect(restored.protocol, RemoteProtocol.smb);
    expect(restored.mode, ConnectionMode.auto);
  });

  test('protocol plans prefer the chosen dialect and still keep fallbacks', () {
    expect(smbPlan(ConnectionMode.auto), [
      SmbDialect.smb3,
      SmbDialect.smb2,
      SmbDialect.smb1,
    ]);
    expect(smbPlan(ConnectionMode.smb1).first, SmbDialect.smb1);
    expect(smbPlan(ConnectionMode.smb1), hasLength(3));
    expect(ftpPlan(ConnectionMode.auto, 21).map((item) => item.label), [
      'FTP',
      'FTPES',
      'FTPS',
    ]);
    expect(ftpPlan(ConnectionMode.auto, 990).first, FtpSecurity.implicitTls);
    expect(ftpPort(FtpSecurity.implicitTls, 21), 990);
    expect(ftpPort(FtpSecurity.plain, 990), 21);
    expect(
      isAuthenticationFailure(Exception('NT_STATUS_LOGON_FAILURE')),
      isTrue,
    );
    expect(isAuthenticationFailure(Exception('connection reset')), isFalse);
    expect(
      friendlyError(
        NegotiateFailure(Exception('timed out'), ['SMB 3', 'SMB 2']),
      ),
      contains('SMB 3、SMB 2'),
    );
  });

  test('byte ranges cover the whole file, a suffix, and an open end', () {
    expect(byteRangeFromHeader(null, 1000), isNotNull);
    expect(byteRangeFromHeader(null, 1000)!.length, 1000);
    final open = byteRangeFromHeader('bytes=200-', 1000);
    expect(open!.start, 200);
    expect(open.endInclusive, 999);
    final suffix = byteRangeFromHeader('bytes=-50', 1000);
    expect(suffix!.start, 950);
    expect(suffix.length, 50);
    expect(byteRangeFromHeader('bytes=1000-1002', 1000), isNull);
    expect(byteRangeFromHeader('bytes=10-4', 1000), isNull);
  });

  test('cache cleanup drops aged files and then the oldest overflow', () {
    final now = DateTime.utc(2026, 10, 25);
    final victims = cacheVictims(
      [
        CacheEntry(
          id: 'old',
          bytes: 10,
          modified: now.subtract(const Duration(days: 5)),
        ),
        CacheEntry(
          id: 'big',
          bytes: 80,
          modified: now.subtract(const Duration(hours: 2)),
        ),
        CacheEntry(id: 'fresh', bytes: 30, modified: now),
      ],
      now: now,
      maxBytes: 100,
      maxAge: const Duration(days: 3),
    );
    expect(victims, ['old', 'big']);
  });

  test('appearance names round trip', () {
    expect(themeModeFromName('light'), ThemeMode.light);
    expect(themeModeFromName('dark'), ThemeMode.dark);
    expect(themeModeFromName('system'), ThemeMode.system);
    expect(themeModeFromName(null), ThemeMode.system);
    expect(themeModeName(ThemeMode.light), 'light');
    expect(themeModeName(themeModeFromName('dark')), 'dark');
  });

  test('video player failures stay short', () {
    expect(
      friendlyError(
        Exception(
          'PlatformException(VideoError, Video player had error androidx.media3.exoplayer.ExoPlaybackException: Source error, null, null)',
        ),
      ),
      '这个视频没法直接播放',
    );
  });

  test('a later video range interrupts the earlier read', () async {
    const total = 400;
    final proxy = MediaProxy(
      session: _FakeSession(_QueuedReader()),
      entry: const RemoteEntry(
        name: 'clip.mp4',
        path: '/clip.mp4',
        kind: EntryKind.file,
        size: total,
      ),
    );
    final firstClient = HttpClient()..autoUncompress = false;
    final secondClient = HttpClient()..autoUncompress = false;
    try {
      final uri = await proxy.start();
      final firstRequest = await firstClient.getUrl(uri);
      final firstResponse = await firstRequest.close();
      final sawBytes = Completer<void>();
      firstResponse.listen(
        (_) {
          if (!sawBytes.isCompleted) sawBytes.complete();
        },
        onError: (_) {},
        cancelOnError: false,
      );
      await sawBytes.future.timeout(const Duration(seconds: 3));

      final secondRequest = await secondClient.getUrl(uri);
      secondRequest.headers.set(HttpHeaders.rangeHeader, 'bytes=392-399');
      final started = DateTime.now();
      final secondResponse = await secondRequest.close().timeout(
        const Duration(seconds: 3),
      );
      final body = await secondResponse.fold<List<int>>(
        [],
        (collected, chunk) => collected..addAll(chunk),
      );
      final elapsed = DateTime.now().difference(started);
      expect(secondResponse.statusCode, HttpStatus.partialContent);
      expect(body, hasLength(8));
      expect(elapsed.inMilliseconds, lessThan(1500));
    } finally {
      firstClient.close(force: true);
      secondClient.close(force: true);
      await proxy.close();
    }
  });

  test('netbios node status returns the workstation name', () {
    final packet = BytesBuilder();
    packet.add(List<int>.filled(12, 0));
    packet.add([3, 0x41, 0x42, 0x43, 0]);
    packet.add([0, 0x21, 0, 1]);
    packet.add([0xC0, 0x0C, 0, 0x21, 0, 1, 0, 0, 0, 1, 0, 19]);
    packet.add([1]);
    packet.add(ascii.encode('LIVINGROOM'.padRight(15)));
    packet.add([0x00, 0x04, 0x00]);
    expect(parseNetbiosNodeStatus(packet.toBytes()), 'LIVINGROOM');
    expect(netbiosNodeStatusQuery().length, 50);
  });
}

class _QueuedReader implements RangeReader {
  Future<void> _tail = Future<void>.value();

  @override
  Future<void> copy({
    required int start,
    int? endExclusive,
    required void Function(List<int> bytes) onBytes,
  }) {
    final gate = _tail;
    final done = Completer<void>();
    _tail = done.future;
    return () async {
      await gate;
      try {
        final end = endExclusive ?? start;
        var offset = start;
        while (offset < end) {
          await Future<void>.delayed(const Duration(milliseconds: 40));
          final count = end - offset < 8 ? end - offset : 8;
          onBytes(Uint8List(count));
          offset += count;
        }
      } finally {
        if (!done.isCompleted) done.complete();
      }
    }();
  }

  @override
  Future<void> close() async {}
}

class _FakeSession extends RemoteSession {
  _FakeSession(this.reader)
    : super(
        SavedAccount(
          id: 'test',
          protocol: RemoteProtocol.smb,
          host: '127.0.0.1',
          port: 445,
          username: 'user',
          password: 'secret',
          domain: '',
          alias: 'test',
          anonymous: false,
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      );

  final RangeReader reader;

  @override
  ConnectionMode get resolvedMode => ConnectionMode.smb2;

  @override
  String get transportLabel => 'test';

  @override
  String get rootPath => '/';

  @override
  Future<List<RemoteEntry>> list(String path) async => [];

  @override
  Future<void> createFolder(String path) async {}

  @override
  Future<void> delete(RemoteEntry entry) async {}

  @override
  Future<void> rename(RemoteEntry entry, String newName) async {}

  @override
  Future<void> download(
    RemoteEntry entry,
    File destination,
    TransferProgress? onProgress, {
    bool Function()? isCancelled,
  }) async {}

  @override
  Future<RangeReader> openRange(RemoteEntry entry) async => reader;

  @override
  Future<void> upload(
    File local,
    String directory,
    String remoteName,
    TransferProgress? onProgress, {
    bool Function()? isCancelled,
  }) async {}

  @override
  Future<void> close() async {}
}
