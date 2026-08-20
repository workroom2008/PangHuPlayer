import 'package:flutter_test/flutter_test.dart';
import 'package:panghu_player/services/server_subtitle_service.dart';

void main() {
  test('服务器字幕结果解析语言、标题、提供方和格式', () {
    final result = ServerSubtitleResult.fromJson({
      'Id': 'sub-1',
      'Language': 'chi',
      'Name': '简体中文',
      'ProviderName': 'OpenSubtitles',
      'Format': 'srt',
    });

    expect(result.id, 'sub-1');
    expect(result.language, 'chi');
    expect(result.displayTitle, '简体中文');
    expect(result.provider, 'OpenSubtitles');
    expect(result.format, 'srt');
  });

  test('服务器字幕结果兼容小写字段和空字段', () {
    final result = ServerSubtitleResult.fromJson({
      'id': 'sub-2',
      'language': 'eng',
      'displayTitle': 'English',
      'provider': 'Jellyfin',
    });

    expect(result.id, 'sub-2');
    expect(result.language, 'eng');
    expect(result.displayTitle, 'English');
    expect(result.provider, 'Jellyfin');
    expect(result.format, 'srt');
  });
}
