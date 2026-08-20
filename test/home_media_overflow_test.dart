import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:panghu_player/models/media_models.dart';
import 'package:panghu_player/providers/app_providers.dart';
import 'package:panghu_player/providers/media_library_provider.dart';
import 'package:panghu_player/screens/home/home_screen.dart';
import 'package:panghu_player/services/media_server_service.dart';
import 'package:panghu_player/services/storage_service.dart';
import 'package:panghu_player/utils/screen_adapter.dart';

class _FakeHomeService extends EmbyService {
  _FakeHomeService() : super(baseUrl: 'http://test', apiKey: 'test-token');

  @override
  Future<List<MediaItem>> getResumeItems({int limit = 20}) async => [];

  @override
  Future<bool> ensureAuthenticated() async => true;
}

class _FixedServersNotifier extends MediaServersNotifier {
  _FixedServersNotifier(List<MediaServer> servers) {
    state = servers;
  }
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.init();
    ScreenAdapter.cardScale = 1.0;
  });

  testWidgets('首页大屏媒体卡片标题和年份不产生底部溢出', (tester) async {
    tester.view.physicalSize = const Size(1968, 2800);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final service = _FakeHomeService();
    final server = MediaServer(
      id: 'server',
      name: '测试服务器',
      url: 'http://test',
      type: ServerType.emby,
      isDefault: true,
    );
    final library = const MediaItem(
      id: 'library',
      title: '电影媒体库',
      posterUrl: '',
    );
    final items = List<MediaItem>.generate(
      3,
      (index) => MediaItem(
        id: 'item-$index',
        title: '这是一个用于验证首页媒体卡片文字长度布局的超长影片标题 $index',
        posterUrl: '',
        year: 2026,
      ),
    );

    final errors = <FlutterErrorDetails>[];
    final oldOnError = FlutterError.onError;
    FlutterError.onError = errors.add;
    try {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            mediaServersProvider
                .overrideWith((ref) => _FixedServersNotifier([server])),
            currentMediaServerServiceProvider.overrideWithValue(service),
            mediaLibraryProvider.overrideWith((ref) {
              final notifier = MediaLibraryNotifier(ref);
              notifier.state = MediaLibraryState(
                libraries: [library],
                libraryItems: {library.id: items},
                hasLoaded: true,
                dataSource: DataSource.cache,
              );
              return notifier;
            }),
          ],
          child: const MaterialApp(home: LibraryPage()),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.textContaining('这是一个用于验证首页媒体卡片文字长度布局的超长影片标题'),
          findsNWidgets(3));
      final categoryList = find.ancestor(
        of: find.textContaining('这是一个用于验证首页媒体卡片文字长度布局的超长影片标题').first,
        matching: find.byType(ListView),
      );
      expect(categoryList, findsOneWidget);
      expect(tester.getSize(categoryList).height, greaterThan(220));
    } finally {
      FlutterError.onError = oldOnError;
    }

    expect(
      errors.where((error) => error.exception.toString().contains('overflowed')),
      isEmpty,
    );
  });
}
