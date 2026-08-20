import 'package:flutter_test/flutter_test.dart';

import 'package:panghu_player/screens/home/home_screen.dart' as home;
import 'package:panghu_player/screens/media_library/media_library_items_screen.dart'
    as shared;
import 'package:panghu_player/screens/servers/media_library_screen.dart' as servers;

void main() {
  test('首页和服务器入口导出同一个媒体库内容页类型', () {
    expect(home.LibraryItemsScreen, same(shared.LibraryItemsScreen));
    expect(servers.LibraryItemsScreen, same(shared.LibraryItemsScreen));
  });
}
