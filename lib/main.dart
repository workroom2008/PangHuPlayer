import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'theme/app_theme.dart';
import 'providers/app_providers.dart';
import 'utils/app_log.dart';
import 'router/app_router.dart';
import 'tv/router/tv_router.dart' as tv_router;
import 'services/storage_service.dart';
import 'database/database_service.dart';
import 'services/http_client.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await StorageService.init();
  await DbService.init();
  await HttpClient.init();

  // 自动判断是否为 TV 环境（Leanback 或无触屏）
  final isTv = await _isTvDevice();
  if (isTv) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent, statusBarIconBrightness: Brightness.light,
    ));
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    runApp(const ProviderScope(child: _TvEntry()));
    return;
  }

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent, statusBarIconBrightness: Brightness.light,
  ));
  runApp(const ProviderScope(child: LanPlayerApp()));
}

/// 判断当前设备是否为 TV
/// 检测策略：UI Mode 为 Leanback 时判定为 TV
Future<bool> _isTvDevice() async {
  // 构建开关：--dart-define=FORCE_TV=true 强制 TV 模式
  // 用于 release 包在模拟器/非 Leanback 设备上测试 TV 界面
  if (const bool.fromEnvironment('FORCE_TV')) return true;
  // 注：不再强制 debug 构建走 TV——用户安装 debug 包验证手机 UI 时
  // 必须走真实设备检测。需要强制 TV 时用 FORCE_TV=true。
  try {
    final uiMode = await _getUiMode();
    return uiMode == 'leanback' || uiMode == 'television';
  } catch (_) {
    return false;
  }
}

Future<String?> _getUiMode() async {
  // 通过 platform channel 获取 UI Mode（Android UiModeManager）
  const platform = MethodChannel('lanplayer/device');
  try {
    final result = await platform.invokeMethod<String>('getUiMode');
    return result?.toLowerCase();
  } catch (_) {
    return null;
  }
}

class LanPlayerApp extends ConsumerWidget {
  const LanPlayerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = ref.watch(darkModeProvider);
    AppLog.setDebugEnabled(ref.watch(debugModeProvider));
    return MaterialApp.router(
      title: 'LAN Player', debugShowCheckedModeBanner: false,
      themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
      darkTheme: AppTheme.darkTheme, theme: AppTheme.lightTheme,
      routerConfig: router,
    );
  }
}

/// TV 端入口应用
class _TvEntry extends ConsumerWidget {
  const _TvEntry();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppLog.setDebugEnabled(ref.watch(debugModeProvider));
    return MaterialApp.router(
      title: 'LAN Player TV',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: AppTheme.darkTheme.copyWith(
        scaffoldBackgroundColor: Colors.black,
        colorScheme: AppTheme.darkTheme.colorScheme.copyWith(surface: Colors.black),
      ),
      theme: AppTheme.darkTheme,
      routerConfig: tv_router.tvRouter,
    );
  }
}
