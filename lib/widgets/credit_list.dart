import 'dart:typed_data';
import 'package:flutter/material.dart';

import '../utils/credit_image_url.dart';
import '../services/http_client.dart';
import '../utils/app_log.dart';
import 'server_image.dart';

/// 演员横向列表：头像加载失败时仍保留姓名和角色信息。
class CreditList extends StatelessWidget {
  final List<Map<String, dynamic>> credits;
  final Map<String, String>? imageHeaders;
  final String? imageBaseUrl;
  final String? imageApiKey;
  final bool compact;

  const CreditList({
    super.key,
    required this.credits,
    this.imageHeaders,
    this.imageBaseUrl,
    this.imageApiKey,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final visible = credits.where((person) {
      final name = (person['name'] ?? person['Name'] ?? '').toString().trim();
      return name.isNotEmpty;
    }).toList();
    if (visible.isEmpty) return const SizedBox.shrink();

    final imageWidth = compact ? 64.0 : 72.0;
    final imageHeight = compact ? 82.0 : 96.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 10),
          child: Text(
            '演员',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        SizedBox(
          height: imageHeight + 48,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: visible.length,
            itemBuilder: (context, index) {
              final person = visible[index];
              final name =
                  (person['name'] ?? person['Name'] ?? '').toString().trim();
              final role = (person['character'] ?? person['Role'] ?? '')
                  .toString()
                  .trim();
              final imageUrls = resolveCreditImageUrls(
                person,
                baseUrl: imageBaseUrl,
                apiKey: imageApiKey,
              );
              return SizedBox(
                width: compact ? 86 : 94,
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: imageWidth,
                          height: imageHeight,
                          child: imageUrls.isEmpty
                              ? _placeholder()
                              : _CreditImage(
                                  urls: imageUrls,
                                  headers: imageHeaders,
                                  width: imageWidth,
                                  placeholder: _placeholder,
                                ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (role.isNotEmpty)
                        Text(
                          role,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 10),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _placeholder() {
    return Container(
      color: Colors.white.withValues(alpha: 0.08),
      child: const Icon(Icons.person_outline, color: Colors.white38, size: 28),
    );
  }
}

/// 按候选 URL 顺序加载演员头像，解决服务器拒绝带 Tag 参数的问题。
class _CreditImage extends StatefulWidget {
  final List<String> urls;
  final Map<String, String>? headers;
  final double width;
  final Widget Function() placeholder;

  const _CreditImage({
    required this.urls,
    required this.headers,
    required this.width,
    required this.placeholder,
  });

  @override
  State<_CreditImage> createState() => _CreditImageState();
}

class _CreditImageState extends State<_CreditImage> {
  late Future<Uint8List?> _imageFuture;

  @override
  void initState() {
    super.initState();
    _imageFuture = widget.urls.length > 1
        ? _loadImageBytes()
        : Future<Uint8List?>.value(null);
  }

  @override
  void didUpdateWidget(covariant _CreditImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.urls != widget.urls || oldWidget.headers != widget.headers) {
      _imageFuture = widget.urls.length > 1
          ? _loadImageBytes()
          : Future<Uint8List?>.value(null);
    }
  }

  Future<Uint8List?> _loadImageBytes() async {
    for (final url in widget.urls) {
      try {
        // 直接下载图片字节并携带认证头，避免缓存组件复用旧请求头。
        final bytes = await HttpClient.getBytes(
          url,
          headers: widget.headers,
          timeout: const Duration(seconds: 12),
        );
        if (bytes.isNotEmpty) return bytes;
      } catch (error) {
        AppLog.w('CreditImage', '演员头像加载失败: $url $error');
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    // 单一 TMDB 地址继续走缓存图片组件，避免无备用地址时额外发起下载。
    if (widget.urls.length == 1) {
      return ServerImage(
        imageUrl: widget.urls.first,
        headers: widget.headers,
        fit: BoxFit.cover,
        memCacheWidth:
            (widget.width * MediaQuery.of(context).devicePixelRatio).round(),
        placeholder: (_, __) => widget.placeholder(),
        errorWidget: (_, __, ___) => widget.placeholder(),
      );
    }
    return FutureBuilder<Uint8List?>(
      future: _imageFuture,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null || bytes.isEmpty) return widget.placeholder();
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          filterQuality: FilterQuality.high,
          cacheWidth:
              (widget.width * MediaQuery.of(context).devicePixelRatio).round(),
        );
      },
    );
  }
}
