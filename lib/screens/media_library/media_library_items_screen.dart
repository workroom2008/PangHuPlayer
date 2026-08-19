import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/media_models.dart';
import '../../services/media_server_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/animation_config.dart';
import '../../widgets/server_image.dart';
import '../detail/detail_screen.dart';
import '../search/search_screen.dart';
import 'media_library_query.dart';

class LibraryItemsScreen extends ConsumerStatefulWidget {
  final MediaServer server;
  final MediaServerService serverService;
  final MediaItem library;

  const LibraryItemsScreen({
    super.key,
    required this.server,
    required this.serverService,
    required this.library,
  });

  @override
  ConsumerState<LibraryItemsScreen> createState() => _LibraryItemsScreenState();
}

class _LibraryItemsScreenState extends ConsumerState<LibraryItemsScreen> {
  late Future<List<MediaItem>> _itemsFuture;
  List<MediaItem> _allItems = const [];
  MediaLibrarySortField _sortField = MediaLibrarySortField.addedDate;
  bool _descending = true;
  bool _isPortrait = true;
  MediaLibraryFilter _filter = const MediaLibraryFilter();

  @override
  void initState() {
    super.initState();
    _itemsFuture = _fetchItems();
  }

  Future<List<MediaItem>> _fetchItems() {
    return widget.serverService.getAllLibraryItems(
      widget.library.id,
      includeBoxSets: widget.library.collectionType == 'boxsets',
    );
  }

  void _reloadItems() {
    setState(() => _itemsFuture = _fetchItems());
  }

