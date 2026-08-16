// 排序面板动画回归测试：
// 打开时淡入+缩放（入场动画），关闭时淡出+缩放（退场动画）。
// 通过渲染层 RenderAnimatedOpacity 在动画中途采样不透明度：
// 若中途即为 0 或 1，说明过渡被跳过（瞬间出现/消失），测试失败。
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lanplayer/models/media_models.dart';
import 'package:lanplayer/screens/home/home_screen.dart';
import 'package:lanplayer/services/media_server_service.dart';

class _FakeService extends MediaServerService {
  _FakeService() : super(baseUrl: 'http://test');
  @override
  Future<bool> testConnection() async => true;
  @override
  Future<List<MediaItem>> getLibraries() async => [];
  @override
  Future<List<MediaItem>> getLibraryItems(String libraryId,
          {int page = 0, int limit = 50, bool includeBoxSets = false}) async =>
      _items;
  @override
  Future<List<MediaItem>> getAllLibraryItems(String libraryId,
          {bool includeBoxSets = false}) async =>
      _items;
  @override
  Future<MediaItem> getItemDetails(String itemId) async => _items.first;
  @override
  Future<String> getStreamUrl(String itemId,
          {String? quality, bool burnInSubtitle = false, int? subtitleIndex}) async =>
      '';
  @override
  Future<List<MediaItem>> search(String query) async => [];
  @override
  Future<void> markWatched(String itemId, {double? progress, int? positionMs}) async {}
  @override
  Future<void> reportPlaybackStart(String itemId, {String? mediaSourceId}) async {}
  @override
  Future<void> reportPlaybackProgress(String itemId, int positionMs,
      {bool isPlaying = true, String? mediaSourceId}) async {}
  @override
  Future<void> reportPlaybackStopped(String itemId, {int? positionMs, String? mediaSourceId}) async {}
  @override
  Future<void> markFavorite(String itemId) async {}
  @override
  Future<void> unmarkFavorite(String itemId) async {}
  @override
  Future<List<ChapterMarker>> getChapters(String itemId) async => [];
  @override
  Future<IntroSkip?> getIntroSkipInfo(String itemId) async => null;
  @override
  Future<List<MediaItem>> getSeasons(String seriesId) async => [];
  @override
  Future<List<MediaItem>> getEpisodes(String seriesId,
      {String? seasonId, int? page, int limit = 50}) async => [];
  @override
  Future<List<MediaItem>> getResumeItems({int limit = 20}) async => [];
  @override
  Map<String, String> get streamHeaders => {};

  final List<MediaItem> _items = [
    MediaItem(id: '1', title: '测试影片', posterUrl: ''),
  ];
}

void main() {
  Widget buildScreen() {
    final server = MediaServer(
      id: 's1',
      name: '服务器',
      url: 'http://test',
      type: ServerType.emby,
    );
    final library = MediaItem(id: 'lib1', title: '电影', posterUrl: '');
    return ProviderScope(
      child: MaterialApp(
        home: LibraryItemsScreen(
          server: server,
          serverService: _FakeService(),
          library: library,
        ),
      ),
    );
  }

  /// 面板对应的 AnimatedOpacity（面板文字最近的祖先）
  AnimatedOpacity panelOpacity(WidgetTester tester) =>
      tester.widget<AnimatedOpacity>(find
          .ancestor(of: find.text('排序顺序'), matching: find.byType(AnimatedOpacity))
          .first);

  double currentOpacity(WidgetTester tester) =>
      tester
          .renderObject<RenderAnimatedOpacity>(find.byType(AnimatedOpacity).first)
          .opacity
          .value;

  testWidgets('打开面板有入场动画（淡入过渡而非瞬间出现）', (tester) async {
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.menu_rounded));
    await tester.pump(); // 触发重建
    expect(find.text('排序顺序'), findsOneWidget);

    // 动画中途（200ms 已过 ~100ms）：不透明度应处于 (0,1) 之间
    await tester.pump(const Duration(milliseconds: 100));
    final mid = currentOpacity(tester);
    expect(mid, greaterThan(0.0), reason: '入场动画中途不应已完全隐藏');
    expect(mid, lessThan(1.0), reason: '入场动画中途不应已完全显示');

    await tester.pumpAndSettle();
    expect(panelOpacity(tester).opacity, 1.0);
  });

  testWidgets('关闭面板有退场动画（淡出过渡而非瞬间消失）', (tester) async {
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    // 打开并等入场完成
    await tester.tap(find.byIcon(Icons.menu_rounded));
    await tester.pumpAndSettle();
    expect(panelOpacity(tester).opacity, 1.0);

    // 点面板任意处关闭
    await tester.tap(find.text('排序顺序'));
    await tester.pump(); // 触发重建 → 动画开始
    await tester.pump(const Duration(milliseconds: 100));

    final mid = currentOpacity(tester);
    expect(mid, greaterThan(0.0), reason: '退场动画中途不应已完全隐藏');
    expect(mid, lessThan(1.0), reason: '退场动画中途不应仍完全显示');

    // 动画结束后完全隐藏
    await tester.pumpAndSettle();
    expect(currentOpacity(tester), 0.0);
  });
}
