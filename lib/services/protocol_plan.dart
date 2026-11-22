import '../models/models.dart';

enum SmbDialect { smb3, smb2, smb1 }

enum FtpSecurity { plain, explicitTls, implicitTls }

class NegotiateFailure implements Exception {
  NegotiateFailure(this.cause, this.tried);

  final Object cause;
  final List<String> tried;
}

List<ConnectionMode> modesFor(RemoteProtocol protocol) {
  return switch (protocol) {
    RemoteProtocol.smb => const [
      ConnectionMode.auto,
      ConnectionMode.smb3,
      ConnectionMode.smb2,
      ConnectionMode.smb1,
    ],
    RemoteProtocol.ftp => const [
      ConnectionMode.auto,
      ConnectionMode.ftp,
      ConnectionMode.ftpes,
      ConnectionMode.ftps,
    ],
  };
}

List<SmbDialect> smbPlan(ConnectionMode mode) {
  const all = [SmbDialect.smb3, SmbDialect.smb2, SmbDialect.smb1];
  final preferred = switch (mode) {
    ConnectionMode.smb2 => SmbDialect.smb2,
    ConnectionMode.smb1 => SmbDialect.smb1,
    _ => SmbDialect.smb3,
  };
  return [preferred, ...all.where((item) => item != preferred)];
}

List<FtpSecurity> ftpPlan(ConnectionMode mode, int port) {
  final preferred = switch (mode) {
    ConnectionMode.ftp => FtpSecurity.plain,
    ConnectionMode.ftpes => FtpSecurity.explicitTls,
    ConnectionMode.ftps => FtpSecurity.implicitTls,
    _ => port == 990 ? FtpSecurity.implicitTls : FtpSecurity.plain,
  };
  final all = port == 990
      ? const [
          FtpSecurity.implicitTls,
          FtpSecurity.explicitTls,
          FtpSecurity.plain,
        ]
      : const [
          FtpSecurity.plain,
          FtpSecurity.explicitTls,
          FtpSecurity.implicitTls,
        ];
  return [preferred, ...all.where((item) => item != preferred)];
}

int ftpPort(FtpSecurity security, int requested) {
  if (security == FtpSecurity.implicitTls && requested == 21) return 990;
  if (security != FtpSecurity.implicitTls && requested == 990) return 21;
  return requested;
}

extension SmbDialectLabel on SmbDialect {
  String get label => switch (this) {
    SmbDialect.smb3 => 'SMB 3',
    SmbDialect.smb2 => 'SMB 2',
    SmbDialect.smb1 => 'SMB 1',
  };

  ConnectionMode get mode => switch (this) {
    SmbDialect.smb3 => ConnectionMode.smb3,
    SmbDialect.smb2 => ConnectionMode.smb2,
    SmbDialect.smb1 => ConnectionMode.smb1,
  };
}

extension FtpSecurityLabel on FtpSecurity {
  String get label => switch (this) {
    FtpSecurity.plain => 'FTP',
    FtpSecurity.explicitTls => 'FTPES',
    FtpSecurity.implicitTls => 'FTPS',
  };

  ConnectionMode get mode => switch (this) {
    FtpSecurity.plain => ConnectionMode.ftp,
    FtpSecurity.explicitTls => ConnectionMode.ftpes,
    FtpSecurity.implicitTls => ConnectionMode.ftps,
  };
}

bool isAuthenticationFailure(Object error) {
  final lower = error.toString().toLowerCase();
  return lower.contains('logon') ||
      lower.contains('authentication') ||
      lower.contains('wrong username') ||
      lower.contains('wrong password') ||
      lower.contains('status_logon_failure') ||
      lower.contains('530');
}
