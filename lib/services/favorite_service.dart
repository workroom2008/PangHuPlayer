import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/media_models.dart';

class FavoriteService {
  static const String _favoritesKey = 'favorite_movies';
  static const String _watchlistKey = 'watchlist_movies';
  static const String _playlistKey = 'playlist_items';
  
  final SharedPreferences _prefs;

  FavoriteService(this._prefs);

  List<FavoriteMovie> _loadFavorites(String key) {
    final data = _prefs.getStringList(key);
    if (data == null) return [];
    return data
        .map((jsonStr) => FavoriteMovie.fromJson(json.decode(jsonStr) as Map<String, dynamic>))
        .toList();
  }

  Future<void> _saveFavorites(String key, List<FavoriteMovie> movies) async {
    final data = movies.map((m) => json.encode(m.toJson())).toList();
    await _prefs.setStringList(key, data);
  }

  List<FavoriteMovie> getFavorites() => _loadFavorites(_favoritesKey);

  Future<void> addFavorite(TMDBMovie movie) async {
    final favorites = getFavorites();
    if (!favorites.any((f) => f.tmdbId == movie.id)) {
      favorites.insert(0, FavoriteMovie.fromTMDBMovie(movie, DateTime.now()));
      await _saveFavorites(_favoritesKey, favorites);
    }
  }

  Future<void> removeFavorite(int tmdbId) async {
    final favorites = getFavorites()..removeWhere((f) => f.tmdbId == tmdbId);
    await _saveFavorites(_favoritesKey, favorites);
  }

  bool isFavorite(int tmdbId) {
    return getFavorites().any((f) => f.tmdbId == tmdbId);
  }

  List<FavoriteMovie> getWatchlist() => _loadFavorites(_watchlistKey);

  Future<void> addToWatchlist(TMDBMovie movie) async {
    final watchlist = getWatchlist();
    if (!watchlist.any((f) => f.tmdbId == movie.id)) {
      watchlist.insert(0, FavoriteMovie.fromTMDBMovie(movie, DateTime.now()));
      await _saveFavorites(_watchlistKey, watchlist);
    }
  }

  Future<void> removeFromWatchlist(int tmdbId) async {
    final watchlist = getWatchlist()..removeWhere((f) => f.tmdbId == tmdbId);
    await _saveFavorites(_watchlistKey, watchlist);
  }

  bool isInWatchlist(int tmdbId) {
    return getWatchlist().any((f) => f.tmdbId == tmdbId);
  }

  // ==================== 片单功能 ====================
  // 支持 MediaItem，存储服务器上的媒体资源

  List<PlaylistItem> getPlaylist() {
    final data = _prefs.getStringList(_playlistKey);
    if (data == null) return [];
    return data
        .map((jsonStr) => PlaylistItem.fromJson(json.decode(jsonStr) as Map<String, dynamic>))
        .toList();
  }

  Future<void> addToPlaylist(MediaItem item) async {
    final playlist = getPlaylist();
    if (!playlist.any((p) => p.itemId == item.id)) {
      playlist.insert(0, PlaylistItem.fromMediaItem(item, DateTime.now()));
      await _savePlaylist(playlist);
    }
  }

  Future<void> removeFromPlaylist(String itemId) async {
    final playlist = getPlaylist()..removeWhere((p) => p.itemId == itemId);
    await _savePlaylist(playlist);
  }

  bool isInPlaylist(String itemId) {
    return getPlaylist().any((p) => p.itemId == itemId);
  }

  Future<void> _savePlaylist(List<PlaylistItem> items) async {
    final data = items.map((m) => json.encode(m.toJson())).toList();
    await _prefs.setStringList(_playlistKey, data);
  }
}

class PlaylistItem {
  final String itemId;
  final String title;
  final String posterUrl;
  final String? backdropUrl;
  final String? overview;
  final double? rating;
  final int? year;
  final MediaType type;
  final DateTime addedAt;
  final String? seriesTitle;
  final int? seasonNumber;
  final int? episodeNumber;

