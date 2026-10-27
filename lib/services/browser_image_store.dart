import 'dart:typed_data';

import 'package:idb_shim/idb_browser.dart';
import 'package:idb_shim/idb.dart' as idb;

class BrowserImageStore {
  BrowserImageStore._();

  static final BrowserImageStore instance = BrowserImageStore._();
  static const _databaseName = 'gamevault-local-images';
  static const _storeName = 'images';
  Future<idb.Database>? _database;
  final Map<String, Uint8List> _cache = {};

  Future<idb.Database> _open() => _database ??= _openDatabase();

  Future<idb.Database> _openDatabase() async {
    final factory = getIdbFactory();
    if (factory == null) {
      throw UnsupportedError('IndexedDB is unavailable in this browser.');
    }
    return factory.open(
      _databaseName,
      version: 1,
      onUpgradeNeeded: (event) {
        if (!event.database.objectStoreNames.contains(_storeName)) {
          event.database.createObjectStore(_storeName);
        }
      },
    );
  }

  Future<void> save(String id, Uint8List bytes) async {
    final database = await _open();
    final transaction = database.transaction(_storeName, idb.idbModeReadWrite);
    await transaction.objectStore(_storeName).put(bytes.toList(), id);
    await transaction.completed;
    _cache[id] = bytes;
  }

  Future<Uint8List?> read(String id) async {
    final cached = _cache[id];
    if (cached != null) return cached;
    final database = await _open();
    final transaction = database.transaction(_storeName, idb.idbModeReadOnly);
    final value = await transaction.objectStore(_storeName).getObject(id);
    await transaction.completed;
    if (value == null) return null;
    if (value is! List) {
      throw const FormatException('Stored image has an invalid format.');
    }
    final bytes = Uint8List.fromList(value.cast<int>());
    _cache[id] = bytes;
    return bytes;
  }

  Future<void> delete(String id) async {
    final database = await _open();
    final transaction = database.transaction(_storeName, idb.idbModeReadWrite);
    await transaction.objectStore(_storeName).delete(id);
    await transaction.completed;
    _cache.remove(id);
  }

  Future<void> clear() async {
    final database = await _open();
    final transaction = database.transaction(_storeName, idb.idbModeReadWrite);
    await transaction.objectStore(_storeName).clear();
    await transaction.completed;
    _cache.clear();
  }
}
