import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/models.dart';
import '../utils/lan.dart';

class ScanCancelled implements Exception {}

class LanScanner {
  Future<void> scan({
    required bool Function() isCancelled,
    required void Function(DiscoveredDevice device) onFound,
    required void Function(int done, int total, List<String> subnets)
    onProgress,
  }) async {
    final addresses = await localScanAddresses();
    if (addresses.isEmpty) {
      throw Exception('没有发现局域网地址。请先连接 Wi-Fi。');
    }
    final hosts = <String>{};
    final subnets = <String>[];
    for (final address in addresses) {
      subnets.add('${address.substring(0, address.lastIndexOf('.'))}.0/24');
      hosts.addAll(hostsInSlash24(address));
    }
    final queue = hosts.toList();
    var cursor = 0;
    var done = 0;
    onProgress(0, queue.length, subnets);

    Future<void> worker() async {
      while (!isCancelled()) {
        final index = cursor++;
        if (index >= queue.length) return;
        try {
          final found = await _probe(queue[index]);
          if (!isCancelled()) {
            for (final device in found) {
              onFound(device);
            }
          }
        } finally {
          done++;
          if (!isCancelled()) onProgress(done, queue.length, subnets);
        }
      }
    }

    final width = queue.length < 36 ? queue.length : 36;
    if (width == 0) return;
    await Future.wait(List.generate(width, (_) => worker()));
    if (isCancelled()) throw ScanCancelled();
  }

  Future<List<DiscoveredDevice>> _probe(String ip) async {
    final opened = await Future.wait([
      _open(ip, 445),
      _open(ip, 21),
      _open(ip, 990),
    ]);
    final smbSocket = opened[0];
    var ftpSocket = opened[1];
    var ftpsSocket = opened[2];
    final devices = <DiscoveredDevice>[];
    try {
      if (smbSocket != null) {
        final name = await lookupNetbiosName(ip);
        devices.add(
          DiscoveredDevice(
            protocol: RemoteProtocol.smb,
            host: ip,
            port: 445,
            hostName: name,
            detail: 'SMB 3 / 2 / 1 · 445',
          ),
        );
      } else {
        final netbios = await _open(ip, 139);
        if (netbios != null) {
          netbios.destroy();
          final name = await lookupNetbiosName(ip);
          devices.add(
            DiscoveredDevice(
              protocol: RemoteProtocol.smb,
              host: ip,
              port: 139,
              hostName: name,
              detail: '只发现 NetBIOS 139，登录仍会尝试 445',
            ),
          );
        }
      }

      if (ftpSocket != null) {
        final banner = await _readBanner(ftpSocket);
        ftpSocket = null;
        devices.add(
          DiscoveredDevice(
            protocol: RemoteProtocol.ftp,
            host: ip,
            port: 21,
            hostName: _bannerName(banner),
            detail: banner ?? 'FTP / FTPES · 21',
          ),
        );
      }
      if (ftpsSocket != null) {
        ftpsSocket.destroy();
        ftpsSocket = null;
        devices.add(
          DiscoveredDevice(
            protocol: RemoteProtocol.ftp,
            host: ip,
            port: 990,
            detail: 'FTPS 990',
          ),
        );
      }
    } finally {
      smbSocket?.destroy();
      ftpSocket?.destroy();
      ftpsSocket?.destroy();
    }
    return devices;
  }

  Future<Socket?> _open(String host, int port) async {
    try {
      return await Socket.connect(
        host,
        port,
        timeout: const Duration(milliseconds: 420),
      );
    } catch (_) {
      return null;
    }
  }

  Future<String?> _readBanner(Socket socket) async {
    try {
      final bytes = await socket.first.timeout(
        const Duration(milliseconds: 700),
      );
      final text = utf8.decode(bytes, allowMalformed: true).trim();
      final cleaned = text.replaceFirst(RegExp(r'^\d{3}[- ]'), '').trim();
      if (cleaned.isEmpty) return null;
      return cleaned.length > 80 ? '${cleaned.substring(0, 80)}…' : cleaned;
    } catch (_) {
      return null;
    } finally {
      socket.destroy();
    }
  }

  String? _bannerName(String? banner) {
    if (banner == null || banner.isEmpty) return null;
    final compact = banner.split(RegExp(r'\s+')).take(4).join(' ');
    return compact.length > 28 ? compact.substring(0, 28) : compact;
  }
}
