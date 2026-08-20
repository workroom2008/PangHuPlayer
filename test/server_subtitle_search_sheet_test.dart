import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panghu_player/services/media_server_service.dart';
import 'package:panghu_player/services/server_subtitle_service.dart';
import 'package:panghu_player/widgets/server_subtitle_search_sheet.dart';

class _FakeSubtitleService extends EmbyService {
  _FakeSubtitleService()
      : super(baseUrl: 'http://test', apiKey: 'test-token', userId: 'user');

  @override
  Future<List<ServerSubtitleResult>> searchSubtitles(
    String itemId, {
    String? language,
  }) async {
    return const [
      ServerSubtitleResult(
        id: 'sub-1',
        language: 'chi',
        displayTitle: '简体中文',
        provider: 'OpenSubtitles',
        format: 'srt',
      ),
    ];
  }
}

void main() {
  testWidgets('服务器字幕搜索面板只显示搜索结果不提供下载动作', (tester) async {
    final service = _FakeSubtitleService();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => ServerSubtitleSearchSheet.show(
                context: context,
                service: service,
                itemId: 'item-1',
                initialQuery: '测试影片',
              ),
              child: const Text('搜索字幕'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('搜索字幕'));
    await tester.pumpAndSettle();
    expect(find.text('简体中文'), findsOneWidget);
    expect(find.text('下载'), findsNothing);
    expect(find.byTooltip('下载'), findsNothing);
  });
}
