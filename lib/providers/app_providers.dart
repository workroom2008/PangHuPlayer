import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import "../utils/app_log.dart";
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:ui';
import '../models/media_models.dart';
import '../services/tmdb_service.dart';
import '../services/media_server_service.dart';
import '../services/moviepilot_service.dart';

import '../services/storage_service.dart';
import 'media_library_provider.dart';
import '../services/favorite_service.dart';
import '../models/player_settings.dart';
import '../database/database_service.dart';

// TMDB Service Provider
final tmdbServiceProvider = Provider<TMDBService>((ref) {
  return TMDBService();
});

// 媒体服务器列表 Provider
final mediaServersProvider = StateNotifierProvider<MediaServersNotifier, List<MediaServer>>((ref) {
  return MediaServersNotifier();
});

class MediaServersNotifier extends StateNotifier<List<MediaServer>> {
  MediaServersNotifier() : super([]) {
    _loadServers();
    _startHealthCheck();
  }

  Timer? _healthTimer;
  Timer? _initialCheckTimer;
  bool _checking = false;

  void _startHealthCheck() {
    _healthTimer?.cancel();
    _healthTimer = Timer.periodic(const Duration(seconds: 60), (_) => _checkConnections());
    // 首次延迟 3 秒检测（等服务器列表加载完成）；可取消，避免 dispose 后仍触发
    _initialCheckTimer?.cancel();
    _initialCheckTimer = Timer(const Duration(seconds: 3), _checkConnections);
  }

  Future<void> _checkConnections() async {
    if (_checking || state.isEmpty) return;
    _checking = true;
    try {
      final results = <MediaServer>[];
      bool changed = false;
      for (final s in state) {
        bool ok;
        try {
          final svc = _getService(s);
          ok = svc != null && await svc.testConnection();
        } catch (_) {
          ok = false;
        }
        results.add(s.copyWith(isConnected: ok));
        if (ok != s.isConnected) changed = true;
      }
      if (changed && mounted) state = results;
    } finally {
      _checking = false;
    }
  }

