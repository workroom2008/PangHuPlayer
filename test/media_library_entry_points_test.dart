import 'package:flutter_test/flutter_test.dart';

import 'package:lanplayer/screens/home/home_screen.dart' as home;
import 'package:lanplayer/screens/media_library/media_library_items_screen.dart'
    as shared;
import 'package:lanplayer/screens/servers/media_library_screen.dart' as servers;

void main() {
  test('首页和服务器入口导出同一个媒体库内容页类型', () {
    expect(home.LibraryItemsScreen, same(shared.LibraryItemsScreen));
    expect(servers.LibraryItemsScreen, same(shared.LibraryItemsScreen));
  });
}
