import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import '../models/media_models.dart';
import '../utils/app_log.dart';
import 'server_subtitle_service.dart';

class MediaServerException implements Exception {
  final String message;

  const MediaServerException(this.message);

  @override
  String toString() => message;
}

class ChapterMarker {
  final String name;
  final int startTicks, endTicks;
  final String? markerType;

  const ChapterMarker(
      {required this.name,
      required this.startTicks,
      required this.endTicks,
      this.markerType});

  Duration get startDuration => Duration(microseconds: startTicks ~/ 10);
  Duration get endDuration => Duration(microseconds: endTicks ~/ 10);
}

class IntroSkip {
  final int introStartTicks, introEndTicks;
  final int? creditsStartTicks, creditsEndTicks;

  const IntroSkip(
      {required this.introStartTicks,
      required this.introEndTicks,
      this.creditsStartTicks,
      this.creditsEndTicks});

  Duration get introStartDuration =>
      Duration(microseconds: introStartTicks ~/ 10);
  Duration get introEndDuration => Duration(microseconds: introEndTicks ~/ 10);
  Duration? get creditsStartDuration => creditsStartTicks != null
      ? Duration(microseconds: creditsStartTicks! ~/ 10)
      : null;
  Duration? get creditsEndDuration => creditsEndTicks != null
      ? Duration(microseconds: creditsEndTicks! ~/ 10)
      : null;
  bool get hasIntro => introEndTicks > introStartTicks;
  bool get hasCredits => creditsStartTicks != null;
}

class TrickplayInfo {
  final int intervalMs; // 每张缩略图对应的时间间隔（毫秒）
  final int tileWidth; // 拼图网格列数
  final int tileHeight; // 拼图网格行数
  final int thumbnailCount; // 每张精灵图包含的缩略图总数

  const TrickplayInfo({
    required this.intervalMs,
    required this.tileWidth,
    required this.tileHeight,
    required this.thumbnailCount,
  });

  /// 每张拼图覆盖的总时长（毫秒）
  int get tileDurationMs => intervalMs * thumbnailCount;
}

/// 精灵图中单张缩略图的定位信息
/// 进度条用此数据从精灵图中裁剪出正确的子图
class TrickplayTile {
  final String spriteSheetUrl; // 精灵图 URL
  final int col; // 列位置（0-indexed）
  final int row; // 行位置（0-indexed）
  final int gridWidth; // 网格总列数
  final int gridHeight; // 网格总行数

  const TrickplayTile({
    required this.spriteSheetUrl,
    required this.col,
    required this.row,
    required this.gridWidth,
    required this.gridHeight,
  });
}

abstract class MediaServerService {
  String baseUrl;
  final Dio dio;

  MediaServerService({required this.baseUrl, Dio? dioClient})
      : dio = dioClient ??
            Dio(BaseOptions(
                baseUrl: baseUrl,
                connectTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 30),
                headers: {
                  'Accept': 'application/json; charset=utf-8',
                })) {
    // 401 自愈拦截器：收到 401 → 强制重新登录 → 用新 token 重试原请求一次。
    // 覆盖两种情况：① 从未登录（首页缓存新鲜时跳过登录，service 一直无 token）；
    // ② token 会话中过期。登录请求自身标记 _isLoginRequest 避免递归死锁；
    // 并发 401 通过 _reauthFuture 共享同一次重登，避免重复登录。
    dio.interceptors.add(InterceptorsWrapper(
      onError: (DioException e, ErrorInterceptorHandler handler) async {
        final opts = e.requestOptions;
        final is401 = e.response?.statusCode == 401;
        final isLogin = opts.extra['_isLoginRequest'] == true;
        final isRetry = opts.extra['_retried401'] == true;
        if (is401 && !isLogin && !isRetry) {
          AppLog.w('Auth', '请求 401，尝试重新认证: ${opts.path}');
          final ok = await reAuthenticate();
          if (ok) {
            try {
              opts.extra['_retried401'] = true;
              opts.headers.addAll(authHeaders); // 用新 token 覆盖请求头里的旧 token
              final response = await dio.fetch<dynamic>(opts);
              AppLog.i('Auth', '401 重试成功: ${opts.path}');
              return handler.resolve(response);
            } on DioException catch (retryError) {
              AppLog.w('Auth', '401 重试仍失败: ${opts.path}');
              return handler.next(retryError);
            }
          } else {
            AppLog.w('Auth', '重新认证失败（可能未配置凭据）: ${opts.path}');
          }
        }
        return handler.next(e);
      },
    ));
  }

  Future<bool>? _reauthFuture;

  /// 强制重新认证（401 拦截器调用）。并发 401 共享同一次重登，避免重复登录。
  Future<bool> reAuthenticate() {
    _reauthFuture ??=
        doReAuthenticate().whenComplete(() => _reauthFuture = null);
    return _reauthFuture!;
  }

  /// 作废过期 token 并重新登录。子类重写；默认仅 ensureAuthenticated()。
  Future<bool> doReAuthenticate() => ensureAuthenticated();

  /// 当前认证请求头（401 重试时用于刷新原请求头里的旧 token）。子类按各自认证方式重写。
  Map<String, String> get authHeaders => const {};

  Future<bool> testConnection();
  Future<List<MediaItem>> getLibraries();
  Future<List<MediaItem>> getLibraryItems(String libraryId,
      {int page = 0, int limit = 50, bool includeBoxSets = false});

  /// 分页拉取库内全部条目（单页默认 50 条，大库需要循环分页取全）
  Future<List<MediaItem>> getAllLibraryItems(String libraryId,
      {bool includeBoxSets = false});
  Future<MediaItem> getItemDetails(String itemId);
  Future<List<ServerSubtitleResult>> searchSubtitles(
    String itemId, {
    String? language,
  });
  Future<void> deleteItem(String itemId);
  Future<String> getStreamUrl(String itemId,
      {String? quality, bool burnInSubtitle = false, int? subtitleIndex});
  Future<List<MediaItem>> search(String query);

  /// 相似推荐（Emby/Jellyfin `/Items/{id}/Similar`）
  /// 服务端不支持时返回空列表，UI 无数据则不显示分区
  Future<List<MediaItem>> getSimilarItems(String itemId) async => [];
  Future<void> markWatched(String itemId, {double? progress, int? positionMs});
  Future<void> markUnwatched(String itemId);
  Future<void> reportPlaybackStart(String itemId, {String? mediaSourceId});
  Future<void> reportPlaybackProgress(String itemId, int positionMs,
      {bool isPlaying = true, String? mediaSourceId});
  Future<void> reportPlaybackStopped(String itemId,
      {int? positionMs, String? mediaSourceId});
  Future<void> markFavorite(String itemId);
  Future<void> unmarkFavorite(String itemId);
  Future<List<ChapterMarker>> getChapters(String itemId);
  Future<IntroSkip?> getIntroSkipInfo(String itemId);
  Future<List<MediaItem>> getSeasons(String seriesId);
  Future<List<MediaItem>> getEpisodes(String seriesId,
      {String? seasonId, int? page, int limit = 50});
  Future<List<MediaItem>> getResumeItems({int limit = 20});

  /// 获取流播放所需的 HTTP 请求头（由子类实现各自的认证方式）
  Map<String, String> get streamHeaders;

  /// 获取图片加载所需的 HTTP 请求头（默认空，需要认证的服务重写）
  Map<String, String> get imageHeaders => const {};

  /// 确保服务已认证（公开方法，供 UI 层在加载图片/视频前调用）
  /// 默认实现：视为已认证（子类按需重写触发登录流程）
  Future<bool> ensureAuthenticated() async => true;

  /// 获取当前的认证信息（登录成功后可调用）
  /// 返回 { 'apiKey': ..., 'userId': ... }，无认证信息返回空 map
  Map<String, String> getAuthInfo() => const {};
}

// ==================== EmbyService ====================

class _CachedAuth {
  final String apiKey;
  final String? userId;

  const _CachedAuth(this.apiKey, this.userId);
}

class EmbyService extends MediaServerService {
  String apiKey;
  String? userId;
  String? _username;
  String? _password;
  bool _userIdLoaded = false;
  String _playSessionId = _generateSessionId();