  @override
  void dispose() {
    _healthTimer?.cancel();
    _initialCheckTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadServers() async {
    try {
      state = await DbService.getServers();
    } catch (_) {
      // 数据库未就绪时回退到 SharedPreferences，但要先确保 StorageService 已初始化
      await StorageService.ready;
      final servers = StorageService.getJsonList(StorageService.serversKey);
      if (servers != null) {
        state = servers.map((json) => MediaServer.fromJson(json)).toList();
      }
    }
  }

  Future<void> addServer(MediaServer server) async {
    state = [...state, server];
    await _saveServers();
  }

  Future<void> removeServer(String serverId) async {
    state = state.where((s) => s.id != serverId).toList();
    await _saveServers();
  }

  Future<void> updateServer(MediaServer server) async {
    state = state.map((s) => s.id == server.id ? server : s).toList();
    await _saveServers();
  }

  Future<void> setDefaultServer(String serverId) async {
    state = state.map((s) => s.copyWith(isDefault: s.id == serverId)).toList();
    try { await DbService.setDefaultServer(serverId); } catch (_) {}
    await _saveServers();
  }

  Future<void> _saveServers() async {
    try { await DbService.saveServers(state); } catch (_) {}
    // 同时保留 SharedPreferences 作为降级备份
    await StorageService.setJsonList(
      StorageService.serversKey,
      state.map((s) => s.toJson()).toList(),
    );
  }

  MediaServer? getDefaultServer() {
    final defaultServer = state.where((s) => s.isDefault).firstOrNull;
    if (defaultServer != null) return defaultServer;
    return state.isNotEmpty ? state.first : null;
  }
}

// 媒体服务缓存
final Map<String, MediaServerService> _serviceCache = {};

/// 清除指定服务器的缓存（登录信息更新后调用）
void clearServiceCache(String serverId) {
  final keysToRemove = _serviceCache.keys.where((k) => k.startsWith('${serverId}_')).toList();
  for (final k in keysToRemove) {
    _serviceCache.remove(k);
  }
  AppLog.i('ServiceCache', 'Cleared ${keysToRemove.length} cache entries for server $serverId');
}

// 当前媒体服务器服务 Provider（带缓存，确保同一配置只创建一次实例）
final currentMediaServerServiceProvider = Provider<MediaServerService?>((ref) {
  final servers = ref.watch(mediaServersProvider);
  final defaultServer = servers.where((s) => s.isDefault).firstOrNull ?? servers.firstOrNull;

  if (defaultServer == null) return null;

  return _getService(defaultServer);
});

// TMDB 电影列表 Provider
final trendingMoviesProvider = FutureProvider<List<TMDBMovie>>((ref) async {
  final tmdbService = ref.watch(tmdbServiceProvider);
  return await tmdbService.getTrending();
});

final popularMoviesProvider = FutureProvider<List<TMDBMovie>>((ref) async {
  final tmdbService = ref.watch(tmdbServiceProvider);
  return await tmdbService.getPopular();
});

final topRatedMoviesProvider = FutureProvider<List<TMDBMovie>>((ref) async {
  final tmdbService = ref.watch(tmdbServiceProvider);
  return await tmdbService.getTopRated();
});

final upcomingMoviesProvider = FutureProvider<List<TMDBMovie>>((ref) async {
  final tmdbService = ref.watch(tmdbServiceProvider);
  return await tmdbService.getUpcoming();
});

final nowPlayingMoviesProvider = FutureProvider<List<TMDBMovie>>((ref) async {
  final tmdbService = ref.watch(tmdbServiceProvider);
  return await tmdbService.getNowPlaying();
});

// TMDB 电视剧列表 Provider
final trendingTVProvider = FutureProvider<List<dynamic>>((ref) async {
  final tmdbService = ref.watch(tmdbServiceProvider);
  return await tmdbService.getTrendingTV();
});

final popularTVProvider = FutureProvider<List<dynamic>>((ref) async {
  final tmdbService = ref.watch(tmdbServiceProvider);
  return await tmdbService.getPopularTV();
});

final topRatedTVProvider = FutureProvider<List<dynamic>>((ref) async {
  final tmdbService = ref.watch(tmdbServiceProvider);
  return await tmdbService.getTopRatedTV();
});

final onTheAirTVProvider = FutureProvider<List<dynamic>>((ref) async {
  final tmdbService = ref.watch(tmdbServiceProvider);
  return await tmdbService.getOnTheAirTV();
});

final airingTodayTVProvider = FutureProvider<List<dynamic>>((ref) async {
  final tmdbService = ref.watch(tmdbServiceProvider);
  return await tmdbService.getAiringTodayTV();
});

// 搜索 Provider
final searchQueryProvider = StateProvider<String>((ref) => '');
final searchResultsProvider = FutureProvider<List<TMDBMovie>>((ref) async {
  final query = ref.watch(searchQueryProvider);
  if (query.isEmpty) return [];
  final sources = ref.watch(selectedSearchSourcesProvider);
  if (!sources.contains('tmdb')) return [];
  final tmdbService = ref.watch(tmdbServiceProvider);
  return await tmdbService.searchMovies(query);
});

// 聚合搜索 — 多选来源
final selectedSearchSourcesProvider = StateProvider<Set<String>>((ref) {
  final stored = StorageService.getString('search_sources');
  if (stored != null && stored.isNotEmpty) {
    return Set.from(stored.split(','));
  }
  return {'tmdb'};
});

final aggregatedSearchProvider = FutureProvider<Map<String, List>>((ref) async {
  final query = ref.watch(searchQueryProvider);
  final sources = ref.watch(selectedSearchSourcesProvider);
  if (query.isEmpty) return {};
  
  final result = <String, List>{};
  final futures = <Future>{};

  // 本地模糊搜索：从已缓存的媒体库中即时匹配（无需网络）
  final libraryState = ref.watch(mediaLibraryProvider);
  final lowerQuery = query.toLowerCase();
  final localMatches = <MediaItem>[];
  for (final items in libraryState.libraryItems.values) {
    for (final item in items) {
      if (item.title.toLowerCase().contains(lowerQuery)) {
        localMatches.add(item);
      }
    }
  }
  // 去重（同一部可能出现在多个库中）
  final seen = <String>{};
  final uniqueLocal = localMatches.where((i) => seen.add(i.id)).take(20).toList();
  if (uniqueLocal.isNotEmpty) result['本地匹配'] = uniqueLocal;
  
  // TMDB
  if (sources.contains('tmdb')) {
    futures.add(ref.watch(tmdbServiceProvider).searchMovies(query).then((items) {
      if (items.isNotEmpty) result['TMDB'] = items;
    }).catchError((_) {}));
  }
  
  // 媒体服务器：搜索已勾选的源 + 当前默认服务器（首页 ServerSelectorChip 选中的）
  final servers = ref.watch(mediaServersProvider);
  final defaultServerId = servers.where((s) => s.isDefault).map((s) => s.id).firstOrNull;

  for (final srv in servers) {
    // 包含用户勾选的源，以及首页选中的默认服务器
    final isSourceSelected = sources.contains(srv.id);
    final isDefaultServer = srv.id == defaultServerId;
    if (!isSourceSelected && !isDefaultServer) continue;

    final svc = _getService(srv);
    if (svc == null) continue;
    futures.add(svc.search(query).then((items) {
      if (items.isNotEmpty) result[srv.name] = items;
    }).catchError((_) {}));
  }
  
  await Future.wait(futures);
  return result;
});

MediaServerService? _getService(MediaServer srv) {
  // 兼容旧数据：旧版本可能把密码存在 apiKey 字段中，password 为 null
  // 如果有用户名但没有 password 但有 apiKey，说明是旧数据格式，把 apiKey 当作 password
  var apiKey = srv.apiKey ?? '';
  var password = srv.password;
  if ((srv.type == ServerType.emby || srv.type == ServerType.jellyfin) &&
      (srv.username?.isNotEmpty ?? false) &&
      (password == null || password.isEmpty) &&
      apiKey.isNotEmpty) {
    AppLog.i('MediaServer', 'Migrating old server data: moving apiKey to password for ${srv.name}');
    password = apiKey;
    apiKey = '';
  }

  final cacheKey = '${srv.id}_${srv.url}_${apiKey}_${srv.username ?? ''}_${password ?? ''}';
  if (_serviceCache.containsKey(cacheKey)) return _serviceCache[cacheKey];

  final service = switch (srv.type) {
    ServerType.emby => EmbyService(
        baseUrl: srv.url,
        apiKey: apiKey,
        username: srv.username,
        password: password,
      ),
    ServerType.jellyfin => JellyfinService(
        baseUrl: srv.url,
        apiKey: apiKey,
        username: srv.username,
        password: password,
      ),
    ServerType.fnos => FnOSService(baseUrl: srv.url, username: srv.username ?? '', password: srv.password ?? ''),
    _ => null,
  };
  if (service == null) return null;
  _serviceCache[cacheKey] = service;
  return service;
}

// MoviePilot Provider
final moviePilotServiceProvider = Provider<MoviePilotService?>((ref) {
  final url = StorageService.getString(StorageService.moviePilotUrlKey);
  final apiKey = StorageService.getString('secure_${StorageService.moviePilotApiKey}');
  final username = StorageService.getString('moviepilot_username');
  final password = StorageService.getString('secure_moviepilot_password');

  if (url == null || url.isEmpty) return null;
  final hasApiKey = apiKey != null && apiKey.isNotEmpty;
  final hasLogin = username != null && username.isNotEmpty && password != null && password.isNotEmpty;
  if (!hasApiKey && !hasLogin) return null;

  return MoviePilotService(baseUrl: url, apiKey: hasApiKey ? apiKey : null, username: username, password: password);
});

// 订阅列表 Provider
final subscriptionsProvider = FutureProvider<List<Subscription>>((ref) async {
  final mpService = ref.watch(moviePilotServiceProvider);
  if (mpService == null) return [];
  
  final subs = await mpService.getSubscriptions();
  return subs.map((json) => Subscription.fromJson(json)).toList();
});

// 弹幕配置 Provider
final danmakuConfigsProvider = StateNotifierProvider<DanmakuConfigsNotifier, List<DanmakuConfig>>((ref) {
  return DanmakuConfigsNotifier();
});

class DanmakuConfigsNotifier extends StateNotifier<List<DanmakuConfig>> {
  DanmakuConfigsNotifier() : super([]) {
    _loadConfigs();
  }

