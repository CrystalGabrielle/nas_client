import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/models.dart';

class AccountStore {
  AccountStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const storageKey = 'saved_accounts_v1';

  final FlutterSecureStorage _storage;

  Future<List<SavedAccount>> load() async {
    try {
      final raw = await _storage.read(key: storageKey);
      if (raw == null || raw.isEmpty) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((item) => SavedAccount.fromJson(Map<String, Object?>.from(item)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> save(SavedAccount account) async {
    final accounts = await load();
    final next = [account, ...accounts.where((item) => item.id != account.id)];
    await _write(next);
  }

  Future<void> remove(String id) async {
    final accounts = await load();
    await _write(accounts.where((item) => item.id != id).toList());
  }

  Future<void> _write(List<SavedAccount> accounts) {
    return _storage.write(
      key: storageKey,
      value: jsonEncode(accounts.map((item) => item.toJson()).toList()),
    );
  }
}

SavedAccount? newestMatch(
  List<SavedAccount> accounts, {
  required RemoteProtocol protocol,
  required String host,
  required int port,
}) {
  final matches =
      accounts
          .where(
            (account) =>
                account.protocol == protocol &&
                account.host.toLowerCase() == host.toLowerCase() &&
                account.port == port,
          )
          .toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  if (matches.isEmpty) return null;
  return matches.first;
}
