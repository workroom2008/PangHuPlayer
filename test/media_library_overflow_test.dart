import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:panghu_player/models/media_models.dart';
import 'package:panghu_player/screens/servers/media_library_screen.dart';
import 'package:panghu_player/services/media_server_service.dart';

class _FakeMediaService extends EmbyService {
  _FakeMediaService() : super(baseUrl: 'http://test', apiKey: 'test-token');

  @override
  Future<List<MediaItem>> getLibraryItems(
    String libraryId, {
    int page = 0,
    int limit = 50,
    bool includeBoxSets = false,
  }) async {
    return List<MediaItem>.generate(
      6,
      (index) => MediaItem(
        id: '$index',
        title: '这是一个用于验证媒体库卡片布局的超长影片标题 $index',
        posterUrl: '',
        year: 2026,
      ),
    );
  }
}

void main() {
  testWidgets('媒体库卡片在小屏和大字体下不产生布局溢出', (tester) async {
    tester.view.physicalSize = const Size(960, 1704);
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final errors = <FlutterErrorDetails>[];
    final oldOnError = FlutterError.onError;
    FlutterError.onError = errors.add;
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: LibraryItemsScreen(
            server: MediaServer(
              id: 'server',
              name: '测试服务器',
              url: 'http://test',
              type: ServerType.emby,
            ),
            serverService: _FakeMediaService(),
            library: const MediaItem(id: 'library', title: '电影', posterUrl: ''),
          ),
        ),
      );
      await tester.pumpAndSettle();
    } finally {
      FlutterError.onError = oldOnError;
    }

    expect(
      errors
          .where((error) => error.exception.toString().contains('overflowed')),
      isEmpty,
    );
  });
}
