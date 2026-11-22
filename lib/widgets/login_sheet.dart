import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/protocol_plan.dart';
import '../theme/app_theme.dart';

Future<LoginResult?> showLoginSheet({
  required BuildContext context,
  required RemoteProtocol protocol,
  required String host,
  required int port,
  String? suggestedAlias,
  SavedAccount? existing,
}) {
  return showModalBottomSheet<LoginResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: _LoginSheet(
          protocol: protocol,
          host: host,
          port: port,
          suggestedAlias: suggestedAlias,
          existing: existing,
        ),
      );
    },
  );
}

class _LoginSheet extends StatefulWidget {
  const _LoginSheet({
    required this.protocol,
    required this.host,
    required this.port,
    this.suggestedAlias,
    this.existing,
  });

  final RemoteProtocol protocol;
  final String host;
  final int port;
  final String? suggestedAlias;
  final SavedAccount? existing;

  @override
  State<_LoginSheet> createState() => _LoginSheetState();
}

class _LoginSheetState extends State<_LoginSheet> {
  late final TextEditingController _alias = TextEditingController(
    text: widget.existing?.alias ?? widget.suggestedAlias ?? '',
  );
  late final TextEditingController _user = TextEditingController(
    text: widget.existing?.username ?? '',
  );
  late final TextEditingController _pass = TextEditingController(
    text: widget.existing?.password ?? '',
  );
  late final TextEditingController _domain = TextEditingController(
    text: widget.existing?.domain ?? '',
  );
  late bool _anonymous = widget.existing?.anonymous ?? false;
  late bool _remember = true;
  late ConnectionMode _mode = widget.existing?.mode ?? ConnectionMode.auto;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _alias.dispose();
    _user.dispose();
    _pass.dispose();
    _domain.dispose();
    super.dispose();
  }

  void _submit() {
    var username = _user.text.trim();
    var password = _pass.text;
    if (_anonymous) {
      if (widget.protocol == RemoteProtocol.ftp) {
        if (username.isEmpty) username = 'anonymous';
        if (password.isEmpty) password = 'anonymous@lan';
      } else if (username.isEmpty) {
        username = 'guest';
      }
    } else if (username.isEmpty) {
      setState(
        () => _error =
            '请输入用户名，或改用${widget.protocol == RemoteProtocol.smb ? '访客' : '匿名'}登录。',
      );
      return;
    }

    final account = SavedAccount(
      id: SavedAccount.makeId(
        protocol: widget.protocol,
        host: widget.host,
        port: widget.port,
        username: username,
        anonymous: _anonymous,
      ),
      protocol: widget.protocol,
      host: widget.host,
      port: widget.port,
      username: username,
      password: password,
      domain: widget.protocol == RemoteProtocol.smb ? _domain.text.trim() : '',
      alias: _alias.text.trim(),
      anonymous: _anonymous,
      updatedAt: DateTime.now(),
      mode: _mode,
    );
    Navigator.pop(context, LoginResult(account: account, remember: _remember));
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final tone = widget.protocol == RemoteProtocol.smb
        ? palette.samba
        : palette.ftp;
    final soft = widget.protocol == RemoteProtocol.smb
        ? palette.sambaSoft
        : palette.ftpSoft;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(28),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.line,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: soft,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                widget.protocol.subtitle,
                style: TextStyle(
                  color: tone,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '登录 ${widget.protocol.title}',
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              '${widget.host}:${widget.port}',
              style: TextStyle(color: palette.muted),
            ),
            const SizedBox(height: 16),
            const Text('连接方式', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final mode in modesFor(widget.protocol))
                  ChoiceChip(
                    label: Text(mode.label),
                    selected: _mode == mode,
                    showCheckmark: false,
                    selectedColor: palette.accentSoft,
                    labelStyle: TextStyle(
                      color: _mode == mode ? palette.accent : palette.ink,
                      fontWeight: FontWeight.w700,
                    ),
                    onSelected: (_) => setState(() => _mode = mode),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              widget.protocol == RemoteProtocol.smb
                  ? '自动会从 SMB 3.1.1 协商到 SMB 2，不行再试 SMB 1。'
                  : '自动会按端口尝试普通 FTP、显式加密 FTPES 和隐式加密 FTPS。',
              style: TextStyle(
                color: palette.muted,
                fontSize: 12,
                height: 1.35,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: palette.danger.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(_error!, style: TextStyle(color: palette.danger)),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _alias,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: '备注',
                hintText: '例如客厅 NAS，可留空',
              ),
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _anonymous,
              activeThumbColor: palette.accent,
              title: Text(
                widget.protocol == RemoteProtocol.smb ? '访客登录' : '匿名登录',
              ),
              subtitle: Text(
                widget.protocol == RemoteProtocol.smb
                    ? '不使用密码，以 guest 访问'
                    : '适合多数只收图的 FTP 设备',
                style: TextStyle(color: palette.muted, fontSize: 12),
              ),
              onChanged: (value) => setState(() => _anonymous = value),
            ),
            if (!_anonymous) ...[
              TextField(
                controller: _user,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: '用户名'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _pass,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: '密码',
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_rounded
                          : Icons.visibility_off_rounded,
                    ),
                  ),
                ),
              ),
              if (widget.protocol == RemoteProtocol.smb) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _domain,
                  decoration: const InputDecoration(
                    labelText: '域',
                    hintText: '一般留空',
                  ),
                ),
              ],
            ],
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _remember,
              activeThumbColor: palette.accent,
              title: const Text('记住并自动登录'),
              subtitle: Text(
                '密码保存在系统安全存储里',
                style: TextStyle(color: palette.muted, fontSize: 12),
              ),
              onChanged: (value) => setState(() => _remember = value),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(onPressed: _submit, child: const Text('登录')),
            ),
          ],
        ),
      ),
    );
  }
}
