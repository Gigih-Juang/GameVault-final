# GameVault

GameVault is a Flutter Web game backlog tracker. It contains no remote game
catalog or game artwork: add only information and images you provide.

## Run locally

1. Install Flutter and the Flutter/Dart VS Code extensions.
2. Open the project folder in VS Code.
3. In the integrated terminal, run:

```powershell
flutter pub get
flutter run -d chrome
```

Sign up and sign in use local demo accounts stored in this browser's
preferences. Passwords are stored as salted PBKDF2-HMAC-SHA-256 hashes, never
as plaintext, and the signed-in session is restored after a refresh. This is
not secure production authentication: browser storage and the client-side app
can be inspected or modified, and anyone with access to this browser profile
can access or delete its data. A stored hash can still be attacked offline, so
do not reuse a sensitive password. Accounts are not synchronized to another
browser or device and can be removed by clearing browser site data.

The collection persists in the current browser's local preferences; imported
image bytes are stored in that browser's IndexedDB. This data is not
synchronized to another browser or device, is not in the Git repository, and
can be removed by clearing browser site data. Browser quotas may limit
storage; GameVault reports save failures.

## Project structure

```text
assets/games/                    Your bundled game images
assets/images/profile_photo.jpg  Optional About Me portrait
lib/data/sample_games.dart       Game metadata supplied by you
lib/models/game.dart             Game model and status enum
lib/services/browser_image_store.dart IndexedDB image storage
lib/state/game_store.dart        Shared state and browser-persistent metadata
lib/services/demo_auth_store.dart Local demo accounts and sessions
lib/widgets/                     Images and demo sign-in/sign-up UI
lib/main.dart                    App shell, pages, forms, and interactions
test/widget_test.dart            Store and widget tests
```

## Add game information and bundled artwork

Edit `lib/data/sample_games.dart`; do not add details you have not supplied.
For example, use your own values:

```dart
const List<Game> sampleGames = [
  Game(
    id: 'my_game',
    title: 'Your title',
    genre: 'Your genre',
    platforms: ['Your platform'],
    rating: 8.5,
    synopsis: 'Your synopsis',
    iconAsset: 'assets/games/my_game/icon.png',
    bannerAsset: 'assets/games/my_game/banner.jpg',
    gameplayAssets: ['assets/games/my_game/gameplay_01.jpg'],
  ),
];
```

Place the referenced files under `assets/games/<game_id>/`. `assets/games/`
is registered in `pubspec.yaml`; keep the exact paths in the dataset. Missing
images use neutral fallbacks. Rating is optional and validated on the 0–10
scale. Empty synopsis, rating, or asset path is not fabricated or fetched.

You can also import images through Add/Edit Game. Use the exact fields
**Icon Asset Path**, **Banner Asset Path**, and **Gameplay Image Path** for
bundled local files, or the adjacent upload controls for browser-local images.
PNG, JPEG, GIF, and WebP files up to 5 MB each are accepted; gameplay imports
are limited to 12 images, and pending imports are capped at 20 MB per game.
Imported files remain in this browser's IndexedDB
after refresh but are not added to the project or shared with other devices.
Add bundled assets to Git if they should ship with the website.

## About Me photo (optional)

No portrait is included. To add your own:

1. In VS Code Explorer, expand `assets`, then `images`.
2. Copy your chosen photo into that folder and rename it exactly
   `profile_photo.jpg` (or update the path in `lib/main.dart` to match its
   extension/name).
3. Confirm `assets/images/` remains listed in `pubspec.yaml`.
4. Run `flutter run -d chrome` and open **About Me** to check the photo.
5. When ready to publish, run these commands in the project terminal:

```powershell
git add assets/images/profile_photo.jpg
git commit -m "Add About Me profile photo"
git push
```

   GitHub Actions will rebuild and publish the bundled image after the push,
   provided Pages is configured as described below.

The About Me page uses the supplied profile details. The optional bundled
portrait is not uploaded anywhere by GameVault.

## Test and release build

```powershell
flutter pub get
flutter analyze
flutter test
flutter build web --release
```

## GitHub Pages

For a repository named `your-repository`, build with:

```powershell
flutter build web --release --base-href "/your-repository/"
```

The included `.github/workflows/deploy-pages.yml` uses the repository name
automatically when `main` is pushed or the workflow is manually run. In the
repository, open **Settings → Pages**, set the source to **GitHub Actions**,
and wait for a successful workflow run. A local build is not a deployment;
GitHub Pages hosting does not provide a database or cross-device account sync.