  List<MediaItem> _visibleItems() {
    return MediaLibraryQuery.apply(
      items: _allItems,
      sortField: _sortField,
      descending: _descending,
      filter: _filter,
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibleItems = _visibleItems();

    return Scaffold(
      backgroundColor: context.bgColor,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildTopBar()),
            SliverToBoxAdapter(child: _buildToolbar(visibleItems.length)),
            FutureBuilder<List<MediaItem>>(
              future: _itemsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return _buildLoadingGrid();
                }
                if (snapshot.hasError || snapshot.data == null) {
                  return _buildErrorState();
                }

                _allItems = snapshot.data!;
                final items = _visibleItems();
                if (items.isEmpty) {
                  return _allItems.isEmpty
                      ? _buildEmptyState()
                      : _buildNoFilterResultsState();
                }
                return _buildItemsGrid(items);
              },
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          IconButton(
            tooltip: '返回',
            onPressed: () => Navigator.pop(context),
            icon: Icon(Icons.arrow_back_rounded, color: context.textPrimary),
          ),
          Expanded(
            child: Text(
              widget.library.title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          IconButton(
            tooltip: '搜索',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => SearchScreen()),
            ),
            icon: Icon(Icons.search_rounded, color: context.textPrimary),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(int resultCount) {
    final hasFilter = _filter.category != null ||
        _filter.genre != null ||
        _filter.year != null ||
        _filter.decade != null ||
        _filter.watched != null ||
        _filter.folder != null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 12, 12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: _showSortPanel,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            _sortLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: context.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          _descending
                              ? Icons.arrow_downward_rounded
                              : Icons.arrow_upward_rounded,
                          color: context.textSecondary,
                          size: 17,
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: context.surfaceColor,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '$resultCount',
                            style: TextStyle(
                              color: context.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: '布局',
                onPressed: _showLayoutPanel,
                icon: Icon(
                  _isPortrait
                      ? Icons.grid_view_rounded
                      : Icons.view_quilt_rounded,
                  color: context.textPrimary,
                ),
              ),
              IconButton(
                tooltip: '筛选',
                onPressed: _showFilterPanel,
                icon: Icon(
                  hasFilter
                      ? Icons.filter_alt_rounded
                      : Icons.filter_alt_outlined,
                  color: hasFilter
                      ? AppTheme.primary
                      : context.textPrimary,
                ),
              ),
            ],
          ),
          if (hasFilter) _buildActiveFilterBar(),
        ],
      ),
    );
  }

  Widget _buildActiveFilterBar() {
    final labels = <String>[
      if (_filter.category != null) _filter.category!,
      if (_filter.genre != null) _filter.genre!,
      if (_filter.year != null) '${_filter.year}',
      if (_filter.decade != null) '${_filter.decade}s',
      if (_filter.watched != null) _filter.watched! ? '已观看' : '未观看',
      if (_filter.folder != null) _filter.folder!,
    ];

    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          ...labels.map(
            (label) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                label,
                style: TextStyle(color: AppTheme.primary, fontSize: 12),
              ),
            ),
          ),
          InkWell(
            onTap: () => setState(() => _filter = const MediaLibraryFilter()),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Text(
                '清除',
                style: TextStyle(color: context.textSecondary, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String get _sortLabel {
    switch (_sortField) {
      case MediaLibrarySortField.addedDate:
        return '按添加日期';
      case MediaLibrarySortField.title:
        return '按标题';
      case MediaLibrarySortField.rating:
        return '按公众评分';
      case MediaLibrarySortField.year:
        return '按出品年份';
      case MediaLibrarySortField.releaseDate:
        return '按首映日期';
      case MediaLibrarySortField.watched:
        return '按播放状态';
    }
  }

  Future<void> _showSortPanel() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.surfaceColor,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _panelTitle('排序'),
            ...MediaLibrarySortField.values.map(
              (field) => _choiceTile(
                label: _sortFieldLabel(field),
                selected: field == _sortField,
                trailing: field == _sortField
                    ? Icon(
                        _descending
                            ? Icons.arrow_downward_rounded
                            : Icons.arrow_upward_rounded,
                        color: AppTheme.primary,
                        size: 18,
                      )
                    : null,
                onTap: () {
                  setState(() {
                    if (_sortField == field) {
                      _descending = !_descending;
                    } else {
                      _sortField = field;
                      _descending = true;
                    }
                  });
                  Navigator.pop(context);
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _showLayoutPanel() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.surfaceColor,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _panelTitle('布局'),
            _choiceTile(
              label: '竖幅',
              selected: _isPortrait,
              trailing: const Icon(Icons.crop_portrait_rounded),
              onTap: () {
                setState(() => _isPortrait = true);
                Navigator.pop(context);
              },
            ),
            _choiceTile(
              label: '横幅',
              selected: !_isPortrait,
              trailing: const Icon(Icons.crop_landscape_rounded),
              onTap: () {
                setState(() => _isPortrait = false);
                Navigator.pop(context);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _showFilterPanel() async {
    var draft = _filter;
    final genres = _allItems
        .expand((item) => item.genres)
        .where((genre) => genre.trim().isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    final folders = MediaLibraryQuery.folders(_allItems);
    final currentYear = DateTime.now().year;
    final decades = _decades;

    final result = await showModalBottomSheet<MediaLibraryFilter>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.surfaceColor,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            void update(MediaLibraryFilter value) {
              setModalState(() => draft = value);
            }

            final selectedYear = draft.year == currentYear ? '今年' : '全部';
            final selectedDecade = draft.decade == null
                ? '全部'
                : '${draft.decade}s';

            return SafeArea(
              child: SizedBox(
                height: MediaQuery.sizeOf(context).height * 0.78,
                child: Column(
                  children: [
                    _panelTitle('筛选'),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.only(bottom: 12),
                        children: [
                          _filterHeading('分类'),
                          ...[
                            ('全部', null),
                            ('电影', '电影'),
                            ('电视节目', '电视节目'),
                          ].map(
                            (entry) => _choiceTile(
                              label: entry.$1,
                              selected: (draft.category ?? '全部') == entry.$1,
                              onTap: () => update(
                                draft.copyWith(category: entry.$2),
                              ),
                            ),
                          ),
                          _filterHeading('类型'),
                          ...[
                            ('全部', null),
                            ...genres.map((genre) => (genre, genre)),
                          ].map(
                            (entry) => _choiceTile(
                              label: entry.$1,
                              selected: (draft.genre ?? '全部') == entry.$1,
                              onTap: () => update(
                                draft.copyWith(genre: entry.$2),
                              ),
                            ),
                          ),
                          _filterHeading('发行年份'),
                          _choiceTile(
                            label: '全部',
                            selected: selectedYear == '全部' &&
                                selectedDecade == '全部',
                            onTap: () => update(
                              draft.copyWith(year: null, decade: null),
                            ),
                          ),
                          _choiceTile(
                            label: '今年',
                            selected: selectedYear == '今年',
                            onTap: () => update(
                              draft.copyWith(year: currentYear, decade: null),
                            ),
                          ),
                          ...decades.map(
                            (decade) => _choiceTile(
                              label: '${decade}s',
                              selected: selectedDecade == '${decade}s',
                              onTap: () => update(
                                draft.copyWith(year: null, decade: decade),
                              ),
                            ),
                          ),
                          _filterHeading('观看状态'),
                          ...[
                            ('全部', null),
                            ('已观看', true),
                            ('未观看', false),
                          ].map(
                            (entry) => _choiceTile(
                              label: entry.$1,
                              selected: draft.watched == entry.$2,
                              onTap: () => update(
                                draft.copyWith(watched: entry.$2),
                              ),
                            ),
                          ),
                          _filterHeading('文件夹'),
                          ...folders.map(
                            (folder) => _choiceTile(
                              label: folder,
                              selected: draft.folder == folder,
                              onTap: () => update(
                                draft.copyWith(folder: folder),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => setModalState(
                                () => draft = const MediaLibraryFilter(),
                              ),
                              icon: const Icon(Icons.restart_alt_rounded),
                              label: const Text('重置'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () => Navigator.pop(context, draft),
                              icon: const Icon(Icons.check_rounded),
                              label: const Text('确定'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (result != null && mounted) {
      setState(() => _filter = result);
    }
  }

  List<int> get _decades {
    final values = _allItems
        .map((item) => item.year)
        .whereType<int>()
        .map((year) => year ~/ 10 * 10)
        .toSet()
        .toList();
    values.addAll([2000, 2010, 2020]);
    return values.toSet().toList()..sort((a, b) => b.compareTo(a));
  }

  String _sortFieldLabel(MediaLibrarySortField field) {
    switch (field) {
      case MediaLibrarySortField.addedDate:
        return '加入日期';
      case MediaLibrarySortField.title:
        return '标题';
      case MediaLibrarySortField.rating:
        return '公众评分';
      case MediaLibrarySortField.year:
        return '出品年份';
      case MediaLibrarySortField.releaseDate:
        return '首映日期';
      case MediaLibrarySortField.watched:
        return '播放状态';
    }
  }

  Widget _panelTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title,
          style: TextStyle(
            color: context.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _filterHeading(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Text(
        title,
        style: TextStyle(
          color: context.textSecondary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _choiceTile({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    return ListTile(
      dense: true,
      onTap: onTap,
      title: Text(
        label,
        style: TextStyle(
          color: selected ? AppTheme.primary : context.textPrimary,
          fontSize: 14,
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      trailing: trailing ??
          (selected
              ? Icon(Icons.check_rounded, color: AppTheme.primary, size: 20)
              : null),
    );
  }

  Widget _buildItemsGrid(List<MediaItem> items) {
    final width = MediaQuery.sizeOf(context).width;
    final crossAxisCount = width < 900 ? 3 : 6;
    final spacing = 12.0;
    final itemWidth =
        (width - 40 - spacing * (crossAxisCount - 1)) / crossAxisCount;
    final textScaler = MediaQuery.textScalerOf(context);
    final posterHeight = _isPortrait ? itemWidth * 1.5 : itemWidth * 10 / 16;
    final titleHeight = textScaler.scale(12) * 1.2 * 2;
    final yearHeight = items.any((item) => item.year != null)
        ? textScaler.scale(11) * 1.2
        : 0;
    final itemHeight = posterHeight + 8 + titleHeight + yearHeight + 4;

    return SliverPadding(
      key: const ValueKey('media-grid'),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      sliver: SliverGrid(
        key: ValueKey('media-grid-$crossAxisCount-columns'),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: spacing,
          mainAxisSpacing: spacing,
          mainAxisExtent: itemHeight,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final item = items[index];
            return _MediaLibraryCard(
              item: item,
              isPortrait: _isPortrait,
              imageHeaders: widget.serverService.imageHeaders,
              onTap: () => _openItem(item),
            ).animate().fadeIn(delay: Duration(milliseconds: 20 * index));
          },
          childCount: items.length,
        ),
      ),
    );
  }

  Widget _buildLoadingGrid() {
    final width = MediaQuery.sizeOf(context).width;
    final crossAxisCount = width < 900 ? 3 : 6;
    final spacing = 12.0;
    final itemWidth =
        (width - 40 - spacing * (crossAxisCount - 1)) / crossAxisCount;
    final posterHeight = _isPortrait ? itemWidth * 1.5 : itemWidth * 10 / 16;
    final itemHeight = posterHeight + 56;

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: spacing,
          mainAxisSpacing: spacing,
          mainAxisExtent: itemHeight,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) => Container(
            decoration: BoxDecoration(
              color: context.surfaceColor,
              borderRadius: BorderRadius.circular(10),
            ),
          ).animate().shimmer(duration: const Duration(milliseconds: 900)),
          childCount: crossAxisCount * 2,
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return SliverToBoxAdapter(
      child: _messageState(
        icon: Icons.error_outline_rounded,
        title: '加载失败',
        action: TextButton.icon(
          onPressed: _reloadItems,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('重试'),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return SliverToBoxAdapter(
      child: _messageState(
        icon: Icons.movie_outlined,
        title: '暂无内容',
      ),
    );
  }

  Widget _buildNoFilterResultsState() {
    return SliverToBoxAdapter(
      child: _messageState(
        icon: Icons.filter_alt_off_rounded,
        title: '没有符合条件的内容',
        action: TextButton.icon(
          onPressed: () => setState(() => _filter = const MediaLibraryFilter()),
          icon: const Icon(Icons.clear_rounded),
          label: const Text('清除筛选'),
        ),
      ),
    );
  }

  Widget _messageState({required IconData icon, required String title, Widget? action}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 100, horizontal: 20),
      child: Column(
        children: [
          Icon(icon, color: context.textSecondary, size: 48),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(color: context.textPrimary, fontSize: 16),
          ),
          if (action != null) action,
        ],
      ),
    );
  }

  void _openItem(MediaItem item) {
    if (item.isBoxSet) {
      Navigator.push(
        context,
        AppAnimations.buildPageRoute(
          page: LibraryItemsScreen(
            server: widget.server,
            serverService: widget.serverService,
            library: item,
          ),
          type: PageTransitionType.fadeSlide,
        ),
      );
      return;
    }
    Navigator.push(
      context,
      AppAnimations.buildPageRoute(
        page: DetailScreen(item: item, service: widget.serverService),
        type: PageTransitionType.fadeSlide,
      ),
    );
  }
}

class _MediaLibraryCard extends StatelessWidget {
  final MediaItem item;
  final bool isPortrait;
  final Map<String, String>? imageHeaders;
  final VoidCallback onTap;

  const _MediaLibraryCard({
    required this.item,
    required this.isPortrait,
    required this.imageHeaders,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final columns = width < 900 ? 3 : 6;
    final itemWidth = (width - 40 - 12 * (columns - 1)) / columns;
    final posterHeight = isPortrait ? itemWidth * 1.5 : itemWidth * 10 / 16;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            height: posterHeight,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Hero(
                    tag: 'media_${item.id}_poster',
                    child: ServerImage(
                      imageUrl: item.posterUrl,
                      headers: imageHeaders,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => _posterPlaceholder(context),
                      errorWidget: (_, __, ___) => _posterPlaceholder(context),
                    ),
                  ),
                  if (item.rating != null && item.rating! > 0)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.72),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          item.rating!.toStringAsFixed(1),
                          style: const TextStyle(
                            color: Color(0xFFFFC107),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  if (item.isWatched == true)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: context.textPrimary,
                            width: 1.5,
                          ),
                        ),
                        child: Icon(
                          Icons.check_rounded,
                          color: context.textPrimary,
                          size: 13,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: context.textPrimary,
              fontSize: 12,
              height: 1.2,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (item.year != null)
            Text(
              '${item.year}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.textSecondary,
                fontSize: 11,
                height: 1.2,
              ),
            ),
        ],
      ),
    );
  }

  Widget _posterPlaceholder(BuildContext context) {
    return Container(
      color: context.surfaceColor,
      child: Center(
        child: Icon(
          Icons.movie_outlined,
          color: context.textSecondary,
          size: 24,
        ),
      ),
    );
  }
}
