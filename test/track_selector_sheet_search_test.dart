import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panghu_player/widgets/track_selector_sheet.dart';

void main() {
  testWidgets('字幕轨道面板提供服务器字幕搜索入口', (tester) async {
    var searched = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => TrackSelectorSheet.show(
                context: context,
                title: '字幕',
                tracks: const [],
                currentIndex: -1,
                onSelect: (_) {},
                onSearch: () async => searched = true,
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('搜索字幕'));
    await tester.pumpAndSettle();

    expect(searched, isTrue);
  });
}
