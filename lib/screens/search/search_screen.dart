import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'dart:async';
import '../../providers/app_providers.dart';
import '../../theme/app_theme.dart';
import '../../utils/animation_config.dart';
import '../../services/storage_service.dart';
import '../../widgets/hero_flight.dart';
import '../detail/detail_screen.dart';

class SearchScreen extends ConsumerStatefulWidget {
  SearchScreen({super.key});
  @override ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounceTimer;

  @override void dispose() { _controller.dispose(); _debounceTimer?.cancel(); super.dispose(); }

  void _onQueryChanged(String q) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      ref.read(searchQueryProvider.notifier).state = q.trim();
    });
  }

  @override
  Widget build(BuildContext context) {
    final searchQuery = ref.watch(searchQueryProvider);
    final aggResult = ref.watch(aggregatedSearchProvider);
    final sources = ref.watch(selectedSearchSourcesProvider);
    return Scaffold(
      backgroundColor: context.bgColor,
      body: SafeArea(child: Column(children: [
        _buildSearchHeader(sources),
        Expanded(child: searchQuery.isEmpty
          ? _buildEmptyState()
          : aggResult.when(
              loading: () => _buildLoadingSections(sources),
              error: (err, _) => _buildErrorState(err.toString()),
              data: (sections) => sections.isEmpty
                ? _buildNoResults()
                : _buildSegmentedResults(sections),
            )),
      ])),
    );
  }

  Widget _buildSearchHeader(Set<String> sources) {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, 2))]),
      child: Row(children: [
        IconButton(icon: Icon(Icons.arrow_back, color: context.textPrimary), onPressed: () => Navigator.pop(context)),
        Expanded(child: Container(
          height: 44,
          decoration: BoxDecoration(color: context.cardColor, borderRadius: BorderRadius.circular(22)),
          child: TextField(
            controller: _controller, autofocus: true,
            style: TextStyle(color: context.textPrimary),
            onChanged: _onQueryChanged,
            decoration: InputDecoration(
              hintText: '搜索电影、电视剧...',
              hintStyle: TextStyle(color: context.textSecondary),
              prefixIcon: Icon(Icons.search, color: context.textSecondary, size: 20),
              suffixIcon: _controller.text.isNotEmpty
                ? IconButton(icon: Icon(Icons.close, color: context.textSecondary, size: 18),
                    onPressed: () { _controller.clear(); ref.read(searchQueryProvider.notifier).state = ''; })
                : null,
              border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
        )),
        const SizedBox(width: 8),
        Container(
          height: 44,
          decoration: BoxDecoration(color: context.cardColor, borderRadius: BorderRadius.circular(22)),
          child: IconButton(
            icon: Icon(Icons.tune_rounded, color: sources.length > 1 ? AppTheme.primary : context.textSecondary, size: 20),
            tooltip: '筛选来源',
            onPressed: () => _showSourceFilter(sources))),
      ]),
    );
  }

  void _showSourceFilter(Set<String> current) {
    final servers = ref.read(mediaServersProvider);
    final selected = Set<String>.from(current);
    showModalBottomSheet(
      context: context, backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(builder: (_, setModalState) {
        void notify() => setModalState(() {});
        return Container(
          margin: const EdgeInsets.all(16), padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: context.surfaceColor, borderRadius: BorderRadius.circular(24)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('搜索来源', style: TextStyle(color: context.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _filterCheckbox('TMDB', 'tmdb', selected, notify),
            for (final s in servers)
              _filterCheckbox(
                s.isDefault ? '${s.name} (默认)' : s.name,
                s.id, selected, notify,
                subtitle: s.type.name,
              ),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              TextButton(onPressed: () {
                selected.clear();
                selected.add('tmdb');
                for (final s in servers) selected.add(s.id);
                notify();
              }, child: const Text('全选')),
              TextButton(onPressed: () {
                selected.clear();
                selected.add('tmdb');
                notify();
              }, child: const Text('重置')),
              FilledButton(
                onPressed: () {
                  ref.read(selectedSearchSourcesProvider.notifier).state = Set<String>.from(selected);
                  StorageService.setString('search_sources', selected.join(','));
                  Navigator.pop(context);
                },
                style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
                child: const Text('确定')),
            ]),
          ]),
        );
      }),
    );
  }

  Widget _filterCheckbox(String name, String id, Set<String> selected, VoidCallback notify, {String? subtitle}) {
    return CheckboxListTile(
      dense: true, activeColor: AppTheme.primary,
      title: Text(name, style: TextStyle(color: context.textPrimary)),
      subtitle: subtitle != null ? Text(subtitle, style: TextStyle(color: context.textSecondary, fontSize: 11)) : null,
      value: selected.contains(id),
      onChanged: (v) {
        if (v == true) {
          selected.add(id);
        } else if (selected.length > 1) {
          selected.remove(id);
        }
        notify();
      },
    );
  }

  Widget _buildSegmentedResults(Map<String, List> sections) {
    final servers = ref.read(mediaServersProvider);
    final entries = sections.entries.toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        for (var i = 0; i < entries.length; i++) ...[
          _buildSection(entries[i].key, entries[i].value, i,
            entries[i].key == 'TMDB' ? null : servers.where((s) => s.name == entries[i].key).firstOrNull),
          if (i < entries.length - 1) const SizedBox(height: 16),
        ],
      ]),
    );
  }

  Widget _buildSection(String label, List items, int index, dynamic server) {
    final isTMDB = label == 'TMDB';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text('$label (${items.length})',
          style: TextStyle(color: context.textPrimary, fontSize: 16, fontWeight: FontWeight.w600),
        ).animate().fadeIn(delay: Duration(milliseconds: 100 * index)).slideY(begin: 0.2),
      ),
      GridView.builder(
        shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, childAspectRatio: 0.65, crossAxisSpacing: 10, mainAxisSpacing: 10),
        itemCount: items.length,
        itemBuilder: (_, i) {
          final card = isTMDB
            ? _TMDBCard(items[i] as dynamic)
            : _MediaCard(items[i] as dynamic, label, server: server);
          return card.animate().fadeIn(delay: Duration(milliseconds: 50 * i + 100 * index)).slideY(begin: 0.1);
        },
      ),
    ]);
  }

  Widget _buildLoadingSections(Set<String> sources) {
    final count = sources.length;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        for (var i = 0; i < count; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i < count - 1 ? 16 : 0),
            child: _buildShimmerSection(),
          ),
      ]),
    );
  }

  Widget _buildShimmerSection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Shimmer.fromColors(
        baseColor: context.cardColor, highlightColor: context.surfaceColor,
        child: Container(height: 16, width: 120, decoration: BoxDecoration(
          color: context.cardColor, borderRadius: BorderRadius.circular(4))),
      ),
      const SizedBox(height: 8),
      GridView.builder(
        shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, childAspectRatio: 0.65, crossAxisSpacing: 10, mainAxisSpacing: 10),
        itemCount: 4,
        itemBuilder: (_, __) => Shimmer.fromColors(
          baseColor: context.cardColor, highlightColor: context.surfaceColor,
          child: Container(decoration: BoxDecoration(
            color: context.cardColor, borderRadius: BorderRadius.circular(12))),
        ),
      ),
    ]);
  }

  Widget _buildEmptyState() => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: context.surfaceColor, shape: BoxShape.circle),
      child: Icon(Icons.search_rounded, color: context.textSecondary, size: 48)),
    const SizedBox(height: 16),
    Text('输入关键词搜索', style: TextStyle(color: context.textSecondary, fontSize: 16)),
  ]));

  Widget _buildErrorState(String error) => Center(child: Text('搜索出错: $error', style: TextStyle(color: Colors.redAccent)));

  Widget _buildNoResults() => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: context.surfaceColor, shape: BoxShape.circle),
      child: Icon(Icons.movie_filter_rounded, color: context.textSecondary, size: 48)),
    const SizedBox(height: 16),
    Text('没有找到结果', style: TextStyle(color: context.textPrimary, fontSize: 18, fontWeight: FontWeight.w600)),
    const SizedBox(height: 4),
    Text('试试其他关键词或更换筛选来源', style: TextStyle(color: context.textSecondary, fontSize: 13)),
  ]));
}

