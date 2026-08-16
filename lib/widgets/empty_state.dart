import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import '../theme/app_theme.dart';

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;
  final String? lottieUrl;

  /// 本地 Lottie 资产路径（优先于 [lottieUrl]，离线可用）
  final String? assetAnimation;

  const EmptyState({
    super.key,
    this.icon = Icons.inbox_rounded,
    required this.title,
    this.subtitle = '',
    this.action,
    this.lottieUrl,
    this.assetAnimation,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (assetAnimation != null)
            SizedBox(width: 120, height: 120, child: Lottie.asset(assetAnimation!, repeat: true))
          else if (lottieUrl != null)
            SizedBox(width: 160, height: 160, child: Lottie.network(lottieUrl!, repeat: true))
          else
            Container(
              width: 88, height: 88,
              decoration: BoxDecoration(
                color: (isDark ? context.textPrimary : Colors.black).withValues(alpha: isDark ? 0.06 : 0.04),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(icon, size: 40, color: (isDark ? context.textPrimary : Colors.black).withValues(alpha: isDark ? 0.25 : 0.2)),
            ),
          SizedBox(height: 20),
          Text(title, style: TextStyle(
            color: isDark ? context.textPrimary70 : Colors.black54,
            fontSize: 17, fontWeight: FontWeight.w600,
          ), textAlign: TextAlign.center),
          if (subtitle.isNotEmpty) ...[SizedBox(height: 6),
            Text(subtitle, style: TextStyle(
              color: isDark ? context.textPrimary38 : Colors.black38,
              fontSize: 14,
            ), textAlign: TextAlign.center),
          ],
          if (action != null) ...[SizedBox(height: 24), action!],
        ]),
      ),
    );
  }
}


