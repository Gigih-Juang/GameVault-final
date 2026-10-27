# Local game assets

Add your own game artwork in a folder per game, for example:

```text
assets/games/my_game/icon.png
assets/games/my_game/banner.jpg
assets/games/my_game/gameplay_01.jpg
```

Then reference the exact paths in `lib/data/sample_games.dart`. This directory
is registered in `pubspec.yaml`; run `flutter pub get` after adding files.
Missing or invalid files display a neutral fallback and are never replaced
with another game's artwork.
