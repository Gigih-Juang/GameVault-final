import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'data/sample_games.dart';
import 'models/game.dart';
import 'services/browser_image_store.dart';
import 'services/demo_auth_store.dart';
import 'state/game_store.dart';
import 'theme/app_theme.dart';
import 'widgets/demo_auth_screen.dart';
import 'widgets/game_image.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final store = await GameStore.load(sampleGames);
    final authStore = await DemoAuthStore.load();
    runApp(GameVaultApp(store: store, authStore: authStore));
  } catch (error) {
    runApp(_StartupErrorApp(error: error));
  }
}

class GameVaultApp extends StatelessWidget {
  const GameVaultApp({super.key, required this.store, required this.authStore});

  final GameStore store;
  final DemoAuthStore authStore;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GameVault',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: _DemoSessionGate(store: store, authStore: authStore),
    );
  }
}

class _StartupErrorApp extends StatefulWidget {
  const _StartupErrorApp({required this.error});

  final Object error;

  @override
  State<_StartupErrorApp> createState() => _StartupErrorAppState();
}

class _StartupErrorAppState extends State<_StartupErrorApp> {
  String? _recoveryError;

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: AppTheme.dark,
    home: Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'GameVault could not read its saved browser data. Existing data was not replaced. '
                  'Back up browser data before clearing it if you need the saved collection.\n\n${widget.error}',
                  textAlign: TextAlign.center,
                ),
                if (_recoveryError != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _recoveryError!,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ],
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: _clearCorruptData,
                  child: const Text('Clear saved data and start fresh'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> _clearCorruptData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear saved GameVault data?'),
        content: const Text(
          'This permanently deletes the unreadable collection and all imported images in this browser.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear data'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await BrowserImageStore.instance.clear();
      await GameStore.clearSavedCollection();
      await DemoAuthStore.clearSavedData();
      final store = await GameStore.load(sampleGames);
      final authStore = await DemoAuthStore.load();
      runApp(GameVaultApp(store: store, authStore: authStore));
    } catch (error) {
      if (mounted) {
        setState(() => _recoveryError = 'Could not clear saved data: $error');
      }
    }
  }
}

class _DemoSessionGate extends StatefulWidget {
  const _DemoSessionGate({required this.store, required this.authStore});

  final GameStore store;
  final DemoAuthStore authStore;

  @override
  State<_DemoSessionGate> createState() => _DemoSessionGateState();
}

class _DemoSessionGateState extends State<_DemoSessionGate> {
  DemoAccount? _account;

  @override
  void initState() {
    super.initState();
    _account = widget.authStore.currentAccount;
  }

  @override
  Widget build(BuildContext context) => _account == null
      ? DemoAuthScreen(
          onSignIn: (identifier, password) async {
            final account = await widget.authStore.signIn(
              identifier: identifier,
              password: password,
            );
            if (account != null && mounted) {
              setState(() => _account = account);
            }
            return account;
          },
          onSignUp: (username, email, password) => widget.authStore.register(
            username: username,
            email: email,
            password: password,
          ),
        )
      : GameVaultShell(
          store: widget.store,
          signedInEmail: _account!.email,
          onLogout: _signOut,
        );

  Future<void> _signOut() async {
    try {
      await widget.authStore.signOut();
      if (mounted) setState(() => _account = null);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not sign out: $error')));
      }
    }
  }
}

enum VaultPage { dashboard, library, wishlist, statistics, aboutMe, settings }

class GameVaultShell extends StatefulWidget {
  const GameVaultShell({
    super.key,
    required this.store,
    required this.signedInEmail,
    required this.onLogout,
  });

  final GameStore store;
  final String signedInEmail;
  final VoidCallback onLogout;

  @override
  State<GameVaultShell> createState() => _GameVaultShellState();
}

class _GameVaultShellState extends State<GameVaultShell> {
  VaultPage _page = VaultPage.dashboard;
  String _query = '';
  String _genre = 'All genres';
  String _status = 'All statuses';
  String _sort = 'Recently added';
  int _heroIndex = 0;
  late final Timer _heroTimer;

  @override
  void initState() {
    super.initState();
    _heroTimer = Timer.periodic(const Duration(seconds: 7), (_) {
      if (!mounted || MediaQuery.maybeOf(context)?.disableAnimations == true) {
        return;
      }
      if (_page != VaultPage.dashboard) return;
      final banners = widget.store.games
          .where(
            (game) =>
                game.bannerImageId != null ||
                (game.bannerAsset?.trim().isNotEmpty ?? false),
          )
          .toList();
      if (banners.length > 1) {
        setState(() => _heroIndex = (_heroIndex + 1) % banners.length);
      }
    });
  }

