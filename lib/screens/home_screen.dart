import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/models.dart';
import '../services/account_store.dart';
import '../services/lan_scanner.dart';
import '../services/remote_session.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import '../utils/format.dart';
import '../utils/lan.dart';
import '../widgets/device_card.dart';
import '../widgets/dialogs.dart';
import '../widgets/login_sheet.dart';
import 'browser_screen.dart';
import 'library_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.onEnter, this.onClose, this.notice});

  final void Function(RemoteSession session, SavedAccount account)? onEnter;
  final VoidCallback? onClose;
  final String? notice;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AccountStore _store = AccountStore();
  final LanScanner _scanner = LanScanner();
  final List<DiscoveredDevice> _devices = [];
  List<SavedAccount> _accounts = const [];
  List<String> _addresses = const [];
  List<String> _subnets = const [];
  bool _scanning = false;
  bool _scanned = false;
  bool _searchOpen = false;
  bool _busy = false;
  int _done = 0;
  int _total = 0;
  int _generation = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reloadAccounts();
    _loadAddresses();
  }

  Future<void> _reloadAccounts() async {
    final accounts = List.of(await _store.load());
    if (!mounted) return;
    accounts.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    setState(() => _accounts = accounts);
  }

  Future<void> _loadAddresses() async {
    try {
      final addresses = await localScanAddresses();
      if (!mounted) return;
      setState(() => _addresses = addresses);
    } catch (_) {}
  }

  Future<void> _scan() async {
    if (_scanning) return;
    final generation = ++_generation;
    setState(() {
      _scanning = true;
      _scanned = true;
      _error = null;
      _done = 0;
      _total = 0;
      _devices.clear();
    });
    try {
      await _scanner.scan(
        isCancelled: () => !mounted || generation != _generation,
        onFound: (device) {
          if (!mounted || generation != _generation) return;
          setState(() {
            _devices.removeWhere((item) => item.key == device.key);
            _devices.add(device);
            _devices.sort(_compareDevices);
          });
        },
        onProgress: (done, total, subnets) {
          if (!mounted || generation != _generation) return;
          setState(() {
            _done = done;
            _total = total;
            _subnets = subnets;
          });
        },
      );
      if (mounted && generation == _generation && _devices.isNotEmpty) {
        HapticFeedback.lightImpact();
      }
    } on ScanCancelled {
      return;
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() => _error = friendlyError(error));
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _scanning = false);
      }
    }
  }

  void _stopScan() {
    _generation++;
    if (mounted) setState(() => _scanning = false);
  }

  Future<void> _connect(SavedAccount account, {required bool remember}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final session = await showProgressTask(
        context: context,
        title: '正在登录 ${account.title}',
        cancellable: true,
        task: (_, isCancelled) async {
          final opened = await RemoteSession.open(account);
          if (isCancelled()) {
            await opened.close();
            throw const TransferCancelled();
          }
          return opened;
        },
      );
      final resolved = account.copyWith(
        mode: session.resolvedMode,
        updatedAt: DateTime.now(),
      );
      try {
        if (remember) {
          await _store.save(resolved);
        } else {
          await _store.remove(account.id);
        }
      } catch (_) {}
      if (!mounted) {
        await session.close();
        return;
      }
      final enter = widget.onEnter;
      if (enter != null) {
        enter(session, resolved);
        return;
      }
      await _reloadAccounts();
      if (!mounted) {
        await session.close();
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => BrowserScreen(session: session, account: resolved),
        ),
      );
    } on TransferCancelled {
      return;
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(friendlyError(error))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _login(DiscoveredDevice device, {SavedAccount? existing}) async {
    final result = await showLoginSheet(
      context: context,
      protocol: device.protocol,
      host: device.host,
      port: _accountPort(device),
      suggestedAlias: _aliasFor(device),
      existing: existing ?? _savedFor(device),
    );
    if (result == null || !mounted) return;
    await _connect(result.account, remember: result.remember);
  }

  Future<void> _openSaved(SavedAccount account) {
    return _connect(account, remember: true);
  }

  int _accountPort(DiscoveredDevice device) {
    if (device.protocol == RemoteProtocol.smb && device.port == 139) return 445;
    return device.port;
  }

  SavedAccount? _savedFor(DiscoveredDevice device) {
    return newestMatch(
      _accounts,
      protocol: device.protocol,
      host: device.host,
      port: _accountPort(device),
    );
  }

  Future<void> _forget(SavedAccount account) async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: '忘记这台设备',
      message: '会删除「${account.title}」保存的用户名和密码。',
      confirm: '忘记',
      danger: true,
    );
    if (!confirmed) return;
    await _store.remove(account.id);
    await _reloadAccounts();
  }

  Future<void> _addManually() async {
    final device = await showDialog<DiscoveredDevice>(
      context: context,
      builder: (context) => const _ManualDeviceDialog(),
    );
    if (device == null || !mounted) return;
    await _login(device);
  }

  bool _online(SavedAccount account) {
    return _devices.any(
      (device) =>
          device.protocol == account.protocol &&
          device.host.toLowerCase() == account.host.toLowerCase() &&
          (device.port == account.port ||
              (account.protocol == RemoteProtocol.smb &&
                  device.port == 139 &&
                  account.port == 445)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final ratio = _total == 0 ? null : _done / _total;
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _scan,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.onClose != null)
                    IconButton(
                      tooltip: '返回',
                      onPressed: widget.onClose,
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.onClose == null) ...[
                          Image.asset(
                            'assets/brand/icon.png',
                            width: 72,
                            height: 72,
                          ),
                          const SizedBox(height: 12),
                        ],
                        Text(
                          widget.onClose == null ? '近邻盘' : '服务器',
                          style: TextStyle(
                            fontSize: 40,
                            fontWeight: FontWeight.w800,
                            height: 1,
                            color: palette.ink,
                            letterSpacing: -1,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.onClose == null
                              ? '直接进入当前网络里已保存的服务器。搜索和切换从这里开始。'
                              : '选择一台已保存的服务器，或搜索局域网。',
                          style: TextStyle(color: palette.muted, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: '外观',
                    icon: const Icon(Icons.brightness_6_rounded),
                    style: IconButton.styleFrom(
                      backgroundColor: palette.card,
                      foregroundColor: palette.ink,
                    ),
                    onSelected: (value) => applyThemeChoice(context, value),
                    itemBuilder: (context) =>
                        themeMenuItems(ThemeScope.of(context).mode),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: '下载位置',
                    onPressed: () => showDownloadLocationSheet(context),
                    icon: const Icon(Icons.download_for_offline_rounded),
                    style: IconButton.styleFrom(
                      backgroundColor: palette.card,
                      foregroundColor: palette.ink,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: '本地文件',
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const LibraryScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.folder_copy_rounded),
                    style: IconButton.styleFrom(
                      backgroundColor: palette.card,
                      foregroundColor: palette.ink,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: '手动添加',
                    onPressed: _addManually,
                    icon: const Icon(Icons.add_rounded),
                    style: IconButton.styleFrom(
                      backgroundColor: palette.card,
                      foregroundColor: palette.ink,
                    ),
                  ),
                ],
              ),
              if (widget.notice != null) ...[
                const SizedBox(height: 12),
                Text(
                  widget.notice!,
                  style: TextStyle(color: palette.danger, height: 1.4),
                ),
              ],
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: palette.card,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: palette.line),
                  ),
                  child: Text(
                    _addresses.isEmpty
                        ? '还没有局域网地址'
                        : '本机 ${_addresses.join('  ·  ')}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              if (_accounts.isNotEmpty) ...[
                _SectionTitle(title: '已记住', count: _accounts.length),
                const SizedBox(height: 10),
                for (final account in _accounts) ...[
                  DeviceCard(
                    protocol: account.protocol,
                    title: account.title,
                    host: account.host,
                    port: account.port,
                    detail: account.anonymous
                        ? '自动登录 · ${account.protocol == RemoteProtocol.smb ? '访客' : '匿名'}'
                        : '自动登录 · ${account.username}',
                    actionLabel: '进入',
                    online: _online(account),
                    onOpen: () => _openSaved(account),
                    onEdit: () => _login(
                      DiscoveredDevice(
                        protocol: account.protocol,
                        host: account.host,
                        port: account.port,
                        hostName: account.alias,
                      ),
                      existing: account,
                    ),
                    onDelete: () => _forget(account),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
              const SizedBox(height: 8),
              if (!_searchOpen && !_scanning && _devices.isEmpty)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      setState(() => _searchOpen = true);
                      _scan();
                    },
                    icon: const Icon(Icons.wifi_tethering_rounded),
                    label: const Text('搜索局域网'),
                  ),
                ),
              if (_searchOpen || _scanning || _devices.isNotEmpty) ...[
                const SizedBox(height: 12),
                _ScanPanel(
                  scanning: _scanning,
                  done: _done,
                  total: _total,
                  ratio: ratio,
                  subnets: _subnets,
                  onPressed: _scanning ? _stopScan : _scan,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: palette.danger)),
                ],
                const SizedBox(height: 18),
                _SectionTitle(title: '扫描结果', count: _devices.length),
                const SizedBox(height: 10),
                if (_devices.isEmpty)
                  _EmptyState(scanned: _scanned, scanning: _scanning)
                else
                  for (final device in _devices) ...[
                    DeviceCard(
                      protocol: device.protocol,
                      title: device.title,
                      host: device.host,
                      port: device.port,
                      detail: device.detail,
                      actionLabel: _savedFor(device) == null ? '登录' : '进入',
                      online: true,
                      onOpen: () {
                        final saved = _savedFor(device);
                        if (saved == null) {
                          _login(device);
                        } else {
                          _connect(saved, remember: true);
                        }
                      },
                      onEdit: () => _login(device),
                    ),
                    const SizedBox(height: 10),
                  ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

int _compareDevices(DiscoveredDevice a, DiscoveredDevice b) {
  final protocol = a.protocol.index.compareTo(b.protocol.index);
  if (protocol != 0) return protocol;
  return _ipRank(a.host).compareTo(_ipRank(b.host));
}

int _ipRank(String host) {
  if (!isValidIpv4(host)) return 1 << 30;
  final parts = host.split('.').map(int.parse).toList();
  return (parts[0] << 24) + (parts[1] << 16) + (parts[2] << 8) + parts[3];
}

String? _aliasFor(DiscoveredDevice device) {
  final name = device.hostName?.trim();
  if (name == null || name.isEmpty) return null;
  return name;
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(width: 8),
        Text(
          '$count',
          style: TextStyle(color: palette.muted, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _ScanPanel extends StatelessWidget {
  const _ScanPanel({
    required this.scanning,
    required this.done,
    required this.total,
    required this.ratio,
    required this.subnets,
    required this.onPressed,
  });

  final bool scanning;
  final int done;
  final int total;
  final double? ratio;
  final List<String> subnets;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: palette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Radar(active: scanning, color: palette.accent),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      scanning ? '正在倾听局域网' : '扫描附近设备',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      scanning
                          ? '${subnets.join('、')}  ·  $done/$total'
                          : 'Samba 会协商 SMB 3、SMB 2 和 SMB 1。图片设备会尝试 FTP、FTPES 和 FTPS。',
                      style: TextStyle(
                        color: palette.muted,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (scanning) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(value: ratio, minHeight: 6),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onPressed,
              child: Text(scanning ? '停止扫描' : '开始扫描'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Radar extends StatefulWidget {
  const _Radar({required this.active, required this.color});

  final bool active;
  final Color color;

  @override
  State<_Radar> createState() => _RadarState();
}

class _RadarState extends State<_Radar> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant _Radar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.active && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 54,
      height: 54,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            painter: _RadarPainter(
              color: widget.color,
              t: widget.active ? _controller.value : 0.15,
            ),
          );
        },
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter({required this.color, required this.t});

  final Color color;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = color.withValues(alpha: 0.35);
    canvas.drawCircle(center, radius * 0.42, ring);
    canvas.drawCircle(center, radius * 0.72, ring);
    canvas.drawCircle(center, radius * 0.98, ring);
    final sweep = Paint()
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: 3.2,
        colors: [color.withValues(alpha: 0), color.withValues(alpha: 0.85)],
        transform: GradientRotation(t * 6.28318),
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, sweep);
    canvas.drawCircle(center, 3.5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.color != color;
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.scanned, required this.scanning});

  final bool scanned;
  final bool scanning;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final text = scanning
        ? '设备会在被发现时出现在这里。'
        : scanned
        ? '这个网段没有打开 445、21 或 990 端口的设备。可以点右上角手动填写 IP。'
        : '还没有扫描。同一 Wi-Fi 下的 Samba 和 FTP / FTPS 图片设备会出现在这里。';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 28),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: palette.line),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(color: palette.muted, height: 1.45),
      ),
    );
  }
}

