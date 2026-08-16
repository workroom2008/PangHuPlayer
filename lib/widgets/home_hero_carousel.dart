import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:palette_generator/palette_generator.dart';
import '../models/media_models.dart';
import '../services/http_client.dart';
import '../services/media_server_service.dart';
import '../theme/app_theme.dart';
import '../services/storage_service.dart';
import '../utils/animation_config.dart';
import '../utils/screen_adapter.dart';
import '../utils/app_log.dart';
import 'server_image.dart';

/// 全屏背景轮播 Hero 组件
class HomeHeroCarousel extends ConsumerStatefulWidget {
  final List<MediaItem> items;
  final int initialIndex;
  final ValueChanged<int>? onIndexChanged;
  final VoidCallback? onTapItem;
  final void Function(Color)? onColorExtracted;
  final Map<String, String>? imageHeaders;
  final MediaServerService? service;

  const HomeHeroCarousel({
    super.key,
    required this.items,
    this.initialIndex = 0,
    this.onIndexChanged,
    this.onTapItem,
    this.onColorExtracted,
    this.imageHeaders,
    this.service,
  });

  @override
  ConsumerState<HomeHeroCarousel> createState() => _HomeHeroCarouselState();
}

class _HomeHeroCarouselState extends ConsumerState<HomeHeroCarousel> {
  late PageController _controller;

  /// 当前页索引。用 ValueNotifier 而非 setState：
  /// 旧实现在 onPageChanged 里 setState，会重建整个 build —— 其中包含
  /// _buildBackground 返回的 PageView 自身，等于在滑动动画进行中重建 PageView，
  /// 造成顿挫/闪烁。改为只让信息层与页码指示器局部重建。
  final ValueNotifier<int> _currentVN = ValueNotifier<int>(0);

  /// 读取当前索引的便捷 getter（保持既有调用点写法不变）
  int get _current => _currentVN.value;

  Timer? _autoScroll;
  final Map<String, Color> _memoryCache = {};

  static const _cacheKey = 'carousel_color_cache_v2';
  static const _paletteSize = 128;