  PlaylistItem({
    required this.itemId,
    required this.title,
    required this.posterUrl,
    this.backdropUrl,
    this.overview,
    this.rating,
    this.year,
    required this.type,
    required this.addedAt,
    this.seriesTitle,
    this.seasonNumber,
    this.episodeNumber,
  });

  factory PlaylistItem.fromMediaItem(MediaItem item, DateTime addedAt) {
    return PlaylistItem(
      itemId: item.id,
      title: item.title,
      posterUrl: item.posterUrl,
      backdropUrl: item.backdropUrl,
      overview: item.overview,
      rating: item.rating,
      year: item.year,
      type: item.type,
      addedAt: addedAt,
      seriesTitle: item.seriesTitle,
      seasonNumber: item.seasonNumber,
      episodeNumber: item.episodeNumber,
    );
  }

  factory PlaylistItem.fromJson(Map<String, dynamic> json) {
    return PlaylistItem(
      itemId: json['itemId'] as String,
      title: json['title'] as String,
      posterUrl: json['posterUrl'] as String,
      backdropUrl: json['backdropUrl'] as String?,
      overview: json['overview'] as String?,
      rating: (json['rating'] as num?)?.toDouble(),
      year: json['year'] as int?,
      type: MediaType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => MediaType.movie,
      ),
      addedAt: DateTime.parse(json['addedAt'] as String),
      seriesTitle: json['seriesTitle'] as String?,
      seasonNumber: json['seasonNumber'] as int?,
      episodeNumber: json['episodeNumber'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'itemId': itemId,
      'title': title,
      'posterUrl': posterUrl,
      'backdropUrl': backdropUrl,
      'overview': overview,
      'rating': rating,
      'year': year,
      'type': type.name,
      'addedAt': addedAt.toIso8601String(),
      'seriesTitle': seriesTitle,
      'seasonNumber': seasonNumber,
      'episodeNumber': episodeNumber,
    };
  }
}

class FavoriteMovie {
  final int tmdbId;
  final String title;
  final String? posterPath;
  final String? backdropPath;
  final String? overview;
  final double? voteAverage;
  final String? releaseDate;
  final DateTime addedAt;
  final String type;

  FavoriteMovie({
    required this.tmdbId,
    required this.title,
    this.posterPath,
    this.backdropPath,
    this.overview,
    this.voteAverage,
    this.releaseDate,
    required this.addedAt,
    this.type = 'movie',
  });

  factory FavoriteMovie.fromTMDBMovie(TMDBMovie movie, DateTime addedAt) {
    return FavoriteMovie(
      tmdbId: movie.id,
      title: movie.title,
      posterPath: movie.posterPath,
      backdropPath: movie.backdropPath,
      overview: movie.overview,
      voteAverage: movie.voteAverage,
      releaseDate: movie.releaseDate,
      addedAt: addedAt,
      type: 'movie',
    );
  }

  factory FavoriteMovie.fromJson(Map<String, dynamic> json) {
    return FavoriteMovie(
      tmdbId: json['tmdbId'] as int,
      title: json['title'] as String,
      posterPath: json['posterPath'] as String?,
      backdropPath: json['backdropPath'] as String?,
      overview: json['overview'] as String?,
      voteAverage: (json['voteAverage'] as num?)?.toDouble(),
      releaseDate: json['releaseDate'] as String?,
      addedAt: DateTime.parse(json['addedAt'] as String),
      type: json['type'] as String? ?? 'movie',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'tmdbId': tmdbId,
      'title': title,
      'posterPath': posterPath,
      'backdropPath': backdropPath,
      'overview': overview,
      'voteAverage': voteAverage,
      'releaseDate': releaseDate,
      'addedAt': addedAt.toIso8601String(),
      'type': type,
    };
  }

  TMDBMovie toTMDBMovie() {
    return TMDBMovie(
      id: tmdbId,
      title: title,
      posterPath: posterPath,
      backdropPath: backdropPath,
      overview: overview,
      voteAverage: voteAverage,
      releaseDate: releaseDate,
    );
  }
}

