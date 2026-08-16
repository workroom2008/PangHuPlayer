/// 轨道标题解析工具（字幕轨 / 音轨通用）
///
/// 服务端（Emby/Jellyfin）的 MediaStreams 字段是首字母大写的 key
/// （DisplayTitle / Title / Language / Codec），而引擎（mpv/Exo）返回的是
/// 小写 key（title / language / codec）。历史代码只查小写 key，导致详情页
/// 轨道选择 sheet 永远显示"轨 N"。这里统一兼容两种形态：
/// 优先服务端可读名（DisplayTitle / Title），再回落小写 title，
/// 其次语言码，最后才是"轨 N"。
String trackDisplayTitle(Map<String, dynamic> track, {int? index, String prefix = '轨'}) {
  for (final key in const ['DisplayTitle', 'Title', 'title']) {
    final v = track[key];
    if (v != null && v.toString().trim().isNotEmpty) return v.toString().trim();
  }
  final lang = (track['Language'] ?? track['language'] ?? '').toString().trim();
  if (lang.isNotEmpty) return lang;
  return index != null ? '$prefix ${index + 1}' : prefix;
}
