import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lanplayer/models/media_models.dart';
import 'package:lanplayer/screens/media_library/media_library_items_screen.dart';
import 'package:lanplayer/services/media_server_service.dart';

class _FakeMediaService extends EmbyService {
  _FakeMediaService() : super(baseUrl: 'http://test', apiKey: 'test-token');

  @override
  Future<List<MediaItem>> getAllLibraryItems(
    String libraryId, {
    bool includeBoxSets = false,
  }) async {
    return [
      MediaItem(
        id: 'one',
        title: '第一文件夹影片',
        posterUrl: '',
        year: 2024,
        rating: 8.0,
        genres: ['剧情'],
        filePath: '/电影库/第一文件夹/one.mkv',
      ),
      MediaItem(
        id: 'two',
        title: '第二文件夹影片',
        posterUrl: '',
        year: 2023,
        rating: 7.0,
        genres: ['动作'],
        filePath: '/电影库/第二文件夹/two.mkv',
      ),
      MediaItem(
        id: 'three',
        title: '第三文件夹影片',
        posterUrl: '',
        year: 2022,
        rating: 6.0,
        genres: ['动画'],
        filePath: '/电影库/第三文件夹/three.mkv',
      ),
      MediaItem(
        id: 'four',
        title: '长标题媒体四',
        posterUrl: '',
        year: 2021,
        rating: 8.1,
        type: MediaType.series,
        filePath: '/电视剧/第四文件夹/four.mkv',
      ),
      MediaItem(
        id: 'five',
        title: '长标题媒体五',
        posterUrl: '',
        year: 2020,
        rating: 8.2,
        filePath: '/电影库/第五文件夹/five.mkv',
      ),
      MediaItem(
        id: 'six',
        title: '长标题媒体六',
        posterUrl: '',
        year: 2019,
        rating: 8.3,
        filePath: '/电影库/第六文件夹/six.mkv',
      ),
      const MediaItem(
        id: 'seven',
        title: '没有路径的媒体七',
        posterUrl: '',
        year: 2018,
        rating: 8.4,
      ),
    ];
  }
}

Widget buildScreen() => MaterialApp(
      home: LibraryItemsScreen(
        server: const MediaServer(
          id: 'server',
          name: '测试服务器',
          url: 'http://test',
          type: ServerType.emby,
        ),
        serverService: _FakeMediaService(),
        library: const MediaItem(id: 'library', title: '电影', posterUrl: ''),
      ),
    );

void main() {
  testWidgets('小屏使用三列且内容页提供排序布局筛选入口', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('media-grid')), findsOneWidget);
    expect(find.byKey(const ValueKey('media-grid-3-columns')), findsOneWidget);
    expect(find.byTooltip('布局'), findsOneWidget);
    expect(find.byTooltip('筛选'), findsOneWidget);
    expect(find.text('类型'), findsNothing);
  });

  testWidgets('大屏使用六列', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('media-grid-6-columns')), findsOneWidget);
  });

  testWidgets('筛选面板选择文件夹后只显示该文件夹媒体', (tester) async {
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('筛选'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('文件夹'),
      240,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('文件夹'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('第二文件夹'),
      160,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('第二文件夹'));
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(find.text('第二文件夹影片'), findsOneWidget);
    expect(find.text('第一文件夹影片'), findsNothing);
  });

  testWidgets('大字体长标题不产生溢出', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final errors = <FlutterErrorDetails>[];
    final oldOnError = FlutterError.onError;
    FlutterError.onError = errors.add;
    try {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
    } finally {
      FlutterError.onError = oldOnError;
    }

    expect(
      errors.where((error) => error.exception.toString().contains('overflowed')),
      isEmpty,
    );
  });
}
