import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/models.dart';
import 'byte_range.dart';
import 'local_files.dart';
import 'remote_session.dart';

class _Stopped implements Exception {
  const _Stopped();
}

/// Serves one remote file over loopback HTTP so the player can request only
/// the ranges it needs.
class MediaProxy {
  MediaProxy({required this.session, required this.entry});

  final RemoteSession session;
  final RemoteEntry entry;
  HttpServer? _server;
  RangeReader? _reader;
  var _requestId = 0;

  Future<Uri> start() async {
    _reader = await session.openRange(entry);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    server.listen(_handle, onError: (_) {});
    return Uri.parse(
      'http://127.0.0.1:${server.port}/media.${_suffix(entry.name)}',
    );
  }

  String _suffix(String name) {
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return 'mp4';
    final ext = name.substring(dot + 1).toLowerCase();
    if (!RegExp(r'^[a-z0-9]{1,5}$').hasMatch(ext)) return 'mp4';
    return ext;
  }

  Future<void> close() async {
    final reader = _reader;
    _reader = null;
    if (reader != null) {
      await reader.close();
    }
    final server = _server;
    _server = null;
    if (server != null) {
      await server.close(force: true);
    }
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    final reader = _reader;
    if (reader == null || !request.uri.path.startsWith('/media')) {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }
    if (request.method != 'GET' && request.method != 'HEAD') {
      response.statusCode = HttpStatus.methodNotAllowed;
      await response.close();
      return;
    }

    final total = entry.size;
    final header = request.headers.value(HttpHeaders.rangeHeader);
    response.bufferOutput = false;
    response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    response.headers.contentType = ContentType.parse(videoMime(entry.name));

    ByteRange? range;
    if (total > 0) {
      range = byteRangeFromHeader(header, total);
      if (header != null && range == null) {
        response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$total');
        await response.close();
        return;
      }
      range ??= ByteRange(0, total - 1);
      final partial = header != null;
      response.statusCode = partial ? HttpStatus.partialContent : HttpStatus.ok;
      response.headers.contentLength = range.length;
      if (partial) {
        response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes ${range.start}-${range.endInclusive}/$total',
        );
      }
    } else {
      response.statusCode = HttpStatus.ok;
    }

    if (request.method == 'HEAD') {
      await response.close();
      return;
    }

    // Phone videos often keep the index at the end of the file. The player
    // then opens a second connection for that tail. This client can only read
    // one range at a time, so the new request has to stop the previous read
    // before the player gives up.
    final requestId = ++_requestId;
    var clientGone = false;
    response.done.then(
      (_) {},
      onError: (_) {
        clientGone = true;
      },
    );

    try {
      await response.flush();
      await reader.copy(
        start: range?.start ?? 0,
        endExclusive: range == null ? null : range.endInclusive + 1,
        onBytes: (chunk) {
          if (_reader == null || clientGone || requestId != _requestId) {
            throw const _Stopped();
          }
          try {
            response.add(chunk);
          } catch (_) {
            throw const _Stopped();
          }
        },
      );
      await response.close();
    } catch (error) {
      if (error is! _Stopped) {
        debugPrint('近邻盘视频传输中断: $error');
      }
      try {
        await response.close();
      } catch (_) {}
    }
  }
}