  Future<void> _loadConfigs() async {
    try {
      state = await DbService.getDanmakuConfigs();
    } catch (_) {
      final configs = StorageService.getJsonList(StorageService.danmakuConfigKey);
      if (configs != null) {
        state = configs.map((json) => DanmakuConfig.fromJson(json)).toList();
      }
    }
  }

  Future<void> addConfig(DanmakuConfig config) async {
    state = [...state, config];
    await _saveConfigs();
  }

  Future<void> removeConfig(String configId) async {
    state = state.where((c) => c.id != configId).toList();
    await _saveConfigs();
  }

  Future<void> updateConfig(DanmakuConfig config) async {
    state = state.map((c) => c.id == config.id ? config : c).toList();
    await _saveConfigs();
  }

  Future<void> _saveConfigs() async {
    try { await DbService.saveDanmakuConfigs(state); } catch (_) {}
    await StorageService.setJsonList(
      StorageService.danmakuConfigKey,
      state.map((c) => c.toJson()).toList(),
    );
  }
}

/// 弹幕显示设置（字体大小、透明度、速度、显示开关、碰撞检测等）
class DanmakuDisplaySettings {
  final double fontSize;
  final double opacity;
  final double speed;
  final bool showTop;
  final bool showBottom;
  final bool showScroll;
  final double syncDelay;       // 弹幕同步偏移（秒），正数延后，负数提前
  final double displayArea;     // 弹幕显示区域（0.5~1.0 占屏幕高度比例）
  final bool tapToSearch;       // 点击弹幕搜索（点弹幕弹出操作：复制/搜索）
  final int maxScrollLines;     // 滚动弹幕最大行数
  final int maxTopLines;        // 顶部弹幕最大行数
  final int maxBottomLines;     // 底部弹幕最大行数
  final bool bold;              // 粗体
  final bool mergeDuplicates;   // 合并重复弹幕
  final bool preventOverlap;    // 防止弹幕重叠
  final bool heatmap;           // 弹幕热力图（进度条上显示密度色带）
  final List<String> blockKeywords;  // 屏蔽关键词列表
  final String charConversion;       // 字符转换：none/s2t(简→繁)/t2s(繁→简)

