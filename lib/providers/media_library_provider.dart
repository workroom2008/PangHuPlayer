import 'dart:async';
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/media_models.dart';
import '../services/media_server_service.dart';
import '../database/media_library_repository.dart';
import 'app_providers.dart';
import '../utils/app_log.dart';

enum DataSource { none, cache, network }

class MediaLibraryState {
  final List<MediaItem> libraries;
  final Map<String, List<MediaItem>> libraryItems;
  final List<MediaItem> carouselItems;
  final bool isLoading;
  final bool hasLoaded;
  final DateTime? lastRefreshTime;
  final String? errorMessage;
  final DataSource dataSource;
  final bool isRefreshing;

  MediaLibraryState({
    this.libraries = const [],
    this.libraryItems = const {},
    this.carouselItems = const [],
    this.isLoading = false,
    this.hasLoaded = false,
    this.lastRefreshTime,
    this.errorMessage,
    this.dataSource = DataSource.none,
    this.isRefreshing = false,
  });

  MediaLibraryState copyWith({
    List<MediaItem>? libraries,
    Map<String, List<MediaItem>>? libraryItems,
    List<MediaItem>? carouselItems,
    bool? isLoading,
    bool? hasLoaded,
    DateTime? lastRefreshTime,
    String? errorMessage,
    DataSource? dataSource,
    bool? isRefreshing,
  }) {
    return MediaLibraryState(
      libraries: libraries ?? this.libraries,
      libraryItems: libraryItems ?? this.libraryItems,
      carouselItems: carouselItems ?? this.carouselItems,
      isLoading: isLoading ?? this.isLoading,
      hasLoaded: hasLoaded ?? this.hasLoaded,
      lastRefreshTime: lastRefreshTime ?? this.lastRefreshTime,
      errorMessage: errorMessage,
      dataSource: dataSource ?? this.dataSource,
      isRefreshing: isRefreshing ?? this.isRefreshing,
    );
  }
}

const _kCacheTTL = Duration(minutes: 30);

class MediaLibraryNotifier extends StateNotifier<MediaLibraryState> {
  final Ref ref;
  MediaServerService? _service;
  String? _currentServerId;

  MediaLibraryNotifier(this.ref) : super(MediaLibraryState()) {
    AppLog.i('MediaLibrary', 'Notifier created');
    ref.listen(currentMediaServerServiceProvider, (previous, next) {
      AppLog.i('MediaLibrary', 'Service changed: prev=${previous != null ? "yes" : "no"}, next=${next != null ? "yes" : "no"}');
      _handleServiceChange(next);
    });
    Future.microtask(() {
      _service = ref.read(currentMediaServerServiceProvider);
      final servers = ref.read(mediaServersProvider);
      _currentServerId = servers.where((s) => s.isDefault).firstOrNull?.id ?? servers.firstOrNull?.id;
      AppLog.i('MediaLibrary', 'Initial service: ${_service != null ? _service!.baseUrl : "null"}');
      if (_service != null && !state.hasLoaded && !state.isLoading) {
        loadAll();
      }
    });
  }

  void _handleServiceChange(MediaServerService? next) {
    final servers = ref.read(mediaServersProvider);
    final defaultServer = servers.where((s) => s.isDefault).firstOrNull ?? servers.firstOrNull;
    final newServerId = defaultServer?.id;

    AppLog.i('MediaLibrary', 'handleServiceChange: serverCount=${servers.length}, defaultId=$newServerId, currentId=$_currentServerId');

    if (_currentServerId == null && next != null) {
      _service = next;
      _currentServerId = newServerId;
      if (!state.hasLoaded && !state.isLoading) {
        loadAll();
      }
      return;
    }

    _service = next;
    if (newServerId != _currentServerId && newServerId != null) {
      _currentServerId = newServerId;
      state = MediaLibraryState();
      if (_service != null) {
        AppLog.i('MediaLibrary', 'Server changed: ${_service!.baseUrl}, starting loadAll');
        loadAll();
      }
    } else if (newServerId == _currentServerId) {
      AppLog.i('MediaLibrary', 'handleServiceChange: same server, skipping reload. service=${next != null ? next.baseUrl : "null"}');
    } else {
      AppLog.i('MediaLibrary', 'Service is null, not loading');
    }
  }

