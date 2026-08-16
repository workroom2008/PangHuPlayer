// 服务器切换器（ServerSelectorChip）溢出回归测试：
// 修复前：芯片宽度按 TextPainter 测量（不含系统字体缩放、不限制文本伸缩），
// 长服务器名 + 大字体缩放时内部 Row（文字+箭头）超过容器宽度 → RIGHT OVERFLOWED。
// 修复后：宽度按 textScaler 换算并封顶 50%，文字包 Flexible 触发省略号，永不上溢。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lanplayer/models/media_models.dart';
import 'package:lanplayer/providers/app_providers.dart';
import 'package:lanplayer/services/storage_service.dart';
import 'package:lanplayer/widgets/server_selector_chip.dart';

/// 固定服务器列表的 Notifier：绕开存储加载，直接注入长名称服务器
class _FixedServersNotifier extends MediaServersNotifier {
  _FixedServersNotifier(List<MediaServer> servers) {
    state = servers;
  }
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.init();
  });

  /// 在手机尺寸（360 逻辑宽）× 大字体缩放 × 超长服务器名下渲染芯片
  Future<void> pumpChip(WidgetTester tester, {double textScale = 1.3}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    const longName = '这是一个特别特别长的服务器名称用来触发宽度溢出问题';
    final server = MediaServer(
      id: 's1',
      name: longName,
      url: 'http://test',
      type: ServerType.emby,
      isDefault: true,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mediaServersProvider
              .overrideWith((ref) => _FixedServersNotifier([server])),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: ServerSelectorChip(),
            ),
          ),
        ),
      ),
    );
    // 让异步的 _loadServers / 健康检查首轮跑完，布局稳定
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('长服务器名 + 大字体缩放下芯片不溢出，文字省略号截断', (tester) async {
    await pumpChip(tester);

    // 溢出会作为 FlutterError 上报（A RenderFlex overflowed...），有即失败
    final exception = tester.takeException();
    expect(exception, isNull, reason: '芯片不应发生 RenderFlex 溢出');

    // 文字仍可见且以省略号截断（Flexible + ellipsis 生效）
    final text = tester.widget<Text>(find.byType(Text).first);
    expect(text.overflow, TextOverflow.ellipsis);
    expect(text.maxLines, 1);

    await tester.pumpWidget(const SizedBox()); // 卸载 → dispose 取消健康检查定时器
    await tester.pump();
  });

  testWidgets('字体缩放 1.0 时芯片正常显示服务器名', (tester) async {
    await pumpChip(tester, textScale: 1.0);

    expect(tester.takeException(), isNull, reason: '芯片不应发生 RenderFlex 溢出');
    expect(find.textContaining('服务器名称'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