  static String _generateSessionId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    return '${now.toRadixString(16)}${now.hashCode.toRadixString(16)}';
  }

  /// 刷新播放会话 ID（每次开始新播放时调用）
  void refreshPlaySession() {
    _playSessionId = _generateSessionId();
  }

  final Map<String, _CachedDetailItem> _detailsCache = {};
  final Map<String, _CachedSeasons> _seasonsCache = {};
  final Map<String, _CachedEpisodes> _episodesCache = {};
  static const int _cacheDurationMs = 5 * 60 * 1000;
  static final Map<String, _CachedAuth> _authCache = {};

  Future<bool>? _authFuture; // 登录并发锁，防止多个调用方重复登录

  static String _authCacheKey(
    String baseUrl,
    String? username,
    String? password,
  ) {
    // 只在内存中保存配置指纹，避免把密码直接作为缓存键。
    return Object.hash(baseUrl, username, password).toRadixString(16);
  }

  String get _currentAuthCacheKey =>
      _authCacheKey(baseUrl, _username, _password);

  EmbyService(
      {required String baseUrl,
      this.apiKey = '',
      this.userId,
      String? username,
      String? password,
      Dio? dioClient})
      : _username = username,
        _password = password,
        super(baseUrl: baseUrl, dioClient: dioClient) {
    if (apiKey.isEmpty) {
      final cachedAuth = _authCache[_currentAuthCacheKey];
      if (cachedAuth != null) {
        apiKey = cachedAuth.apiKey;
        userId ??= cachedAuth.userId;
        _userIdLoaded = userId != null && userId!.isNotEmpty;
      }
    }
    if (apiKey.isNotEmpty) {
      dio.options.headers['X-MediaBrowser-Token'] = apiKey;
    }
    AppLog.i('Emby',
        'init baseUrl=$baseUrl hasKey=${apiKey.isNotEmpty} hasUser=${(username ?? '').isNotEmpty}');
  }

  void clearCache() {
    _detailsCache.clear();
    _seasonsCache.clear();
    _episodesCache.clear();
  }

  @override
  Map<String, String> get streamHeaders => {'X-MediaBrowser-Token': apiKey};

  @override
  Map<String, String> get imageHeaders =>
      apiKey.isNotEmpty ? {'X-MediaBrowser-Token': apiKey} : const {};

  @override
  Future<bool> ensureAuthenticated() => _ensureAuth();

  /// 使用用户名密码登录，获取 AccessToken 并填充 apiKey 和 userId
  /// 适用于 Emby/Jellyfin 服务器，无需手动配置 API 密钥
  Future<bool> loginByUsernamePassword() async {
    if (_username == null || _password == null) return false;
    if (_username!.isEmpty) return false;

    AppLog.i('Emby', '尝试用户名密码登录: $_username');
    try {
      final deviceId = 'LANPlayer_${DateTime.now().millisecondsSinceEpoch}';
      final authHeader = 'MediaBrowser Client="LANPlayer", Device="LANPlayer", '
          'DeviceId="$deviceId", Version="1.0.0"';
      final response = await dio.post(
        '$baseUrl/Users/AuthenticateByName',
        data: {'Username': _username, 'Pw': _password},
        options: Options(headers: {
          'Content-Type': 'application/json',
          'Authorization': authHeader,
        }, extra: {
          '_isLoginRequest': true
        }),
      );

      final statusCode = response.statusCode ?? 0;
      if (statusCode >= 200 && statusCode < 300 && response.data is Map) {
        final data = response.data as Map;
        final accessToken = data['AccessToken']?.toString() ??
            (data['User'] as Map?)?['AccessToken']?.toString();
        final userIdStr = (data['User'] as Map?)?['Id']?.toString() ??
            data['User']?['Id']?.toString();

        if (accessToken != null && accessToken.isNotEmpty) {
          apiKey = accessToken;
          userId = userIdStr;
          _userIdLoaded = userId != null && userId!.isNotEmpty;

          // 更新全局认证头
          dio.options.headers['X-MediaBrowser-Token'] = apiKey;
          _authCache[_currentAuthCacheKey] = _CachedAuth(apiKey, userId);

          AppLog.i('Emby', '用户名密码登录成功: userId=$userId');
          return true;
        }
      }

      AppLog.w('Emby', '用户名密码登录失败: HTTP $statusCode');
    } catch (e) {
      AppLog.w('Emby', '用户名密码登录异常: $e');
    }
    return false;
  }

  /// 确保已通过认证（有 apiKey）
  /// 如果没有 apiKey 但有用户名密码，则自动登录获取 access token
  /// 并发锁：多个调用方同时调用时共享同一次登录，避免重复请求
  Future<bool> _ensureAuth() async {
    if (apiKey.isNotEmpty) return true;
    if (_username == null || _password == null || _username!.isEmpty)
      return false;
    _authFuture ??=
        loginByUsernamePassword().whenComplete(() => _authFuture = null);
    return _authFuture!;
  }

  @override
  Map<String, String> get authHeaders =>
      apiKey.isNotEmpty ? {'X-MediaBrowser-Token': apiKey} : const {};

  /// 401 自愈：作废当前（可能过期的）token，用用户名密码强制重新登录。
  @override
  Future<bool> doReAuthenticate() async {
    if (_username == null || _username!.isEmpty) {
      return apiKey.isNotEmpty; // 无凭据无法重登
    }
    AppLog.i('Emby', '作废旧 token，强制重新登录: $_username');
    _authCache.remove(_currentAuthCacheKey);
    apiKey = '';
    userId = null;
    _userIdLoaded = false;
    dio.options.headers.remove('X-MediaBrowser-Token');
    return await loginByUsernamePassword();
  }

  Future<String> _ensureUserId() async {
    if (_userIdLoaded && userId != null && userId!.isNotEmpty) return userId!;
    // 先确保认证
    await _ensureAuth();
    try {
      if (userId != null && userId!.isNotEmpty) {
        try {
          final r = await dio.get('/Users/$userId');
          if (r.statusCode == 200) {
            _userIdLoaded = true;
            AppLog.i('Emby', 'userId OK: $userId');
            return userId!;
          }
        } catch (e) {
          AppLog.w('Emby', '/Users/\$userId failed: $e');
        }
      }
      final r = await dio.get('/Users');
      final users = (r.data is List) ? (r.data as List) : <dynamic>[];
      if (users.isNotEmpty) {
        userId = users.first['Id']?.toString() ?? '';
        _userIdLoaded = true;
        AppLog.i('Emby', 'userId from /Users: $userId');
        return userId!;
      }
      AppLog.w('Emby', '/Users returned empty list');
    } catch (e) {
      AppLog.e('Emby', '_ensureUserId failed', e);
    }
    _userIdLoaded = true;
    return userId ?? '';
  }

  @override
  Future<bool> testConnection() async {
    try {
      await _ensureUserId();
      final r = await dio.get('/System/Info');
      AppLog.i('Emby', 'connection OK, server=${r.data['ServerName']}');
      return r.statusCode == 200;
    } catch (e) {
      AppLog.e('Emby', 'connection FAILED', e);
      return false;
    }
  }

  @override
  Map<String, String> getAuthInfo() {
    if (apiKey.isEmpty) return const {};
    return {
      'apiKey': apiKey,
      if (userId != null && userId!.isNotEmpty) 'userId': userId!,
    };
  }

  @override
  Future<List<MediaItem>> getLibraries() async {
    try {
      await _ensureUserId();
      final r = await dio.get('/Users/$userId/Views');
      final items = (r.data['Items'] as List?) ?? [];
      AppLog.i('Emby', 'getLibraries: ${items.length} views');
      return items
          .map((i) => MediaItem(
              id: i['Id'] ?? '',
              title: i['Name'] ?? '',
              posterUrl: i['ImageTags']?['Primary'] != null
                  ? '$baseUrl/Items/${i['Id']}/Images/Primary?api_key=$apiKey'
                  : '',
              type: i['CollectionType'] == 'tvshows'
                  ? MediaType.series
                  : MediaType.movie,
              collectionType: i['CollectionType']?.toString()))
          .toList();
    } catch (e) {
      AppLog.e('Emby', 'getLibraries FAILED', e);
      return [];
    }
  }

  @override
  Future<List<MediaItem>> getLibraryItems(String libraryId,
      {int page = 0, int limit = 50, bool includeBoxSets = false}) async {
    try {
      await _ensureUserId();
      final hasUid = userId != null && userId!.isNotEmpty;
      // Jellyfin 的合集(boxsets)库必须显式 IncludeItemTypes=BoxSet 才返回合集条目
      // （实测 Movie,Series 过滤下返回 0；Emby 则两者都返回），故 boxsets 库追加。
      final itemTypes = includeBoxSets ? 'Movie,Series,BoxSet' : 'Movie,Series';
      final params = <String, dynamic>{
        'StartIndex': page * limit,
        'Limit': limit,
        'Recursive': true,
        'IncludeItemTypes': itemTypes,
        'SortBy': 'DateCreated',
        'SortOrder': 'Descending',
        'Fields': 'Genres,MediaSources,Overview,CommunityRating,ProviderIds'
      };
      if (libraryId.isNotEmpty) params['ParentId'] = libraryId;
      final path = hasUid ? '/Users/$userId/Items' : '/Items';
      final r = await dio.get(path, queryParameters: params);
      final items = (r.data['Items'] as List?) ?? [];
      AppLog.i('Emby',
          'getLibraryItems($libraryId) uid=$userId: ${items.length} items (boxsets=$includeBoxSets)');
      return _parseItems(items);
    } catch (e) {
      // 网络/鉴权错误必须向上抛：上层（首页缓存刷新）才能回退到旧数据，
      // 而不是把错误吞成空列表，覆盖并清空正常的缓存
      AppLog.e('Emby', 'getLibraryItems FAILED: $libraryId', e);
      rethrow;
    }
  }

  /// 分页拉取库内全部条目：Emby/Jellyfin 单页默认 50 条，大库只取第一页会"少".
  /// （实测 Emby 166 部 / Jellyfin 173 部电影的库，之前都只显示 50）。每页 200 条循环直到取完。
  @override
  Future<List<MediaItem>> getAllLibraryItems(String libraryId,
      {bool includeBoxSets = false}) async {
    final all = <MediaItem>[];
    var page = 0;
    const perPage = 200;
    while (page < 50) {
      final batch = await getLibraryItems(libraryId,
          page: page, limit: perPage, includeBoxSets: includeBoxSets);
      all.addAll(batch);
      if (batch.length < perPage) break;
      page++;
    }
    AppLog.i('Emby',
        'getAllLibraryItems($libraryId): ${all.length} items (${page + 1} 页)');
    return all;
  }

  @override
  Future<List<MediaItem>> getSimilarItems(String itemId) async {
    try {
      await _ensureUserId();
      final r = await dio.get('/Items/$itemId/Similar', queryParameters: {
        'Limit': 12,
        'Fields': 'Genres,MediaSources,Overview,CommunityRating,ProviderIds',
      });
      final items = (r.data['Items'] as List?) ?? [];
      AppLog.i('Emby', 'getSimilarItems($itemId): ${items.length} items');
      return _parseItems(items);
    } catch (e) {
      AppLog.w('Emby', 'getSimilarItems FAILED (服务端可能不支持): $e');
      return [];
    }
  }

  @override
  Future<MediaItem> getItemDetails(String itemId) async {
    final cached = _detailsCache[itemId];
    final now = DateTime.now().millisecondsSinceEpoch;
    if (cached != null && now - cached.timestamp < _cacheDurationMs) {
      AppLog.d('Emby', 'getItemDetails cache hit: $itemId');
      return cached.item;
    }

    await _ensureUserId();
    final r = await dio.get('/Users/$userId/Items/$itemId', queryParameters: {
      'Fields':
          'Overview,Genres,People,MediaSources,MediaStreams,ProviderIds,CommunityRating',
    });
    final item = _parseItem(r.data);
    _detailsCache[itemId] = _CachedDetailItem(item);
    AppLog.d('Emby',
        'getItemDetails cached: $itemId (${_detailsCache.length} items)');
    return item;
  }

  @override
  Future<List<ServerSubtitleResult>> searchSubtitles(
    String itemId, {
    String? language,
  }) async {
    await _ensureUserId();
    try {
      final body = <String, dynamic>{
        if (language != null && language.isNotEmpty) 'Language': language,
        'IsForced': false,
        'IsHearingImpaired': false,
      };
      final response = await dio.post(
        '/Items/$itemId/RemoteSearch/Subtitles',
        data: body,
        options: Options(contentType: Headers.jsonContentType),
      );
      final raw = response.data;
      final list = raw is List
          ? raw
          : raw is Map
              ? (raw['SearchResults'] ??
                  raw['Results'] ??
                  raw['results'] ??
                  raw['Items'] ??
                  const [])
              : const [];
      return (list is List ? list : const [])
          .whereType<Map>()
          .map((entry) => ServerSubtitleResult.fromJson(
                Map<String, dynamic>.from(entry),
              ))
          .where((result) => result.id.isNotEmpty)
          .toList();
    } catch (e) {
      throw MediaServerSubtitleException('字幕搜索失败: $e');
    }
  }

  /// 从媒体服务器删除媒体条目（Emby/Jellyfin 通用接口）。
  @override
  Future<void> deleteItem(String itemId) async {
    await _ensureUserId();
    try {
      await dio.delete('/Items/$itemId');
      _detailsCache.remove(itemId);
    } catch (e) {
      throw MediaServerException('删除媒体失败: $e');
    }
  }

  /// 画质选项 → MaxStreamingBitrate（bps）：
  /// auto/original = 直连或自适应（不设 bitrate 上限）；
  /// 1080p/720p/4k 映射为对应的转码码率上限
  static String? _resolveBitrate(String? quality) {
    switch (quality) {
      case null:
      case 'auto':
      case 'original':
        return null;
      case '720p':
        return '4000000';
      case '1080p':
        return '8000000';
      case '4k':
        return '40000000';
      default:
        return quality; // 兼容直接传数字字符串
    }
  }

  @override
  Future<String> getStreamUrl(String itemId,
      {String? quality,
      bool burnInSubtitle = false,
      int? subtitleIndex}) async {
    await _ensureUserId();
    await _ensureAuth();
    final bitrate = _resolveBitrate(quality);

    // 字幕烧录：请求服务器用 FFmpeg 把字幕编码进视频流（SubtitleMethod=Encode）。
    // 此时服务器必须转码，DirectPlay 会被忽略，字幕变成画面像素——
    // 适合截图/投屏要带字幕或客户端渲染不了的复杂字幕。
    final burnQuery = burnInSubtitle
        ? '&SubtitleMethod=Encode'
            '&TranscodingSubtitleMethod=Encode'
            '${subtitleIndex != null ? '&SubtitleStreamIndex=$subtitleIndex' : ''}'
        : '';

    // Emby 需要先获取 PlaybackInfo 拿到真实 MediaSourceId 和 PlaySessionId
    try {
      final r = await dio.post(
        '/Items/$itemId/PlaybackInfo',
        data: {
          'UserId': userId,
          'AllowVideoStreamCopy': true,
          'AllowAudioStreamCopy': true,
          'EnableDirectPlay': true,
          'EnableDirectStream': true,
        },
      );
      final mediaSources = (r.data['MediaSources'] as List?) ?? [];
      final playSessionId = r.data['PlaySessionId']?.toString();
      if (mediaSources.isNotEmpty) {
        final sourceId = mediaSources[0]['Id']?.toString() ?? itemId;
        String url =
            '$baseUrl/Videos/$itemId/stream?api_key=$apiKey&Static=true'
            '&MediaSourceId=$sourceId'
            '&DeviceId=$_playSessionId'
            '$burnQuery';
        if (playSessionId != null && playSessionId.isNotEmpty) {
          url += '&PlaySessionId=$playSessionId';
        }
        if (bitrate != null) url += '&MaxStreamingBitrate=$bitrate';
        AppLog.i('Emby', 'streamUrl (PlaybackInfo): $url');
        return url;
      }
    } catch (e) {
      AppLog.w('Emby', 'PlaybackInfo failed, fallback: $e');
    }

    // Fallback: 直接用 itemId 作为 MediaSourceId
    String url =
        '$baseUrl/Videos/$itemId/stream?api_key=$apiKey&Static=true&MediaSourceId=$itemId&DeviceId=$_playSessionId$burnQuery';
    if (bitrate != null) url += '&MaxStreamingBitrate=$bitrate';
    AppLog.i('Emby', 'streamUrl (fallback): $url');
    return url;
  }

  @override
  Future<List<MediaItem>> search(String query) async {
    try {
      await _ensureUserId();
      final r = await dio.get('/Items', queryParameters: {
        'SearchTerm': query,
        'IncludeItemTypes': 'Movie,Series',
        'Recursive': true,
        'Limit': 50,
        'Fields': 'Overview,Genres,CommunityRating,ProviderIds',
      });
      final items = (r.data['Items'] as List?) ?? [];
      final filtered = items.where((i) {
        final type = i['Type']?.toString() ?? '';
        return type == 'Movie' || type == 'Series';
      }).toList();
      AppLog.i('Emby',
          'search "$query": ${items.length} total, ${filtered.length} filtered');
      return _parseItems(filtered);
    } catch (e) {
      AppLog.w('Emby', 'search failed: $e');
      return [];
    }
  }

  @override
  Future<void> markWatched(String itemId,
      {double? progress, int? positionMs}) async {
    try {
      final params = <String, dynamic>{};
      if (positionMs != null) {
        params['PlaybackPositionTicks'] =
            (positionMs * 10000); // ms → ticks (100ns)
      } else if (progress != null) {
        params['PlaybackPositionTicks'] = (progress * 10000000).round();
      }
      // Emby UserData 端点要求 Content-Type: application/json，参数放在 body
      // 用 queryParameters 会触发 415 Unsupported Media Type
      await dio.post(
        '/Users/$userId/Items/$itemId/UserData',
        data: params,
        options: Options(contentType: Headers.jsonContentType),
      );
      AppLog.d('Emby',
          'markWatched: itemId=$itemId, posTicks=${params['PlaybackPositionTicks']}');
    } catch (e) {
      AppLog.e('Emby', 'markWatched FAILED: $e');
    }
  }

  /// 取消已观看（Emby/Jellyfin：UserData Played=false）
  @override
  Future<void> markUnwatched(String itemId) async {
    try {
      await dio.post(
        '/Users/$userId/Items/$itemId/UserData',
        data: {'Played': false},
        options: Options(contentType: Headers.jsonContentType),
      );
      AppLog.d('Emby', 'markUnwatched: itemId=$itemId');
    } catch (e) {
      AppLog.e('Emby', 'markUnwatched FAILED: $e');
    }
  }

  /// 播放开始上报 — 注册播放会话，使项目出现在"继续观看"列表
  @override
  Future<void> reportPlaybackStart(String itemId,
      {String? mediaSourceId}) async {
    try {
      final data = <String, dynamic>{
        'ItemId': itemId,
        'MediaSourceId': mediaSourceId ?? itemId,
        'PlayMethod': 'DirectStream',
        'CanSeek': true,
        'IsPaused': false,
        'IsMuted': false,
        'PlaySessionId': _playSessionId,
      };
      await dio.post(
        '/Sessions/Playing',
        data: data,
        options: Options(contentType: Headers.jsonContentType),
      );
      AppLog.i('Emby',
          'reportPlaybackStart OK: itemId=$itemId sessionId=$_playSessionId');
    } catch (e) {
      AppLog.e('Emby', 'reportPlaybackStart FAILED: $e');
    }
  }

  /// 播放进度定期上报 — 更新服务器端播放位置
  @override
  Future<void> reportPlaybackProgress(String itemId, int positionMs,
      {bool isPlaying = true, String? mediaSourceId}) async {
    try {
      final ticks = positionMs * 10000; // ms → 100ns ticks
      final data = <String, dynamic>{
        'ItemId': itemId,
        'MediaSourceId': mediaSourceId ?? itemId,
        'PositionTicks': ticks,
        'IsPaused': !isPlaying,
        'IsMuted': false,
        'CanSeek': true,
        'PlayMethod': 'DirectStream',
        'PlaySessionId': _playSessionId,
      };
      await dio.post(
        '/Sessions/Playing/Progress',
        data: data,
        options: Options(contentType: Headers.jsonContentType),
      );
      AppLog.d('Emby',
          'reportPlaybackProgress: itemId=$itemId, posTicks=$ticks, posMs=$positionMs');
    } catch (e) {
      AppLog.e('Emby',
          'reportPlaybackProgress FAILED: $e, posMs=$positionMs, ticks=${positionMs * 10000}');
    }
  }

  /// 播放停止上报 — 提交最终位置，服务器据此更新"继续观看"进度
  @override
  Future<void> reportPlaybackStopped(String itemId,
      {int? positionMs, String? mediaSourceId}) async {
    try {
      final data = <String, dynamic>{
        'ItemId': itemId,
        'MediaSourceId': mediaSourceId ?? itemId,
        'PlaySessionId': _playSessionId,
      };
      if (positionMs != null) {
        data['PositionTicks'] = positionMs * 10000;
      }
      await dio.post(
        '/Sessions/Playing/Stopped',
        data: data,
        options: Options(contentType: Headers.jsonContentType),
      );
      AppLog.i('Emby',
          'reportPlaybackStopped OK: itemId=$itemId, pos=${positionMs}ms');
    } catch (e) {
      AppLog.e('Emby', 'reportPlaybackStopped FAILED: $e');
    }
  }

  @override
  Future<void> markFavorite(String itemId) async {
    try {
      await dio.post('/Users/$userId/FavoriteItems/$itemId');
    } catch (_) {}
  }

  @override
  Future<void> unmarkFavorite(String itemId) async {
    try {
      await dio.delete('/Users/$userId/FavoriteItems/$itemId');
    } catch (_) {}
  }

  @override
  Future<List<ChapterMarker>> getChapters(String itemId) async {
    try {
      await _ensureUserId();
      // 从 Item 详情中获取 Chapters（/Items/{id}/Chapters 端点不存在）
      final r = await dio.get('/Users/$userId/Items/$itemId', queryParameters: {
        'Fields': 'Chapters',
      });
      final chapters = (r.data['Chapters'] as List?) ?? [];
      final result = <ChapterMarker>[];
      for (int i = 0; i < chapters.length; i++) {
        final c = chapters[i];
        final startTicks = (c['StartPositionTicks'] as num?)?.toInt() ?? 0;
        // 用下一章的起始位置作为本章结束，最后一章默认 1s
        final endTicks = (i + 1 < chapters.length)
            ? ((chapters[i + 1]['StartPositionTicks'] as num?)?.toInt() ??
                startTicks + 10000000)
            : startTicks + 10000000;
        result.add(ChapterMarker(
          name: c['Name']?.toString() ?? '',
          startTicks: startTicks,
          endTicks: endTicks,
          markerType: c['MarkerType']?.toString(),
        ));
      }
      AppLog.d('Emby', 'getChapters: ${result.length} chapters for $itemId');
      return result;
    } catch (e) {
      AppLog.w('Emby', 'getChapters failed: $e');
      return [];
    }
  }

  @override
  Future<IntroSkip?> getIntroSkipInfo(String itemId) async {
    // 0) Jellyfin 10.9+ 官方 MediaSegments API: GET /MediaSegments/{itemId}
    //    返回 { Items: [{ Type: 'Intro'|'Outro'|..., StartTicks, EndTicks }], TotalRecordCount }
    try {
      final r = await dio.get('/MediaSegments/$itemId');
      if (r.statusCode == 200 && r.data is Map) {
        final items = (r.data['Items'] as List?) ?? [];
        if (items.isNotEmpty) {
          int? introStart, introEnd, creditsStart, creditsEnd;
          for (final seg in items) {
            if (seg is! Map) continue;
            final type = (seg['Type'] as String?)?.toLowerCase() ?? '';
            final start = (seg['StartTicks'] as num?)?.toInt();
            final end = (seg['EndTicks'] as num?)?.toInt();
            if (start == null || end == null) continue;
            AppLog.d(
                'Emby', 'MediaSegment: type=$type, start=$start, end=$end');
            if (type == 'intro') {
              introStart = start;
              introEnd = end;
            } else if (type == 'outro' || type == 'credits') {
              creditsStart = start;
              creditsEnd = end;
            }
          }
          if (introStart != null && introEnd != null && introEnd > introStart) {
            AppLog.i('Emby',
                'IntroSkip via MediaSegments API: intro=$introStart→$introEnd, credits=$creditsStart→$creditsEnd');
            return IntroSkip(
              introStartTicks: introStart,
              introEndTicks: introEnd,
              creditsStartTicks: creditsStart,
              creditsEndTicks: creditsEnd,
            );
          }
          // 只有 credits 也返回
          if (creditsStart != null) {
            AppLog.i('Emby',
                'IntroSkip via MediaSegments API (credits only): $creditsStart→$creditsEnd');
            return IntroSkip(
              introStartTicks: 0,
              introEndTicks: 0,
              creditsStartTicks: creditsStart,
              creditsEndTicks: creditsEnd,
            );
          }
        }
      }
    } catch (e) {
      AppLog.d('Emby', 'MediaSegments API 不可用（可能非 Jellyfin 10.9+）: $e');
    }

    // 1) Jellyfin IntroSkipper 插件: GET /Episodes/{episodeId}/IntroTimestamps
    try {
      final r = await dio.get('/Episodes/$itemId/IntroTimestamps');
      if (r.statusCode == 200 && r.data is Map) {
        final result = _parseIntroResponse(r.data as Map<String, dynamic>);
        if (result != null) {
          AppLog.i('Emby',
              'IntroSkip via Jellyfin API: intro=${result.hasIntro}, credits=${result.hasCredits}');
          return result;
        }
      }
    } catch (e) {
      AppLog.d('Emby', 'Jellyfin IntroTimestamps 不可用: $e');
    }

    // 2) Emby IntroSkip 插件: 多种端点模式
    for (final path in [
      '/Episodes/$itemId/IntroTimestamps',
      '/Items/$itemId/IntroTimestamps',
      '/emby/IntroSkip/Items/$itemId',
    ]) {
      try {
        final r = await dio.get(path);
        if (r.statusCode == 200 && r.data is Map) {
          final result = _parseIntroResponse(r.data as Map<String, dynamic>);
          if (result != null) {
            AppLog.i('Emby',
                'IntroSkip via Emby plugin ($path): intro=${result.hasIntro}');
            return result;
          }
        }
      } catch (_) {}
    }

    // 3) 章节数据回退（少数服务器通过 MarkerType 标记 Intro）
    final ch = await getChapters(itemId);
    // 位置合理性校验需要总时长：部分服务器把普通章节命名为"片头/片尾"
    //（位置可能在片头之后很远/片尾之前很远），直接当标记会导致
    // "跳过片头后立刻弹跳过片尾"、autoSkip 误跳整集。
    final durTicks = await _getItemRunTimeTicks(itemId);
    int? introStart, introEnd, creditsStart, creditsEnd;
    for (final c in ch) {
      final mt = c.markerType?.toLowerCase() ?? '';
      final nm = c.name.toLowerCase();
      // Emby/Jellyfin 标准 marker：Intro（整段区间）
      if (mt == 'intro') {
        introStart = c.startTicks;
        introEnd = c.endTicks;
        AppLog.d('Emby', 'chapter marker Intro: ${c.startTicks}→${c.endTicks}');
        continue;
      }
      // Outro/Credits marker
      if (mt == 'outro' || mt == 'credits') {
        creditsStart = c.startTicks;
        creditsEnd = c.endTicks;
        AppLog.d('Emby', 'chapter marker $mt: ${c.startTicks}→${c.endTicks}');
        continue;
      }
      // 兼容 IntroSkipper 的 MarkerType
      if (mt == 'introstart' || nm == 'intro start' || nm.contains('片头开始')) {
        introStart = c.startTicks;
      }
      if (mt == 'introend' || nm == 'intro end' || nm == '片头结束') {
        introEnd = c.startTicks;
      }
      if (mt == 'creditsstart' || nm == 'credits start' || nm == '片尾开始') {
        creditsStart = c.startTicks;
      }
      // 中文名兜底
      if (nm.contains('片头') && introStart == null) introStart = c.startTicks;
      if (nm.contains('片尾') && creditsStart == null) {
        creditsStart = c.startTicks;
        creditsEnd = c.endTicks;
      }
    }
    // 合理性校验：片头必须在前 25%；片尾必须在后 50% 且晚于片头结束。
    // 异常位置直接丢弃对应标记，宁缺毋滥（避免乱跳过）。
    if (durTicks != null && durTicks > 0) {
      if (introStart != null &&
          introEnd != null &&
          introEnd > durTicks * 25 ~/ 100) {
        AppLog.w('Emby',
            'IntroSkip chapters: intro 位置异常（${introEnd}ms > 前25%），丢弃 intro');
        introStart = null;
        introEnd = null;
      }
      if (creditsStart != null &&
          (creditsStart < durTicks ~/ 2 ||
              (introEnd != null && creditsStart <= introEnd))) {
        AppLog.w('Emby',
            'IntroSkip chapters: credits 位置异常（${creditsStart}ms），丢弃 credits');
        creditsStart = null;
        creditsEnd = null;
      }
    }
    if (introStart != null && introEnd != null && introEnd > introStart) {
      AppLog.i('Emby',
          'IntroSkip via chapters: intro=$introStart→$introEnd, credits=$creditsStart→$creditsEnd');
      return IntroSkip(
        introStartTicks: introStart,
        introEndTicks: introEnd,
        creditsStartTicks: creditsStart,
        creditsEndTicks: creditsEnd,
      );
    }
    // 只有 credits 也返回（可能电影只有片尾）
    if (creditsStart != null) {
      AppLog.i('Emby',
          'IntroSkip via chapters (credits only): $creditsStart→$creditsEnd');
      return IntroSkip(
        introStartTicks: 0,
        introEndTicks: 0,
        creditsStartTicks: creditsStart,
        creditsEndTicks: creditsEnd,
      );
    }
    AppLog.i('Emby',
        'IntroSkip: 未检测到片头片尾信息 (itemId=$itemId, chapters=${ch.length})');
    return null;
  }

  /// 获取条目总时长（ticks），用于片头片尾位置合理性校验
  Future<int?> _getItemRunTimeTicks(String itemId) async {
    try {
      await _ensureUserId();
      final r = await dio.get('/Users/$userId/Items/$itemId',
          queryParameters: {'Fields': 'Chapters'});
      return (r.data['RunTimeTicks'] as num?)?.toInt();
    } catch (_) {
      return null;
    }
  }

  /// 解析 IntroSkip 插件返回的时间戳数据（兼容多种字段名格式）
  IntroSkip? _parseIntroResponse(Map<String, dynamic> data) {
    int? introStart, introEnd, creditsStart;

    // Jellyfin IntroSkipper: IntroStart / IntroEnd (ticks)
    // Emby 插件变体: IntroStartTicks / IntroEndTicks
    introStart = (data['IntroStart'] as num?)?.toInt() ??
        (data['IntroStartTicks'] as num?)?.toInt() ??
        (data['intro_start'] as num?)?.toInt();
    introEnd = (data['IntroEnd'] as num?)?.toInt() ??
        (data['IntroEndTicks'] as num?)?.toInt() ??
        (data['intro_end'] as num?)?.toInt();

    // Credits
    creditsStart = (data['CreditsStart'] as num?)?.toInt() ??
        (data['CreditsStartTicks'] as num?)?.toInt() ??
        (data['credits_start'] as num?)?.toInt();

    if (introStart != null && introEnd != null && introEnd > introStart) {
      return IntroSkip(
        introStartTicks: introStart,
        introEndTicks: introEnd,
        creditsStartTicks: creditsStart,
      );
    }
    return null;
  }

  @override
  Future<List<MediaItem>> getSeasons(String seriesId) async {
    final cacheKey = seriesId;
    final cached = _seasonsCache[cacheKey];
    final now = DateTime.now().millisecondsSinceEpoch;
    if (cached != null && now - cached.timestamp < _cacheDurationMs) {
      AppLog.d('Emby', 'getSeasons cache hit: $seriesId');
      return cached.seasons;
    }
    // 不吞错：HTTP 错误/网络错误向上抛出，让 UI 能区分"加载失败"与"无数据"
    await _ensureUserId();
    final r = await dio.get('/Shows/$seriesId/Seasons',
        queryParameters: {'UserId': userId, 'Fields': 'Overview'});
    _throwIfHttpError(r);
    final seasons = ((r.data['Items'] as List?) ?? [])
        .map((i) => _parseItem({
              'Id': i['Id'] ?? '',
              'Name': i['Name'] ?? '',
              'Type': 'Season',
              'IndexNumber': i['IndexNumber'],
              'ImageTags': {'Primary': i['ImageTags']?['Primary'] ?? ''},
              'Overview': i['Overview'],
            }))
        .toList();
    // 只缓存非空结果，避免 401/网络错误返回的空列表被负缓存
    if (seasons.isNotEmpty) {
      _seasonsCache[cacheKey] = _CachedSeasons(seasons);
      AppLog.d(
          'Emby', 'getSeasons cached: $seriesId (${seasons.length} seasons)');
    }
    return seasons;
  }

  @override
  Future<List<MediaItem>> getEpisodes(String seriesId,
      {String? seasonId, int? page, int limit = 50}) async {
    final cacheKey = '${seriesId}_${seasonId ?? ''}_$limit';
    final cached = _episodesCache[cacheKey];
    final now = DateTime.now().millisecondsSinceEpoch;
    if (cached != null &&
        now - cached.timestamp < _cacheDurationMs &&
        page == null) {
      AppLog.d('Emby', 'getEpisodes cache hit: $cacheKey');
      return cached.episodes;
    }
    // 不吞错：HTTP 错误/网络错误向上抛出，让 UI 能区分"加载失败"与"无数据"
    await _ensureUserId();
    final params = <String, dynamic>{
      'UserId': userId,
      'Fields': 'Overview,MediaSources',
      'SortBy': 'SortName',
      'Limit': limit
    };
    if (seasonId != null) params['SeasonId'] = seasonId;
    if (page != null) params['StartIndex'] = page * limit;
    final r =
        await dio.get('/Shows/$seriesId/Episodes', queryParameters: params);
    _throwIfHttpError(r);
    final episodes = _parseItems((r.data['Items'] as List?) ?? []);
    _sortEpisodes(episodes);
    // 只缓存非空结果，避免 401/网络错误返回的空列表被负缓存
    if (page == null && episodes.isNotEmpty) {
      _episodesCache[cacheKey] = _CachedEpisodes(episodes);
      AppLog.d('Emby',
          'getEpisodes cached: $cacheKey (${episodes.length} episodes)');
    }
    return episodes;
  }

  /// 按 (季, 集) 稳定排序剧集列表。部分服务器的 SortName 缺失或乱序
  /// （例如把第13集排在最前），不排序会导致："第1集"卡片实际播放第13集、
  /// 自动连播/上一集下一集跳到随机集。
  void _sortEpisodes(List<MediaItem> episodes) {
    episodes.sort((a, b) {
      final sa = a.seasonNumber ?? 0, sb = b.seasonNumber ?? 0;
      if (sa != sb) return sa.compareTo(sb);
      return (a.episodeNumber ?? 0).compareTo(b.episodeNumber ?? 0);
    });
  }

  /// 将 HTTP 错误状态码转为异常抛出。
  /// 必要原因：FnOSService 子类设置了 validateStatus=(_)=>true 接受所有状态码，
  /// 401 等错误不会自动抛 DioException，需手动转换，上层 UI 才能感知"加载失败"。
  void _throwIfHttpError(Response r) {
    final status = r.statusCode ?? 0;
    if (status >= 400) {
      throw DioException(
        requestOptions: r.requestOptions,
        response: r,
        type: DioExceptionType.badResponse,
        message: 'HTTP $status',
      );
    }
  }

  List<MediaItem> _parseItems(List items) =>
      items.map((i) => _parseItem(i)).toList();

  @override
  Future<List<MediaItem>> getResumeItems({int limit = 20}) async {
    try {
      await _ensureUserId();
      final r = await dio.get('/Users/$userId/Items/Resume', queryParameters: {
        'Limit': limit,
        'IncludeItemTypes': 'Movie,Episode',
        'Recursive': true,
        'EnableTotalRecordCount': false,
        'Fields':
            'Overview,Genres,MediaSources,CommunityRating,ProviderIds,SeriesId,SeasonId,EpisodeNumber',
      });
      final items = (r.data['Items'] as List?) ?? [];
      AppLog.i('Emby', 'getResumeItems: ${items.length} items');
      for (final it in items) {
        AppLog.d('Emby',
            '  resume: ${it['Name']} (${it['Type']}, id=${it['Id']}, hasImage=${it['ImageTags']?['Primary'] != null})');
      }
      return _parseItems(items);
    } catch (e) {
      AppLog.e('Emby', 'getResumeItems FAILED: $e');
      return [];
    }
  }

  MediaItem _parseItem(dynamic item) {
    final m = item is Map<String, dynamic> ? item : <String, dynamic>{};
    final mediaSources = (m['MediaSources'] as List?) ?? [];
    final firstSource = mediaSources.isNotEmpty ? mediaSources.first : null;
    final providerIds = m['ProviderIds'] as Map?;
    final tmdbIdStr =
        providerIds?['Tmdb']?.toString() ?? providerIds?['TMDB']?.toString();
    final tmdbId = tmdbIdStr != null ? int.tryParse(tmdbIdStr) : null;
    final userData = m['UserData'];
    final playbackTicks = userData?['PlaybackPositionTicks'];
    final runTimeTicks = m['RunTimeTicks'];
    double? watchProgress;
    if (playbackTicks != null && runTimeTicks != null && runTimeTicks > 0) {
      watchProgress = (playbackTicks / runTimeTicks).toDouble().clamp(0.0, 1.0);
    }
    return MediaItem(
      id: m['Id']?.toString() ?? '',
      title: m['Name'] ?? '',
      posterUrl: m['ImageTags']?['Primary'] != null
          ? '$baseUrl/Items/${m['Id']}/Images/Primary?api_key=$apiKey'
          : '',
      backdropUrl: m['BackdropImageTags']?.isNotEmpty == true
          ? '$baseUrl/Items/${m['Id']}/Images/Backdrop/0?api_key=$apiKey'
          : null,
      overview: m['Overview'],
      rating: (m['CommunityRating'] as num?)?.toDouble(),
      year: m['ProductionYear'],
      genres: (m['Genres'] as List?)?.map((e) => e.toString()).toList() ?? [],
      type: m['Type'] == 'Series'
          ? MediaType.series
          : m['Type'] == 'Episode'
              ? MediaType.episode
              : MediaType.movie,
      isBoxSet: m['Type'] == 'BoxSet',
      seasonNumber: m['ParentIndexNumber'] ?? m['SeasonNumber'],
      episodeNumber: m['IndexNumber'] ?? m['EpisodeNumber'],
      seriesTitle: m['SeriesName'],
      seriesId: m['SeriesId']?.toString(),
      duration: m['RunTimeTicks'] != null
          ? (m['RunTimeTicks'] / 10000000).toInt()
          : 0,
      imdbId: providerIds?['Imdb']?.toString(),
      tmdbId: tmdbId,
      isWatched: userData?['Played'] ?? false,
      isFavorite: userData?['IsFavorite'] ?? false,
      watchProgress: watchProgress,
      filePath: firstSource?['Path']?.toString(),
      director: _extractPeople(m, 'Director')?.firstOrNull,
      cast: _extractPeople(m, 'Actor'),
      videoTracks: _extractStreams(m, 'Video'),
      audioTracks: _extractStreams(m, 'Audio'),
      subtitleTracks: _extractStreams(m, 'Subtitle'),
      people: _extractPeopleFull(m)?.map((p) {
        final imageTag = p['PrimaryImageTag']?.toString().trim();
        final personId = p['Id']?.toString().trim();
        if (imageTag != null &&
            imageTag.isNotEmpty &&
            personId != null &&
            personId.isNotEmpty) {
          p['ImageUrl'] =
              '$baseUrl/Items/${Uri.encodeComponent(personId)}/Images/Primary'
              '?api_key=${Uri.encodeQueryComponent(apiKey)}'
              '&Tag=${Uri.encodeQueryComponent(imageTag)}';
        }
        return p;
      }).toList(),
    );
  }

  List<String>? _extractPeople(Map m, String type) {
    final p = (m['People'] as List?)
        ?.where((e) => e['Type'] == type)
        .map((e) => e['Name']?.toString() ?? '')
        .where((n) => n.isNotEmpty)
        .toList();
    return p != null && p.isNotEmpty ? p : null;
  }

  List<Map<String, dynamic>>? _extractPeopleFull(Map m) {
    final p = (m['People'] as List?)
        ?.map((e) => {
              'Id': e['Id']?.toString() ?? '',
              'Name': e['Name']?.toString() ?? '',
              'Role': e['Role']?.toString() ?? e['Type']?.toString() ?? '',
              'Type': e['Type']?.toString() ?? '',
              'PrimaryImageTag': e['PrimaryImageTag']?.toString(),
            })
        .where((e) => (e['Name'] as String).isNotEmpty)
        .toList();
    return p != null && p.isNotEmpty ? p : null;
  }

  List<Map<String, dynamic>>? _extractStreams(Map m, String type) {
    final s = (m['MediaSources'] as List?)?.firstOrNull;
    if (s == null) return null;
    final streams = (s['MediaStreams'] as List?)
        ?.where((e) => e['Type'] == type)
        .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
        .toList();
    return streams != null && streams.isNotEmpty ? streams : null;
  }
}