  Future<void> loadAll({bool forceRefresh = false}) async {
    final service = _service;
    final serverId = _currentServerId;
    if (service == null || serverId == null) return;

    final cacheLoaded = await _loadFromDb(serverId);
    final hasCache = cacheLoaded && state.libraries.isNotEmpty;
    final cacheFresh = _isCacheFresh();

    if (!hasCache) {
      state = state.copyWith(isLoading: true);
    } else if (forceRefresh) {
      state = state.copyWith(isRefreshing: true);
    }

    if (hasCache && cacheFresh && !forceRefresh) {
      AppLog.i('MediaLibrary', 'Cache is fresh, skipping network refresh');
      state = state.copyWith(isLoading: false);
      return;
    }

    try {
      AppLog.i('MediaLibrary', 'Ensuring authentication for ${service.baseUrl}...');
      final authed = await service.ensureAuthenticated();
      if (!authed) {
        AppLog.e('MediaLibrary', 'Authentication failed for ${service.baseUrl}');
        state = state.copyWith(
          isLoading: false,
          isRefreshing: false,
          errorMessage: hasCache ? '认证失败，显示缓存数据' : '认证失败，请检查用户名和密码',
        );
        return;
      }
      AppLog.i('MediaLibrary', 'Authentication OK, loading libraries...');
      final libraries = await service.getLibraries();
      state = state.copyWith(libraries: libraries);

      AppLog.i('MediaLibrary', 'Loading ${libraries.length} library items...');
      final itemsMap = <String, List<MediaItem>>{};
      await Future.wait(libraries.map((lib) async {
        try {
          // 分页拉全量（单页默认 50 条，大库只取第一页会"少"）；
          // boxsets 库需显式带上 BoxSet 类型（Jellyfin 用 Movie,Series 查合集返回 0）
          final items = await service.getAllLibraryItems(
            lib.id,
            includeBoxSets: lib.collectionType == 'boxsets',
          );
          itemsMap[lib.id] = items;
          AppLog.i('MediaLibrary', 'Library ${lib.title}: ${items.length} items');
        } catch (e) {
          AppLog.w('MediaLibrary', 'Failed to load ${lib.title}: $e');
          itemsMap[lib.id] = state.libraryItems[lib.id] ?? [];
        }
      }));
      state = state.copyWith(libraryItems: itemsMap);

      final allItems = itemsMap.values.expand((x) => x).toList();
      final allWithBackdrop = allItems.where((i) => i.backdropUrl?.isNotEmpty == true).toList()..shuffle();
      final carousel = allWithBackdrop.take(6).toList();
      final now = DateTime.now();
      final carouselItems = carousel.isEmpty
          ? (() {
              final withPosters = allItems.where((i) => i.posterUrl.isNotEmpty).toList()..shuffle();
              return withPosters.take(6).toList();
            })()
          : carousel;

      // 为缺少 backdrop 的 carousel 条目从 detail API 补全宽幅背景图（FnOS list 不带 backdrop）
      final enrichedCarousel = await Future.wait(carouselItems.map((item) async {
        if (item.backdropUrl != null && item.backdropUrl!.isNotEmpty) return item;
        try {
          final detail = await service.getItemDetails(item.id);
          if (detail.backdropUrl != null && detail.backdropUrl!.isNotEmpty) {
            return item.copyWith(backdropUrl: detail.backdropUrl);
          }
        } catch (_) {}
        return item;
      }));

      state = state.copyWith(
        carouselItems: enrichedCarousel,
        hasLoaded: true,
        isLoading: false,
        isRefreshing: false,
        lastRefreshTime: now,
        errorMessage: null,
        dataSource: DataSource.network,
      );

      AppLog.i('MediaLibrary', 'Load complete: ${libraries.length} libraries, ${allItems.length} items');

      _saveToDbBackground(serverId, libraries, itemsMap, enrichedCarousel, now);

      _preloadAllImages(libraries, itemsMap, state.carouselItems, service);
    } catch (e) {
      AppLog.e('MediaLibrary', 'Load failed', e);
      state = state.copyWith(
        isLoading: false,
        isRefreshing: false,
        errorMessage: hasCache ? '刷新失败，显示缓存数据' : e.toString(),
      );
    }
  }

  bool _isCacheFresh() {
    final lastRefresh = state.lastRefreshTime;
    if (lastRefresh == null) return false;
    final age = DateTime.now().difference(lastRefresh);
    return age < _kCacheTTL;
  }

  Future<bool> _loadFromDb(String serverId) async {
    try {
      final hasCache = await MediaLibraryRepository.hasCache(serverId);
      if (!hasCache) {
        AppLog.i('MediaLibrary', 'No DB cache for server $serverId');
        return false;
      }

      final libraries = await MediaLibraryRepository.getLibraries(serverId);
      final libraryItems = await MediaLibraryRepository.getLibraryItems(serverId);
      final carouselItems = await MediaLibraryRepository.getCarouselItems(serverId);
      final lastRefreshTime = await MediaLibraryRepository.getLastRefreshTime(serverId);

      if (libraries.isEmpty) {
        AppLog.i('MediaLibrary', 'DB cache empty for server $serverId');
        return false;
      }

      state = state.copyWith(
        libraries: libraries,
        libraryItems: libraryItems,
        carouselItems: carouselItems,
        hasLoaded: true,
        lastRefreshTime: lastRefreshTime,
        dataSource: DataSource.cache,
      );

      final totalItems = libraryItems.values.fold<int>(0, (s, l) => s + l.length);
      final fresh = _isCacheFresh();
      AppLog.i('MediaLibrary',
          'DB cache loaded: ${libraries.length} libraries, $totalItems items, last refresh: $lastRefreshTime, fresh=$fresh');
      return true;
    } catch (e) {
      AppLog.w('MediaLibrary', 'Load from DB failed: $e');
      return false;
    }
  }

