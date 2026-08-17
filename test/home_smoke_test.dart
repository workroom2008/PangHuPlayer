// HomeScreen 冒烟测试：验证能无异常完成构建/布局，且不泄漏定时器。
// 若此处改为「只收集不断言」，测试就失去了证明能力（TDD：测试必须能失败）。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lanplayer/screens/home/home_screen.dart';
import 'package:lanplayer/services/storage_service.dart';

void main() {
  setUp(() async {
    // 测试环境注入 SharedPreferences 内存实现，否则平台通道抛 MissingPluginException，
    // 且多个 provider 在构建时同步读取 StorageService，未初始化会抛 LateInitializationError
    SharedPreferences.setMockInitialValues({});
    await StorageService.init();
  });

  testWidgets('HomeScreen 可无异常构建且不泄漏定时器', (tester) async {
    final errors = <FlutterErrorDetails>[];
    final oldOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      errors.add(details);
      // 吞掉，继续跑，收集所有异常
    };

    try {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: HomeScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
    } finally {
      FlutterError.onError = oldOnError;
    }

    // 卸载整棵树 → 触发所有 dispose → 取消 widget 内定时器
    // （MediaServersNotifier 的周期健康检查由 ProviderScope dispose 一并取消）
    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    for (final e in errors) {
      debugPrint('--- 捕获异常: ${e.exception}');
    }

    expect(
      errors,
      isEmpty,
      reason: 'HomeScreen 构建/布局阶段不应抛出异常，实际捕获 ${errors.length} 个',
    );
  });
}