class _ManualDeviceDialog extends StatefulWidget {
  const _ManualDeviceDialog();

  @override
  State<_ManualDeviceDialog> createState() => _ManualDeviceDialogState();
}

class _ManualDeviceDialogState extends State<_ManualDeviceDialog> {
  final TextEditingController _host = TextEditingController();
  final TextEditingController _port = TextEditingController(text: '21');
  RemoteProtocol _protocol = RemoteProtocol.smb;
  String? _error;

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  void _submit() {
    final host = _host.text.trim();
    if (!isValidIpv4(host) &&
        !RegExp(r'^[A-Za-z0-9][A-Za-z0-9.-]*$').hasMatch(host)) {
      setState(() => _error = '请输入 IP 或主机名');
      return;
    }
    final port = _protocol == RemoteProtocol.smb
        ? 445
        : int.tryParse(_port.text.trim());
    if (port == null || port < 1 || port > 65535) {
      setState(() => _error = '端口不正确');
      return;
    }
    Navigator.pop(
      context,
      DiscoveredDevice(protocol: _protocol, host: host, port: port),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('手动添加'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SegmentedButton<RemoteProtocol>(
            segments: const [
              ButtonSegment(value: RemoteProtocol.smb, label: Text('Samba')),
              ButtonSegment(value: RemoteProtocol.ftp, label: Text('图片设备')),
            ],
            selected: {_protocol},
            onSelectionChanged: (value) =>
                setState(() => _protocol = value.first),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _host,
            decoration: const InputDecoration(
              labelText: 'IP 或主机名',
              hintText: '192.168.1.20',
            ),
          ),
          if (_protocol == RemoteProtocol.ftp) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _port,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '端口',
                helperText: '21 为 FTP / FTPES，990 为 FTPS',
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: TextStyle(color: AppPalette.of(context).danger),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('下一步')),
      ],
    );
  }
}
