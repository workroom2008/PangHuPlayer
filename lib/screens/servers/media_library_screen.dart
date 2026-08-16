import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shimmer/shimmer.dart';
import '../../theme/app_theme.dart';
import '../../models/media_models.dart';
import '../../services/media_server_service.dart';
import '../../utils/animation_config.dart';
import '../../widgets/server_image.dart';
import '../detail/detail_screen.dart';

class MediaLibraryScreen extends ConsumerStatefulWidget {
  final MediaServer server;

  MediaLibraryScreen({
    super.key,
    required this.server,
  });

  @override
  ConsumerState<MediaLibraryScreen> createState() => _MediaLibraryScreenState();
}

class _MediaLibraryScreenState extends ConsumerState<MediaLibraryScreen> {
  late MediaServerService? _serverService;
  Future<List<MediaItem>>? _librariesFuture;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initServerService();
  }

  void _initServerService() {
    switch (widget.server.type) {
      case ServerType.emby:
        _serverService = EmbyService(
          baseUrl: widget.server.url,
          apiKey: widget.server.apiKey ?? '',
          username: widget.server.username,
          password: widget.server.password,
        );
        break;
      case ServerType.jellyfin:
        _serverService = JellyfinService(
          baseUrl: widget.server.url,
          apiKey: widget.server.apiKey ?? '',
          username: widget.server.username,
          password: widget.server.password,
        );
        break;
      case ServerType.fnos:
        _serverService = FnOSService(
          baseUrl: widget.server.url,
          username: widget.server.username,
          password: widget.server.password ?? widget.server.apiKey,
        );
        break;
      default:
        _serverService = null;
    }
    _loadLibraries();
  }

  void _loadLibraries() {
    if (_serverService != null) {
      _librariesFuture = _serverService!.getLibraries();
    }
    setState(() => _isLoading = false);
  }

  void _openLibrary(MediaItem library) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => LibraryItemsScreen(
          server: widget.server,
          serverService: _serverService!,
          library: library,
        ),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.1, 0),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              )),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bgColor,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 100,
            pinned: true,
            backgroundColor: context.bgColor,
            leading: Padding(
              padding: const EdgeInsets.all(8),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha:0.5),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: Icon(Icons.arrow_back, color: context.textPrimary),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.server.name,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: context.textPrimary,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    widget.server.url,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.textSecondary,
                    ),
                  ),
                ],
              ),
              titlePadding: const EdgeInsets.only(left: 16, bottom: 16),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  if (_isLoading)
                    _buildLoadingState()
                  else if (_serverService == null)
                    _buildErrorState('不支持的服务器类型')
                  else
                    FutureBuilder<List<MediaItem>>(
                      future: _librariesFuture,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return _buildLoadingState();
                        }
                        if (snapshot.hasError || snapshot.data == null) {
                          return _buildErrorState('加载媒体库失败');
                        }
                        final libraries = snapshot.data!;
                        if (libraries.isEmpty) {
                          return _buildEmptyState();
                        }
                        return _buildLibrariesGrid(libraries);
                      },
                    ),
                  SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.2,
      ),
      itemCount: 6,
      itemBuilder: (context, index) => Shimmer.fromColors(
        baseColor: context.cardColor,
        highlightColor: context.surfaceColor,
        child: Container(
          decoration: BoxDecoration(
            color: context.cardColor,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: context.surfaceColor,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.error_outline, color: AppTheme.error, size: 48),
          ),
          SizedBox(height: 24),
          Text(
            message,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: context.textPrimary,
            ),
          ),
          SizedBox(height: 12),
          ElevatedButton(
            onPressed: _loadLibraries,
            child: Text('重试'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: context.surfaceColor,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.video_library_rounded, color: context.textSecondary, size: 48),
          ),
          SizedBox(height: 24),
          Text(
            '暂无媒体库',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: context.textPrimary,
            ),
          ),
          SizedBox(height: 8),
          Text(
            '在服务器中添加媒体库后将在此显示',
            style: TextStyle(
              fontSize: 14,
              color: context.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLibrariesGrid(List<MediaItem> libraries) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.2,
      ),
      itemCount: libraries.length,
      itemBuilder: (context, index) {
        final library = libraries[index];
        return _LibraryCard(
          library: library,
          imageHeaders: _serverService?.imageHeaders,
          onTap: () => _openLibrary(library),
        ).animate().fadeIn(delay: Duration(milliseconds: 50 * index)).slideY(begin: 0.1);
      },
    );
  }
}

class _LibraryCard extends StatelessWidget {
  final MediaItem library;
  final Map<String, String>? imageHeaders;
  final VoidCallback onTap;

