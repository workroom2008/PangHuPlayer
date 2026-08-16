import 'dart:io';
import 'package:crypto/crypto.dart';

/// 文件哈希计算工具
/// 用于弹弹play弹幕匹配
class FileHashUtil {
  /// 计算文件前16MB的MD5哈希
  /// 弹弹play使用文件前16MB的MD5进行哈希匹配
  static Future<String?> computeFileHash(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;

      final length = await file.length();
      if (length < 16 * 1024 * 1024) return null; // 小于16MB不计算

      final stream = file.openRead(0, 16 * 1024 * 1024);
      final digest = await md5.bind(stream).first;
      return digest.toString();
    } catch (_) {
      return null;
    }
  }
}