class _CachedDetailItem {
  final MediaItem item;
  final int timestamp;
  _CachedDetailItem(this.item)
      : timestamp = DateTime.now().millisecondsSinceEpoch;
}

class _CachedSeasons {
  final List<MediaItem> seasons;
  final int timestamp;
  _CachedSeasons(this.seasons)
      : timestamp = DateTime.now().millisecondsSinceEpoch;
}

class _CachedEpisodes {
  final List<MediaItem> episodes;
  final int timestamp;
  _CachedEpisodes(this.episodes)
      : timestamp = DateTime.now().millisecondsSinceEpoch;
}

// ==================== JellyfinService ====================

class JellyfinService extends EmbyService {
  JellyfinService(
      {required String baseUrl,
      String apiKey = '',
      String? userId,
      String? username,
      String? password,
      Dio? dioClient})
      : super(
            baseUrl: baseUrl,
            apiKey: apiKey,
            userId: userId,
            username: username,
            password: password,
            dioClient: dioClient) {
    // EmbyService 构造函数已设置 X-MediaBrowser-Token
    // 追加 X-Emby-Token（Jellyfin 专用），同时保留 X-MediaBrowser-Token（兼容 Emby 服务器）
    dio.options.headers['X-Emby-Token'] = apiKey;
    // 兜底：默认 query 参数带上 api_key，兼容仅接受 URL 参数认证的服务器
    dio.options.queryParameters['api_key'] = apiKey;
    AppLog.i('Jellyfin',
        'init baseUrl=$baseUrl (dual auth: X-MediaBrowser-Token + X-Emby-Token + api_key)');
  }

