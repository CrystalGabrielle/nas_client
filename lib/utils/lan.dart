import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

bool isPrivateIpv4(String ip) {
  final parts = ip.split('.');
  if (parts.length != 4) return false;
  final numbers = <int>[];
  for (final part in parts) {
    final value = int.tryParse(part);
    if (value == null || value < 0 || value > 255) return false;
    numbers.add(value);
  }
  final a = numbers[0];
  final b = numbers[1];
  if (a == 10) return true;
  if (a == 192 && b == 168) return true;
  if (a == 172 && b >= 16 && b <= 31) return true;
  return false;
}

bool isValidIpv4(String ip) {
  final parts = ip.split('.');
  if (parts.length != 4) return false;
  for (final part in parts) {
    final value = int.tryParse(part);
    if (value == null || value < 0 || value > 255) return false;
    if (part != value.toString()) return false;
  }
  return true;
}

List<String> hostsInSlash24(String ip) {
  if (!isValidIpv4(ip)) return const [];
  final prefix = ip.substring(0, ip.lastIndexOf('.'));
  return [
    for (var host = 1; host <= 254; host++)
      if ('$prefix.$host' != ip) '$prefix.$host',
  ];
}

bool _skipInterface(String name) {
  const blocked = [
    'tun',
    'tap',
    'ppp',
    'docker',
    'veth',
    'vmnet',
    'awdl',
    'llw',
    'utun',
    'dummy',
    'lo',
    'br-',
  ];
  return blocked.any(name.contains);
}

bool _preferInterface(String name) {
  const preferred = ['wlan', 'wifi', 'eth', 'en', 'rmnet', 'swlan'];
  return preferred.any(name.contains);
}

Future<bool> canReachHost(
  String host,
  int port, {
  Duration timeout = const Duration(milliseconds: 1500),
}) async {
  if (host.trim().isEmpty || port <= 0 || port > 65535) return false;
  try {
    final socket = await Socket.connect(host, port, timeout: timeout);
    socket.destroy();
    return true;
  } catch (_) {
    return false;
  }
}

Future<List<String>> localScanAddresses() async {
  final interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
    includeLinkLocal: false,
  );
  final preferred = <String>[];
  final fallback = <String>[];
  for (final iface in interfaces) {
    final name = iface.name.toLowerCase();
    final virtual = _skipInterface(name);
    for (final address in iface.addresses) {
      if (!isPrivateIpv4(address.address)) continue;
      final target = virtual ? fallback : preferred;
      if (!target.contains(address.address)) target.add(address.address);
    }
  }
  preferred.sort((a, b) {
    final aName = _nameFor(interfaces, a);
    final bName = _nameFor(interfaces, b);
    return (_preferInterface(bName) ? 1 : 0) -
        (_preferInterface(aName) ? 1 : 0);
  });
  final chosen = preferred.isNotEmpty ? preferred : fallback;
  if (chosen.length <= 2) return chosen;
  return chosen.take(2).toList();
}

String _nameFor(List<NetworkInterface> interfaces, String ip) {
  for (final iface in interfaces) {
    for (final address in iface.addresses) {
      if (address.address == ip) return iface.name.toLowerCase();
    }
  }
  return '';
}

Uint8List netbiosNodeStatusQuery() {
  return Uint8List.fromList([
    0x00,
    0x01,
    0x00,
    0x00,
    0x00,
    0x01,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x20,
    ...ascii.encode('CKAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'),
    0x00,
    0x00,
    0x21,
    0x00,
    0x01,
  ]);
}

String? parseNetbiosNodeStatus(Uint8List data) {
  if (data.length < 48) return null;
  var offset = 12;
  if (offset >= data.length) return null;
  final questionLength = data[offset];
  offset += 1 + questionLength + 1 + 4;
  if (offset >= data.length) return null;

  if ((data[offset] & 0xC0) == 0xC0) {
    offset += 2;
  } else {
    while (offset < data.length && data[offset] != 0) {
      offset += 1 + data[offset];
    }
    offset += 1;
  }
  offset += 8;
  if (offset + 3 > data.length) return null;
  final recordLength = (data[offset] << 8) | data[offset + 1];
  offset += 2;
  if (recordLength < 1 || offset + recordLength > data.length) return null;

  final count = data[offset];
  offset += 1;
  String? fallback;
  for (var index = 0; index < count; index++) {
    if (offset + 18 > data.length) break;
    final name = ascii
        .decode(data.sublist(offset, offset + 15), allowInvalid: true)
        .replaceAll('\u0000', '')
        .trim();
    final suffix = data[offset + 15];
    final flags = (data[offset + 16] << 8) | data[offset + 17];
    offset += 18;
    if (name.isEmpty) continue;
    final group = flags & 0x8000 != 0;
    fallback ??= name;
    if (!group && (suffix == 0x00 || suffix == 0x20)) return name;
  }
  return fallback;
}

Future<String?> lookupNetbiosName(String ip) async {
  RawDatagramSocket? socket;
  try {
    socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket.send(netbiosNodeStatusQuery(), InternetAddress(ip), 137);
    final event = await socket
        .timeout(const Duration(milliseconds: 450))
        .firstWhere(
          (item) => item == RawSocketEvent.read,
          orElse: () => RawSocketEvent.closed,
        );
    if (event != RawSocketEvent.read) return null;
    final datagram = socket.receive();
    if (datagram == null) return null;
    return parseNetbiosNodeStatus(datagram.data);
  } catch (_) {
    return null;
  } finally {
    socket?.close();
  }
}
