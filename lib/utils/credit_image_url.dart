/// 解析演员头像地址，兼容 Emby/Jellyfin 和 TMDB 返回的字段格式。
String? resolveCreditImageUrl(Map<String, dynamic> person) {
  // 服务端详情通常返回 ImageUrl，优先使用可直接访问的地址。
  for (final key in const ['ImageUrl', 'imageUrl', 'image_url']) {
    final value = person[key]?.toString().trim() ?? '';
    if (value.isNotEmpty) return value;
  }

  // TMDB credits 返回 profile_path，需要补全图片域名和尺寸路径。
  final profilePath = person['profile_path']?.toString().trim() ?? '';
  if (profilePath.isNotEmpty) {
    final normalized =
        profilePath.startsWith('/') ? profilePath : '/$profilePath';
    return 'https://image.tmdb.org/t/p/w185$normalized';
  }
  return null;
}

/// 返回演员头像候选地址，主地址失败时由界面按顺序尝试备用地址。
List<String> resolveCreditImageUrls(
  Map<String, dynamic> person, {
  String? baseUrl,
  String? apiKey,
}) {
  final urls = <String>[];
  final primary = resolveCreditImageUrl(person);
  if (primary != null) urls.add(primary);

  final personId = (person['Id'] ?? person['id'])?.toString().trim() ?? '';
  final server = baseUrl?.trim().replaceFirst(RegExp(r'/+$'), '') ?? '';
  if (server.isNotEmpty && personId.isNotEmpty) {
    final encodedId = Uri.encodeComponent(personId);
    final query = (apiKey ?? '').trim().isEmpty
        ? ''
        : '?api_key=${Uri.encodeQueryComponent(apiKey!.trim())}';
    final fallback = '$server/Items/$encodedId/Images/Primary$query';
    if (!urls.contains(fallback)) urls.add(fallback);
  }
  return urls;
}
