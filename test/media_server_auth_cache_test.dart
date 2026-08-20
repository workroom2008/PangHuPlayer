import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lanplayer/services/media_server_service.dart';

class _CountingAuthAdapter implements HttpClientAdapter {
  int loginRequests = 0;
  Map<String, dynamic>? loginData;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path.contains('AuthenticateByName')) {
      loginRequests++;
      loginData = Map<String, dynamic>.from(options.data as Map);
      return ResponseBody.fromString(
        jsonEncode({
          'AccessToken': 'cached-access-token',
          'User': {'Id': 'cached-user-id'},
        }),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
    }
    return ResponseBody.fromString('{}', 200);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('认证成功后重建服务实例不会再次发送用户名密码登录', () async {
    final adapter = _CountingAuthAdapter();

    final first = EmbyService(
      baseUrl: 'http://auth-cache-test',
      username: 'alice',
      password: 'password',
      dioClient: Dio()..httpClientAdapter = adapter,
    );
    expect(await first.ensureAuthenticated(), isTrue);

    final second = EmbyService(
      baseUrl: 'http://auth-cache-test',
      username: 'alice',
      password: 'password',
      dioClient: Dio()..httpClientAdapter = adapter,
    );
    expect(await second.ensureAuthenticated(), isTrue);

    expect(adapter.loginRequests, 1);
    expect(adapter.loginData, {'Username': 'alice', 'Pw': 'password'});
    expect(second.apiKey, 'cached-access-token');
  });
}
