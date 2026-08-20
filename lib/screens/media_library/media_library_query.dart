import '../../models/media_models.dart';

enum MediaLibrarySortField {
  addedDate,
  title,
  rating,
  year,
  releaseDate,
  watched,
}

enum MediaLibraryLayout {
  grid,
  folder,
  list,
}

class MediaLibraryFilter {
  final String? category;
  final String? genre;
  final int? year;
  final int? decade;
  final bool? watched;
  final String? folder;

  const MediaLibraryFilter({
    this.category,
    this.genre,
    this.year,
    this.decade,
    this.watched,
    this.folder,
  });

  MediaLibraryFilter copyWith({
    Object? category = _unset,
    Object? genre = _unset,
    Object? year = _unset,
    Object? decade = _unset,
    Object? watched = _unset,
    Object? folder = _unset,
  }) {
    return MediaLibraryFilter(
      category:
          identical(category, _unset) ? this.category : category as String?,
      genre: identical(genre, _unset) ? this.genre : genre as String?,
      year: identical(year, _unset) ? this.year : year as int?,
      decade: identical(decade, _unset) ? this.decade : decade as int?,
      watched: identical(watched, _unset) ? this.watched : watched as bool?,
      folder: identical(folder, _unset) ? this.folder : folder as String?,
    );
  }
}

const _unset = Object();

class MediaLibraryQuery {
  static List<MediaItem> apply({
    required List<MediaItem> items,
    required MediaLibrarySortField sortField,
    required bool descending,
    required MediaLibraryFilter filter,
  }) {
    final filtered = items.where((item) {
      final categoryMatches = filter.category == null ||
          filter.category == '全部' ||
          (filter.category == '电影' && item.type == MediaType.movie) ||
          (filter.category == '电视节目' && item.type != MediaType.movie);
      final genreMatches =
          filter.genre == null || item.genres.contains(filter.genre);
      final yearMatches = filter.year == null || item.year == filter.year;
      final decadeMatches = filter.decade == null ||
          (item.year != null &&
              item.year! >= filter.decade! &&
              item.year! < filter.decade! + 10);
      final watchedMatches = filter.watched == null ||
          (filter.watched! ? item.isWatched == true : item.isWatched != true);
      final folderMatches =
          filter.folder == null || _folderFor(item) == filter.folder;
      return categoryMatches &&
          genreMatches &&
          yearMatches &&
          decadeMatches &&
          watchedMatches &&
          folderMatches;
    }).toList();

    final indexed = filtered.indexed.toList();
    int compare((int, MediaItem) a, (int, MediaItem) b) {
      int result;
      switch (sortField) {
        case MediaLibrarySortField.title:
          result = a.$2.title.compareTo(b.$2.title);
        case MediaLibrarySortField.rating:
          result = (a.$2.rating ?? 0).compareTo(b.$2.rating ?? 0);
        case MediaLibrarySortField.year:
        case MediaLibrarySortField.releaseDate:
          result = (a.$2.year ?? 0).compareTo(b.$2.year ?? 0);
        case MediaLibrarySortField.watched:
          result = (a.$2.isWatched == true ? 1 : 0)
              .compareTo(b.$2.isWatched == true ? 1 : 0);
        case MediaLibrarySortField.addedDate:
          result = 0;
      }
      if (result == 0) return a.$1.compareTo(b.$1);
      return descending ? -result : result;
    }

    indexed.sort(compare);
    return indexed.map((entry) => entry.$2).toList();
  }

  static List<String> folders(List<MediaItem> items) {
    final result = <String>{};
    for (final item in items) {
      result.add(_folderFor(item));
    }
    return result.toList();
  }

  /// 按媒体文件父目录分组，保持媒体首次出现时的文件夹顺序。
  static Map<String, List<MediaItem>> folderGroups(List<MediaItem> items) {
    final groups = <String, List<MediaItem>>{};
    for (final item in items) {
      groups.putIfAbsent(_folderFor(item), () => <MediaItem>[]).add(item);
    }
    return groups;
  }

  static String _folderFor(MediaItem item) {
    final path = item.filePath?.trim() ?? '';
    if (path.isEmpty) return '未分类';

    final parts =
        path.split(RegExp(r'[\\/]')).where((part) => part.isNotEmpty).toList();
    if (parts.length < 2) return '未分类';
    return parts[parts.length - 2];
  }
}