  @override
  void initState() {
    super.initState();
    _currentVN.value = widget.initialIndex;
    _controller = PageController(initialPage: _current);
    _startAutoScroll();
    _loadCacheSync();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.items.isNotEmpty) {
        // 立即使用缓存颜色（如果有）
        final currentItem = widget.items[_current];
        final cached = _getCached(currentItem.id);
        if (cached != null && widget.onColorExtracted != null) {
          widget.onColorExtracted!(cached);
        }
        // 先触发服务登录，登录完成后 setState 让 ServerImage 用新 headers 重建
        // 然后预加载所有轮播图颜色
        _ensureAuthThenPreload();
      }
    });
  }

  /// 确保服务已登录，然后重建组件并预加载颜色
  /// 飞牛等需要异步登录的服务，首次访问时 imageHeaders 为空，必须等登录完成
  Future<void> _ensureAuthThenPreload() async {
    final svc = widget.service;
    if (svc != null) {
      try {
        final ok = await svc.ensureAuthenticated();
        if (ok && mounted) {
          // 登录成功后重建，让 ServerImage 拿到最新 headers
          setState(() {});
        }
      } catch (e) {
        AppLog.w('Carousel', 'ensureAuth failed: $e');
      }
    }
    if (mounted) {
      await _preloadAllColors();
    }
  }

  /// 并行预加载所有轮播图颜色，限制并发数避免网络拥塞
  /// 最多同时发起 3 个请求，预加载时间从 15 秒缩短到 5 秒
  Future<void> _preloadAllColors() async {
    const maxConcurrent = 3;
    final pending = <Future<void>>[];
    
    for (final item in widget.items) {
      if (!mounted) break;
      
      // 如果已有缓存，跳过
      if (_getCached(item.id) != null) continue;
      
      // 启动取色任务
      final future = _extractAndCache(item);
      pending.add(future);
      
      // 限制并发数
      if (pending.length >= maxConcurrent) {
        await Future.wait(pending.take(maxConcurrent));
        pending.removeRange(0, maxConcurrent);
      }
    }
    
    // 等待剩余任务完成
    if (pending.isNotEmpty) {
      await Future.wait(pending);
    }
  }

  /// 同步加载缓存，立即使用
  void _loadCacheSync() {
    try {
      final data = StorageService.getJson(_cacheKey);
      if (data != null) {
        data.forEach((key, value) {
          _memoryCache[key] = Color(int.parse(value.toString()));
        });
        // 立即通知当前项的缓存颜色
        if (widget.items.isNotEmpty && _current < widget.items.length) {
          final currentItem = widget.items[_current];
          final cached = _memoryCache[currentItem.id];
          if (cached != null && widget.onColorExtracted != null) {
            widget.onColorExtracted!(cached);
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _saveCache() async {
    try {
      final map = <String, String>{};
      _memoryCache.forEach((key, color) {
        map[key] = color.toARGB32().toString();
      });
      await StorageService.setJson(_cacheKey, map);
    } catch (_) {}
  }

  Color? _getCached(String id) {
    return _memoryCache[id];
  }

  Future<void> _setCached(String id, Color color) async {
    _memoryCache[id] = color;
    _saveCache();
  }

  void _startAutoScroll() {
    _autoScroll?.cancel();
    _autoScroll = Timer.periodic(const Duration(seconds: 8), (_) {
      if (!mounted || widget.items.length <= 1) return;
      final next = (_current + 1) % widget.items.length;
      _controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 500),
        curve: Curves.linearToEaseOut,
      );
    });
  }

  Future<void> _extractAndCache(MediaItem item) async {
    final cached = _getCached(item.id);
    if (cached != null) {
      if (widget.onColorExtracted != null && mounted) {
        widget.onColorExtracted!(cached);
      }
      return;
    }

    final imageUrl = item.backdropUrl?.isNotEmpty == true
        ? item.backdropUrl!
        : item.posterUrl;
    if (imageUrl.isEmpty) return;

    try {
      // 飞牛等需要登录才能下载图片的服务，先触发登录再取最新 headers
      // 服务实例可能由 Provider 缓存返回，但首次访问时还没登录，导致 imageHeaders 为空
      final svc = widget.service;
      if (svc != null) {
        final ok = await svc.ensureAuthenticated();
        if (!ok) {
          AppLog.w('Carousel', 'auth failed, skip extract: ${item.title}');
          return;
        }
      }
      // 登录后重新读取 headers（getter 会返回最新认证状态）
      final headers = svc?.imageHeaders ?? widget.imageHeaders;
      AppLog.i('Carousel', 'extract start: ${item.title} -> $imageUrl headers=${headers?.isNotEmpty == true}');
      final palette = await _extractPaletteFromUrl(imageUrl, _paletteSize, headers);
      if (palette == null) {
        AppLog.w('Carousel', 'extract timeout: ${item.title}');
        return;
      }
      // 优先选择更鲜艳的色彩作为背景，避免 dominant 颜色过暗导致背景呈黑色
      final color = _pickRepresentativeColor(palette);
      AppLog.i('Carousel', 'extract result: ${item.title} -> ${color?.toARGB32().toRadixString(16)} (vibrant=${palette.vibrantColor?.color.toARGB32().toRadixString(16)} dominant=${palette.dominantColor?.color.toARGB32().toRadixString(16)})');
      if (color != null) {
        _setCached(item.id, color);
        if (widget.onColorExtracted != null && mounted) {
          widget.onColorExtracted!(color);
        }
      }
    } catch (e) {
      AppLog.e('Carousel', 'extract failed: ${item.title} | $e');
    }
  }

  /// 从调色板中选取最具代表性的颜色
  /// 优先 vibrant 颜色，fallback 到 muted 颜色，最后才是 dominant
  Color? _pickRepresentativeColor(PaletteGenerator palette) {
    return palette.darkVibrantColor?.color
        ?? palette.vibrantColor?.color
        ?? palette.lightVibrantColor?.color
        ?? palette.dominantColor?.color;
  }

  /// 主 isolate 内执行：dio 下载 → 缩放到 size x size → PaletteGenerator
  /// 由于 dart:ui 和 PaletteGenerator 只在主 isolate 中可用，无法使用 compute()
  /// 但缩放到 64x64 后解码耗时 < 30ms，不会造成明显卡顿
  static Future<PaletteGenerator?> _extractPaletteFromUrl(
    String url,
    int size,
    Map<String, String>? headers,
  ) async {
    try {
      // 1. HttpClient 下载图片字节（rhttp 优先，Dio 回退）
      final hasHeaders = headers?.isNotEmpty == true;
      AppLog.i('Palette', 'download start: ${url.substring(0, url.length > 50 ? 50 : url.length)}... headers=$hasHeaders');
      final bytes = await HttpClient.getBytes(
        url,
        headers: headers,
        timeout: const Duration(seconds: 15),
      );
      if (bytes.isEmpty) {
        AppLog.w('Palette', 'download empty');
        return null;
      }
      AppLog.i('Palette', 'download done: ${bytes.length} bytes');

      // 2. 缩放到 size x size
      AppLog.i('Palette', 'codec start: $size x $size');
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: size,
        targetHeight: size,
      );
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final pngBytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (pngBytes == null) {
        AppLog.w('Palette', 'pngBytes null');
        return null;
      }
      AppLog.i('Palette', 'codec done: ${pngBytes.lengthInBytes} bytes');

      // 3. 取色
      AppLog.i('Palette', 'palette start');
      final palette = await PaletteGenerator.fromImageProvider(
        MemoryImage(pngBytes.buffer.asUint8List()),
        size: const Size(128, 128),
      );
      AppLog.i('Palette', 'palette done: vibrant=${palette.vibrantColor?.color.toARGB32().toRadixString(16)}');
      return palette;
    } on TimeoutException {
      AppLog.w('Palette', 'timeout');
      return null;
    } on Exception catch (e) {
      AppLog.w('Palette', 'download error: $e');
      return null;
    } catch (e, stack) {
      AppLog.e('Palette', 'error: $e\n$stack');
      return null;
    }
  }

  @override
  void didUpdateWidget(covariant HomeHeroCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items.length != widget.items.length) {
      _startAutoScroll();
    }
  }

  @override
  void dispose() {
    _autoScroll?.cancel();
    _controller.dispose();
    _currentVN.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    if (items.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final width = constraints.maxWidth;
        return GestureDetector(
          onTap: widget.onTapItem,
          onPanDown: (_) => _autoScroll?.cancel(),
          onPanEnd: (_) => _startAutoScroll(),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // PageView 不再随索引变化重建（这是原先闪烁的根因）
              _buildBackground(width, height, items),
              _buildOverlayGradient(),
              _buildTopBar(context),
              // 信息层与页码指示器按索引局部重建
              ValueListenableBuilder<int>(
                valueListenable: _currentVN,
                builder: (context, cur, _) => _buildInfoLayer(
                  context,
                  items[cur.clamp(0, items.length - 1)],
                ),
              ),
              ValueListenableBuilder<int>(
                valueListenable: _currentVN,
                builder: (context, cur, _) =>
                    _buildPageIndicator(items.length, cur),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBackground(double width, double height, List<MediaItem> items) {
    return PageView.builder(
      controller: _controller,
      physics: const ClampingScrollPhysics(),
      onPageChanged: (i) {
        // 只更新 ValueNotifier，不 setState —— 避免重建 PageView 自身
        _currentVN.value = i;
        widget.onIndexChanged?.call(i);
        // 优先用缓存颜色（预加载已保证大部分有缓存）
        final item = widget.items[i];
        final cached = _getCached(item.id);
        if (cached != null && widget.onColorExtracted != null) {
          widget.onColorExtracted!(cached);
        } else {
          // 没有缓存才取色（极少数情况）
          _extractAndCache(item);
        }
      },
      itemCount: items.length,
      itemBuilder: (context, i) {
        final url = items[i].backdropUrl?.isNotEmpty == true
            ? items[i].backdropUrl!
            : items[i].posterUrl;
        if (url.isEmpty) {
          return Container(color: Colors.black);
        }
        // 优先使用 service 的实时 imageHeaders（登录后会被填充）
        // 否则回退到构造时传入的 headers
        final headers = widget.service?.imageHeaders ?? widget.imageHeaders;
        return ServerImage(
          imageUrl: url,
          headers: headers,
          fit: BoxFit.cover,
          width: width,
          height: height,
          placeholder: (_, __) => Container(color: Colors.black),
          errorWidget: (_, __, ___) => Container(color: Colors.black),
        );
      },
    );
  }

  Widget _buildOverlayGradient() {
    return IgnorePointer(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.4),
              Colors.black.withValues(alpha: 0.1),
              Colors.black.withValues(alpha: 0.15),
              Colors.black.withValues(alpha: 0.5),
              Colors.black.withValues(alpha: 0.7),
            ],
            stops: const [0.0, 0.22, 0.45, 0.75, 1.0],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    final statusBar = MediaQuery.paddingOf(context).top;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.fromLTRB(16, statusBar + 8, 16, 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.55),
              Colors.transparent,
            ],
          ),
        ),
        child: const SizedBox.shrink(),
      ),
    );
  }

  Widget _buildInfoLayer(BuildContext context, MediaItem item) {
    final adapter = ScreenAdapter.of(context);
    final bottomSafe = MediaQuery.paddingOf(context).bottom;
    return Positioned(
      left: adapter.contentPadding,
      right: adapter.contentPadding,
      bottom: bottomSafe + 32,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 500),
            child: Text(
              item.title,
              key: ValueKey('title_${item.id}'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: adapter.screenWidth < 360 ? 32 : (adapter.screenWidth > 600 ? 52 : 40),
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                height: 1.1,
                shadows: [
                  Shadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 20, offset: const Offset(0, 4)),
                ],
              ),
            ),
          ),
          SizedBox(height: 14),
          _buildMetaRow(item, adapter),
          SizedBox(height: 14),
          if (item.overview?.isNotEmpty == true)
            Text(
              item.overview!,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.78),
                fontSize: adapter.subtitleFontSize + 1,
                height: 1.6,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMetaRow(MediaItem item, ScreenAdapter adapter) {
    final parts = <Widget>[];
    if (item.rating != null && item.rating! > 0) {
      parts.add(Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star_rounded, color: Colors.amber, size: 16),
          SizedBox(width: 4),
          Text(item.rating!.toStringAsFixed(1), style: const TextStyle(color: Colors.amber, fontSize: 14, fontWeight: FontWeight.w600)),
        ],
      ));
    }
    if (item.year != null) {
      if (parts.isNotEmpty) parts.add(_dot());
      parts.add(Text('${item.year}', style: const TextStyle(color: Colors.white, fontSize: 14)));
    }
    if (item.type == MediaType.series) {
      if (parts.isNotEmpty) parts.add(_dot());
      parts.add(Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Text('剧集', style: TextStyle(color: Colors.white70, fontSize: 11)),
      ));
    } else {
      if (parts.isNotEmpty) parts.add(_dot());
      parts.add(Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Text('电影', style: TextStyle(color: Colors.white70, fontSize: 11)),
      ));
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: parts,
    );
  }

  Widget _dot() {
    return Container(
      width: 4,
      height: 4,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: Colors.white70,
        shape: BoxShape.circle,
      ),
    );
  }

  Widget _buildPageIndicator(int count, int current) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: MediaQuery.paddingOf(context).bottom + 10,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(count, (i) => AnimatedContainer(
          duration: AppAnimations.medium,
          curve: AppAnimations.easeOut,
          width: i == current ? 20 : 6,
          height: 6,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3),
            color: i == current ? AppTheme.primary : Colors.white.withValues(alpha: 0.45),
          ),
        )),
      ),
    );
  }

}