  @override
  Map<String, String> get streamHeaders =>
      {'X-Emby-Token': apiKey, 'X-MediaBrowser-Token': apiKey};

  @override
  Map<String, String> get imageHeaders => apiKey.isNotEmpty
      ? {'X-Emby-Token': apiKey, 'X-MediaBrowser-Token': apiKey}
      : const {};

  @override
  Map<String, String> get authHeaders => apiKey.isNotEmpty
      ? {'X-Emby-Token': apiKey, 'X-MediaBrowser-Token': apiKey}
      : const {};

  /// 401 自愈：作废双头旧 token 和 api_key，强制重新登录。
  @override
  Future<bool> doReAuthenticate() async {
    if (_username == null || _username!.isEmpty) {
      return apiKey.isNotEmpty; // 无凭据无法重登
    }
    AppLog.i('Jellyfin', '作废旧 token，强制重新登录: $_username');
    apiKey = '';
    userId = null;
    _userIdLoaded = false;
    dio.options.headers.remove('X-MediaBrowser-Token');
    dio.options.headers.remove('X-Emby-Token');
    dio.options.queryParameters['api_key'] = '';
    return await loginByUsernamePassword();
  }

  /// 登录成功后同步更新 Jellyfin 专有的 X-Emby-Token 和 api_key 查询参数
  @override
  Future<bool> loginByUsernamePassword() async {
    final ok = await super.loginByUsernamePassword();
    if (ok) {
      // 同步更新 Jellyfin 专有头
      dio.options.headers['X-Emby-Token'] = apiKey;
      dio.options.queryParameters['api_key'] = apiKey;
    }
    return ok;
  }

