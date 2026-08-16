import 'package:go_router/go_router.dart';
import '../screens/home/tv_home_screen.dart';
import '../screens/player/tv_player_screen.dart';
import '../screens/servers/tv_servers_screen.dart';
import '../screens/settings/tv_settings_screen.dart';
import '../screens/library/tv_library_screen.dart';
import '../screens/detail/tv_detail_screen.dart';
import '../screens/search/tv_search_screen.dart';
import '../screens/playlist/tv_playlist_screen.dart';
import '../../models/media_models.dart';
import '../../services/media_server_service.dart';
import '../../utils/page_transitions.dart';

/// TV 端路由表。
///
/// 与手机端共用 [PageTransitions] 的转场分档，保持整个 App 转场语言一致。
/// 改造前只有 `/library/:id` 一条做了内联的镜像转场，其余 7 条走平台默认。
final tvRouter = GoRouter(
  initialLocation: '/',
  routes: [
    // ── 根级：纯淡入 ──
    GoRoute(
      path: '/',
      pageBuilder: (ctx, st) =>
          PageTransitions.fade(key: st.pageKey, child: const TvHomeScreen()),
    ),

    // ── 进入内容：淡入 + 轻微放大 ──
    GoRoute(
      path: '/player/:id',
      pageBuilder: (ctx, st) {
        final extra = st.extra as Map<String, dynamic>?;
        return PageTransitions.immersive(
          key: st.pageKey,
          child: TvPlayerScreen(
            media: extra!['media'] as MediaItem,
            streamUrl: extra['url'] as String? ?? '',
            httpHeaders: extra['headers'] as Map<String, String>?,
            episodes: (extra['episodes'] as List<dynamic>?)?.cast<MediaItem>(),
            service: extra['service'] as MediaServerService?,
            resumePositionMs: extra['resumePositionMs'] as int?,
          ),
        );
      },
    ),
    GoRoute(
      path: '/detail/:id',
      pageBuilder: (ctx, st) {
        final extra = st.extra as Map<String, dynamic>?;
        return PageTransitions.immersive(
          key: st.pageKey,
          child: TvDetailScreen(
            item: extra!['item'] as MediaItem,
            service: extra['service'] as MediaServerService?,
            heroTag: extra['heroTag'] as String?,
          ),
        );
      },
    ),

    // ── 层级导航：右入右出镜像 ──
    GoRoute(
      path: '/library/:id',
      pageBuilder: (ctx, st) {
        final extra = st.extra as Map<String, dynamic>?;
        return PageTransitions.slideRight(
          key: st.pageKey,
          child: TvLibraryScreen(library: extra!['library'] as MediaItem),
        );
      },
    ),
    GoRoute(
      path: '/servers',
      pageBuilder: (ctx, st) => PageTransitions.slideRight(
          key: st.pageKey, child: const TvServersScreen()),
    ),
    GoRoute(
      path: '/settings',
      pageBuilder: (ctx, st) => PageTransitions.slideRight(
          key: st.pageKey, child: const TvSettingsScreen()),
    ),
    GoRoute(
      path: '/playlist',
      pageBuilder: (ctx, st) => PageTransitions.slideRight(
          key: st.pageKey, child: const TvPlaylistScreen()),
    ),

    // ── 覆盖式面板：下方淡入上滑 ──
    GoRoute(
      path: '/search',
      pageBuilder: (ctx, st) => PageTransitions.fadeSlideUp(
          key: st.pageKey, child: const TvSearchScreen()),
    ),
  ],
);
