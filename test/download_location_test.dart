import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_client/services/download_location.dart';

class _FakePlatform implements DownloadLocationPlatform {
  PickedDownloadDirectory? picked;
  String? writtenPath;
  bool granted = true;
  int released = 0;

  @override
  Future<PickedDownloadDirectory?> pickDirectory() async => picked;

  @override
  Future<String?> writeFile({
    required String directoryUri,
    required String source,
    required String displayName,
  }) async {
    writtenPath = '/download/$displayName';
    return writtenPath;
  }

  @override
  Future<bool> hasPermission(String directoryUri) async => granted;

  @override
  Future<void> releaseDirectory(String directoryUri) async {
    released++;
  }
}

void main() {
  late Directory temp;
  late _FakePlatform platform;
  late DownloadLocationStore store;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('dl_loc_test');
    platform = _FakePlatform();
    store = DownloadLocationStore(
      platform: platform,
      supportDirectory: () async => temp,
    );
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('defaults to system mode and needs a grant', () async {
    expect(store.mode, DownloadLocation.system);
    expect(store.needsGrant, isTrue);
    expect(await store.hasValidGrant(), isFalse);
  });

  test('chooseDirectory stores uri and clears the need for a grant', () async {
    platform.picked = const PickedDownloadDirectory(
      uri: 'content://tree/download',
      displayName: 'Download',
    );
    final picked = await store.chooseDirectory(mode: DownloadLocation.system);
    expect(picked, isNotNull);
    expect(store.mode, DownloadLocation.system);
    expect(store.directoryUri, 'content://tree/download');
    expect(store.directoryName, 'Download');
    expect(store.needsGrant, isFalse);
    expect(await store.hasValidGrant(), isTrue);
  });

  test('preferences survive a reload', () async {
    await store.setMode(DownloadLocation.custom);
    platform.picked = const PickedDownloadDirectory(
      uri: 'content://tree/myfolder',
      displayName: '我的文件夹',
    );
    await store.chooseDirectory(mode: DownloadLocation.custom);

    final reloaded = DownloadLocationStore(
      platform: platform,
      supportDirectory: () async => temp,
    );
    await reloaded.load();
    expect(reloaded.mode, DownloadLocation.custom);
    expect(reloaded.directoryUri, 'content://tree/myfolder');
    expect(reloaded.directoryName, '我的文件夹');
  });

  test('private mode does not need or use a grant', () async {
    await store.setMode(DownloadLocation.private);
    expect(store.needsGrant, isFalse);
    expect(await store.hasValidGrant(), isFalse);
  });

  test(
    'deliver writes to the granted folder and removes the staging file',
    () async {
      platform.picked = const PickedDownloadDirectory(
        uri: 'content://tree/download',
        displayName: 'Download',
      );
      await store.chooseDirectory(mode: DownloadLocation.system);

      final staging = File('${temp.path}/video.mp4');
      await staging.writeAsBytes([1, 2, 3]);

      final result = await store.deliver(
        source: staging,
        displayName: 'video.mp4',
        privateDirectory: () async => temp,
      );
      expect(result, '/download/video.mp4');
      expect(platform.writtenPath, '/download/video.mp4');
      expect(await staging.exists(), isFalse);
    },
  );

  test('deliver is a no-op in private mode', () async {
    await store.setMode(DownloadLocation.private);
    final staging = File('${temp.path}/notes.txt');
    await staging.writeAsString('hi');
    final result = await store.deliver(
      source: staging,
      displayName: 'notes.txt',
      privateDirectory: () async => temp,
    );
    expect(result, isNull);
    expect(await staging.exists(), isTrue);
  });

  test('revoked grant is detected and clearDirectory releases it', () async {
    platform.picked = const PickedDownloadDirectory(
      uri: 'content://tree/download',
      displayName: 'Download',
    );
    await store.chooseDirectory(mode: DownloadLocation.system);
    platform.granted = false;
    expect(await store.hasValidGrant(), isFalse);

    await store.clearDirectory();
    expect(platform.released, 1);
    expect(store.directoryUri, isNull);
    expect(store.needsGrant, isTrue);
  });

  test('corrupt preferences fall back to the safe default', () async {
    final pref = File('${temp.path}/download_location.json');
    await pref.writeAsString('not json');
    await store.load();
    expect(store.mode, DownloadLocation.system);
  });
}
