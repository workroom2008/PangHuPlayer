import 'package:flutter_test/flutter_test.dart';

import 'package:lanplayer/utils/credit_image_url.dart';

void main() {
  test('优先使用服务端 ImageUrl', () {
    expect(
      resolveCreditImageUrl({
        'ImageUrl': 'http://server/person.jpg',
        'profile_path': '/tmdb.jpg',
      }),
      'http://server/person.jpg',
    );
  });

  test('兼容小写字段并拼接 TMDB profile_path', () {
    expect(
      resolveCreditImageUrl({'imageUrl': '', 'profile_path': '/actor.jpg'}),
      'https://image.tmdb.org/t/p/w185/actor.jpg',
    );
  });

  test('空字段返回 null', () {
    expect(resolveCreditImageUrl({'Name': '演员'}), isNull);
  });

  test('服务端缺少 ImageUrl 时生成带认证参数的备用人物头像地址', () {
    expect(
      resolveCreditImageUrls(
        {'Id': 'person/1', 'Name': '演员'},
        baseUrl: 'http://server',
        apiKey: 'token',
      ),
      contains(
        'http://server/Items/person%2F1/Images/Primary?api_key=token',
      ),
    );
  });
}
