import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gamevault/main.dart';
import 'package:gamevault/models/game.dart';
import 'package:gamevault/services/demo_auth_store.dart';
import 'package:gamevault/state/game_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const first = Game(
    id: 'first',
    title: 'Alpha',
    rating: 8,
    genre: 'RPG',
    releaseYear: 2018,
  );
  const second = Game(
    id: 'second',
    title: 'Beta',
    releaseYear: 2020,
    status: GameStatus.playing,
    completionPercentage: 45,
    playtimeHours: 12,
  );

  test('filters and sorts the collection', () {
    final store = GameStore([first, second]);
    expect(store.filterGames(query: 'alp').single.id, 'first');
    expect(store.filterGames(genre: 'RPG').single.id, 'first');
    expect(store.filterGames(status: 'Playing').single.id, 'second');
    expect(store.filterGames(sort: 'Title A–Z').first.id, 'first');
    expect(store.filterGames(sort: 'Progress').first.id, 'second');
    expect(store.filterGames(sort: 'Rating').first.id, 'first');
    expect(store.filterGames(sort: 'Release year').first.id, 'second');
    expect(store.filterGames(sort: 'Playtime').first.id, 'second');
    expect(store.averageRating, 8);
    expect(Game.decodeList(jsonEncode([first.toJson()])).single.id, 'first');
  });

  test('supports add, edit, delete, wishlist, and reset', () {
    final store = GameStore([first]);
    store.add(second);
    store.toggleWishlist('first');
    expect(store.games.first.isInWishlist, isTrue);
    store.update(first.copyWith(isFavorite: true));
    expect(store.games.first.isFavorite, isTrue);
    store.delete('second');
    expect(store.games, hasLength(1));
    store.reset();
    expect(store.games.map((game) => game.id), ['first']);
  });

  test('loads and persists the saved collection', () async {
    SharedPreferences.setMockInitialValues({
      'gamevault.games.v1': jsonEncode([first.toJson()]),
    });
    final store = await GameStore.load(const []);
    expect(store.games.single.id, 'first');
    store.add(second);
    await store.flush();
    final preferences = await SharedPreferences.getInstance();
    expect(
      Game.decodeList(preferences.getString('gamevault.games.v1')!).length,
      2,
    );
  });

  test('rejects corrupt collection data instead of replacing it', () async {
    SharedPreferences.setMockInitialValues({
      'gamevault.games.v1': 'not valid json',
    });
    await expectLater(GameStore.load(const []), throwsFormatException);
  });

  test(
    'registers hashed accounts, rejects duplicates, and restores sessions',
    () async {
      SharedPreferences.setMockInitialValues({});
      var auth = await DemoAuthStore.load();
      await auth.register(
        username: 'PlayerOne',
        email: 'player@example.test',
        password: 'securepass1',
      );

      final preferences = await SharedPreferences.getInstance();
      final accounts = jsonDecode(
        preferences.getString('gamevault.accounts.v1')!,
      ) as List<dynamic>;
      final savedAccount = accounts.single as Map<String, dynamic>;
      expect(savedAccount['passwordHash'], isNot('securepass1'));
      expect(savedAccount['salt'], isNotEmpty);
      await expectLater(
        auth.register(
          username: 'playerone',
          email: 'other@example.test',
          password: 'securepass1',
        ),
        throwsA(isA<DemoAuthException>()),
      );
      await expectLater(
        auth.register(
          username: 'OtherPlayer',
          email: 'PLAYER@example.test',
          password: 'securepass1',
        ),
        throwsA(isA<DemoAuthException>()),
      );
      expect(
        await auth.signIn(identifier: 'PlayerOne', password: 'wrongpass1'),
        isNull,
      );
      expect(
        (await auth.signIn(
          identifier: 'player@example.test',
          password: 'securepass1',
        ))?.username,
        'PlayerOne',
      );

      auth = await DemoAuthStore.load();
      expect(auth.currentAccount?.email, 'player@example.test');
      await auth.signOut();
      expect((await DemoAuthStore.load()).currentAccount, isNull);
    },
  );

  testWidgets('renders the empty GameVault dashboard', (tester) async {
    for (final size in [
      const Size(1440, 900),
      const Size(768, 1024),
      const Size(375, 812),
    ]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          home: GameVaultShell(
            store: GameStore(const []),
            signedInEmail: 'demo@example.test',
            onLogout: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Welcome to GameVault'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
