import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import '../theme/app_theme.dart';
import '../providers/app_providers.dart';
import '../utils/app_log.dart';
import '../services/storage_service.dart';
import '../database/database_service.dart';
import '../services/http_client.dart';
import 'router/tv_router.dart';

/// TV 端强制深色主题（符合 TV 沉浸式硬约束）
final _tvDarkTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  scaffoldBackgroundColor: const Color(0xFF0A0A0A),
  colorScheme: ColorScheme.dark(
    primary: const Color(0xFF6366F1),
    secondary: const Color(0xFF6366F1),
    surface: const Color(0xFF0A0A0A),
  ),
  fontFamily: null,
);

/// TV 应用根 Widget
///
/// 设计原则：
/// 1. 立即 runApp 显示主界面框架，不等任何初始化
/// 2. 后台并行初始化各项服务（MediaKit/Storage/DB/Http）
/// 3. 初始化完成后自动触发媒体库加载
/// 4. 加载过程中显示转圈，加载完成后显示内容
class LanPlayerTvApp extends ConsumerStatefulWidget {
  const LanPlayerTvApp({super.key});

  @override
  ConsumerState<LanPlayerTvApp> createState() => _LanPlayerTvAppState();
}

class _LanPlayerTvAppState extends ConsumerState<LanPlayerTvApp> {
  /// 是否完成基础初始化（MediaKit/Storage/DB/Http）
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    // 关键：postFrameCallback 中启动后台初始化，不阻塞首帧渲染
    WidgetsBinding.instance.addPostFrameCallback((_) => _initInBackground());
  }

  /// 后台并行初始化各项服务，不阻塞 UI
  Future<void> _initInBackground() async {
    AppLog.i('TvApp', 'start parallel init');

    // 并行执行所有初始化任务（互不依赖）
    final results = await Future.wait([
      _initMediaKit(),
      _initStorage(),
      _initDb(),
      _initHttp(),
    ]);

    // 配置系统 UI
    try {
      SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ));
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } catch (_) {}

    if (!mounted) return;

    // 标记初始化完成，触发 UI 重建
    setState(() => _initialized = true);
    AppLog.i('TvApp', 'init complete, results: $results');
  }

  Future<bool> _initMediaKit() async {
    try {
      MediaKit.ensureInitialized();
      return true;
    } catch (e) {
      AppLog.e('TvApp', 'MediaKit init failed', e);
      return false;
    }
  }

  Future<bool> _initStorage() async {
    try {
      await StorageService.init();
      return true;
    } catch (e) {
      AppLog.e('TvApp', 'StorageService init failed', e);
      return false;
    }
  }

  Future<bool> _initDb() async {
    try {
      await DbService.init();
      return true;
    } catch (e) {
      AppLog.e('TvApp', 'DbService init failed', e);
      return false;
    }
  }

  Future<bool> _initHttp() async {
    try {
      await HttpClient.init();
      return true;
    } catch (e) {
      AppLog.e('TvApp', 'HttpClient init failed', e);
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    AppLog.setDebugEnabled(true);

    return Shortcuts(
      shortcuts: <LogicalKeySet, Intent>{
        LogicalKeySet(LogicalKeyboardKey.select): const ActivateIntent(),
        LogicalKeySet(LogicalKeyboardKey.enter): const ActivateIntent(),
      },
      child: MaterialApp.router(
        title: 'LAN Player TV',
        debugShowCheckedModeBanner: false,
        theme: _tvDarkTheme,
        darkTheme: _tvDarkTheme,
        themeMode: ThemeMode.dark,
        routerConfig: tvRouter,
      ),
    );
  }
}

/// TV 启动入口：立即 runApp 主 App，后台异步初始化
///
/// 优化点：
/// 1. 不再使用 Splash 包装，直接启动主 App
/// 2. 首帧渲染 < 500ms（无阻塞）
/// 3. 基础服务在 runApp 后并行初始化（MediaKit/Storage/DB/Http）
/// 4. Provider 通过 StorageService.ready 等待 prefs 就绪后再读取
/// 5. 媒体库数据由 mediaLibraryProvider 自动加载（监听服务变化）
void mainTv() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const ProviderScope(
      child: LanPlayerTvApp(),
    ),
  );
}

/// flutter build -t 入口必须叫 main
void main() => mainTv();