  /// Trickplay 缩略图 URL（Jellyfin 10.9+ 专属特性）
  String getTrickplayTileUrl(String itemId, int sheetIndex, {int width = 320}) {
    final uid = userId ?? '';
    return '$baseUrl/Videos/$itemId/Trickplay/$width/$sheetIndex.jpg?api_key=$apiKey'
        '${uid.isNotEmpty ? '&UserId=$uid' : ''}';
  }

  /// 获取 Trickplay 元数据（缩略图间隔等信息）
  Future<TrickplayInfo?> getTrickplayInfo(String itemId) async {
    try {
      final r = await dio.get('/Videos/$itemId/Trickplay');
      if (r.statusCode == 200 && r.data is Map) {
        final data = r.data as Map<String, dynamic>;
        final widthMap = data['320'] ?? data.values.firstOrNull;
        if (widthMap is Map) {
          return TrickplayInfo(
            intervalMs: (widthMap['Interval'] as num?)?.toInt() ?? 10000,
            tileWidth: (widthMap['TileWidth'] as num?)?.toInt() ?? 10,
            tileHeight: (widthMap['TileHeight'] as num?)?.toInt() ?? 10,
            thumbnailCount:
                (widthMap['ThumbnailCount'] as num?)?.toInt() ?? 100,
          );
        }
      }
    } catch (e) {
      // 服务器未生成 Trickplay 缩略图时返回 404，属正常降级，不刷 WARN；
      // 其它错误（网络/鉴权等）才需要告警
      if (e is DioException && e.response?.statusCode == 404) {
        AppLog.d('Jellyfin', 'Trickplay 未生成（服务器无缩略图），拖拽预览已降级');
      } else {
        AppLog.w('Jellyfin', 'getTrickplayInfo failed: $e');
      }
    }
    return null;
  }

