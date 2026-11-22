import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/account_store.dart';
import '../services/local_files.dart';
import '../services/remote_session.dart';
import '../theme/app_theme.dart';
import '../utils/lan.dart';
import 'browser_screen.dart';
import 'home_screen.dart';

class ShellScreen extends StatefulWidget {
  const ShellScreen({super.key});

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  final AccountStore _store = AccountStore();
  RemoteSession? _session;
  SavedAccount? _account;
  bool _booting = true;
  String _status = '正在查找已保存的服务器';
  String? _notice;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    final session = _session;
    _session = null;
    session?.close();
    super.dispose();
  }

  Future<void> _boot() async {
    final cleanup = tidyLocalFiles().then((_) {}, onError: (Object _) {});
    List<SavedAccount> accounts;
    try {
      accounts = List.of(await _store.load());
    } catch (_) {
      accounts = [];
    }
    accounts.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    if (accounts.isEmpty) {
      await cleanup;
      if (!mounted) return;
      setState(() => _booting = false);
      return;
    }
    final candidates = accounts.take(8).toList();
    final reachable = <SavedAccount>[];
    await Future.wait(
      candidates.map((account) async {
        final open = await canReachHost(account.host, account.port);
        if (open) reachable.add(account);
      }),
    );
    reachable.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    for (final account in reachable) {
      if (!mounted) return;
      setState(() => _status = '正在进入 ${account.title}');
      RemoteSession? session;
      try {
        session = await RemoteSession.open(
          account,
        ).timeout(const Duration(seconds: 20));
        final resolved = account.copyWith(
          mode: session.resolvedMode,
          updatedAt: DateTime.now(),
        );
        try {
          await _store.save(resolved);
        } catch (_) {}
        if (!mounted) {
          await session.close();
          return;
        }
        setState(() {
          _session = session;
          _account = resolved;
          _booting = false;
        });
        await cleanup;
        return;
      } catch (_) {
        try {
          await session?.close();
        } catch (_) {}
      }
    }
    await cleanup;
    if (!mounted) return;
    setState(() {
      _booting = false;
      _notice = '已保存的服务器现在不在这个网络里。';
    });
  }

  void _enter(RemoteSession session, SavedAccount account) {
    final previous = _session;
    setState(() {
      _session = session;
      _account = account;
      _notice = null;
    });
    if (previous != null && !identical(previous, session)) {
      previous.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_booting) return _BootView(status: _status);
    final session = _session;
    final account = _account;
    if (session == null || account == null) {
      return HomeScreen(onEnter: _enter, notice: _notice);
    }
    return BrowserScreen(
      key: ValueKey(account.id),
      session: session,
      account: account,
      ownsSession: false,
      onSwitchServer: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (routeContext) => HomeScreen(
              onClose: () => Navigator.pop(routeContext),
              onEnter: (nextSession, nextAccount) {
                Navigator.pop(routeContext);
                _enter(nextSession, nextAccount);
              },
            ),
          ),
        );
      },
    );
  }
}

class _BootView extends StatelessWidget {
  const _BootView({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset('assets/brand/icon.png', width: 88, height: 88),
              const SizedBox(height: 16),
              Text(
                '近邻盘',
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w800,
                  color: palette.ink,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 22),
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                status,
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.muted, height: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
