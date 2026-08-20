import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:panghu_player/models/media_models.dart';
import 'package:panghu_player/screens/home/home_screen.dart';
import 'package:panghu_player/services/media_server_service.dart';

class _SortTestService extends EmbyService {
  _SortTestService() : super(baseUrl: 'http://test', apiKey: 'test-token');

  @override
  Future<List<MediaItem>> getAllLibraryItems(
    String libraryId, {
    bool includeBoxSets = false,
  }) async {
    return const [
      MediaItem(id: 'one', title: 'B', posterUrl: '', year: 2024),
      MediaItem(id: 'two', title: 'A', posterUrl: '', year: 2023),
    ];
  }
}

Widget buildScreen() {
  return MaterialApp(
    home: LibraryItemsScreen(
      server: const MediaServer(
        id: 'server',
        name: '测试服务器',
        url: 'http://test',
        type: ServerType.emby,
      ),
      serverService: _SortTestService(),
      library: const MediaItem(id: 'library', title: '电影', posterUrl: ''),
    ),
  );
}

void main() {
  testWidgets('排序入口打开面板并切换排序字段', (tester) async {
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    expect(find.text('按添加日期'), findsOneWidget);
    await tester.tap(find.text('按添加日期'));
    await tester.pumpAndSettle();

    expect(find.text('排序'), findsOneWidget);
    await tester.tap(find.text('标题'));
    await tester.pumpAndSettle();

    expect(find.text('按标题'), findsOneWidget);
  });
}
