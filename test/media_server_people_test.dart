import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:panghu_player/services/media_server_service.dart';

class _PeopleAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      jsonEncode({
        'Id': 'item-1',
        'Name': '演员图片测试',
        'Type': 'Movie',
        'People': [
          {
            'Id': 'person/1',
            'Name': '有效演员',
            'Type': 'Actor',
            'PrimaryImageTag': 'tag/?value',
          },
          {
            'Id': 'person-2',
            'Name': '空标签演员',
            'Type': 'Actor',
            'PrimaryImageTag': '  ',
          },
          {
            'Id': 'person-3',
            'Name': '无标签演员',
            'Type': 'Actor',
          },
        ],
      }),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('演员图片只为非空 PrimaryImageTag 生成经过编码的 URL', () async {
    final service = EmbyService(
      baseUrl: 'http://media-server',
      apiKey: 'access/token',
      userId: 'user-id',
      dioClient: Dio()..httpClientAdapter = _PeopleAdapter(),
    );

    final item = await service.getItemDetails('item-1');
    final people = item.people!;
    final valid = people.firstWhere((person) => person['Name'] == '有效演员');
    final emptyTag = people.firstWhere((person) => person['Name'] == '空标签演员');
    final missingTag = people.firstWhere((person) => person['Name'] == '无标签演员');

    final imageUrl = valid['ImageUrl'] as String;
    final imageUri = Uri.parse(imageUrl);
    expect(imageUrl, contains('/Items/person%2F1/Images/Primary'));
    expect(imageUri.queryParameters['api_key'], 'access/token');
    expect(imageUri.queryParameters['Tag'], 'tag/?value');
    expect(emptyTag['ImageUrl'], isNull);
    expect(missingTag['ImageUrl'], isNull);
  });

  test('Emby 和 Jellyfin 图片请求头都携带访问令牌', () {
    final emby = EmbyService(baseUrl: 'http://emby', apiKey: 'emby-token');
    final jellyfin = JellyfinService(
      baseUrl: 'http://jellyfin',
      apiKey: 'jellyfin-token',
    );

    expect(emby.imageHeaders, {'X-MediaBrowser-Token': 'emby-token'});
    expect(jellyfin.imageHeaders, {
      'X-Emby-Token': 'jellyfin-token',
      'X-MediaBrowser-Token': 'jellyfin-token',
    });
  });
}