  bool _isSavingCache = false;
  void _saveToDbBackground(
    String serverId,
    List<MediaItem> libraries,
    Map<String, List<MediaItem>> libraryItems,
    List<MediaItem> carouselItems,
    DateTime lastRefreshTime,
  ) {
    if (_isSavingCache) return;
    _isSavingCache = true;

    Future.microtask(() async {
      try {
        await MediaLibraryRepository.upsertAll(
          serverId: serverId,
          libraries: libraries,
          libraryItems: libraryItems,
          carouselItems: carouselItems,
          lastRefreshTime: lastRefreshTime,
        );
        AppLog.i('MediaLibrary', 'DB cache upserted for server $serverId');
      } catch (e) {
        AppLog.w('MediaLibrary', 'Save to DB failed: $e');
      } finally {
        _isSavingCache = false;
      }
    });
  }

  void _preloadAllImages(
    List<MediaItem> libraries,
    Map<String, List<MediaItem>> itemsMap,
    List<MediaItem> carousel,
    MediaServerService service,
  ) {
    final urls = <String>{};
    final headers = service.imageHeaders;
    final headerMap = headers.isEmpty ? null : headers;

    for (final lib in libraries) {
      if (lib.posterUrl.isNotEmpty) urls.add(lib.posterUrl);
    }

    for (final item in carousel) {
      final backdrop = item.backdropUrl;
      if (backdrop != null && backdrop.isNotEmpty) urls.add(backdrop);
      if (item.posterUrl.isNotEmpty) urls.add(item.posterUrl);
    }

    for (final items in itemsMap.values) {
      for (var i = 0; i < items.length && i < 8; i++) {
        if (items[i].posterUrl.isNotEmpty) urls.add(items[i].posterUrl);
      }
    }

    if (urls.isEmpty) return;

    final urlList = urls.toList();
    AppLog.i('MediaLibrary', 'Preloading ${urlList.length} images (TV scope)...');

    Future.microtask(() => _preloadImagesConcurrently(urlList, headerMap));
  }

  Future<void> _preloadImagesConcurrently(
    List<String> urls,
    Map<String, String>? headers,
  ) async {
    const maxConcurrent = 2;
    var completedCount = 0;
    final queue = List<String>.from(urls);
    var activeCount = 0;

    final completer = Completer<void>();

    void preloadNext() {
      while (queue.isNotEmpty && activeCount < maxConcurrent) {
        final url = queue.removeLast();
        activeCount++;

        final provider = CachedNetworkImageProvider(
          url,
          headers: headers,
        );

        final listener = ImageStreamListener(
          (info, synchronousCall) {
            completedCount++;
            activeCount--;
            if (completedCount % 20 == 0) {
              AppLog.i('MediaLibrary', 'Preload progress: $completedCount/${urls.length}');
            }
            if (queue.isEmpty && activeCount == 0) {
              AppLog.i('MediaLibrary', 'Preload complete: $completedCount images');
              if (!completer.isCompleted) completer.complete();
            } else {
              preloadNext();
            }
          },
          onError: (e, stack) {
            completedCount++;
            activeCount--;
            if (queue.isEmpty && activeCount == 0) {
              if (!completer.isCompleted) completer.complete();
            } else {
              preloadNext();
            }
          },
        );

        provider.resolve(const ImageConfiguration()).addListener(listener);
      }
    }

    preloadNext();

    await completer.future.timeout(
      const Duration(seconds: 60),
      onTimeout: () {
        AppLog.w('MediaLibrary', 'Preload timeout at $completedCount/${urls.length}');
      },
    );
  }

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true);
    await loadAll();
  }

  MediaItem? getItemById(String id) {
    for (final items in state.libraryItems.values) {
      for (final item in items) {
        if (item.id == id) return item;
      }
    }
    for (final lib in state.libraries) {
      if (lib.id == id) return lib;
    }
    return null;
  }

  MediaItem? getItemByTitle(String title) {
    final lowerTitle = title.trim().toLowerCase();
    for (final items in state.libraryItems.values) {
      for (final item in items) {
        if (item.title.trim().toLowerCase() == lowerTitle) return item;
      }
    }
    return null;
  }

  List<MediaItem> getItemsForLibrary(String libraryId) {
    return state.libraryItems[libraryId] ?? [];
  }
}

final mediaLibraryProvider = StateNotifierProvider<MediaLibraryNotifier, MediaLibraryState>((ref) {
  return MediaLibraryNotifier(ref);
});
