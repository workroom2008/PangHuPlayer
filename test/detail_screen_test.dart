import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:panghu_player/models/media_models.dart';
import 'package:panghu_player/screens/detail/detail_screen.dart';
import 'package:panghu_player/services/media_server_service.dart';
import 'package:panghu_player/services/storage_service.dart';

class _FakeDetailService extends EmbyService {
  _FakeDetailService()
      : super(baseUrl: 'http://test', apiKey: 'test-token', userId: 'user');

  @override
  Future<MediaItem> getItemDetails(String itemId) async {
    return const MediaItem(
      id: 'media-1',
      title: '测试影片',
      posterUrl: '',
      overview: '影片简介',
      isFavorite: false,
      isWatched: false,
      audioTracks: [
        {'Language': 'eng', 'Title': 'English', 'Codec': 'aac'},
      ],
      subtitleTracks: [
        {'Language': 'chi', 'Title': '简体中文', 'Codec': 'srt'},
      ],
    );
  }

  @override
  Future<List<MediaItem>> search(String query) async => const [];

  @override
  Future<List<MediaItem>> getSimilarItems(String itemId) async => const [];
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.init();
  });

  testWidgets('详情页只保留一组操作和轨道入口', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: DetailScreen(
            item: const MediaItem(
              id: 'media-1',
              title: '测试影片',
              posterUrl: 'https://example.com/poster.jpg',
            ),
            service: _FakeDetailService(),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byKey(const ValueKey('detail-track-controls')), findsOneWidget);
    expect(find.byTooltip('下载'), findsNothing);
    expect(find.byTooltip('收藏'), findsOneWidget);
    expect(find.byTooltip('选择音频'), findsOneWidget);
    expect(find.byTooltip('选择字幕'), findsOneWidget);
    expect(find.byTooltip('标记已观看'), findsOneWidget);
    expect(find.byTooltip('删除'), findsOneWidget);
    expect(find.byKey(const ValueKey('detail-poster')), findsOneWidget);
    expect(find.byKey(const ValueKey('detail-play-button')), findsOneWidget);
    final playSize = tester.getSize(
      find.byKey(const ValueKey('detail-play-button')),
    );
    expect(playSize.height, lessThanOrEqualTo(60));
    expect(find.text('预告片'), findsNothing);
  });

  testWidgets('详情页保留没有头像的演员姓名', (tester) async {
    final service = _FakeDetailServiceWithPeople();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: DetailScreen(
            item: const MediaItem(
              id: 'media-people',
              title: '演员测试',
              posterUrl: '',
            ),
            service: service,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('有效演员'), findsOneWidget);
    expect(find.text('无头像演员'), findsOneWidget);
  });

  testWidgets('详情请求晚于搜索完成时仍加载演员表', (tester) async {
    final service = _FakeDetailServiceWithDelayedDetails();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: DetailScreen(
            item: const MediaItem(
              id: 'media-delayed-people',
              title: '延迟详情测试',
              posterUrl: '',
            ),
            service: service,
          ),
        ),
      ),
    );

    // 让标题搜索先返回，再放行服务端详情请求，复现 Future.any 的竞态。
    await tester.pump(const Duration(milliseconds: 50));
    service.completeDetails();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('延迟演员'), findsOneWidget);
  });
}

class _FakeDetailServiceWithPeople extends _FakeDetailService {
  @override
  Future<MediaItem> getItemDetails(String itemId) async {
    return const MediaItem(
      id: 'media-people',
      title: '演员测试',
      posterUrl: '',
      overview: '影片简介',
      people: [
        {'Name': '有效演员', 'ImageUrl': 'https://example.com/cast.jpg'},
        {'Name': '无头像演员'},
      ],
    );
  }
}

class _FakeDetailServiceWithDelayedDetails extends _FakeDetailService {
  final Completer<MediaItem> _details = Completer<MediaItem>();

  @override
  Future<MediaItem> getItemDetails(String itemId) => _details.future;

  @override
  Future<List<MediaItem>> search(String query) async => const [
        MediaItem(
          id: 'media-delayed-people',
          title: '延迟详情测试',
          posterUrl: '',
        ),
      ];

  void completeDetails() {
    _details.complete(const MediaItem(
      id: 'media-delayed-people',
      title: '延迟详情测试',
      posterUrl: '',
      people: [
        {'Name': '延迟演员', 'ImageUrl': 'https://example.com/cast.jpg'},
      ],
    ));
  }
}
