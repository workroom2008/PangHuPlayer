import 'package:flutter_test/flutter_test.dart';

import 'package:lanplayer/utils/adaptive_layout.dart';

void main() {
  test('媒体库列数按宽度自适应并限制范围', () {
    expect(adaptiveMediaColumnCount(390), 2);
    expect(adaptiveMediaColumnCount(800), 5);
    expect(adaptiveMediaColumnCount(1440), 8);
  });
}
