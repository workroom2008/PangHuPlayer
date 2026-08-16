import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// 媒体服务器图片加载组件。
///
/// 与 [CachedNetworkImage] 相比新增：
/// - [memCacheWidth]：按 `ScreenAdapter.cardWidth * devicePixelRatio` 传入，
///   避免全尺寸海报解码进内存（`_MediaItemCard` 之前未设此值）。
/// - [fadeInDuration]：图片加载完成时淡入，而非硬切。
class ServerImage extends StatelessWidget {
  final String imageUrl;
  final Map<String, String>? headers;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Widget Function(BuildContext, String, Object)? errorWidget;
  final Widget Function(BuildContext, String)? placeholder;
  final int? memCacheWidth;
  final Duration fadeInDuration;

  const ServerImage({
    super.key,
    required this.imageUrl,
    this.headers,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.errorWidget,
    this.placeholder,
    this.memCacheWidth,
    this.fadeInDuration = const Duration(milliseconds: 200),
  });

  @override
  Widget build(BuildContext context) {
    if (imageUrl.isEmpty) {
      return _buildError(context, '', null);
    }

    final hasHeaders = headers != null && headers!.isNotEmpty;

    return CachedNetworkImage(
      imageUrl: imageUrl,
      httpHeaders: hasHeaders ? headers! : null,
      fit: fit,
      width: width,
      height: height,
      memCacheWidth: memCacheWidth,
      fadeInDuration: fadeInDuration,
      placeholder: placeholder ?? (context, url) => Container(color: Theme.of(context).cardColor),
      errorWidget: errorWidget ?? (context, url, error) => _buildError(context, url, error),
    );
  }

  Widget _buildError(BuildContext context, String url, Object? error) {
    return Container(
      color: Theme.of(context).cardColor,
      child: const Center(child: Icon(Icons.movie, color: Colors.white24)),
    );
  }
}