  @override
  Future<String> _ensureUserId() async {
    if (_userIdLoaded && userId != null && userId!.isNotEmpty) return userId!;
    // 确保已认证（如果没有 apiKey 但有用户名密码，先自动登录）
    await _ensureAuth();
    try {
      final r = await dio.get('/Users');
      if (r.statusCode == 200 && r.data is List) {
        final users = r.data as List;
        if (users.isNotEmpty) {
          userId = users.first['Id']?.toString() ?? '';
          if (userId!.isNotEmpty) {
            _userIdLoaded = true;
            AppLog.i('Jellyfin', 'userId: $userId');
            return userId!;
          }
        }
      }
    } catch (e) {
      AppLog.w('Jellyfin', '/Users failed: $e');
    }
    _userIdLoaded = true;
    return userId ?? '';
  }
}

// ==================== FnOSService ====================
//
// 飞牛影视 (FnOS) 客户端实现
// 参考 FlyNarwhal 官方客户端（GitHub: fnOS/fly-narwhal）
// 使用飞牛专有 API：/v/api/v1/* + Authx 单层签名 + Cookie 会话
//
// 登录流程：
//   1. 检测中继模式（域名含 5ddd.com 或 fnos.net），构造 Cookie: mode=relay
//   2. POST /v/api/v1/login  body: {username, password, app_name: "trimemedia-web"}
//      响应：{code: 0, msg: ..., data: {token: ...}}，code==0 表示成功
//   3. 保存 Cookie: Trim-MC-token=<token>[; mode=relay]
//
// 后续请求：
//   - Authorization: <token>
//   - Cookie: Trim-MC-token=<token>[; mode=relay]
//   - Authx: nonce=<6位随机>&timestamp=<毫秒>&sign=<md5(apiKey_path_nonce_timestamp_dataJsonMd5_apiSecret)>
//   - User-Agent: Chrome UA
//
// 同时保留 Jellyfin 兼容模式：部分老版本飞牛部署支持 Jellyfin API，
// login() 先尝试 Jellyfin 认证，失败则回退到飞牛专有 API

class FnOSService extends EmbyService {
  // 飞牛专有 API 密钥（来自 FlyNarwhal app_constants.dart）
  static const String _fnosApiKey = 'NDzZTVxnRKP8Z0jXg1VAMonaG8akvh';
  static const String _fnosApiSecret = '16CCEB3D-AB42-077D-36A1-F355324E4237';
  static const String _fnosApiBase = '/v/api/v1';
  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36';

  final String? username;
  final String? password;
  String? _fnosToken;
  String? _cookie;
  bool _isRelayMode = false;
  bool _jellyfinMode = false;

  /// 缓存媒体库 ID → category 映射，供 getLibraryItems 决定 tags.type 过滤
  final Map<String, String> _libraryCategoryCache = {};

  /// 当前是否运行在 Jellyfin 兼容模式
  bool get isJellyfinMode => _jellyfinMode;

  /// 公开 token 的只读访问
  String? get token => _jellyfinMode ? apiKey : _fnosToken;

  @override
  Map<String, String> get streamHeaders {
    if (_jellyfinMode) return {'X-Emby-Token': apiKey};
    final headers = <String, String>{};
    if (_fnosToken != null && _fnosToken!.isNotEmpty) {
      headers['Authorization'] = _fnosToken!;
    }
    if (_cookie != null && _cookie!.isNotEmpty) {
      headers['Cookie'] = _cookie!;
    }
    headers['User-Agent'] = _userAgent;
    return headers;
  }

  @override
  Map<String, String> get imageHeaders {
    if (_jellyfinMode) return const {};
    final headers = <String, String>{};
    if (_fnosToken != null && _fnosToken!.isNotEmpty) {
      headers['Authorization'] = _fnosToken!;
    }
    if (_cookie != null && _cookie!.isNotEmpty) {
      headers['Cookie'] = _cookie!;
    }
    headers['User-Agent'] = _userAgent;
    return headers;
  }

  @override
  Future<bool> ensureAuthenticated() async {
    if (_jellyfinMode) return apiKey.isNotEmpty;
    if (_fnosToken != null && _fnosToken!.isNotEmpty) return true;
    return await login();
  }

  @override
  Map<String, String> get authHeaders {
    if (_jellyfinMode) {
      return apiKey.isNotEmpty ? {'X-Emby-Token': apiKey} : const {};
    }
    final h = <String, String>{};
    if (_fnosToken != null && _fnosToken!.isNotEmpty)
      h['Authorization'] = _fnosToken!;
    if (_cookie != null && _cookie!.isNotEmpty) h['Cookie'] = _cookie!;
    return h;
  }

  /// 401 自愈：作废所有旧 token，强制重新登录（先 Jellyfin 兼容、后飞牛专有）。
  @override
  Future<bool> doReAuthenticate() async {
    if (username == null || username!.isEmpty) {
      return (_jellyfinMode && apiKey.isNotEmpty) ||
          (_fnosToken?.isNotEmpty == true);
    }
    AppLog.i('FnOS', '作废旧 token，强制重新登录: $username');
    _fnosToken = null;
    _cookie = null;
    _jellyfinMode = false;
    apiKey = '';
    userId = null;
    _userIdLoaded = false;
    dio.options.headers.remove('X-Emby-Token');
    return await login();
  }

  FnOSService(
      {required String baseUrl, this.username, this.password, Dio? dioClient})
      : super(baseUrl: baseUrl, apiKey: '', dioClient: dioClient) {
    // 接受所有状态码，便于读取非 200 响应体进行调试
    dio.options.validateStatus = (_) => true;
    // 清除 EmbyService 构造函数设置的空 token 头
    dio.options.headers.remove('X-MediaBrowser-Token');
    // 检测中继模式
    _isRelayMode = _detectRelayMode(baseUrl);
  }

  /// 中继模式检测：域名包含 5ddd.com 或 fnos.net
  static bool _detectRelayMode(String baseUrl) {
    try {
      final uri = Uri.tryParse(baseUrl);
      if (uri == null) return false;
      final host = uri.host.toLowerCase();
      return host.contains('5ddd.com') || host.contains('fnos.net');
    } catch (_) {
      return false;
    }
  }

  // ==================== 登录 ====================

  Future<bool> login() async {
    if (username == null || password == null) return false;
    // ── 第一步：飞牛专有 API 登录（优先，支持 tags.type 过滤等原生能力）──
    if (await _tryFnOSLogin()) {
      return true;
    }
    // ── 第二步：尝试 Jellyfin 兼容认证（部分飞牛版本仅支持此模式）──
    return await _tryJellyfinLogin();
  }

  /// Jellyfin 兼容登录：POST /Users/AuthenticateByName
  Future<bool> _tryJellyfinLogin() async {
    AppLog.i('FnOS', '尝试 Jellyfin 兼容认证...');
    try {
      final deviceId = 'LANPlayer_${DateTime.now().millisecondsSinceEpoch}';
      final authHeader =
          'MediaBrowser Client="FnOSPlayer", Device="LANPlayer", '
          'DeviceId="$deviceId", Version="1.0.0"';
      final response = await dio.post(
        '$baseUrl/Users/AuthenticateByName',
        data: {'Username': username, 'Pw': password},
        options: Options(headers: {
          'Content-Type': 'application/json',
          'Authorization': authHeader,
        }, extra: {
          '_isLoginRequest': true
        }),
      );

      final statusCode = response.statusCode ?? 0;
      if (statusCode >= 200 && statusCode < 300 && response.data is Map) {
        final data = response.data as Map;
        final accessToken = data['AccessToken']?.toString() ??
            (data['User'] as Map?)?['AccessToken']?.toString();
        final userIdStr = (data['User'] as Map?)?['Id']?.toString() ??
            data['User']?['Id']?.toString();

        if (accessToken != null && accessToken.isNotEmpty) {
          _jellyfinMode = true;
          apiKey = accessToken;
          userId = userIdStr;

          dio.options.headers['X-Emby-Token'] = apiKey;
          dio.options.headers.remove('X-MediaBrowser-Token');

          if (userId == null || userId!.isEmpty) {
            try {
              final usersRes = await dio.get('$baseUrl/Users');
              if (usersRes.statusCode == 200 && usersRes.data is List) {
                final users = usersRes.data as List;
                if (users.isNotEmpty) {
                  userId = users.first['Id']?.toString() ?? '';
                }
              }
            } catch (_) {}
          }

          AppLog.i('FnOS', 'Jellyfin 兼容登录成功: userId=$userId');
          return true;
        }
      }

      AppLog.w(
          'FnOS', 'Jellyfin 认证失败: HTTP $statusCode, body=${response.data}');
    } catch (e) {
      AppLog.w('FnOS', 'Jellyfin 认证异常: $e');
    }
    return false;
  }

