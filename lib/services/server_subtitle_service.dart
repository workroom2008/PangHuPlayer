/// Emby/Jellyfin 原生远程字幕的数据模型和异常。
class ServerSubtitleResult {
  final String id;
  final String language;
  final String displayTitle;
  final String provider;
  final String format;

  const ServerSubtitleResult({
    required this.id,
    required this.language,
    required this.displayTitle,
    required this.provider,
    required this.format,
  });

  factory ServerSubtitleResult.fromJson(Map<String, dynamic> json) {
    final language = (json['Language'] ??
            json['language'] ??
            json['ThreeLetterISOLanguageName'] ??
            'und')
        .toString();
    final title = (json['Name'] ??
            json['name'] ??
            json['DisplayTitle'] ??
            json['displayTitle'] ??
            language)
        .toString();
    return ServerSubtitleResult(
      id: (json['Id'] ?? json['id'] ?? '').toString(),
      language: language,
      displayTitle: title,
      provider: (json['ProviderName'] ??
              json['provider'] ??
              json['Provider'] ??
              '服务器')
          .toString(),
      format:
          (json['Format'] ?? json['format'] ?? 'srt').toString().toLowerCase(),
    );
  }
}

class MediaServerSubtitleException implements Exception {
  final String message;

  const MediaServerSubtitleException(this.message);

  @override
  String toString() => message;
}
