import 'package:go_router/go_router.dart';
import '../screens/home/home_screen.dart';
import '../screens/detail/detail_screen.dart';
import '../screens/player/player_screen.dart' as player;
import '../screens/settings/settings_screen.dart';
import '../screens/log/log_screen.dart';
import '../screens/servers/servers_screen.dart';
import '../screens/servers/media_library_screen.dart';
import '../screens/servers/add_server_screen.dart';
import '../screens/search/search_screen.dart';
import '../screens/subscriptions/subscriptions_screen.dart';
import '../screens/calendar/calendar_screen.dart';
import '../screens/danmaku/danmaku_screen.dart';
import '../screens/library/library_screen.dart';
import '../screens/home/resources_page.dart';
import '../models/media_models.dart';
import '../services/media_server_service.dart';
import '../utils/page_transitions.dart';

/// 手机端路由表。
///
/// 全部使用 pageBuilder + PageTransitions 统一转场，不再走 Android 平台默认
/// 转场（Zoom），避免与 Navigator.push 处的自定义转场混杂成两种视觉语言。
/// 转场分档见 [PageTransitions] 文档。
final router = GoRouter(
  initialLocation: '/',
  routes: [
    // ── 根级：纯淡入 ──
    GoRoute(
      path: '/',
      pageBuilder: (ctx, st) =>
          PageTransitions.fade(key: st.pageKey, child: HomeScreen()),
    ),
    GoRoute(
      path: '/resources',
      pageBuilder: (ctx, st) =>
          PageTransitions.fade(key: st.pageKey, child: ResourcesPage()),
    ),

    // ── 进入内容：淡入 + 轻微放大 ──
    GoRoute(
      path: '/detail/tmdb_:id',
      pageBuilder: (ctx, st) {
        final extra = st.extra as Map<String, dynamic>?;
        return PageTransitions.immersive(
          key: st.pageKey,
          child: DetailScreen(item: extra?['item'] as dynamic),
        );
      },
    ),
    GoRoute(
      path: '/detail/:id',
      pageBuilder: (ctx, st) {
        final extra = st.extra as Map<String, dynamic>?;
        return PageTransitions.immersive(
          key: st.pageKey,
          child: DetailScreen(
            item: extra?['item'] as dynamic,
            server: extra?['server'] as dynamic,
            resumeEpisodeId: extra?['resumeEpisodeId'] as String?,
          ),
        );
      },
    ),
    GoRoute(
      path: '/player/:id',
      pageBuilder: (ctx, st) {
        final extra = st.extra as Map<String, dynamic>?;
        return PageTransitions.immersive(
          key: st.pageKey,
          child: player.PlayerScreen(
            media: extra!['media'] as MediaItem,
            streamUrl: extra['url'] as String,
            httpHeaders: extra['headers'] as Map<String, String>?,
            episodes: (extra['episodes'] as List<dynamic>?)?.cast<MediaItem>(),
            service: extra['service'] as MediaServerService?,
            server: extra['server'] as MediaServer?,
            resumePositionMs: extra['resumePositionMs'] as int?,
          ),
        );
      },
    ),

    // ── 层级导航：右入右出镜像 ──
    GoRoute(
      path: '/settings',
      pageBuilder: (ctx, st) =>
          PageTransitions.slideRight(key: st.pageKey, child: SettingsScreen()),
    ),
    GoRoute(
      path: '/logs',
      pageBuilder: (ctx, st) =>
          PageTransitions.slideRight(key: st.pageKey, child: LogScreen()),
    ),
    GoRoute(
      path: '/servers',
      pageBuilder: (ctx, st) =>
          PageTransitions.slideRight(key: st.pageKey, child: ServersScreen()),
    ),
    GoRoute(
      path: '/add-server',
      pageBuilder: (ctx, st) {
        final extra = st.extra as Map<String, dynamic>?;
        return PageTransitions.slideRight(
          key: st.pageKey,
          child: AddServerScreen(initialType: extra?['type'] as ServerType?),
        );
      },
    ),
    GoRoute(
      path: '/library/:id',
      pageBuilder: (ctx, st) {
        final extra = st.extra as Map<String, dynamic>?;
        return PageTransitions.slideRight(
          key: st.pageKey,
          child: MediaLibraryScreen(server: extra!['srv'] as dynamic),
        );
      },
    ),
    GoRoute(
      path: '/subscriptions',
      pageBuilder: (ctx, st) =>
          PageTransitions.slideRight(key: st.pageKey, child: SubscriptionsPage()),
    ),
    GoRoute(
      path: '/calendar',
      pageBuilder: (ctx, st) =>
          PageTransitions.slideRight(key: st.pageKey, child: CalendarScreen()),
    ),
    GoRoute(
      path: '/danmaku',
      pageBuilder: (ctx, st) =>
          PageTransitions.slideRight(key: st.pageKey, child: DanmakuScreen()),
    ),
    GoRoute(
      path: '/library_browse',
      pageBuilder: (ctx, st) =>
          PageTransitions.slideRight(key: st.pageKey, child: LibraryScreen()),
    ),

    // ── 覆盖式面板：下方淡入上滑 ──
    GoRoute(
      path: '/search',
      pageBuilder: (ctx, st) =>
          PageTransitions.fadeSlideUp(key: st.pageKey, child: SearchScreen()),
    ),
  ],
);
