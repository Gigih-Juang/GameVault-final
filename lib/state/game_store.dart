import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/game.dart';

class GameStore extends ChangeNotifier {
  GameStore(List<Game> initialGames, {this._persist})
    : _initialGames = List.of(initialGames) {
    _games = List.of(initialGames);
  }

  static const _storageKey = 'gamevault.games.v1';
  final List<Game> _initialGames;
  final Future<void> Function(List<Game>)? _persist;
  late List<Game> _games;
  Future<void> _writeTail = Future.value();
  String? persistenceError;

  List<Game> get games => List.unmodifiable(_games);
  double get totalPlaytime =>
      _games.fold<double>(0, (total, game) => total + game.playtimeHours);
  double? get averageRating {
    final rated = _games.where((game) => game.rating != null).toList();
    if (rated.isEmpty) return null;
    return rated.fold<double>(0, (sum, game) => sum + game.rating!) /
        rated.length;
  }

  static Future<GameStore> load(List<Game> initialGames) async {
    final preferences = await SharedPreferences.getInstance();
    final stored = preferences.getString(_storageKey);
    final games = stored == null ? initialGames : Game.decodeList(stored);
    return GameStore(
      games,
      persist: (games) async {
        final encoded = jsonEncode(games.map((game) => game.toJson()).toList());
        final saved = await preferences.setString(_storageKey, encoded);
        if (!saved) {
          throw StateError(
            'Browser storage did not confirm saving the collection.',
          );
        }
      },
    );
  }

  static Future<void> clearSavedCollection() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_storageKey);
  }

  Future<void> clearPersistentCollection({
    List<Game> resetTo = const [],
  }) async {
    await _writeTail;
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_storageKey);
    _games = List.of(resetTo);
    persistenceError = null;
    notifyListeners();
  }

  Future<void> retrySave() async {
    final persist = _persist;
    if (persist == null) return;
    await _writeTail;
    try {
      await persist(List<Game>.unmodifiable(_games));
      persistenceError = null;
    } catch (error) {
      persistenceError =
          'Could not save to this browser: $error. Export or back up your data before closing this tab.';
    }
    notifyListeners();
  }

  Future<void> flush() async {
    await _writeTail;
    if (persistenceError != null) throw StateError(persistenceError!);
  }

  void add(Game game) {
    if (_games.any((existing) => existing.id == game.id)) {
      throw ArgumentError('A game with ID "${game.id}" already exists.');
    }
    _games = [..._games, game];
    _changed();
  }

  void update(Game game) {
    final index = _games.indexWhere((existing) => existing.id == game.id);
    if (index < 0) throw ArgumentError('Game "${game.id}" was not found.');
    _games = [..._games]..[index] = game;
    _changed();
  }

  void delete(String id) {
    _games = _games.where((game) => game.id != id).toList();
    _changed();
  }

  void toggleFavorite(String id) =>
      _change(id, (game) => game.copyWith(isFavorite: !game.isFavorite));

  void toggleWishlist(String id) =>
      _change(id, (game) => game.copyWith(isInWishlist: !game.isInWishlist));

  void _change(String id, Game Function(Game game) transform) {
    final index = _games.indexWhere((game) => game.id == id);
    if (index < 0) throw ArgumentError('Game "$id" was not found.');
    _games = [..._games]..[index] = transform(_games[index]);
    _changed();
  }

  void reset() {
    _games = List.of(_initialGames);
    _changed();
  }

  void _changed() {
    persistenceError = null;
    notifyListeners();
    final persist = _persist;
    if (persist == null) return;
    final snapshot = List<Game>.unmodifiable(_games);
    _writeTail = _writeTail.then((_) async {
      try {
        await persist(snapshot);
        if (persistenceError != null) {
          persistenceError = null;
          notifyListeners();
        }
      } catch (error) {
        persistenceError =
            'Could not save to this browser: $error. Export or back up your data before closing this tab.';
        notifyListeners();
      }
    });
  }

  List<Game> filterGames({
    String query = '',
    String genre = 'All genres',
    String status = 'All statuses',
    String sort = 'Recently added',
  }) {
    final normalizedQuery = query.trim().toLowerCase();
    final result = _games.where((game) {
      final matchesQuery =
          normalizedQuery.isEmpty ||
          game.title.toLowerCase().contains(normalizedQuery);
      final matchesGenre =
          genre == 'All genres' ||
          game.genre?.toLowerCase() == genre.toLowerCase();
      final matchesStatus =
          status == 'All statuses' || game.status.label == status;
      return matchesQuery && matchesGenre && matchesStatus;
    }).toList();
    switch (sort) {
      case 'Title A–Z':
        result.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
      case 'Release year':
        result.sort((a, b) {
          if (a.releaseYear == null) return b.releaseYear == null ? 0 : 1;
          if (b.releaseYear == null) return -1;
          return b.releaseYear!.compareTo(a.releaseYear!);
        });
      case 'Rating':
        result.sort((a, b) {
          if (a.rating == null) return b.rating == null ? 0 : 1;
          if (b.rating == null) return -1;
          return b.rating!.compareTo(a.rating!);
        });
      case 'Playtime':
        result.sort((a, b) => b.playtimeHours.compareTo(a.playtimeHours));
      case 'Progress':
        result.sort(
          (a, b) => b.completionPercentage.compareTo(a.completionPercentage),
        );
    }
    return result;
  }
}
