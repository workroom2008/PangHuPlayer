import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:panghu_player/screens/detail/credit_image_failure.dart';

void main() {
  test('只有服务器明确返回 404 或 410 才隐藏演员图片', () {
    expect(
      shouldHideCreditImageAfterError(
        const HttpExceptionWithStatus(404, 'Invalid statusCode: 404'),
      ),
      isTrue,
    );
    expect(
      shouldHideCreditImageAfterError(
        const HttpExceptionWithStatus(410, 'Invalid statusCode: 410'),
      ),
      isTrue,
    );
  });

  test('认证、网络和服务端暂时错误不会隐藏演员图片', () {
    expect(
      shouldHideCreditImageAfterError(
        const HttpExceptionWithStatus(401, 'Invalid statusCode: 401'),
      ),
      isFalse,
    );
    expect(
      shouldHideCreditImageAfterError(
        const HttpExceptionWithStatus(403, 'Invalid statusCode: 403'),
      ),
      isFalse,
    );
    expect(
      shouldHideCreditImageAfterError(
        const HttpExceptionWithStatus(500, 'Invalid statusCode: 500'),
      ),
      isFalse,
    );
    expect(shouldHideCreditImageAfterError(StateError('network timeout')),
        isFalse);
  });
}
