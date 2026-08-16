import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../providers/app_providers.dart';

import '../../theme/app_theme.dart';
import '../../utils/screen_adapter.dart';
import '../../utils/animation_config.dart';
import '../../widgets/animated_card.dart';
import '../detail/detail_screen.dart';
import '../calendar/calendar_screen.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final adapter = ScreenAdapter.of(context);
    
    return Scaffold(
      backgroundColor: context.bgColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(adapter),
            _buildTabBar(),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _FavoritesTab(),
                  _WatchlistTab(),
                  _CalendarTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ScreenAdapter adapter) {
    return Padding(
      padding: EdgeInsets.all(adapter.contentPadding),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha:0.3),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: Icon(Icons.arrow_back, color: context.textPrimary),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          SizedBox(width: 16),
          Text(
            '我的片单',
            style: TextStyle(
              color: context.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: AppTheme.primary,
          borderRadius: BorderRadius.circular(12),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: context.textPrimary,
        unselectedLabelColor: context.textSecondary,
        labelStyle: const TextStyle(fontWeight: FontWeight.w600),
        tabs: const [
          Tab(text: '收藏'),
          Tab(text: '想看'),
          Tab(text: '日历'),
        ],
      ),
    );
  }
}

class _FavoritesTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoriteMoviesProvider);
    final adapter = ScreenAdapter.of(context);

    if (favorites.isEmpty) {
      return _buildEmptyState(context, Icons.favorite_border, '还没有收藏的电影', '收藏喜欢的电影，随时重温');
    }

    return GridView.builder(
      padding: EdgeInsets.all(adapter.contentPadding),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: adapter.crossAxisCount,
        crossAxisSpacing: adapter.cardSpacing,
        mainAxisSpacing: adapter.cardSpacing,
        childAspectRatio: adapter.cardAspectRatio,
      ),
      itemCount: favorites.length,
      itemBuilder: (context, index) {
        final movie = favorites[index];
        return ScaleCard(
          onTap: () {
            Navigator.push(
              context,
              AppAnimations.buildPageRoute(
                page: DetailScreen.fromTMDB(movie.toTMDBMovie()),
                type: PageTransitionType.fadeSlide,
              ),
            );
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(adapter.cardRadius),
            child: Stack(
              children: [
                // Hero 共享元素：海报飞到详情页
                movie.posterPath != null
                    ? Hero(
                        tag: 'media_${movie.tmdbId}_poster',
                        child: CachedNetworkImage(
                          imageUrl: 'https://image.tmdb.org/t/p/w300${movie.posterPath}',
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                          placeholder: (_, __) => Container(color: context.textPrimary.withValues(alpha:0.1)),
                          errorWidget: (_, __, ___) => Container(
                            color: context.textPrimary.withValues(alpha:0.1),
                            child: Icon(Icons.movie, color: context.textPrimary),
                          ),
                        ),
                      )
                    : Container(
                        color: context.textPrimary.withValues(alpha:0.1),
                        child: Icon(Icons.movie, color: context.textPrimary),
                      ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppTheme.error.withValues(alpha:0.9),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.favorite, color: context.textPrimary, size: 14),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black.withValues(alpha:0.8)],
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          movie.title,
                          style: TextStyle(color: context.textPrimary, fontSize: 12, fontWeight: FontWeight.w500),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (movie.voteAverage != null)
                          Row(
                            children: [
                              Icon(Icons.star, color: Colors.amber, size: 10),
                              SizedBox(width: 2),
                              Text(
                                movie.voteAverage!.toStringAsFixed(1),
                                style: TextStyle(color: context.textPrimary, fontSize: 10),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _WatchlistTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final watchlist = ref.watch(watchlistMoviesProvider);
    final adapter = ScreenAdapter.of(context);

    if (watchlist.isEmpty) {
      return _buildEmptyState(context, Icons.bookmark_border, '想看列表是空的', '添加想看的电影，慢慢欣赏');
    }

    return ListView.builder(
      padding: EdgeInsets.all(adapter.contentPadding),
      itemCount: watchlist.length,
      itemBuilder: (context, index) {
        final movie = watchlist[index];
        return ScaleCard(
          onTap: () {
            Navigator.push(
              context,
              AppAnimations.buildPageRoute(
                page: DetailScreen.fromTMDB(movie.toTMDBMovie()),
                type: PageTransitionType.fadeSlide,
              ),
            );
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: context.cardColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
                  // Hero 共享元素：海报飞到详情页
                  child: movie.posterPath != null
                      ? Hero(
                          tag: 'media_${movie.tmdbId}_poster',
                          child: CachedNetworkImage(
                            imageUrl: 'https://image.tmdb.org/t/p/w200${movie.posterPath}',
                            width: 80,
                            height: 120,
                            fit: BoxFit.cover,
                          ),
                        )
                      : Container(
                          width: 80,
                          height: 120,
                          color: context.textPrimary.withValues(alpha:0.1),
                          child: Icon(Icons.movie, color: context.textPrimary),
                        ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          movie.title,
                          style: TextStyle(
                            color: context.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: 4),
                        if (movie.releaseDate != null)
                          Text(
                            movie.releaseDate!.substring(0, 4),
                            style: TextStyle(
                              color: context.textPrimary.withValues(alpha:0.6),
                              fontSize: 12,
                            ),
                          ),
                        SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(Icons.star, color: Colors.amber.withValues(alpha:0.8), size: 14),
                            SizedBox(width: 4),
                            Text(
                              movie.voteAverage?.toStringAsFixed(1) ?? '--',
                              style: TextStyle(
                                color: context.textPrimary,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: IconButton(
                    icon: Icon(Icons.play_circle_fill, color: AppTheme.primary, size: 36),
                    // 与卡片点击一致：进入详情页（详情页内可播放/订阅）
                    onPressed: () {
                    Navigator.push(
                      context,
                      AppAnimations.buildPageRoute(
                        page: DetailScreen.fromTMDB(movie.toTMDBMovie()),
                        type: PageTransitionType.fadeSlide,
                      ),
                    );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

Widget _buildEmptyState(BuildContext context, IconData icon, String title, String subtitle) {
  return Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 64, color: context.textPrimary.withValues(alpha:0.3)),
        SizedBox(height: 16),
        Text(
          title,
          style: TextStyle(
            color: context.textPrimary.withValues(alpha:0.5),
            fontSize: 18,
            fontWeight: FontWeight.w500,
          ),
        ),
        SizedBox(height: 8),
        Text(
          subtitle,
          style: TextStyle(
            color: context.textPrimary.withValues(alpha:0.3),
            fontSize: 14,
          ),
        ),
      ],
    ),
  );
}

class _CalendarTab extends StatelessWidget {
  _CalendarTab();

  @override
  Widget build(BuildContext context) {
    return CalendarScreen(embedded: true);
  }
}

