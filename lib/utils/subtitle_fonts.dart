import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../services/storage_service.dart';
import 'app_log.dart';

/// 自定义字幕字体管理
///
/// 用户选择的 .ttf/.otf 字体文件复制到应用文档目录，注册为全局字体
/// `LanSubtitleFont`，ExoPlayer 外挂字幕的 Flutter 层渲染使用。
///
/// - [ensureLoaded] 幂等：app 启动/播放器构建时调用，已注册则跳过
/// - MPV 内嵌字幕由 libass 原生渲染，自定义字体文件不生效（UI 已注明）
class SubtitleFonts {
  static const fontFamily = 'LanSubtitleFont';
  static const _keyPath = 'subtitle_font_path';
  static bool _loaded = false;
  static String? _loadedPath;

  /// 已保存的自定义字体路径（SharedPreferences）
  static String? get savedPath => StorageService.getString(_keyPath);

  /// 字体文件名（用于 UI 展示）
  static String? get savedName {
    final p = savedPath;
    if (p == null || p.isEmpty) return null;
    return p.split(Platform.pathSeparator).last;
  }

  static Future<void> savePath(String path) => StorageService.setString(_keyPath, path);

  static Future<void> clear() async {
    await StorageService.setString(_keyPath, '');
    _loaded = false;
    _loadedPath = null;
  }

  /// 幂等注册：字体已加载且路径一致则跳过
  static Future<bool> ensureLoaded() async {
    final path = savedPath;
    if (path == null || path.isEmpty) return false;
    if (_loaded && _loadedPath == path) return true;
    try {
      final file = File(path);
      if (!await file.exists()) return false;
      final bytes = await file.readAsBytes();
      final loader = FontLoader(fontFamily)
        ..addFont(Future.value(ByteData.sublistView(bytes)));
      await loader.load();
      _loaded = true;
      _loadedPath = path;
      AppLog.i('SubtitleFonts', '自定义字体已注册: $path');
      return true;
    } catch (e) {
      AppLog.w('SubtitleFonts', '字体注册失败: $e');
      return false;
    }
  }

  /// 把选择的字体文件复制到应用文档目录，返回新路径
  static Future<String?> copyToAppDir(String sourcePath) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final fontsDir = Directory('${dir.path}/subtitle_fonts');
      if (!await fontsDir.exists()) await fontsDir.create(recursive: true);
      final name = sourcePath.split(Platform.pathSeparator).last;
      final dest = '${fontsDir.path}/$name';
      await File(sourcePath).copy(dest);
      return dest;
    } catch (e) {
      AppLog.w('SubtitleFonts', '复制字体失败: $e');
      return null;
    }
  }
}
