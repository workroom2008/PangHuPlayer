import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import '../../theme/app_theme.dart';
import '../../models/media_models.dart';
import '../../providers/app_providers.dart';


class SubscriptionsPage extends ConsumerStatefulWidget {
  SubscriptionsPage({super.key});

  @override
  ConsumerState<SubscriptionsPage> createState() => _SubscriptionsPageState();
}

class _SubscriptionsPageState extends ConsumerState<SubscriptionsPage> {
  @override
  Widget build(BuildContext context) {
    final subscriptionsAsync = ref.watch(subscriptionsProvider);
    final mpService = ref.watch(moviePilotServiceProvider);

    return Scaffold(
      backgroundColor: context.bgColor,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 120,
            pinned: true,
            backgroundColor: context.bgColor,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                '订阅管理',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: context.textPrimary,
                ),
              ),
              titlePadding: EdgeInsets.only(left: 16, bottom: 16),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  if (mpService == null)
                    _buildConfigWarning()
                  else
                    subscriptionsAsync.when(
                      loading: () => _buildLoadingList(),
                      error: (err, _) => _buildErrorWidget(err.toString()),
                      data: (subs) => subs.isEmpty
                          ? _buildEmptyState()
                          : _buildSubscriptionsList(subs),
                    ),
                  SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfigWarning() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.warning.withValues(alpha:0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.warning.withValues(alpha:0.3)),
      ),
      child: Column(
        children: [
          Icon(Icons.warning_rounded, color: AppTheme.warning, size: 40),
          SizedBox(height: 16),
          Text(
            '请先配置MoviePilot服务器',
            style: TextStyle(
              color: context.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 8),
          Text(
            '前往设置页面配置MoviePilot以使用订阅功能',
            style: TextStyle(color: context.textSecondary, fontSize: 14),
          ),
        ],
      ),
    ).animate().fadeIn();
  }

  Widget _buildLoadingList() {
    return Column(
      children: List.generate(5, (_) => Shimmer.fromColors(
        baseColor: context.cardColor,
        highlightColor: context.surfaceColor,
        child: Container(
          height: 100,
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: context.cardColor,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      )),
    );
  }

  Widget _buildErrorWidget(String error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, color: AppTheme.error, size: 48),
          SizedBox(height: 16),
          Text('加载失败', style: TextStyle(color: context.textPrimary)),
          Text(error, style: TextStyle(color: context.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: context.surfaceColor,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.download_rounded, color: context.textSecondary, size: 48),
          ),
          SizedBox(height: 24),
          Text(
            '暂无订阅',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: context.textPrimary,
            ),
          ),
          SizedBox(height: 8),
          Text(
            '在电影详情页点击"订阅下载"添加订阅',
            style: TextStyle(
              fontSize: 14,
              color: context.textSecondary,
            ),
          ),
        ],
      ),
    ).animate().fadeIn();
  }

  Widget _buildSubscriptionsList(List<Subscription> subs) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: subs.length,
      itemBuilder: (_, i) => Slidable(
        key: ValueKey('sub-${subs[i].id}'),
        endActionPane: ActionPane(
          motion: const ScrollMotion(),
          children: [
            SlidableAction(
              onPressed: (_) async {
                final mpService = ref.read(moviePilotServiceProvider);
                if (mpService != null && subs[i].moviePilotId != null) {
                  await mpService.deleteSubscribe(subs[i].moviePilotId!);
                  ref.invalidate(subscriptionsProvider);
                }
              },
              backgroundColor: AppTheme.error,
              foregroundColor: context.textPrimary,
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(14),
                bottomRight: Radius.circular(14),
              ),
              label: '取消订阅',
              icon: Icons.cancel_outlined,
            ),
          ],
        ),
        child: _SubscriptionListCard(subscription: subs[i]),
      ),
    );
  }
}



class _SubscriptionListCard extends StatelessWidget {
  final Subscription subscription;

  const _SubscriptionListCard({required this.subscription});

  @override
  Widget build(BuildContext context) {
    final posterUrl = subscription.posterUrl;
    return SizedBox(
      height: 100,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: context.surfaceColor,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(14),
                bottomLeft: Radius.circular(14),
              ),
              child: SizedBox(
                width: 70,
                height: 100,
                child: posterUrl != null && posterUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: posterUrl,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                        placeholder: (_, __) => Container(color: context.cardColor, child: Center(child: Icon(Icons.movie_rounded, color: context.textSecondary, size: 24))),
                        errorWidget: (_, __, ___) => Container(color: context.cardColor, child: Center(child: Icon(Icons.movie_rounded, color: context.textSecondary, size: 24))),
                      )
                    : Container(color: context.cardColor, child: Center(child: Icon(Icons.movie_rounded, color: context.textSecondary, size: 24))),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        subscription.title.isNotEmpty ? subscription.title : '未知标题',
                        style: TextStyle(
                          color: context.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _getStatusColor(subscription.status).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(_getStatusIcon(subscription.status), color: _getStatusColor(subscription.status), size: 12),
                              SizedBox(width: 3),
                              Text(
                                _getStatusText(subscription.status),
                                style: TextStyle(color: _getStatusColor(subscription.status), fontSize: 11, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            subscription.type == MediaType.movie ? '电影' : '电视剧',
                            style: TextStyle(color: AppTheme.primary, fontSize: 11, fontWeight: FontWeight.w500),
                          ),
                        ),
                        if (subscription.quality != null && subscription.quality!.isNotEmpty) ...[
                          SizedBox(width: 8),
                          Icon(Icons.hd_rounded, color: context.textSecondary, size: 12),
                          SizedBox(width: 2),
                          Text(
                            subscription.quality!,
                            style: TextStyle(color: context.textSecondary, fontSize: 11),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Icon(Icons.chevron_left_rounded, color: context.textSecondary.withValues(alpha: 0.5), size: 18),
            ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(SubscriptionStatus status) {
    switch (status) {
      case SubscriptionStatus.pending:
        return AppTheme.warning;
      case SubscriptionStatus.downloading:
        return AppTheme.primary;
      case SubscriptionStatus.completed:
        return AppTheme.success;
      case SubscriptionStatus.failed:
        return AppTheme.error;
    }
  }

  IconData _getStatusIcon(SubscriptionStatus status) {
    switch (status) {
      case SubscriptionStatus.pending:
        return Icons.schedule_rounded;
      case SubscriptionStatus.downloading:
        return Icons.downloading_rounded;
      case SubscriptionStatus.completed:
        return Icons.check_circle_rounded;
      case SubscriptionStatus.failed:
        return Icons.error_rounded;
    }
  }

  String _getStatusText(SubscriptionStatus status) {
    switch (status) {
      case SubscriptionStatus.pending:
        return '等待中';
      case SubscriptionStatus.downloading:
        return '下载中';
      case SubscriptionStatus.completed:
        return '已完成';
      case SubscriptionStatus.failed:
        return '失败';
    }
  }
}