  /// 飞牛专有 API 登录：POST /v/api/v1/login
  /// 参考 FlyNarwhal login_view_model.dart
  Future<bool> _tryFnOSLogin() async {
    AppLog.i(
        'FnOS', '尝试飞牛专有 API 登录: ${_isRelayMode ? "relay" : "direct"} mode');
    const loginPath = '/v/api/v1/login';
    final url = '$baseUrl$loginPath';

    try {
      final requestData = {
        'username': username,
        'password': password,
        'app_name': 'trimemedia-web',
      };
      // Authx 签名使用完整路径（与 FlyNarwhal 一致，路径 = 请求的 URL path）
      final authx = _generateAuthx(loginPath, data: requestData);
      final response = await dio.post(
        url,
        data: requestData,
        options: Options(headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'User-Agent': _userAgent,
          'Authx': authx,
        }, extra: {
          '_isLoginRequest': true
        }),
      );

      final statusCode = response.statusCode ?? 0;
      if (statusCode < 200 || statusCode >= 300) {
        AppLog.w('FnOS', 'HTTP $statusCode $url, body=${response.data}');
        return false;
      }

      final res = response.data;
      if (res is! Map) {
        AppLog.w('FnOS', '响应不是 JSON Map: ${res.runtimeType}');
        return false;
      }

      // 飞牛响应格式：{code, msg, data}
      final code = res['code'];
      final msg = res['msg']?.toString() ?? '';
      if (code != 0) {
        AppLog.w('FnOS', '登录失败: code=$code msg=$msg');
        return false;
      }

      final dataMap = res['data'];
      if (dataMap is! Map) {
        AppLog.w('FnOS', '响应 data 字段缺失或非 Map');
        return false;
      }
      final token = dataMap['token']?.toString();
      if (token == null || token.isEmpty) {
        AppLog.w('FnOS', 'token 为空');
        return false;
      }

      _fnosToken = token;
      _jellyfinMode = false;
      // 构造 Cookie，中继模式追加 mode=relay
      _cookie = _isRelayMode
          ? 'Trim-MC-token=$token; mode=relay'
          : 'Trim-MC-token=$token';

      AppLog.i(
          'FnOS', '飞牛 API 登录成功: tokenLen=${token.length} relay=$_isRelayMode');
      return true;
    } catch (e) {
      AppLog.w('FnOS', '登录异常 $url: $e');
      return false;
    }
  }

  // ==================== 认证保障 ====================

  @override
  Future<bool> _ensureAuth() async {
    if (_jellyfinMode) return apiKey.isNotEmpty;
    if (_fnosToken != null && _fnosToken!.isNotEmpty) return true;
    // 并发锁：复用父类 _authFuture，多个调用方共享同一次登录
    _authFuture ??= login().whenComplete(() => _authFuture = null);
    return _authFuture!;
  }

  // ==================== 连接测试 ====================

  @override
  Future<bool> testConnection() async {
    try {
      if (_jellyfinMode && apiKey.isNotEmpty) {
        // Jellyfin 模式：使用标准 /System/Info
        dio.options.validateStatus = (s) => s != null && s < 500;
        final r = await dio.get('$baseUrl/System/Info');
        return r.statusCode == 200;
      }
      // 飞牛专有模式：尝试登录后调用 /mediadb/list
      if (!await _ensureAuth()) return false;
      final res = await _fnosGet('/mediadb/list');
      return res != null;
    } catch (e) {
      AppLog.w('FnOS', 'testConnection failed: $e');
      return false;
    }
  }

  // ==================== 媒体库操作（双模式路由）====================

  @override
  Future<List<MediaItem>> getLibraries() async {
    if (_jellyfinMode) return super.getLibraries();
    await _ensureAuth();
    try {
      // GET /v/api/v1/mediadb/list
      // FlyNarwhal MediaDbListResponse: {guid, title, posters[], category, view_type}
      final res = await _fnosGet('/mediadb/list');
      if (res == null) return [];
      final list = _extractList(res);
      _libraryCategoryCache.clear();
      return list.map((c) {
        final m = c is Map ? Map<String, dynamic>.from(c) : <String, dynamic>{};
        final guid = m['guid']?.toString() ?? '';
        final name = m['title']?.toString() ?? '';
        final poster = _firstImagePath(m['posters'] ?? m['poster']);
        final category = m['category']?.toString().toLowerCase() ?? '';
        final viewType = m['view_type'];
        _libraryCategoryCache[guid] = category;
        final type = category.contains('tv') ||
                category.contains('series') ||
                viewType == 1
            ? MediaType.series
            : MediaType.movie;
        return MediaItem(
          id: guid,
          title: name,
          posterUrl: _resolveImageUrl(poster, width: 500),
          type: type,
        );
      }).toList();
    } catch (e) {
      AppLog.w('FnOS', 'getLibraries failed: $e');
      return [];
    }
  }

  @override
  Future<List<MediaItem>> getLibraryItems(String libraryId,
      {int page = 0, int limit = 50, bool includeBoxSets = false}) async {
    if (_jellyfinMode)
      return super.getLibraryItems(libraryId,
          page: page, limit: limit, includeBoxSets: includeBoxSets);
    await _ensureAuth();
    try {
      // 根据媒体库 category 决定 tags.type 过滤，避免返回 Season/Episode 子条目
      final category = _libraryCategoryCache[libraryId] ?? '';
      final typeFilter = category.contains('tv') || category.contains('series')
          ? ['TV']
          : category.contains('movie')
              ? ['Movie']
              : ['TV', 'Movie']; // Mix 或未知类型：排除 Season/Episode

      // 分页获取全部条目（每页 200，循环直到取完）
      const pageSize = 200;
      var currentPage = 1;
      final allItems = <MediaItem>[];
      while (true) {
        final requestData = {
          if (libraryId.isNotEmpty) 'ancestor_guid': libraryId,
          'exclude_grouped_video': 1,
          'sort_type': 'DESC',
          'sort_column': 'create_time',
          'page_size': pageSize,
          'page': currentPage,
          'tags': {
            'type': typeFilter,
          },
        };
        final res = await _fnosPost('/item/list', requestData);
        if (res == null) break;
        final list = _extractList(res);
        if (list.isEmpty) break;
        allItems.addAll(_fnosParseItems(list));
        // 如果返回数量不足一页，说明已到最后一页
        if (list.length < pageSize) break;
        currentPage++;
      }
      return allItems;
    } catch (e) {
      AppLog.w('FnOS', 'getLibraryItems failed: $e');
      return [];
    }
  }

  @override
  Future<List<MediaItem>> getAllLibraryItems(String libraryId,
      {bool includeBoxSets = false}) async {
    // FnOS 的 getLibraryItems 内部已按页取全量且忽略 page/limit 参数，
    // 直接返回即可；若用父类循环分页会对同一批数据重复追加。
    return getLibraryItems(libraryId, includeBoxSets: includeBoxSets);
  }

  @override
  Future<MediaItem> getItemDetails(String itemId) async {
    if (_jellyfinMode) return super.getItemDetails(itemId);
    await _ensureAuth();
    // GET /v/api/v1/item/{guid}
    final res = await _fnosGet('/item/$itemId');
    return _fnosParseItem(res ?? <String, dynamic>{}, itemId);
  }

  @override
  Future<String> getStreamUrl(String itemId,
      {String? quality,
      bool burnInSubtitle = false,
      int? subtitleIndex}) async {
    if (_jellyfinMode)
      return super.getStreamUrl(itemId,
          quality: quality,
          burnInSubtitle: burnInSubtitle,
          subtitleIndex: subtitleIndex);
    await _ensureAuth();
    // POST /v/api/v1/play/info  body: {item_guid: itemId}
    // 响应中包含 media_guid，用于构造 /media/range/ 流地址
    final res = await _fnosPost('/play/info', {'item_guid': itemId});
    if (res != null) {
      // 优先使用 media_guid 构造 /media/range/ 流（支持 HTTP Range，兼容旧固件）
      final mediaGuid = res['media_guid']?.toString();
      if (mediaGuid != null && mediaGuid.isNotEmpty) {
        final url = '$baseUrl$_fnosApiBase/media/range/$mediaGuid';
        AppLog.i('FnOS', 'streamUrl (media/range): $url');
        return url;
      }
      // 其次尝试 file_stream.file（新版固件可能提供）
      final fileStream = res['file_stream'];
      if (fileStream is Map) {
        final file = fileStream['file']?.toString();
        if (file != null && file.isNotEmpty) {
          final url = file.startsWith('http') ? file : '$baseUrl$file';
          AppLog.i('FnOS', 'streamUrl (file_stream): $url');
          return url;
        }
      }
      // 再尝试 play_link
      final playLink = res['play_link']?.toString();
      if (playLink != null && playLink.isNotEmpty) {
        final url =
            playLink.startsWith('http') ? playLink : '$baseUrl$playLink';
        AppLog.i('FnOS', 'streamUrl (play_link): $url');
        return url;
      }
    }
    // Fallback: 直接构造 stream/video/<guid>（兼容旧版）
    final fallback = '$baseUrl$_fnosApiBase/stream/video/$itemId';
    AppLog.i('FnOS', 'fallback streamUrl: $fallback');
    return fallback;
  }

  Future<String> getDirectStreamUrl(String itemId) async =>
      getStreamUrl(itemId);

  @override
  Future<List<MediaItem>> search(String query) async {
    if (_jellyfinMode) return super.search(query);
    await _ensureAuth();
    try {
      // GET /v/api/v1/search/list?q=<query>
      // 使用 queryParameters 让 dio 正确处理 query string，
      // 同时 Authx 签名也会基于排序后的 query 生成
      final res = await _fnosGet('/search/list', query: {'q': query});
      if (res == null) return [];
      final list = _extractList(res);
      return _fnosParseItems(list);
    } catch (e) {
      AppLog.w('FnOS', 'search failed: $e');
      return [];
    }
  }

  @override
  Future<void> markWatched(String itemId,
      {double? progress, int? positionMs}) async {
    if (_jellyfinMode)
      return super
          .markWatched(itemId, progress: progress, positionMs: positionMs);
    await _ensureAuth();
    try {
      // 上报播放进度（用于"继续观看"）
      if (positionMs != null) {
        // POST /v/api/v1/play/record  body: {item_guid, ts, duration, ...}
        await _fnosPost('/play/record', {
          'item_guid': itemId,
          'media_guid': '',
          'video_guid': '',
          'audio_guid': '',
          'subtitle_guid': '',
          'resolution': '',
          'bitrate': 0,
          'ts': positionMs ~/ 1000,
          'duration': 0,
          'play_link': '',
          'device_id': 'LANPlayer',
          'direct_link_audio_index': 0,
          'lan': 'original',
          'device_name': 'LANPlayer',
        });
        return;
      }
      // 标记已看：POST /v/api/v1/item/watched  body: {item_guid}
      await _fnosPost('/item/watched', {'item_guid': itemId});
    } catch (e) {
      AppLog.w('FnOS', 'markWatched failed: $e');
    }
  }

  @override
  Future<void> markUnwatched(String itemId) async {
    if (_jellyfinMode) return super.markUnwatched(itemId);
    await _ensureAuth();
    try {
      await _fnosPost('/item/unwatched', {'item_guid': itemId});
    } catch (e) {
      AppLog.w('FnOS', 'markUnwatched failed: $e');
    }
  }

  @override
  Future<void> markFavorite(String itemId) async {
    if (_jellyfinMode) return super.markFavorite(itemId);
    await _ensureAuth();
    try {
      // PUT /v/api/v1/item/favorite  body: {item_guid}
      await _fnosRequest('/item/favorite',
          data: {'item_guid': itemId}, method: 'PUT');
    } catch (e) {
      AppLog.w('FnOS', 'markFavorite failed: $e');
    }
  }

  @override
  Future<void> unmarkFavorite(String itemId) async {
    if (_jellyfinMode) return super.unmarkFavorite(itemId);
    await _ensureAuth();
    try {
      // DELETE /v/api/v1/item/favorite  body: {item_guid}
      await _fnosRequest('/item/favorite',
          data: {'item_guid': itemId}, method: 'DELETE');
    } catch (e) {
      AppLog.w('FnOS', 'unmarkFavorite failed: $e');
    }
  }

  @override
  Future<List<ChapterMarker>> getChapters(String itemId) async {
    if (_jellyfinMode) return super.getChapters(itemId);
    return [];
  }

  @override
  Future<IntroSkip?> getIntroSkipInfo(String itemId) async {
    if (_jellyfinMode) return super.getIntroSkipInfo(itemId);
    return null;
  }

  @override
  Future<List<MediaItem>> getSeasons(String seriesId) async {
    if (_jellyfinMode) return super.getSeasons(seriesId);
    await _ensureAuth();
    // GET /v/api/v1/season/list/{guid}
    // _fnosGet 返回 null 即请求失败，向上抛错让 UI 感知（不吞错成 []）
    final res = await _fnosGet('/season/list/$seriesId');
    if (res == null) {
      throw Exception('FnOS getSeasons failed for $seriesId');
    }
    final list = _extractList(res);
    return list.map((s) {
      final m = s is Map ? Map<String, dynamic>.from(s) : <String, dynamic>{};
      final guid = m['guid']?.toString() ?? '';
      final seasonNumber = (m['season_number'] as num?)?.toInt() ?? 1;
      return MediaItem(
        id: guid,
        title: m['title']?.toString() ?? '第$seasonNumber季',
        posterUrl: _resolveImageUrl(m['poster'] ?? m['posters'], width: 500),
        type: MediaType.series,
        seasonNumber: seasonNumber,
        overview: m['overview']?.toString(),
        seriesTitle: m['tv_title']?.toString() ?? m['parent_title']?.toString(),
        totalEpisodes: (m['number_of_episodes'] as num?)?.toInt(),
      );
    }).toList();
  }

  @override
  Future<List<MediaItem>> getEpisodes(String seriesId,
      {String? seasonId, int? page, int limit = 50}) async {
    if (_jellyfinMode)
      return super
          .getEpisodes(seriesId, seasonId: seasonId, page: page, limit: limit);
    await _ensureAuth();
    // GET /v/api/v1/episode/list/{guid}
    // seasonId 优先；否则使用 seriesId
    // _fnosGet 返回 null 即请求失败，向上抛错让 UI 感知（不吞错成 []）
    final targetGuid = seasonId ?? seriesId;
    final res = await _fnosGet('/episode/list/$targetGuid');
    if (res == null) {
      throw Exception('FnOS getEpisodes failed for $targetGuid');
    }
    final list = _extractList(res);
    final items = _fnosParseItems(list);
    _sortEpisodes(items);
    return items;
  }

  @override
  Future<List<MediaItem>> getResumeItems({int limit = 20}) async {
    if (_jellyfinMode) return super.getResumeItems(limit: limit);
    await _ensureAuth();
    try {
      // GET /v/api/v1/play/list  返回最近观看列表
      final res = await _fnosGet('/play/list');
      if (res == null) return [];
      final list = _extractList(res);
      final items = _fnosParseItems(list);
      return items.take(limit).toList();
    } catch (e) {
      AppLog.w('FnOS', 'getResumeItems failed: $e');
      return [];
    }
  }

  // ==================== 飞牛专有 API 工具方法 ====================

  /// 从响应中提取 list（兼容多种字段名）
  List _extractList(Map<String, dynamic> res) {
    final list = res['list'];
    if (list is List) return list;
    final items = res['items'];
    if (items is List) return items;
    final data = res['data'];
    if (data is List) return data;
    return const [];
  }

  /// 解析图片 URL：相对路径拼接飞牛图片服务基路径
  /// 飞牛图片服务端点为 {baseUrl}/v/api/v1/sys/img{path}，可选 ?w={width} 服务端缩放。
  /// 注意：该端点需要 Authorization 头（见 imageHeaders），裸 URL 会返回 "Auth Failed"。
  String _resolveImageUrl(dynamic url, {int width = 0}) {
    final path = _firstImagePath(url);
    if (path.isEmpty) return '';
    if (path.startsWith('http')) return path;
    final normalized = path.startsWith('/') ? path : '/$path';
    final base = '$baseUrl$_fnosApiBase/sys/img';
    return width > 0 ? '$base$normalized?w=$width' : '$base$normalized';
  }

  /// 从可能为 String 或 List 的字段中取出单个图片路径。
  /// item/list、season/list、episode/list 返回 poster（单个字符串）；
  /// item/{guid} 详情返回 posters/backdrops（字段名为复数但通常仍是单个字符串，偶尔为数组）。
  String _firstImagePath(dynamic v) {
    if (v == null) return '';
    if (v is String) return v.trim();
    if (v is List) {
      for (final e in v) {
        final s = e?.toString().trim() ?? '';
        if (s.isNotEmpty) return s;
      }
      return '';
    }
    return v.toString().trim();
  }

  String _md5(String input) {
    return md5.convert(utf8.encode(input)).toString();
  }

  /// 生成 Authx 头值（参考 FlyNarwhalAuthHelper.generateAuthx）
  /// 算法：MD5(apiKey_path_nonce_timestamp_dataJsonMd5_apiSecret)
  /// 其中 dataJsonMd5 = MD5(jsonEncode(data)) 或 MD5(sortedQuery) 或 MD5("")
  String _generateAuthx(String path,
      {Map<String, dynamic>? queryParameters, dynamic data}) {
    // nonce: 6 位随机数字（100000~999999）
    final random = DateTime.now().microsecond;
    final nonce = (100000 + random % 900000).toString();
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();

    String dataJsonMd5;
    if (data != null) {
      dataJsonMd5 = _md5(jsonEncode(data));
    } else if (queryParameters != null && queryParameters.isNotEmpty) {
      final sortedKeys = queryParameters.keys.toList()..sort();
      final sortedQuery = sortedKeys
          .where((k) => queryParameters[k] != null)
          .map((k) => '$k=${queryParameters[k]}')
          .join('&');
      dataJsonMd5 = _md5(sortedQuery);
    } else {
      dataJsonMd5 = _md5('');
    }

    final signSource = [
      _fnosApiKey,
      path,
      nonce,
      timestamp,
      dataJsonMd5,
      _fnosApiSecret
    ].join('_');
    return 'nonce=$nonce&timestamp=$timestamp&sign=${_md5(signSource)}';
  }

  /// 飞牛 API 通用请求方法
  /// 自动添加 Authorization、Cookie、Authx、User-Agent 头
  Future<Map<String, dynamic>?> _fnosRequest(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    String method = 'GET',
    int retry = 1,
  }) async {
    final fullPath = '$_fnosApiBase$path';
    final url = '$baseUrl$fullPath';
    final authx = _generateAuthx(
      fullPath,
      queryParameters: queryParameters,
      data: data is Map<String, dynamic> ? data : null,
    );
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'User-Agent': _userAgent,
      'Authx': authx,
    };
    if (_fnosToken != null && _fnosToken!.isNotEmpty) {
      headers['Authorization'] = _fnosToken!;
    }
    if (_cookie != null && _cookie!.isNotEmpty) {
      headers['Cookie'] = _cookie!;
    }

    try {
      Response response;
      switch (method) {
        case 'POST':
          response = await dio.post(url,
              data: data, options: Options(headers: headers));
          break;
        case 'PUT':
          response = await dio.put(url,
              data: data, options: Options(headers: headers));
          break;
        case 'DELETE':
          response = await dio.delete(url,
              data: data, options: Options(headers: headers));
          break;
        default:
          response = await dio.get(
            url,
            queryParameters: queryParameters,
            options: Options(headers: headers),
          );
      }

      final statusCode = response.statusCode ?? 0;
      if (statusCode < 200 || statusCode >= 300) {
        AppLog.w('FnOS',
            'HTTP $statusCode $method $fullPath, body=${response.data}');
        return null;
      }

      final res = response.data;
      if (res is! Map) {
        AppLog.w('FnOS', '响应非 JSON Map: ${res.runtimeType}');
        return null;
      }

      // 飞牛响应格式：{code, msg, data}
      final code = res['code'];
      if (code == null) {
        // 不带 code 字段的响应，直接返回整个 Map
        return Map<String, dynamic>.from(res);
      }
      if (code == 0 || code == 200) {
        final dataField = res['data'];
        if (dataField is Map) {
          return Map<String, dynamic>.from(dataField);
        } else if (dataField is List) {
          // data 是数组时包装成 {list: [...]} 便于上层处理
          return {'list': dataField};
        }
        return <String, dynamic>{};
      } else if (code == 5000 && res['msg'] == 'invalid sign' && retry > 0) {
        AppLog.w('FnOS', '签名错误，重试...');
        await Future.delayed(const Duration(milliseconds: 500));
        return _fnosRequest(path,
            data: data,
            queryParameters: queryParameters,
            method: method,
            retry: retry - 1);
      } else {
        AppLog.w('FnOS', 'API错误 ${res['msg']} (code=$code)');
        return null;
      }
    } catch (e) {
      AppLog.w('FnOS', '请求失败 $method $fullPath: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> _fnosGet(String p,
          {Map<String, dynamic>? query}) =>
      _fnosRequest(p, queryParameters: query, method: 'GET');
  Future<Map<String, dynamic>?> _fnosPost(String p, dynamic d) =>
      _fnosRequest(p, data: d, method: 'POST');

  List<MediaItem> _fnosParseItems(List items) =>
      items.map((i) => _fnosParseItem(i)).toList();

  MediaItem _fnosParseItem(dynamic item, [String? fallbackId]) {
    if (item is! Map) {
      return MediaItem(
          id: fallbackId ?? '',
          title: '',
          posterUrl: '',
          type: MediaType.movie);
    }
    final m = Map<String, dynamic>.from(item);
    final guid =
        m['guid']?.toString() ?? m['id']?.toString() ?? fallbackId ?? '';
    final title = m['title']?.toString() ?? m['name']?.toString() ?? '';
    final typeStr = m['type']?.toString() ?? '';
    final typeLower = typeStr.toLowerCase();
    final isSeries = typeStr == 'TV' ||
        typeStr == 'Series' ||
        typeStr == 'Season' ||
        typeLower.contains('tv') ||
        typeLower.contains('series');
    final isEpisode = typeStr == 'Episode' || typeLower.contains('episode');

    // FlyNarwhal MediaItem 字段映射
    final yearStr =
        m['release_date']?.toString() ?? m['first_air_date']?.toString();
    final voteAverage = m['vote_average'];
    final mediaStream = m['media_stream'];
    String? quality;
    if (mediaStream is Map) {
      final r = mediaStream['resolutions'];
      if (r is List && r.isNotEmpty) {
        quality = r.first.toString();
      }
    }
    final watchedVal = m['watched'];
    final isFavoriteInt = m['is_favorite'];
    final isWatched = watchedVal == 1 || watchedVal == true;
    final isFavorite = isFavoriteInt == 1 || isFavoriteInt == true;

    // 背景图：FnOS list API 常不带 backdrop 字段，解析为空时返回 null（与 Jellyfin 一致），
    // 以便 Hero 的 `backdropUrl ?? posterUrl` 能回退到海报，避免首页 Hero 纯暗色背景。
    final backdrop = _resolveImageUrl(
        m['backdrop'] ?? m['backdrops'] ?? m['background'],
        width: 1600);

    return MediaItem(
      id: guid,
      title: title,
      posterUrl: _resolveImageUrl(m['poster'] ?? m['posters'], width: 1080),
      backdropUrl: backdrop.isEmpty ? null : backdrop,
      overview: m['overview']?.toString(),
      rating: (voteAverage is num)
          ? voteAverage.toDouble()
          : double.tryParse(voteAverage?.toString() ?? ''),
      year: yearStr != null && yearStr.length >= 4
          ? int.tryParse(yearStr.substring(0, 4))
          : null,
      releaseDate:
          m['release_date']?.toString() ?? m['first_air_date']?.toString(),
      genres: const [],
      type: isSeries
          ? MediaType.series
          : (isEpisode ? MediaType.episode : MediaType.movie),
      duration: (m['duration'] as num?)?.toInt() ?? 0,
      seasonNumber: (m['season_number'] as num?)?.toInt(),
      episodeNumber: (m['episode_number'] as num?)?.toInt(),
      seriesTitle: m['tv_title']?.toString() ?? m['ancestor_name']?.toString(),
      totalSeasons: (m['number_of_seasons'] as num?)?.toInt(),
      totalEpisodes: (m['number_of_episodes'] as num?)?.toInt(),
      imdbId: m['imdb_id']?.toString(),
      quality: quality,
      isWatched: isWatched,
      isFavorite: isFavorite,
      filePath: m['file_name']?.toString() ?? m['file_path']?.toString(),
    );
  }
}