  const DanmakuDisplaySettings({
    this.fontSize = 24,
    this.opacity = 1.0,
    this.speed = 12,
    this.showTop = true,
    this.showBottom = true,
    this.showScroll = true,
    this.syncDelay = 0.0,
    this.displayArea = 1.0,
    this.tapToSearch = false,
    this.maxScrollLines = 4,
    this.maxTopLines = 4,
    this.maxBottomLines = 4,
    this.bold = false,
    this.mergeDuplicates = false,
    this.preventOverlap = true,
    this.heatmap = true,
    this.blockKeywords = const [],
    this.charConversion = 'none',
  });

  DanmakuDisplaySettings copyWith({
    double? fontSize,
    double? opacity,
    double? speed,
    bool? showTop,
    bool? showBottom,
    bool? showScroll,
    double? syncDelay,
    double? displayArea,
    bool? tapToSearch,
    int? maxScrollLines,
    int? maxTopLines,
    int? maxBottomLines,
    bool? bold,
    bool? mergeDuplicates,
    bool? preventOverlap,
    bool? heatmap,
    List<String>? blockKeywords,
    String? charConversion,
  }) {
    return DanmakuDisplaySettings(
      fontSize: fontSize ?? this.fontSize,
      opacity: opacity ?? this.opacity,
      speed: speed ?? this.speed,
      showTop: showTop ?? this.showTop,
      showBottom: showBottom ?? this.showBottom,
      showScroll: showScroll ?? this.showScroll,
      syncDelay: syncDelay ?? this.syncDelay,
      displayArea: displayArea ?? this.displayArea,
      tapToSearch: tapToSearch ?? this.tapToSearch,
      maxScrollLines: maxScrollLines ?? this.maxScrollLines,
      maxTopLines: maxTopLines ?? this.maxTopLines,
      maxBottomLines: maxBottomLines ?? this.maxBottomLines,
      bold: bold ?? this.bold,
      mergeDuplicates: mergeDuplicates ?? this.mergeDuplicates,
      preventOverlap: preventOverlap ?? this.preventOverlap,
      heatmap: heatmap ?? this.heatmap,
      blockKeywords: blockKeywords ?? this.blockKeywords,
      charConversion: charConversion ?? this.charConversion,
    );
  }