class _TMDBCard extends StatelessWidget {
  final dynamic movie;
  const _TMDBCard(this.movie);

  @override
  Widget build(BuildContext context) {
    final title = movie.title ?? '';
    final posterPath = movie.posterPath ?? movie['poster_path'];
    final voteAverage = movie.voteAverage ?? movie['vote_average'];
    return _buildCard(context,
      title: title,
      posterPath: posterPath != null ? 'https://image.tmdb.org/t/p/w300$posterPath' : null,
      rating: voteAverage?.toString(),
      heroTag: movie.id != null ? 'media_${movie.id}_poster' : null,
      onTap: () => Navigator.push(context, AppAnimations.buildPageRoute(
        page: DetailScreen.fromTMDB(movie), type: PageTransitionType.fadeSlide)));
  }

  static Widget _buildCard(BuildContext context, {required String title, String? posterPath, String? rating, String? heroTag, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(color: context.cardColor, borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Stack(children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              // Hero 共享元素：海报从卡片飞到详情页（与 DetailScreen 的 media_xxx_poster 标签配对）
              child: heroTag != null && posterPath != null
                ? Hero(
                    tag: heroTag,
                    flightShuttleBuilder: heroFlightShuttle,
                    child: CachedNetworkImage(imageUrl: posterPath, fit: BoxFit.cover, width: double.infinity),
                  )
                : posterPath != null
                    ? CachedNetworkImage(imageUrl: posterPath, fit: BoxFit.cover, width: double.infinity)
                    : Container(color: context.cardColor, child: Center(child: Icon(Icons.movie, color: context.textSecondary))),
            ),
            if (rating != null)
              Positioned(top: 8, right: 8, child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.star, color: Colors.amber, size: 10),
                  const SizedBox(width: 2),
                  Text(rating, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
                ]),
              )),
          ])),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(title, style: TextStyle(color: context.textPrimary, fontSize: 12, fontWeight: FontWeight.w500),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ]),
      ),
    );
  }
}

class _MediaCard extends StatelessWidget {
  final dynamic item;
  final String serverName;
  final dynamic server;
  const _MediaCard(this.item, this.serverName, {this.server});

  @override
  Widget build(BuildContext context) {
    final poster = (item.posterUrl?.isNotEmpty ?? false) ? item.posterUrl : null;
    return _TMDBCard._buildCard(context,
      title: item.title ?? '',
      posterPath: poster,
      heroTag: item.id != null ? 'media_${item.id}_poster' : null,
      onTap: () => Navigator.push(context, AppAnimations.buildPageRoute(
        page: DetailScreen(item: item, server: server), type: PageTransitionType.fadeSlide)),
    );
  }
}
