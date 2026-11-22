enum RemoteProtocol { smb, ftp }

enum ConnectionMode { auto, smb3, smb2, smb1, ftp, ftpes, ftps }

ConnectionMode _modeFrom(String? raw) {
  for (final mode in ConnectionMode.values) {
    if (mode.name == raw) return mode;
  }
  return ConnectionMode.auto;
}

extension ConnectionModeLabel on ConnectionMode {
  String get label => switch (this) {
    ConnectionMode.auto => '自动',
    ConnectionMode.smb3 => 'SMB 3',
    ConnectionMode.smb2 => 'SMB 2',
    ConnectionMode.smb1 => 'SMB 1',
    ConnectionMode.ftp => 'FTP',
    ConnectionMode.ftpes => 'FTPES',
    ConnectionMode.ftps => 'FTPS',
  };
}

extension RemoteProtocolLabel on RemoteProtocol {
  String get title => switch (this) {
    RemoteProtocol.smb => 'Samba',
    RemoteProtocol.ftp => '图片设备',
  };

  String get subtitle => switch (this) {
    RemoteProtocol.smb => 'SMB 文件共享',
    RemoteProtocol.ftp => 'FTP 图片 / 文件',
  };

  int get defaultPort => switch (this) {
    RemoteProtocol.smb => 445,
    RemoteProtocol.ftp => 21,
  };
}

class SavedAccount {
  const SavedAccount({
    required this.id,
    required this.protocol,
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    required this.domain,
    required this.alias,
    required this.anonymous,
    required this.updatedAt,
    this.mode = ConnectionMode.auto,
  });

  final String id;
  final RemoteProtocol protocol;
  final String host;
  final int port;
  final String username;
  final String password;
  final String domain;
  final String alias;
  final bool anonymous;
  final DateTime updatedAt;
  final ConnectionMode mode;

  String get title {
    final name = alias.trim();
    if (name.isNotEmpty) return name;
    return '${protocol.title} · $host';
  }

  static String makeId({
    required RemoteProtocol protocol,
    required String host,
    required int port,
    required String username,
    required bool anonymous,
  }) {
    final user = anonymous ? '*' : username.trim().toLowerCase();
    return '${protocol.name}|${host.trim().toLowerCase()}|$port|$user';
  }

  SavedAccount copyWith({
    String? username,
    String? password,
    String? domain,
    String? alias,
    bool? anonymous,
    DateTime? updatedAt,
    ConnectionMode? mode,
  }) {
    return SavedAccount(
      id: id,
      protocol: protocol,
      host: host,
      port: port,
      username: username ?? this.username,
      password: password ?? this.password,
      domain: domain ?? this.domain,
      alias: alias ?? this.alias,
      anonymous: anonymous ?? this.anonymous,
      updatedAt: updatedAt ?? this.updatedAt,
      mode: mode ?? this.mode,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'protocol': protocol.name,
      'host': host,
      'port': port,
      'username': username,
      'password': password,
      'domain': domain,
      'alias': alias,
      'anonymous': anonymous,
      'updatedAt': updatedAt.toIso8601String(),
      'mode': mode.name,
    };
  }

  factory SavedAccount.fromJson(Map<String, Object?> json) {
    return SavedAccount(
      id: json['id']! as String,
      protocol: RemoteProtocol.values.byName(json['protocol']! as String),
      host: json['host']! as String,
      port: json['port']! as int,
      username: json['username'] as String? ?? '',
      password: json['password'] as String? ?? '',
      domain: json['domain'] as String? ?? '',
      alias: json['alias'] as String? ?? '',
      anonymous: json['anonymous'] as bool? ?? false,
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      mode: _modeFrom(json['mode'] as String?),
    );
  }
}

class DiscoveredDevice {
  const DiscoveredDevice({
    required this.protocol,
    required this.host,
    required this.port,
    this.hostName,
    this.detail,
  });

  final RemoteProtocol protocol;
  final String host;
  final int port;
  final String? hostName;
  final String? detail;

  String get title {
    final name = hostName?.trim();
    if (name != null && name.isNotEmpty) return name;
    return protocol == RemoteProtocol.smb ? 'Samba 设备' : '图片设备';
  }

  String get key => '${protocol.name}|$host|$port';
}

enum EntryKind { directory, file, unknown }

class RemoteEntry {
  const RemoteEntry({
    required this.name,
    required this.path,
    required this.kind,
    required this.size,
    this.modified,
    this.isShare = false,
  });

  final String name;
  final String path;
  final EntryKind kind;
  final int size;
  final DateTime? modified;
  final bool isShare;

  bool get isDirectory => kind == EntryKind.directory;
}

class LoginResult {
  const LoginResult({required this.account, required this.remember});

  final SavedAccount account;
  final bool remember;
}
