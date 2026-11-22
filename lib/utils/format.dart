import '../services/protocol_plan.dart';

String formatBytes(int bytes) {
  if (bytes < 0) return '';
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = value >= 10 || value == value.roundToDouble() ? 0 : 1;
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}

String formatDate(DateTime? time) {
  if (time == null) return '未知时间';
  final local = time.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}

DateTime? smbTimestamp(int value) {
  if (value <= 0) return null;
  final time = DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
  if (time.year < 1980 || time.year > 2200) return null;
  return time;
}

String friendlyError(Object error) {
  if (error is NegotiateFailure) {
    final detail = friendlyError(error.cause);
    if (error.tried.isEmpty) return detail;
    return '$detail 已尝试 ${error.tried.join('、')}。';
  }
  final raw = error
      .toString()
      .replaceFirst(RegExp(r'^[A-Za-z0-9_\.]*Exception:\s*'), '')
      .trim();
  final lower = raw.toLowerCase();
  if (lower.contains('530') ||
      lower.contains('logon') ||
      lower.contains('authentication') ||
      lower.contains('access denied') ||
      lower.contains('status_logon_failure') ||
      lower.contains('status_access_denied') ||
      lower.contains('wrong password')) {
    return '用户名或密码不正确，或者这台设备不允许当前身份访问。';
  }
  if (lower.contains('timed out') || lower.contains('timeout')) {
    return '连接超时。请确认设备已开机，并且和手机在同一个 Wi-Fi。';
  }
  if (lower.contains('connection refused') ||
      lower.contains('socketexception') ||
      lower.contains("can't connect") ||
      lower.contains('network is unreachable') ||
      lower.contains('failed host lookup')) {
    return '连不上这台设备。';
  }
  if (lower.contains('already exists')) {
    return '已经有同名文件或文件夹。';
  }
  if (lower.contains('videoerror') ||
      lower.contains('exoplayback') ||
      lower.contains('source error')) {
    return '这个视频没法直接播放';
  }
  if (raw.isEmpty) return '操作没有完成。';
  if (raw.length > 160) return '${raw.substring(0, 160)}…';
  return raw;
}
