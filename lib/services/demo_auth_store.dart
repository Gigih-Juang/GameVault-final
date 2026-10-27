import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DemoAccount {
  const DemoAccount({required this.username, required this.email});

  final String username;
  final String email;
}

class DemoAuthException implements Exception {
  const DemoAuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _StoredAccount {
  const _StoredAccount({
    required this.username,
    required this.email,
    required this.salt,
    required this.passwordHash,
  });

  final String username;
  final String email;
  final String salt;
  final String passwordHash;

  DemoAccount get publicAccount =>
      DemoAccount(username: username, email: email);

  Map<String, Object> toJson() => {
    'username': username,
    'email': email,
    'salt': salt,
    'passwordHash': passwordHash,
  };

  factory _StoredAccount.fromJson(Object? json) {
    if (json is! Map<String, dynamic> ||
        json['username'] is! String ||
        json['email'] is! String ||
        json['salt'] is! String ||
        json['passwordHash'] is! String) {
      throw const FormatException('A saved GameVault account is invalid.');
    }
    return _StoredAccount(
      username: json['username'] as String,
      email: json['email'] as String,
      salt: json['salt'] as String,
      passwordHash: json['passwordHash'] as String,
    );
  }
}

class DemoAuthStore {
  DemoAuthStore._(this._preferences, this._accounts, this.currentAccount);

  static const _accountsKey = 'gamevault.accounts.v1';
  static const _sessionKey = 'gamevault.session.v1';
  static const _hashIterations = 120000;

  static final _passwordHasher = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: _hashIterations,
    bits: 256,
  );
  static final _secureRandom = Random.secure();

  final SharedPreferences _preferences;
  final List<_StoredAccount> _accounts;
  DemoAccount? currentAccount;

  static Future<DemoAuthStore> load() async {
    final preferences = await SharedPreferences.getInstance();
    final encodedAccounts = preferences.getString(_accountsKey);
    final List<_StoredAccount> accounts;
    if (encodedAccounts == null) {
      accounts = [];
    } else {
      final decoded = jsonDecode(encodedAccounts);
      if (decoded is! List) {
        throw const FormatException('Saved GameVault accounts are invalid.');
      }
      accounts = decoded.map(_StoredAccount.fromJson).toList();
    }

    final sessionIdentifier = preferences.getString(_sessionKey);
    final current = sessionIdentifier == null
        ? null
        : _findAccount(accounts, sessionIdentifier)?.publicAccount;
    if (sessionIdentifier != null && current == null) {
      await preferences.remove(_sessionKey);
    }
    return DemoAuthStore._(preferences, accounts, current);
  }

  static Future<void> clearSavedData() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_accountsKey);
    await preferences.remove(_sessionKey);
  }

  Future<void> register({
    required String username,
    required String email,
    required String password,
  }) async {
    final normalizedUsername = username.trim();
    final normalizedEmail = email.trim();
    if (_accounts.any(
      (account) =>
          account.username.toLowerCase() == normalizedUsername.toLowerCase(),
    )) {
      throw const DemoAuthException('That username is already registered.');
    }
    if (_accounts.any(
      (account) => account.email.toLowerCase() == normalizedEmail.toLowerCase(),
    )) {
      throw const DemoAuthException(
        'That email address is already registered.',
      );
    }

    final salt = List<int>.generate(16, (_) => _secureRandom.nextInt(256));
    final passwordHash = await _hashPassword(password, salt);
    final account = _StoredAccount(
      username: normalizedUsername,
      email: normalizedEmail,
      salt: base64Encode(salt),
      passwordHash: base64Encode(passwordHash),
    );
    final updatedAccounts = [..._accounts, account];
    final saved = await _preferences.setString(
      _accountsKey,
      jsonEncode(updatedAccounts.map((item) => item.toJson()).toList()),
    );
    if (!saved) {
      throw const DemoAuthException(
        'The browser could not save this account. Check available storage and try again.',
      );
    }
    _accounts.add(account);
  }

  Future<DemoAccount?> signIn({
    required String identifier,
    required String password,
  }) async {
    final normalizedIdentifier = identifier.trim().toLowerCase();
    final account = _accounts.cast<_StoredAccount?>().firstWhere(
      (item) =>
          item != null &&
          (item.username.toLowerCase() == normalizedIdentifier ||
              item.email.toLowerCase() == normalizedIdentifier),
      orElse: () => null,
    );
    if (account == null) return null;

    final salt = base64Decode(account.salt);
    final expectedHash = base64Decode(account.passwordHash);
    final actualHash = await _hashPassword(password, salt);
    if (!_constantTimeEquals(actualHash, expectedHash)) return null;

    final saved = await _preferences.setString(_sessionKey, account.email);
    if (!saved) {
      throw const DemoAuthException(
        'The browser could not save your sign-in session.',
      );
    }
    currentAccount = account.publicAccount;
    return currentAccount;
  }

  Future<void> signOut() async {
    final removed = await _preferences.remove(_sessionKey);
    if (!removed && _preferences.containsKey(_sessionKey)) {
      throw const DemoAuthException(
        'The browser could not clear your sign-in session.',
      );
    }
    currentAccount = null;
  }

  static _StoredAccount? _findAccount(
    List<_StoredAccount> accounts,
    String identifier,
  ) {
    final normalized = identifier.toLowerCase();
    for (final account in accounts) {
      if (account.email.toLowerCase() == normalized) return account;
    }
    return null;
  }

  static Future<List<int>> _hashPassword(
    String password,
    List<int> salt,
  ) async {
    final key = await _passwordHasher.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
    return key.extractBytes();
  }

  static bool _constantTimeEquals(List<int> first, List<int> second) {
    if (first.length != second.length) return false;
    var difference = 0;
    for (var index = 0; index < first.length; index++) {
      difference |= first[index] ^ second[index];
    }
    return difference == 0;
  }
}