  _LibraryCard({
    required this.library,
    this.imageHeaders,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.surfaceColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: ServerImage(
                  imageUrl: library.posterUrl,
                  headers: imageHeaders,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  placeholder: (_, __) => Container(
                    color: context.cardColor,
                    child: Center(child: Icon(Icons.video_library, color: context.textSecondary)),
                  ),
                  errorWidget: (_, __, ___) => Container(
                    color: context.cardColor,
                    child: Center(child: Icon(Icons.video_library, color: context.textSecondary)),
                  ),
                ),
              ),
            ),
            SizedBox(height: 12),
            Text(
              library.title,
              style: TextStyle(
                color: context.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class LibraryItemsScreen extends ConsumerStatefulWidget {
  final MediaServer server;
  final MediaServerService serverService;
  final MediaItem library;

  LibraryItemsScreen({
    super.key,
    required this.server,
    required this.serverService,
    required this.library,
  });

  @override
  ConsumerState<LibraryItemsScreen> createState() => _LibraryItemsScreenState();
}

class _LibraryItemsScreenState extends ConsumerState<LibraryItemsScreen> {
  Future<List<MediaItem>>? _itemsFuture;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  void _loadItems() {
    // boxsets 库需显式带上 BoxSet 类型（Jellyfin 用 Movie,Series 查合集返回 0）
    _itemsFuture = widget.serverService.getLibraryItems(
      widget.library.id,
      includeBoxSets: widget.library.collectionType == 'boxsets',
    );
    setState(() => _isLoading = false);
  }

  void _openItem(MediaItem item) {
    // 合集（BoxSet）：点击后展示合集内的影视列表，而不是合集详情页
    if (item.isBoxSet) {
      Navigator.push(
        context,
        AppAnimations.buildPageRoute(
          page: LibraryItemsScreen(
            server: widget.server,
            serverService: widget.serverService,
            library: item,
          ),
          type: PageTransitionType.fadeSlide,
        ),
      );
      return;
    }
    Navigator.push(
      context,
      AppAnimations.buildPageRoute(
        page: DetailScreen(item: item, service: widget.serverService),
        type: PageTransitionType.fadeSlide,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bgColor,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 80,
            pinned: true,
            backgroundColor: context.bgColor,
            leading: Padding(
              padding: const EdgeInsets.all(8),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha:0.5),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: Icon(Icons.arrow_back, color: context.textPrimary),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                widget.library.title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: context.textPrimary,
                ),
              ),
              titlePadding: const EdgeInsets.only(left: 16, bottom: 16),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  if (_isLoading)
                    _buildLoadingState()
                  else
                    FutureBuilder<List<MediaItem>>(
                      future: _itemsFuture,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return _buildLoadingState();
                        }
                        if (snapshot.hasError || snapshot.data == null) {
                          return _buildErrorState();
                        }
                        final items = snapshot.data!;
                        if (items.isEmpty) {
                          return _buildEmptyState();
                        }
                        return _buildItemsGrid(items);
                      },
                    ),
                  SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.65,
      ),
      itemCount: 9,
      itemBuilder: (context, index) => Shimmer.fromColors(
        baseColor: context.cardColor,
        highlightColor: context.surfaceColor,
        child: Container(
          decoration: BoxDecoration(
            color: context.cardColor,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: context.surfaceColor,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.error_outline, color: AppTheme.error, size: 48),
          ),
          SizedBox(height: 24),
          Text(
            '加载失败',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: context.textPrimary,
            ),
          ),
          SizedBox(height: 12),
          ElevatedButton(
            onPressed: _loadItems,
            child: Text('重试'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: context.surfaceColor,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.movie_rounded, color: context.textSecondary, size: 48),
          ),
          SizedBox(height: 24),
          Text(
            '暂无内容',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: context.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemsGrid(List<MediaItem> items) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.65,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return _MediaItemCard(
          item: item,
          imageHeaders: widget.serverService.imageHeaders,
          onTap: () => _openItem(item),
        ).animate().fadeIn(delay: Duration(milliseconds: 30 * index));
      },
    );
  }
}

class _MediaItemCard extends StatelessWidget {
  final MediaItem item;
  final Map<String, String>? imageHeaders;
  final VoidCallback onTap;

  _MediaItemCard({
    required this.item,
    this.imageHeaders,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                // Hero 共享元素：海报飞到详情页
                child: Hero(
                  tag: 'media_${item.id}_poster',
                  child: ServerImage(
                    imageUrl: item.posterUrl,
                    headers: imageHeaders,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    placeholder: (_, __) => Container(
                      color: context.cardColor,
                      child: Center(child: Icon(Icons.movie, color: context.textSecondary)),
                    ),
                    errorWidget: (_, __, ___) => Container(
                      color: context.cardColor,
                      child: Center(child: Icon(Icons.movie, color: context.textSecondary)),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(height: 8),
            Text(
              item.title,
              style: TextStyle(
                color: context.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (item.year != null)
              Text(
                item.year.toString(),
                style: TextStyle(
                  color: context.textSecondary,
                  fontSize: 11,
                ),
              ),
          ],
        ),
      ),
    );
  }
}


