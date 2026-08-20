// 轨道标题解析工具测试：
// 服务端 MediaStreams 是大写 key（DisplayTitle/Title/Language），
// 引擎返回的是小写 key（title/language）。修复前详情页轨道选择 sheet
// 只查小写 key，永远显示"轨 N"。这里验证公共解析器兼容两种形态。
import 'package:flutter_test/flutter_test.dart';
import 'package:panghu_player/utils/track_titles.dart';

void main() {
  group('trackDisplayTitle', () {
    test('优先服务端 DisplayTitle（大写 key）', () {
      final track = {'DisplayTitle': 'Chinese (简体)', 'Language': 'chi', 'Codec': 'srt'};
      expect(trackDisplayTitle(track), 'Chinese (简体)');
    });

    test('其次服务端 Title（大写 key）', () {
      final track = {'Title': 'English - DTS-HD MA 5.1', 'Language': 'eng'};
      expect(trackDisplayTitle(track), 'English - DTS-HD MA 5.1');
    });

    test('引擎小写 title 也能识别', () {
      final track = {'title': '音轨 2', 'language': 'jpn'};
      expect(trackDisplayTitle(track), '音轨 2');
    });

    test('无 DisplayTitle/Title 时用语言码', () {
      expect(trackDisplayTitle({'Language': 'zho'}), 'zho');
      expect(trackDisplayTitle({'language': 'en'}), 'en');
    });

    test('什么都没有时按序号回落 "轨 N"', () {
      expect(trackDisplayTitle({'Codec': 'aac'}, index: 2), '轨 3');
    });

    test('自定义前缀（字幕/音轨文案）', () {
      expect(trackDisplayTitle(const {}, index: 0, prefix: '字幕'), '字幕 1');
      expect(trackDisplayTitle(const {}, index: 4, prefix: '音轨'), '音轨 5');
    });

    test('空串标题视为无，继续回落', () {
      expect(trackDisplayTitle({'DisplayTitle': '', 'Language': 'eng'}), 'eng');
    });
  });
}
