// HomeScreen 白屏复现测试：pump 后捕获 build/layout 阶段异常
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lanplayer/screens/home/home_screen.dart';

void main() {
  testWidgets('HomeScreen smoke build', (tester) async {
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
    } catch (e) {
      errors.add(FlutterErrorDetails(exception: e, library: 'test'));
    } finally {
      FlutterError.onError = oldOnError;
    }

    debugPrint('=== 捕获异常数: ${errors.length} ===');
    for (final e in errors) {
      debugPrint('--- ${e.exception}');
      debugPrint('${e.stack}');
    }
  });
}