  Map<String, dynamic> toJson() => {
        'fontSize': fontSize,
        'opacity': opacity,
        'speed': speed,
        'showTop': showTop,
        'showBottom': showBottom,
        'showScroll': showScroll,
        'syncDelay': syncDelay,
        'displayArea': displayArea,
        'tapToSearch': tapToSearch,
        'maxScrollLines': maxScrollLines,
        'maxTopLines': maxTopLines,
        'maxBottomLines': maxBottomLines,
        'bold': bold,
        'mergeDuplicates': mergeDuplicates,
        'preventOverlap': preventOverlap,
        'heatmap': heatmap,
        'blockKeywords': blockKeywords,
        'charConversion': charConversion,
      };

  factory DanmakuDisplaySettings.fromJson(Map<String, dynamic> json) {
    return DanmakuDisplaySettings(
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 24,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
      speed: (json['speed'] as num?)?.toDouble() ?? 12,
      showTop: json['showTop'] as bool? ?? true,
      showBottom: json['showBottom'] as bool? ?? true,
      showScroll: json['showScroll'] as bool? ?? true,
      syncDelay: (json['syncDelay'] as num?)?.toDouble() ?? 0.0,
      displayArea: (json['displayArea'] as num?)?.toDouble() ?? 1.0,
      tapToSearch: json['tapToSearch'] as bool? ?? false,
      maxScrollLines: (json['maxScrollLines'] as num?)?.toInt() ?? 4,
      maxTopLines: (json['maxTopLines'] as num?)?.toInt() ?? 4,
      maxBottomLines: (json['maxBottomLines'] as num?)?.toInt() ?? 4,
      bold: json['bold'] as bool? ?? false,
      mergeDuplicates: json['mergeDuplicates'] as bool? ?? false,
      preventOverlap: json['preventOverlap'] as bool? ?? true,
      heatmap: json['heatmap'] as bool? ?? true,
      blockKeywords: (json['blockKeywords'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      charConversion: json['charConversion'] as String? ?? 'none',
    );
  }
}

/// 弹幕显示设置 Notifier
class DanmakuDisplayNotifier extends StateNotifier<DanmakuDisplaySettings> {
  DanmakuDisplayNotifier() : super(const DanmakuDisplaySettings()) {
    _load();
  }

  Future<void> _load() async {
    try {
      final json = await DbService.getDanmakuDisplayJson();
      if (json != null) {
        state = DanmakuDisplaySettings.fromJson(jsonDecode(json) as Map<String, dynamic>);
        return;
      }
    } catch (_) {}
    final str = StorageService.getString('danmaku_display');
    if (str != null) {
      try {
        final map = jsonDecode(str) as Map<String, dynamic>;
        state = DanmakuDisplaySettings.fromJson(map);
      } catch (_) {}
    }
  }

  Future<void> update(DanmakuDisplaySettings settings) async {
    state = settings;
    final json = jsonEncode(settings.toJson());
    try { await DbService.setDanmakuDisplayJson(json); } catch (_) {}
    await StorageService.setString('danmaku_display', json);
  }
}

/// 弹幕显示设置 Provider
final danmakuDisplayProvider =
    StateNotifierProvider<DanmakuDisplayNotifier, DanmakuDisplaySettings>((ref) {
  return DanmakuDisplayNotifier();
});

// SharedPreferences Provider
final sharedPreferencesProvider = FutureProvider<SharedPreferences>((ref) async {
  return await SharedPreferences.getInstance();
});

// FavoriteService Provider
final favoriteServiceProvider = FutureProvider<FavoriteService>((ref) async {
  final prefs = await ref.watch(sharedPreferencesProvider.future);
  return FavoriteService(prefs);
});

// 收藏列表 Provider
final favoriteMoviesProvider = StateNotifierProvider<FavoriteMoviesNotifier, List<FavoriteMovie>>((ref) {
  return FavoriteMoviesNotifier(ref);
});

class FavoriteMoviesNotifier extends StateNotifier<List<FavoriteMovie>> {
  final Ref ref;
  FavoriteService? _service;

  FavoriteMoviesNotifier(this.ref) : super([]) {
    _init();
  }

  Future<void> _init() async {
    final service = await ref.watch(favoriteServiceProvider.future);
    _service = service;
    state = service.getFavorites();
  }

  Future<void> addFavorite(TMDBMovie movie) async {
    await _service?.addFavorite(movie);
    state = _service?.getFavorites() ?? [];
  }

  Future<void> removeFavorite(int tmdbId) async {
    await _service?.removeFavorite(tmdbId);
    state = _service?.getFavorites() ?? [];
  }

  Future<void> toggleFavorite(TMDBMovie movie) async {
    if (isFavorite(movie.id)) {
      await removeFavorite(movie.id);
    } else {
      await addFavorite(movie);
    }
  }

  bool isFavorite(int tmdbId) {
    return state.any((f) => f.tmdbId == tmdbId);
  }
}

// 观看列表 Provider
final watchlistMoviesProvider = StateNotifierProvider<WatchlistMoviesNotifier, List<FavoriteMovie>>((ref) {
  return WatchlistMoviesNotifier(ref);
});

// 片单 Provider（存储用户添加的媒体资源）
final playlistProvider = StateNotifierProvider<PlaylistNotifier, List<PlaylistItem>>((ref) {
  return PlaylistNotifier(ref);
});

class PlaylistNotifier extends StateNotifier<List<PlaylistItem>> {
  final Ref ref;
  FavoriteService? _service;

  PlaylistNotifier(this.ref) : super([]) {
    _init();
  }

  Future<void> _init() async {
    final service = await ref.watch(favoriteServiceProvider.future);
    _service = service;
    state = service.getPlaylist();
  }

  Future<void> addToPlaylist(MediaItem item) async {
    await _service?.addToPlaylist(item);
    state = _service?.getPlaylist() ?? [];
  }

  Future<void> removeFromPlaylist(String itemId) async {
    await _service?.removeFromPlaylist(itemId);
    state = _service?.getPlaylist() ?? [];
  }

  Future<void> togglePlaylist(MediaItem item) async {
    if (isInPlaylist(item.id)) {
      await removeFromPlaylist(item.id);
    } else {
      await addToPlaylist(item);
    }
  }

  bool isInPlaylist(String itemId) {
    return state.any((p) => p.itemId == itemId);
  }
}

class WatchlistMoviesNotifier extends StateNotifier<List<FavoriteMovie>> {
  final Ref ref;
  FavoriteService? _service;

  WatchlistMoviesNotifier(this.ref) : super([]) {
    _init();
  }

  Future<void> _init() async {
    final service = await ref.watch(favoriteServiceProvider.future);
    _service = service;
    state = service.getWatchlist();
  }

  Future<void> addToWatchlist(TMDBMovie movie) async {
    await _service?.addToWatchlist(movie);
    state = _service?.getWatchlist() ?? [];
  }

  Future<void> removeFromWatchlist(int tmdbId) async {
    await _service?.removeFromWatchlist(tmdbId);
    state = _service?.getWatchlist() ?? [];
  }

  Future<void> toggleWatchlist(TMDBMovie movie) async {
    if (isInWatchlist(movie.id)) {
      await removeFromWatchlist(movie.id);
    } else {
      await addToWatchlist(movie);
    }
  }

  bool isInWatchlist(int tmdbId) {
    return state.any((f) => f.tmdbId == tmdbId);
  }
}

// 旧的收藏列表 Provider（保留兼容）
final favoritesProvider = StateNotifierProvider<FavoritesNotifier, List<String>>((ref) {
  return FavoritesNotifier();
});

class FavoritesNotifier extends StateNotifier<List<String>> {
  FavoritesNotifier() : super([]) {
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    state = StorageService.getStringList(StorageService.favoritesKey) ?? [];
  }

  Future<void> addFavorite(String itemId) async {
    if (!state.contains(itemId)) {
      state = [...state, itemId];
      await StorageService.setStringList(StorageService.favoritesKey, state);
    }
  }

  Future<void> removeFavorite(String itemId) async {
    state = state.where((id) => id != itemId).toList();
    await StorageService.setStringList(StorageService.favoritesKey, state);
  }

  bool isFavorite(String itemId) => state.contains(itemId);
}

// 观看历史 Provider
final watchHistoryProvider = StateNotifierProvider<WatchHistoryNotifier, List<Map<String, dynamic>>>((ref) {
  return WatchHistoryNotifier();
});

class WatchHistoryNotifier extends StateNotifier<List<Map<String, dynamic>>> {
  WatchHistoryNotifier() : super([]) {
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      state = await DbService.getWatchHistory();
    } catch (_) {
      final history = StorageService.getJsonList(StorageService.watchHistoryKey);
      if (history != null) {
        state = history;
      }
    }
  }

  Future<void> addToHistory(Map<String, dynamic> item) async {
    state = [
      item,
      ...state.where((h) => h['id'] != item['id']),
    ].take(100).toList();
    try { await DbService.addToHistory(item); } catch (_) {}
    await StorageService.setJsonList(StorageService.watchHistoryKey, state);
  }

  Future<void> removeFromHistory(String itemId) async {
    state = state.where((h) => h['id'] != itemId).toList();
    try { await DbService.removeFromHistory(itemId); } catch (_) {}
    await StorageService.setJsonList(StorageService.watchHistoryKey, state);
  }

  Future<void> clearHistory() async {
    state = [];
    try { await DbService.clearHistory(); } catch (_) {}
    await StorageService.remove(StorageService.watchHistoryKey);
  }
}

// 播放器设置 Provider
final playerSettingsProvider = StateNotifierProvider<PlayerSettingsNotifier, PlayerSettings>((ref) {
  return PlayerSettingsNotifier();
});

class PlayerSettingsNotifier extends StateNotifier<PlayerSettings> {
  PlayerSettingsNotifier() : super(PlayerSettings.defaults) {
    _load();
  }

