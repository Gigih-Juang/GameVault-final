import 'dart:convert';

enum GameStatus { backlog, playing, completed, onHold, dropped }

extension GameStatusLabel on GameStatus {
  String get label => switch (this) {
    GameStatus.backlog => 'Want to Play',
    GameStatus.playing => 'Playing',
    GameStatus.completed => 'Completed',
    GameStatus.onHold => 'On Hold',
    GameStatus.dropped => 'Dropped',
  };
}

class Game {
  const Game({
    required this.id,
    required this.title,
    this.genre,
    this.platforms = const [],
    this.developer,
    this.releaseYear,
    this.rating,
    this.synopsis,
    this.iconAsset,
    this.bannerAsset,
    this.gameplayAssets = const [],
    this.iconImageId,
    this.bannerImageId,
    this.gameplayImageIds = const [],
    this.status = GameStatus.backlog,
    this.completionPercentage = 0,
    this.playtimeHours = 0,
    this.personalNotes,
    this.isFavorite = false,
    this.isInWishlist = false,
  }) : assert(completionPercentage >= 0 && completionPercentage <= 100),
       assert(rating == null || (rating >= 0 && rating <= 10)),
       assert(playtimeHours >= 0);

  final String id;
  final String title;
  final String? genre;
  final List<String> platforms;
  final String? developer;
  final int? releaseYear;
  final double? rating;
  final String? synopsis;
  final String? iconAsset;
  final String? bannerAsset;
  final List<String> gameplayAssets;
  final String? iconImageId;
  final String? bannerImageId;
  final List<String> gameplayImageIds;
  final GameStatus status;
  final int completionPercentage;
  final double playtimeHours;
  final String? personalNotes;
  final bool isFavorite;
  final bool isInWishlist;

  Game copyWith({
    String? id,
    String? title,
    String? genre,
    List<String>? platforms,
    String? developer,
    int? releaseYear,
    double? rating,
    String? synopsis,
    String? iconAsset,
    String? bannerAsset,
    List<String>? gameplayAssets,
    String? iconImageId,
    String? bannerImageId,
    List<String>? gameplayImageIds,
    GameStatus? status,
    int? completionPercentage,
    double? playtimeHours,
    String? personalNotes,
    bool? isFavorite,
    bool? isInWishlist,
  }) => Game(
    id: id ?? this.id,
    title: title ?? this.title,
    genre: genre ?? this.genre,
    platforms: platforms ?? this.platforms,
    developer: developer ?? this.developer,
    releaseYear: releaseYear ?? this.releaseYear,
    rating: rating ?? this.rating,
    synopsis: synopsis ?? this.synopsis,
    iconAsset: iconAsset ?? this.iconAsset,
    bannerAsset: bannerAsset ?? this.bannerAsset,
    gameplayAssets: gameplayAssets ?? this.gameplayAssets,
    iconImageId: iconImageId ?? this.iconImageId,
    bannerImageId: bannerImageId ?? this.bannerImageId,
    gameplayImageIds: gameplayImageIds ?? this.gameplayImageIds,
    status: status ?? this.status,
    completionPercentage: completionPercentage ?? this.completionPercentage,
    playtimeHours: playtimeHours ?? this.playtimeHours,
    personalNotes: personalNotes ?? this.personalNotes,
    isFavorite: isFavorite ?? this.isFavorite,
    isInWishlist: isInWishlist ?? this.isInWishlist,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'genre': genre,
    'platforms': platforms,
    'developer': developer,
    'releaseYear': releaseYear,
    'rating': rating,
    'synopsis': synopsis,
    'iconAsset': iconAsset,
    'bannerAsset': bannerAsset,
    'gameplayAssets': gameplayAssets,
    'iconImageId': iconImageId,
    'bannerImageId': bannerImageId,
    'gameplayImageIds': gameplayImageIds,
    'status': status.name,
    'completionPercentage': completionPercentage,
    'playtimeHours': playtimeHours,
    'personalNotes': personalNotes,
    'isFavorite': isFavorite,
    'isInWishlist': isInWishlist,
  };

  factory Game.fromJson(Map<String, Object?> json) {
    final statusName = json['status'] as String?;
    return Game(
      id: json['id'] as String,
      title: json['title'] as String,
      genre: json['genre'] as String?,
      platforms: (json['platforms'] as List<Object?>? ?? const [])
          .map((value) => value as String)
          .toList(),
      developer: json['developer'] as String?,
      releaseYear: json['releaseYear'] as int?,
      rating: (json['rating'] as num?)?.toDouble(),
      synopsis: json['synopsis'] as String?,
      iconAsset: json['iconAsset'] as String?,
      bannerAsset: json['bannerAsset'] as String?,
      gameplayAssets: (json['gameplayAssets'] as List<Object?>? ?? const [])
          .map((value) => value as String)
          .toList(),
      iconImageId: json['iconImageId'] as String?,
      bannerImageId: json['bannerImageId'] as String?,
      gameplayImageIds: (json['gameplayImageIds'] as List<Object?>? ?? const [])
          .map((value) => value as String)
          .toList(),
      status: GameStatus.values.firstWhere(
        (value) => value.name == statusName,
        orElse: () =>
            throw const FormatException('Stored game status is invalid.'),
      ),
      completionPercentage: json['completionPercentage'] as int? ?? 0,
      playtimeHours: (json['playtimeHours'] as num? ?? 0).toDouble(),
      personalNotes: json['personalNotes'] as String?,
      isFavorite: json['isFavorite'] as bool? ?? false,
      isInWishlist: json['isInWishlist'] as bool? ?? false,
    );
  }

  static List<Game> decodeList(String value) {
    final decoded = jsonDecode(value) as List<Object?>;
    final games = decoded
        .map((item) => Game.fromJson(item as Map<String, Object?>))
        .toList();
    for (final game in games) {
      if (game.id.trim().isEmpty ||
          game.title.trim().isEmpty ||
          (game.rating != null &&
              (!game.rating!.isFinite ||
                  game.rating! < 0 ||
                  game.rating! > 10)) ||
          game.completionPercentage < 0 ||
          game.completionPercentage > 100 ||
          !game.playtimeHours.isFinite ||
          game.playtimeHours < 0) {
        throw const FormatException(
          'Stored game data is outside valid ranges.',
        );
      }
    }
    final ids = games.map((game) => game.id).toSet();
    if (ids.length != games.length) {
      throw const FormatException('Stored game IDs are not unique.');
    }
    return games;
  }
}
