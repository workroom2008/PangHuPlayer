import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// 判断演员图片是否已经被服务器明确确认不存在。
///
/// 认证失败、网络异常、缓存异常和 5xx 都可能在稍后恢复，不能据此永久
/// 把演员从详情页过滤掉；只有明确的 404/410 才代表图片资源确实不存在。
bool shouldHideCreditImageAfterError(Object error) {
  if (error is! HttpExceptionWithStatus) return false;
  return error.statusCode == 404 || error.statusCode == 410;
}