  void _load() async {
    try {
      final json = await DbService.getPlayerSettingsJson();
      if (json != null) {
        state = PlayerSettings.fromJsonString(json);
        return;
      }
    } catch (_) {}
    final saved = StorageService.getString(StorageService.playerSettingsKey);
    if (saved != null) {
      state = PlayerSettings.fromJsonString(saved);
    }
  }

  Future<void> update(PlayerSettings Function(PlayerSettings) transform) async {
    state = transform(state);
    final json = state.toJsonString();
    try { await DbService.setPlayerSettingsJson(json); } catch (_) {}
    await StorageService.setString(StorageService.playerSettingsKey, json);
  }

  Future<void> reset() async {
    state = PlayerSettings.defaults;
    final json = state.toJsonString();
    try { await DbService.setPlayerSettingsJson(json); } catch (_) {}
    await StorageService.setString(StorageService.playerSettingsKey, json);
  }
}

// 主题状态（持久化到 StorageService）
// 用 NotifierProvider 替代 StateProvider + ref.listenSelf：
// listenSelf 在 riverpod 2.x 已标记弃用（3.0 移除），官方替代是 Notifier.listenSelf。
// 持久化逻辑仍封装在 Notifier 内部，调用方无需关心存储。
class DarkModeNotifier extends Notifier<bool> {
  @override
  bool build() {
    listenSelf((_, next) {
      StorageService.setBool(StorageService.themeKey, next);
    });
    return StorageService.getBool(StorageService.themeKey) ?? true;
  }

