import 'dart:io';
import 'dart:typed_data';

import 'package:smb_connect/smb_connect.dart';
// ignore: implementation_imports
import 'package:smb_connect/src/connect/impl/smb2/smb2_connect.dart';
// ignore: implementation_imports
import 'package:smb_connect/src/connect/smb_file_stream.dart';
// ignore: implementation_imports
import 'package:smb_connect/src/exceptions.dart';
// ignore: implementation_imports
import 'package:smb_connect/src/smb/nt_status.dart';
// ignore: implementation_imports
import 'package:smb_connect/src/smb_constants.dart';

/// Largest read the bundled SMB client can reassemble. Larger custom reads
/// desynchronize its socket reader and the transfer never finishes.
const smbReadChunk = 64936;

/// Outgoing SMB2 is framed with a 16-bit length.
const smbWriteChunk = 64936;

Stream<Uint8List> fileBlocks(File file, int size) async* {
  final input = await file.open();
  try {
    final block = Uint8List(size);
    while (true) {
      final read = await input.readInto(block);
      if (read <= 0) break;
      final copy = Uint8List(read);
      copy.setRange(0, read, block);
      yield copy;
    }
  } finally {
    await input.close();
  }
}

Future<void> readRemote({
  required SmbConnect smb,
  required SmbFile file,
  required int start,
  required int? endExclusive,
  required int knownSize,
  required void Function(List<int> bytes) onBytes,
  required bool Function() isCancelled,
}) async {
  if (smb is! Smb2Connect) {
    final stream = await smb.openRead(file, start, endExclusive);
    await for (final chunk in stream) {
      if (isCancelled()) break;
      onBytes(chunk);
    }
    return;
  }

  final opened = await smb.openFile(
    file,
    access: SmbConstants.O_RDONLY,
    openFlags: 0,
    sharing: SmbConstants.DEFAULT_SHARING,
    attrs: SmbConstants.ATTR_NORMAL,
  );
  if (opened.status != NtStatus.NT_STATUS_OK) {
    throw SmbException.getMessageByCode(opened.status);
  }
  final tree = await smb.shareTree(file.share);
  final fileId = Uint8List.fromList(opened.fileId);
  final remoteSize = opened.getSize() > 0 ? opened.getSize() : knownSize;
  final length = endExclusive == null
      ? (remoteSize > start ? remoteSize - start : null)
      : endExclusive - start;
  final buffer = Uint8List(smbReadChunk);
  var position = 0;
  try {
    while (length == null || position < length) {
      if (isCancelled()) return;
      final remain = length == null ? smbReadChunk : length - position;
      final want = remain < smbReadChunk ? remain : smbReadChunk;
      if (want <= 0) return;
      final read = await smbReadFromFile(
        file,
        tree,
        fileId,
        0,
        buffer,
        start + position,
        0,
        want,
      );
      if (read <= 0) return;
      if (isCancelled()) return;
      final copy = Uint8List(read);
      copy.setRange(0, read, buffer);
      onBytes(copy);
      position += read;
    }
  } finally {
    try {
      await smbCloseFile(file, tree, fileId, 0);
    } catch (_) {}
  }
}