  @override
  void dispose() {
    _heroTimer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        final width = MediaQuery.sizeOf(context).width;
        final compact = width < 850;
        return Scaffold(
          drawer: compact ? Drawer(child: _navigation()) : null,
          body: Row(
            children: [
              if (!compact) SizedBox(width: 248, child: _navigation()),
              Expanded(
                child: Column(
                  children: [
                    _topBar(compact),
                    if (widget.store.persistenceError != null)
                      MaterialBanner(
                        content: Text(widget.store.persistenceError!),
                        leading: const Icon(Icons.warning_amber_rounded),
                        actions: [
                          TextButton(
                            onPressed: widget.store.retrySave,
                            child: const Text('Retry save'),
                          ),
                        ],
                      ),
                    Expanded(child: _content()),
                  ],
                ),
              ),
            ],
          ),
          floatingActionButton: _page == VaultPage.library
              ? FloatingActionButton.extended(
                  onPressed: _addGame,
                  icon: const Icon(Icons.add),
                  label: const Text('Add game'),
                )
              : null,
        );
      },
    );
  }

  Widget _navigation() {
    const items = [
      (VaultPage.dashboard, Icons.space_dashboard_rounded, 'Dashboard'),
      (VaultPage.library, Icons.grid_view_rounded, 'My Library'),
      (VaultPage.wishlist, Icons.favorite_border_rounded, 'Wishlist'),
      (VaultPage.statistics, Icons.query_stats_rounded, 'Statistics'),
      (VaultPage.aboutMe, Icons.account_circle_outlined, 'About Me'),
      (VaultPage.settings, Icons.settings_outlined, 'Settings'),
    ];
    return Material(
      color: AppTheme.sidebar,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 30, 14, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 4, 0, 36),
              child: Row(
                children: [
                  Icon(
                    Icons.sports_esports_rounded,
                    color: AppTheme.blue,
                    size: 26,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'GAMEVAULT',
                    style: TextStyle(
                      fontSize: 15,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 0, 0, 10),
              child: Text(
                'MENU',
                style: TextStyle(
                  color: AppTheme.muted,
                  fontSize: 10,
                  letterSpacing: 1.6,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: ListTile(
                  dense: true,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  selected: _page == item.$1,
                  selectedTileColor: AppTheme.blue.withValues(alpha: .14),
                  leading: Icon(
                    item.$2,
                    color: _page == item.$1 ? AppTheme.blue : AppTheme.muted,
                    size: 20,
                  ),
                  title: Text(
                    item.$3,
                    style: TextStyle(
                      color: _page == item.$1
                          ? Colors.white
                          : AppTheme.secondaryText,
                      fontWeight: _page == item.$1
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                  onTap: () {
                    setState(() => _page = item.$1);
                    Navigator.of(context).maybePop();
                  },
                ),
              ),
            const Spacer(),
            ListTile(
              dense: true,
              leading: const Icon(Icons.logout_rounded, color: AppTheme.muted),
              title: const Text(
                'Sign Out',
                style: TextStyle(color: AppTheme.secondaryText),
              ),
              onTap: widget.onLogout,
            ),
            Container(
              margin: const EdgeInsets.all(5),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.panel,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.line),
              ),
              child: Text(
                'Signed in as ${widget.signedInEmail}\n\nYour collection is saved only in this browser.',
                style: const TextStyle(
                  color: AppTheme.secondaryText,
                  height: 1.55,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topBar(bool compact) {
    return Container(
      height: 78,
      padding: EdgeInsets.symmetric(horizontal: compact ? 18 : 34),
      decoration: const BoxDecoration(
        color: AppTheme.background,
        border: Border(bottom: BorderSide(color: AppTheme.line)),
      ),
      child: Row(
        children: [
          if (compact)
            Builder(
              builder: (context) => IconButton(
                icon: const Icon(Icons.menu_rounded),
                onPressed: () => Scaffold.of(context).openDrawer(),
              ),
            ),
          Text(
            _pageTitle,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          if (_page == VaultPage.library || _page == VaultPage.wishlist)
            SizedBox(
              width: compact ? 150 : 250,
              height: 40,
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Search games...',
                  prefixIcon: Icon(Icons.search, size: 19),
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
          if (!compact) ...[
            const SizedBox(width: 16),
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppTheme.panel,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.person_outline, color: AppTheme.blue),
            ),
          ],
        ],
      ),
    );
  }

  String get _pageTitle => switch (_page) {
    VaultPage.dashboard => 'Dashboard',
    VaultPage.library => 'My Library',
    VaultPage.wishlist => 'Wishlist',
    VaultPage.statistics => 'Statistics',
    VaultPage.aboutMe => 'About Me',
    VaultPage.settings => 'Settings',
  };

  Widget _content() => SingleChildScrollView(
    padding: EdgeInsets.fromLTRB(
      MediaQuery.sizeOf(context).width < 600 ? 18 : 34,
      28,
      MediaQuery.sizeOf(context).width < 600 ? 18 : 34,
      40,
    ),
    child: switch (_page) {
      VaultPage.dashboard => _dashboard(),
      VaultPage.library => _library(),
      VaultPage.wishlist => _wishlist(),
      VaultPage.statistics => _statistics(),
      VaultPage.aboutMe => _aboutMe(),
      VaultPage.settings => _settings(),
    },
  );

  Widget _dashboard() {
    final games = widget.store.games;
    final playing = games
        .where((game) => game.status == GameStatus.playing)
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _welcomeBanner(games),
        const SizedBox(height: 26),
        _sectionTitle(
          'Your overview',
          'Calculated from your current collection',
        ),
        const SizedBox(height: 15),
        _statGrid([
          _StatData('Total games', '${games.length}', Icons.sports_esports),
          _StatData(
            'Playing now',
            '${_count(GameStatus.playing)}',
            Icons.play_circle_outline,
          ),
          _StatData(
            'Completed',
            '${_count(GameStatus.completed)}',
            Icons.task_alt,
          ),
          _StatData(
            'Playtime',
            '${_formatHours(widget.store.totalPlaytime)}h',
            Icons.schedule,
          ),
        ]),
        const SizedBox(height: 30),
        _sectionTitle('Continue playing', 'Pick up where you left off'),
        const SizedBox(height: 12),
        if (playing.isEmpty)
          _emptyCard(
            Icons.play_circle_outline,
            'Nothing in progress yet',
            'Games you mark as “Playing” will show up here.',
          )
        else
          _gameGrid(playing),
        const SizedBox(height: 25),
        _sectionTitle('Recently added', 'Your newest additions'),
        const SizedBox(height: 12),
        if (games.isEmpty)
          _emptyCard(
            Icons.library_add_outlined,
            'Your vault is ready',
            'Add your own game data and local artwork to start building your collection.',
            action: _addGame,
          )
        else
          _gameGrid(games.reversed.take(4).toList()),
      ],
    );
  }

  Widget _welcomeBanner(List<Game> games) {
    final banners = games
        .where(
          (game) =>
              game.bannerImageId != null ||
              (game.bannerAsset?.trim().isNotEmpty ?? false),
        )
        .toList();
    final selected = banners.isEmpty
        ? null
        : banners[_heroIndex % banners.length];
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 210),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF17365F), Color(0xFF12233D), Color(0xFF111926)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.line),
      ),
      child: Stack(
        children: [
          if (selected != null)
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 750),
                  child: Opacity(
                    key: ValueKey(selected.id),
                    opacity: .28,
                    child: _gameImage(
                      selected.bannerAsset,
                      icon: Icons.image_outlined,
                      browserImageId: selected.bannerImageId,
                    ),
                  ),
                ),
              ),
            ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: const LinearGradient(
                  colors: [
                    Color(0xCC101B2B),
                    Color(0x66101824),
                    Color(0xAA101722),
                  ],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'YOUR PERSONAL GAME LIBRARY',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.8,
                    color: Color(0xFF9CC9FF),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 15),
                const Text(
                  'Welcome to GameVault',
                  style: TextStyle(fontSize: 29, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                const Text(
                  'A calm home for the games you own, play, and plan to finish.',
                  style: TextStyle(color: AppTheme.secondaryText, height: 1.5),
                ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: _addGame,
                  icon: const Icon(Icons.add),
                  label: const Text('Add a game'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _library() {
    final genres = {
      'All genres',
      ...widget.store.games
          .map((game) => game.genre)
          .whereType<String>()
          .where((genre) => genre.trim().isNotEmpty),
    };
    final statuses = ['All statuses', ...GameStatus.values.map((e) => e.label)];
    final games = widget.store.filterGames(
      query: _query,
      genre: _genre,
      status: _status,
      sort: _sort,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(
          'All games',
          '${widget.store.games.length} titles in your vault',
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _dropdown(
              _genre,
              genres.toList(),
              (value) => setState(() => _genre = value),
            ),
            _dropdown(
              _status,
              statuses,
              (value) => setState(() => _status = value),
            ),
            _dropdown(_sort, [
              'Recently added',
              'Title A–Z',
              'Release year',
              'Rating',
              'Playtime',
              'Progress',
            ], (value) => setState(() => _sort = value)),
          ],
        ),
        const SizedBox(height: 22),
        if (games.isEmpty)
          _emptyCard(
            Icons.grid_view_rounded,
            widget.store.games.isEmpty ? 'No games yet' : 'No matches found',
            widget.store.games.isEmpty
                ? 'Add a game using your own information and local assets.'
                : 'Try changing your search or filters.',
            action: widget.store.games.isEmpty ? _addGame : null,
          )
        else
          _gameGrid(games),
      ],
    );
  }

  Widget _wishlist() {
    final games = widget.store.games
        .where((game) => game.isInWishlist)
        .where(
          (game) => game.title.toLowerCase().contains(_query.toLowerCase()),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Your wishlist', '${games.length} games saved for later'),
        const SizedBox(height: 20),
        if (games.isEmpty)
          _emptyCard(
            Icons.favorite_border,
            'Wishlist is empty',
            'Mark a game as wanted to keep it on your wishlist.',
          )
        else
          _gameGrid(games),
      ],
    );
  }

  Widget _statistics() {
    final total = widget.store.games.length;
    final statuses = GameStatus.values;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(
          'Collection statistics',
          'Live totals from your game data',
        ),
        const SizedBox(height: 18),
        _statGrid([
          _StatData('Total games', '$total', Icons.sports_esports),
          _StatData(
            'Completed',
            '${_count(GameStatus.completed)}',
            Icons.task_alt,
          ),
          _StatData(
            'Currently playing',
            '${_count(GameStatus.playing)}',
            Icons.play_circle,
          ),
          _StatData(
            'Total playtime',
            '${_formatHours(widget.store.totalPlaytime)}h',
            Icons.schedule,
          ),
          _StatData(
            'Average rating',
            widget.store.averageRating?.toStringAsFixed(1) ?? '—',
            Icons.star_outline,
          ),
          _StatData(
            'Want to Play',
            '${_count(GameStatus.backlog)}',
            Icons.bookmark_border,
          ),
        ]),
        const SizedBox(height: 25),
        _sectionTitle('Status distribution', 'Games by your current status'),
        const SizedBox(height: 14),
        for (final status in statuses)
          _distributionRow(
            status.label,
            _count(status),
            total == 0 ? 0 : _count(status) / total,
          ),
        const SizedBox(height: 20),
        _sectionTitle('Completion', 'Average progress across your collection'),
        const SizedBox(height: 12),
        _distributionRow(
          'Average completion',
          total == 0
              ? 0
              : (widget.store.games.fold<int>(
                          0,
                          (sum, game) => sum + game.completionPercentage,
                        ) /
                        total)
                    .round(),
          total == 0
              ? 0
              : widget.store.games.fold<int>(
                      0,
                      (sum, game) => sum + game.completionPercentage,
                    ) /
                    total /
                    100,
          suffix: '%',
        ),
      ],
    );
  }

  Widget _settings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Settings', 'About your local GameVault'),
        const SizedBox(height: 18),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: _panelDecoration(),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'GameVault',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                'A private, client-side game backlog tracker. Game details and artwork are provided by you; the app does not fetch game data or use external image services.',
                style: TextStyle(color: AppTheme.secondaryText, height: 1.6),
              ),
              SizedBox(height: 12),
              Text(
                'Changes made in the app remain in memory for this session and are lost when the browser is refreshed.',
                style: TextStyle(color: AppTheme.secondaryText, height: 1.6),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        FilledButton.tonalIcon(
          onPressed: () async {
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Clear local GameVault data?'),
                content: const Text(
                  'This permanently deletes the saved collection and all images imported into this browser. Bundled data in the project is not deleted. This cannot be undone.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Clear data'),
                  ),
                ],
              ),
            );
            if (confirmed == true) {
              try {
                await BrowserImageStore.instance.clear();
                await widget.store.clearPersistentCollection(
                  resetTo: sampleGames,
                );
              } catch (error) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Could not clear local data: $error'),
                    ),
                  );
                }
              }
            }
          },
          icon: const Icon(Icons.delete_outline),
          label: const Text('Clear local data'),
        ),
      ],
    );
  }

  Widget _aboutMe() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(30),
          decoration: _panelDecoration(),
          child: Column(
            children: [
              ClipOval(
                child: SizedBox(
                  width: 144,
                  height: 144,
                  child: Image.asset(
                    'assets/image/tes.jpg',
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stack) => Container(
                      color: const Color(0xFF1A2637),
                      child: const Icon(
                        Icons.person_outline,
                        size: 76,
                        color: AppTheme.muted,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              const Text(
                'GIGIH JUANG PRANANTA',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .6,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'NIM  25051204416',
                style: TextStyle(color: AppTheme.secondaryText),
              ),
              const SizedBox(height: 8),
              const Text(
                'Prodi  Teknik Informatika 2025I',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.secondaryText),
              ),
              const SizedBox(height: 24),
              const Text(
                '“Just Prove Yourself”',
                style: TextStyle(
                  color: AppTheme.blue,
                  fontSize: 19,
                  fontWeight: FontWeight.w600,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  int _count(GameStatus status) =>
      widget.store.games.where((game) => game.status == status).length;

  Widget _sectionTitle(String title, String subtitle) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(color: AppTheme.muted, fontSize: 12),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _statGrid(List<_StatData> items) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 950
            ? 4
            : constraints.maxWidth > 560
            ? 2
            : 1;
        final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: items
              .map(
                (item) => SizedBox(
                  width: width,
                  child: Container(
                    padding: const EdgeInsets.all(17),
                    decoration: _panelDecoration(),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: AppTheme.blue.withValues(alpha: .13),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            item.icon,
                            color: AppTheme.blue,
                            size: 21,
                          ),
                        ),
                        const SizedBox(width: 13),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.value,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              item.label,
                              style: const TextStyle(
                                color: AppTheme.muted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _gameGrid(List<Game> games) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 1050
            ? 4
            : constraints.maxWidth > 720
            ? 3
            : constraints.maxWidth > 450
            ? 2
            : 1;
        final width = (constraints.maxWidth - (columns - 1) * 14) / columns;
        return Wrap(
          spacing: 14,
          runSpacing: 14,
          children: games
              .map((game) => SizedBox(width: width, child: _gameCard(game)))
              .toList(),
        );
      },
    );
  }

  Widget _gameCard(Game game) => InkWell(
    borderRadius: BorderRadius.circular(14),
    onTap: () => _showDetails(game),
    child: Container(
      decoration: _panelDecoration(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 145,
            width: double.infinity,
            child: _gameImage(
              game.bannerAsset,
              icon: Icons.image_outlined,
              browserImageId: game.bannerImageId,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(13, 12, 9, 13),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        game.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        game.status.label,
                        style: const TextStyle(
                          color: AppTheme.muted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: game.isFavorite ? 'Remove favorite' : 'Add favorite',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => widget.store.toggleFavorite(game.id),
                  icon: Icon(
                    game.isFavorite ? Icons.favorite : Icons.favorite_border,
                    color: game.isFavorite ? AppTheme.blue : AppTheme.muted,
                    size: 19,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _gameImage(
    String? asset, {
    required IconData icon,
    String? browserImageId,
  }) => GameImage(
    assetPath: asset,
    browserImageId: browserImageId,
    fallback: icon,
  );

  Widget _emptyCard(
    IconData icon,
    String title,
    String description, {
    VoidCallback? action,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
      decoration: _panelDecoration(),
      child: Column(
        children: [
          Icon(icon, color: AppTheme.blue, size: 30),
          const SizedBox(height: 11),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            description,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.muted, fontSize: 12),
          ),
          if (action != null) ...[
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: action,
              icon: const Icon(Icons.add),
              label: const Text('Add game'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _dropdown(
    String value,
    List<String> values,
    ValueChanged<String> onChanged,
  ) {
    return DropdownButton<String>(
      value: values.contains(value) ? value : values.first,
      items: values
          .map((option) => DropdownMenuItem(value: option, child: Text(option)))
          .toList(),
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
    );
  }

  Widget _distributionRow(
    String label,
    num value,
    double fraction, {
    String suffix = '',
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          SizedBox(
            width: 145,
            child: Text(label, style: const TextStyle(fontSize: 12)),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: fraction.clamp(0, 1),
                minHeight: 8,
                backgroundColor: AppTheme.panel,
                color: AppTheme.blue,
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 42,
            child: Text(
              '$value$suffix',
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: AppTheme.secondaryText,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  BoxDecoration _panelDecoration() => BoxDecoration(
    color: AppTheme.panel,
    borderRadius: BorderRadius.circular(14),
    border: Border.all(color: AppTheme.line),
  );

  Future<void> _addGame() async {
    final game = await showDialog<Game>(
      context: context,
      builder: (context) => GameFormDialog(
        existingIds: widget.store.games.map((game) => game.id).toSet(),
      ),
    );
    if (game != null) {
      widget.store.add(game);
      await _flushWithFeedback();
    }
  }

  Future<void> _editGame(Game game) async {
    final updated = await showDialog<Game>(
      context: context,
      builder: (context) => GameFormDialog(
        game: game,
        existingIds: widget.store.games.map((game) => game.id).toSet(),
      ),
    );
    if (updated != null) {
      final previousImageIds = {
        if (game.iconImageId != null) game.iconImageId!,
        if (game.bannerImageId != null) game.bannerImageId!,
        ...game.gameplayImageIds,
      };
      final retainedImageIds = {
        if (updated.iconImageId != null) updated.iconImageId!,
        if (updated.bannerImageId != null) updated.bannerImageId!,
        ...updated.gameplayImageIds,
      };
      widget.store.update(updated);
      try {
        await widget.store.flush();
        for (final id in previousImageIds.difference(retainedImageIds)) {
          await BrowserImageStore.instance.delete(id);
        }
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'The edit is active, but saving to browser storage failed. Check local storage before leaving.',
              ),
            ),
          );
        }
      }
    }
  }

  Future<void> _flushWithFeedback() async {
    try {
      await widget.store.flush();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'The change is active, but browser storage could not save it. Check local storage before leaving.',
            ),
          ),
        );
      }
    }
  }

  void _showDetails(Game game) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        contentPadding: EdgeInsets.zero,
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 220,
                  width: double.infinity,
                  child: _gameImage(
                    game.bannerAsset,
                    icon: Icons.image_outlined,
                    browserImageId: game.bannerImageId,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        game.title,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (game.iconAsset != null || game.iconImageId != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: SizedBox(
                            width: 64,
                            height: 64,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: _gameImage(
                                game.iconAsset,
                                icon: Icons.videogame_asset_outlined,
                                browserImageId: game.iconImageId,
                              ),
                            ),
                          ),
                        ),
                      Text(
                        [
                          if (game.genre?.isNotEmpty == true) game.genre!,
                          if (game.developer?.isNotEmpty == true)
                            game.developer!,
                          if (game.platforms.isNotEmpty)
                            game.platforms.join(', '),
                          if (game.releaseYear != null) '${game.releaseYear}',
                        ].join('  •  '),
                        style: const TextStyle(color: AppTheme.muted),
                      ),
                      const SizedBox(height: 14),
                      if (game.rating != null)
                        Text(
                          'Rating  ${game.rating!.toStringAsFixed(1)} / 10',
                          style: const TextStyle(color: AppTheme.blue),
                        ),
                      if (game.synopsis?.trim().isNotEmpty == true) ...[
                        const SizedBox(height: 14),
                        Text(
                          game.synopsis!,
                          style: const TextStyle(
                            color: AppTheme.secondaryText,
                            height: 1.55,
                          ),
                        ),
                      ],
                      const SizedBox(height: 15),
                      Text(
                        '${game.status.label}  •  ${game.completionPercentage}%  •  ${_formatHours(game.playtimeHours)}h',
                        style: const TextStyle(color: AppTheme.secondaryText),
                      ),
                      if (game.personalNotes?.trim().isNotEmpty == true) ...[
                        const SizedBox(height: 12),
                        Text(
                          game.personalNotes!,
                          style: const TextStyle(color: AppTheme.muted),
                        ),
                      ],
                      if (game.gameplayAssets.isNotEmpty ||
                          game.gameplayImageIds.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        const Text(
                          'Gameplay gallery',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 100,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount:
                                game.gameplayAssets.length +
                                game.gameplayImageIds.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(width: 8),
                            itemBuilder: (context, index) => ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: SizedBox(
                                width: 150,
                                child: index < game.gameplayAssets.length
                                    ? _gameImage(
                                        game.gameplayAssets[index],
                                        icon: Icons.broken_image_outlined,
                                      )
                                    : _gameImage(
                                        null,
                                        icon: Icons.broken_image_outlined,
                                        browserImageId:
                                            game.gameplayImageIds[index -
                                                game.gameplayAssets.length],
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              _editGame(game);
                            },
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('Edit'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () {
                              if (game.isInWishlist) {
                                widget.store.update(
                                  game.copyWith(
                                    isInWishlist: false,
                                    status: GameStatus.backlog,
                                  ),
                                );
                              } else {
                                widget.store.toggleWishlist(game.id);
                              }
                            },
                            icon: Icon(
                              game.isInWishlist
                                  ? Icons.library_add_outlined
                                  : Icons.favorite_border,
                            ),
                            label: Text(
                              game.isInWishlist
                                  ? 'Move to library'
                                  : 'Add to wishlist',
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: () =>
                                widget.store.toggleFavorite(game.id),
                            icon: Icon(
                              game.isFavorite ? Icons.star : Icons.star_border,
                            ),
                            label: Text(
                              game.isFavorite ? 'Favorited' : 'Favorite',
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () => _deleteGame(game),
                            icon: const Icon(
                              Icons.delete_outline,
                              color: Colors.redAccent,
                            ),
                            label: const Text(
                              'Delete',
                              style: TextStyle(color: Colors.redAccent),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteGame(Game game) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this game?'),
        content: Text(
          '“${game.title}” will be removed from your library and wishlist.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    widget.store.delete(game.id);
    Navigator.pop(context);
    try {
      await widget.store.flush();
      final imageIds = {
        if (game.iconImageId != null) game.iconImageId!,
        if (game.bannerImageId != null) game.bannerImageId!,
        ...game.gameplayImageIds,
      };
      for (final id in imageIds) {
        await BrowserImageStore.instance.delete(id);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'The game was removed, but browser storage could not finish cleanup.',
            ),
          ),
        );
      }
    }
  }
}

String _formatHours(double hours) => hours == hours.roundToDouble()
    ? hours.round().toString()
    : hours.toStringAsFixed(1);

class _StatData {
  const _StatData(this.label, this.value, this.icon);
  final String label;
  final String value;
  final IconData icon;
}

class GameFormDialog extends StatefulWidget {
  const GameFormDialog({super.key, this.game, this.existingIds = const {}});
  final Game? game;
  final Set<String> existingIds;

  @override
  State<GameFormDialog> createState() => _GameFormDialogState();
}

class _GameFormDialogState extends State<GameFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _id;
  late final TextEditingController _title;
  late final TextEditingController _genre;
  late final TextEditingController _platforms;
  late final TextEditingController _developer;
  late final TextEditingController _year;
  late final TextEditingController _rating;
  late final TextEditingController _synopsis;
  late final TextEditingController _icon;
  late final TextEditingController _banner;
  late final TextEditingController _gameplay;
  late final TextEditingController _progress;
  late final TextEditingController _playtime;
  late final TextEditingController _notes;
  late GameStatus _status;
  late bool _favorite;
  late bool _wishlist;
  String? _iconImageId;
  String? _bannerImageId;
  List<String> _gameplayImageIds = [];
  Uint8List? _pendingIcon;
  Uint8List? _pendingBanner;
  final List<Uint8List> _pendingGameplay = [];

  @override
  void initState() {
    super.initState();
    final game = widget.game;
    _id = TextEditingController(text: game?.id ?? '');
    _title = TextEditingController(text: game?.title ?? '');
    _genre = TextEditingController(text: game?.genre ?? '');
    _platforms = TextEditingController(text: game?.platforms.join(', ') ?? '');
    _developer = TextEditingController(text: game?.developer ?? '');
    _year = TextEditingController(text: game?.releaseYear?.toString() ?? '');
    _rating = TextEditingController(text: game?.rating?.toString() ?? '');
    _synopsis = TextEditingController(text: game?.synopsis ?? '');
    _icon = TextEditingController(text: game?.iconAsset ?? '');
    _banner = TextEditingController(text: game?.bannerAsset ?? '');
    _gameplay = TextEditingController(
      text: game?.gameplayAssets.join(', ') ?? '',
    );
    _iconImageId = game?.iconImageId;
    _bannerImageId = game?.bannerImageId;
    _gameplayImageIds = List.of(game?.gameplayImageIds ?? const []);
    _progress = TextEditingController(
      text: '${game?.completionPercentage ?? 0}',
    );
    _playtime = TextEditingController(text: '${game?.playtimeHours ?? 0}');
    _notes = TextEditingController(text: game?.personalNotes ?? '');
    _status = game?.status ?? GameStatus.backlog;
    _favorite = game?.isFavorite ?? false;
    _wishlist = game?.isInWishlist ?? false;
  }

  @override
  void dispose() {
    for (final controller in [
      _id,
      _title,
      _genre,
      _platforms,
      _developer,
      _year,
      _rating,
      _synopsis,
      _icon,
      _banner,
      _gameplay,
      _progress,
      _playtime,
      _notes,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.game == null ? 'Add game' : 'Edit game'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _field(_title, 'Title *', required: true),
                _field(
                  _id,
                  'ID (leave blank to generate)',
                  readOnly: widget.game != null,
                ),
                _field(_genre, 'Genre'),
                _field(_platforms, 'Platforms (comma-separated)'),
                _field(_developer, 'Developer'),
                Row(
                  children: [
                    Expanded(
                      child: _field(_year, 'Release year', number: true),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _field(_rating, 'Rating (0–10)', number: true),
                    ),
                  ],
                ),
                _field(_synopsis, 'Synopsis', lines: 3),
                _imageField(
                  controller: _icon,
                  label: 'Icon Asset Path',
                  imageId: _iconImageId,
                  pending: _pendingIcon,
                  onPick: _pickIcon,
                  onRemove: () => setState(() {
                    _iconImageId = null;
                    _pendingIcon = null;
                    _icon.clear();
                  }),
                ),
                _imageField(
                  controller: _banner,
                  label: 'Banner Asset Path',
                  imageId: _bannerImageId,
                  pending: _pendingBanner,
                  onPick: _pickBanner,
                  onRemove: () => setState(() {
                    _bannerImageId = null;
                    _pendingBanner = null;
                    _banner.clear();
                  }),
                ),
                _field(_gameplay, 'Gameplay Image Path'),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _pickGameplay,
                    icon: const Icon(Icons.upload_file_outlined),
                    label: const Text('Upload gameplay images'),
                  ),
                ),
                if (_gameplayImageIds.isNotEmpty ||
                    _pendingGameplay.isNotEmpty ||
                    _gameplay.text.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 70,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final path in _split(_gameplay.text))
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: SizedBox(
                              width: 96,
                              height: 64,
                              child: GameImage(
                                assetPath: path,
                                fallback: Icons.broken_image_outlined,
                              ),
                            ),
                          ),
                        for (final id in _gameplayImageIds)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Stack(
                              children: [
                                SizedBox(
                                  width: 96,
                                  height: 64,
                                  child: GameImage(
                                    browserImageId: id,
                                    fallback: Icons.broken_image_outlined,
                                  ),
                                ),
                                Positioned(
                                  right: 0,
                                  top: 0,
                                  child: IconButton(
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () => setState(
                                      () => _gameplayImageIds.remove(id),
                                    ),
                                    icon: const Icon(Icons.close, size: 17),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        for (
                          var index = 0;
                          index < _pendingGameplay.length;
                          index++
                        )
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Stack(
                              children: [
                                Image.memory(
                                  _pendingGameplay[index],
                                  width: 96,
                                  height: 64,
                                  fit: BoxFit.cover,
                                ),
                                Positioned(
                                  right: 0,
                                  top: 0,
                                  child: IconButton(
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () => setState(
                                      () => _pendingGameplay.removeAt(index),
                                    ),
                                    icon: const Icon(Icons.close, size: 17),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Images imported here stay in this browser only, not in your Git repository.',
                    style: TextStyle(color: AppTheme.muted, fontSize: 11),
                  ),
                ),
                DropdownButtonFormField<GameStatus>(
                  initialValue: _status,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: GameStatus.values
                      .map(
                        (status) => DropdownMenuItem(
                          value: status,
                          child: Text(status.label),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setState(() => _status = value ?? _status),
                ),
                Row(
                  children: [
                    Expanded(
                      child: _field(_progress, 'Progress %', number: true),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _field(_playtime, 'Playtime hours', number: true),
                    ),
                  ],
                ),
                _field(_notes, 'Personal notes', lines: 2),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Favorite'),
                  value: _favorite,
                  onChanged: (value) => setState(() => _favorite = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('In wishlist'),
                  value: _wishlist,
                  onChanged: (value) => setState(() => _wishlist = value),
                ),
                const Text(
                  'Use paths such as assets/games/my_game/banner.jpg. Add the files and register their folder in pubspec.yaml.',
                  style: TextStyle(color: AppTheme.muted, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(widget.game == null ? 'Add game' : 'Save changes'),
        ),
      ],
    );
  }

  Widget _imageField({
    required TextEditingController controller,
    required String label,
    required String? imageId,
    required Uint8List? pending,
    required VoidCallback onPick,
    required VoidCallback onRemove,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _field(
                controller,
                label,
                assetPathList: false,
                onValueChanged: () => setState(() {
                  if (label == 'Icon Asset Path') {
                    _iconImageId = null;
                    _pendingIcon = null;
                  } else {
                    _bannerImageId = null;
                    _pendingBanner = null;
                  }
                }),
              ),
            ),
            IconButton(
              tooltip: 'Upload image',
              onPressed: onPick,
              icon: const Icon(Icons.upload_file_outlined),
            ),
          ],
        ),
        if (pending != null || imageId != null || controller.text.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SizedBox(
              width: 170,
              height: 84,
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: pending != null
                        ? Image.memory(
                            pending,
                            width: 170,
                            height: 84,
                            fit: BoxFit.cover,
                          )
                        : GameImage(
                            assetPath: controller.text,
                            browserImageId: imageId,
                            fallback: Icons.image_outlined,
                          ),
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: IconButton(
                      tooltip: 'Remove image',
                      onPressed: onRemove,
                      icon: const Icon(Icons.close),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool required = false,
    bool number = false,
    bool readOnly = false,
    bool assetPathList = true,
    VoidCallback? onValueChanged,
    int lines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: controller,
        maxLines: lines,
        readOnly: readOnly,
        onChanged: (_) => setState(() => onValueChanged?.call()),
        keyboardType: number
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        decoration: InputDecoration(labelText: label),
        validator: (value) {
          if (required && (value == null || value.trim().isEmpty)) {
            return 'Title is required';
          }
          if (label.startsWith('ID') &&
              value != null &&
              value.trim().isNotEmpty &&
              widget.existingIds.contains(value.trim()) &&
              value.trim() != widget.game?.id) {
            return 'This ID is already in use';
          }
          if (value != null && value.trim().isNotEmpty && number) {
            final parsed = num.tryParse(value);
            if (parsed == null) return 'Enter a valid number';
            if (!parsed.isFinite) return 'Enter a finite number';
            if ((label.startsWith('Release year') ||
                    label.startsWith('Progress')) &&
                parsed % 1 != 0) {
              return 'Enter a whole number';
            }
            if (label.startsWith('Rating') && (parsed < 0 || parsed > 10)) {
              return 'Rating must be from 0 to 10';
            }
            if (label.startsWith('Progress') && (parsed < 0 || parsed > 100)) {
              return 'Progress must be from 0 to 100';
            }
            if ((label.startsWith('Release year') ||
                    label.startsWith('Playtime')) &&
                parsed < 0) {
              return 'Value cannot be negative';
            }
            if (label.startsWith('Release year') &&
                (parsed < 1800 || parsed > 2100)) {
              return 'Enter a year between 1800 and 2100';
            }
          }
          if (value != null &&
              value.trim().isNotEmpty &&
              (label.contains('Asset Path') ||
                  label.contains('Gameplay Image Path'))) {
            final paths = assetPathList ? value.split(',') : [value];
            if (paths.any(
              (path) =>
                  !path.trim().startsWith('assets/') ||
                  path.trim().contains('://'),
            )) {
              return 'Use a bundled local path beginning with assets/';
            }
          }
          return null;
        },
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final id = _id.text.trim().isNotEmpty
        ? _id.text.trim()
        : 'game-${DateTime.now().microsecondsSinceEpoch}';
    final platforms = _split(_platforms.text);
    final gameplay = _split(_gameplay.text);
    try {
      final imageStore = BrowserImageStore.instance;
      final iconImageId = _pendingIcon == null
          ? _iconImageId
          : _newImageId('icon');
      final bannerImageId = _pendingBanner == null
          ? _bannerImageId
          : _newImageId('banner');
      final newGameplayIds = <String>[];
      for (var index = 0; index < _pendingGameplay.length; index++) {
        newGameplayIds.add(_newImageId('gameplay-$index'));
      }
      if (_pendingIcon != null) {
        await imageStore.save(iconImageId!, _pendingIcon!);
      }
      if (_pendingBanner != null) {
        await imageStore.save(bannerImageId!, _pendingBanner!);
      }
      for (var index = 0; index < newGameplayIds.length; index++) {
        await imageStore.save(newGameplayIds[index], _pendingGameplay[index]);
      }
      if (!mounted) return;
      Navigator.pop(
        context,
        Game(
          id: id,
          title: _title.text.trim(),
          genre: _nullable(_genre.text),
          platforms: platforms,
          developer: _nullable(_developer.text),
          releaseYear: int.tryParse(_year.text.trim()),
          rating: double.tryParse(_rating.text.trim()),
          synopsis: _nullable(_synopsis.text),
          iconAsset: _nullable(_icon.text),
          bannerAsset: _nullable(_banner.text),
          gameplayAssets: gameplay,
          iconImageId: iconImageId,
          bannerImageId: bannerImageId,
          gameplayImageIds: [..._gameplayImageIds, ...newGameplayIds],
          status: _status,
          completionPercentage: int.tryParse(_progress.text) ?? 0,
          playtimeHours: double.tryParse(_playtime.text) ?? 0,
          personalNotes: _nullable(_notes.text),
          isFavorite: _favorite,
          isInWishlist: _wishlist,
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not store imported image: $error')),
        );
      }
    }
  }

  String _newImageId(String kind) =>
      'gamevault-$kind-${DateTime.now().microsecondsSinceEpoch}-${_pendingGameplay.length}';

  Future<void> _pickIcon() async {
    final bytes = await _pickOneImage();
    if (bytes != null) {
      if (!_withinImageLimit([?_pendingBanner, ..._pendingGameplay, bytes])) {
        _showPickError('Imported images are limited to 20 MB per game.');
        return;
      }
      setState(() {
        _iconImageId = null;
        _pendingIcon = bytes;
        _icon.clear();
      });
    }
  }

  Future<void> _pickBanner() async {
    final bytes = await _pickOneImage();
    if (bytes != null) {
      if (!_withinImageLimit([?_pendingIcon, ..._pendingGameplay, bytes])) {
        _showPickError('Imported images are limited to 20 MB per game.');
        return;
      }
      setState(() {
        _bannerImageId = null;
        _pendingBanner = bytes;
        _banner.clear();
      });
    }
  }

  Future<Uint8List?> _pickOneImage() async {
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (picked == null) return null;
      return await _readImage(picked);
    } catch (error) {
      _showPickError(error);
      return null;
    }
  }

  Future<void> _pickGameplay() async {
    try {
      final remaining = 12 - _gameplayImageIds.length - _pendingGameplay.length;
      if (remaining <= 0) {
        _showPickError('Maximum of 12 gameplay images reached.');
        return;
      }
      final picked = await ImagePicker().pickMultiImage(limit: remaining);
      final images = <Uint8List>[];
      for (final file in picked) {
        final image = await _readImage(file);
        if (!_withinImageLimit([
          ?_pendingIcon,
          ?_pendingBanner,
          ..._pendingGameplay,
          ...images,
          image,
        ])) {
          throw const FormatException(
            'Imported images are limited to 20 MB per game.',
          );
        }
        images.add(image);
      }
      if (images.isNotEmpty && mounted) {
        setState(() => _pendingGameplay.addAll(images));
      }
    } catch (error) {
      _showPickError(error);
    }
  }

  Future<Uint8List> _readImage(XFile file) async {
    final bytes = await file.readAsBytes();
    const maxBytes = 5 * 1024 * 1024;
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw const FormatException('Image must be between 1 byte and 5 MB.');
    }
    if (!_isSupportedImage(bytes)) {
      throw const FormatException('Choose a PNG, JPEG, GIF, or WebP image.');
    }
    return bytes;
  }

  bool _isSupportedImage(Uint8List bytes) {
    final png =
        bytes.length >= 8 &&
        const [
          137,
          80,
          78,
          71,
          13,
          10,
          26,
          10,
        ].asMap().entries.every((entry) => bytes[entry.key] == entry.value);
    final jpeg =
        bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff;
    final gif =
        bytes.length >= 6 &&
        (String.fromCharCodes(bytes.take(6)) == 'GIF87a' ||
            String.fromCharCodes(bytes.take(6)) == 'GIF89a');
    final webp =
        bytes.length >= 12 &&
        String.fromCharCodes(bytes.take(4)) == 'RIFF' &&
        String.fromCharCodes(bytes.skip(8).take(4)) == 'WEBP';
    return png || jpeg || gif || webp;
  }

  bool _withinImageLimit(List<Uint8List> images) =>
      images.fold<int>(0, (total, image) => total + image.length) <=
      20 * 1024 * 1024;

  void _showPickError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Image import failed: $error')));
  }

  String? _nullable(String value) => value.trim().isEmpty ? null : value.trim();
  List<String> _split(String value) => value
      .split(',')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList();
}