  void set(bool value) => state = value;
  void toggle() => state = !state;
}

final darkModeProvider =
    NotifierProvider<DarkModeNotifier, bool>(DarkModeNotifier.new);

class ThemeColorNotifier extends Notifier<Color> {
  @override
  Color build() {
    listenSelf((_, next) {
      StorageService.setString(
        StorageService.themeColorKey,
        next.toARGB32().toRadixString(16).padLeft(8, '0'),
      );
    });
    final saved = StorageService.getString(StorageService.themeColorKey);
    if (saved != null) {
      final parsed = int.tryParse(saved, radix: 16);
      if (parsed != null) return Color(parsed);
    }
    return const Color(0xFF6366F1);
  }

  void set(Color value) => state = value;
}

final themeColorProvider =
    NotifierProvider<ThemeColorNotifier, Color>(ThemeColorNotifier.new);
final debugModeProvider = StateProvider<bool>((ref) => false);

// 媒体库缓存 — 标题 → ID 快速索引，加速发现页查库存
class MediaCache extends StateNotifier<Map<String, String>> {
  MediaCache() : super({});

  bool hasItem(String title) => state.containsKey(title.trim().toLowerCase());
  String? itemId(String title) => state[title.trim().toLowerCase()];

  Future<void> build(MediaServerService svc) async {
    if (state.isNotEmpty) return; // 只构建一次
    try {
      final libs = await svc.getLibraries();
      for (final lib in libs) {
        final items = await svc.getLibraryItems(lib.id, limit: 9999);
        final m = Map<String, String>.from(state);
        for (final item in items) {
          m[item.title.trim().toLowerCase()] = item.id;
        }
        state = m;
      }
    } catch (_) {}
  }
}

final mediaCacheProvider = StateNotifierProvider<MediaCache, Map<String, String>>((ref) => MediaCache());
class HomeCacheNotifier extends StateNotifier<HomeCacheState> {
  HomeCacheNotifier() : super(HomeCacheState());

  Future<void> refresh(MediaServerService svc) async {
    AppLog.i('Home', 'fetching carousel items...');
    try {
      final libs = await svc.getLibraries();
      final carousel = <MediaItem>[];
      final categories = <String, List<MediaItem>>{};

      for (final lib in libs) {
        try {
          final items = await svc.getLibraryItems(lib.id, limit: 30);
          AppLog.i('Emby', 'getLibraryItems(${lib.id}) uid=xxx: ${items.length} items');
          if (items.isNotEmpty) categories[lib.title] = items;
          for (final item in items) {
            if (item.posterUrl.isNotEmpty) carousel.add(item);
          }
        } catch (_) {}
      }

      state = HomeCacheState(carousel: carousel.take(10).toList(), categories: categories, loaded: true);
    } catch (_) {
      state = HomeCacheState(loaded: false);
    }
  }
}

class HomeCacheState {
  final List<MediaItem> carousel;
  final Map<String, List<MediaItem>> categories;
  final bool loaded;
  const HomeCacheState({this.carousel = const [], this.categories = const {}, this.loaded = false});
}

final homeCacheProvider = StateNotifierProvider<HomeCacheNotifier, HomeCacheState>((ref) => HomeCacheNotifier());


