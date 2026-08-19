import 'package:flutter_test/flutter_test.dart';
import 'package:lanplayer/models/media_models.dart';
import 'package:lanplayer/screens/media_library/media_library_query.dart';

MediaItem item({
  required String id,
  required String title,
  MediaType type = MediaType.movie,
  int? year,
  double? rating,
  bool? watched,
  List<String> genres = const [],
  String? filePath,
}) => MediaItem(
      id: id,
      title: title,
      posterUrl: '',
      type: type,
      year: year,
      rating: rating,
      isWatched: watched,
      genres: genres,
      filePath: filePath,
    );

void main() {
  final items = [
    item(
      id: 'a',
      title: 'Beta',
      year: 2024,
      rating: 7.2,
      genres: ['剧情'],
      filePath: r'D:\Movies\Beta\beta.mkv',
    ),
    item(
      id: 'b',
      title: 'Alpha',
      type: MediaType.series,
      year: 2012,
      rating: 9.1,
      watched: true,
      genres: ['动作'],
      filePath: r'D:\Shows\Alpha\alpha.mkv',
    ),
    item(
      id: 'c',
      title: 'Gamma',
      year: 2020,
      rating: 7.2,
      watched: false,
      genres: ['剧情'],
    ),
  ];

  test('标题升序和降序都保持可预测顺序', () {
    final ascending = MediaLibraryQuery.apply(
      items: items,
      sortField: MediaLibrarySortField.title,
      descending: false,
      filter: const MediaLibraryFilter(),
    );
    final descending = MediaLibraryQuery.apply(
      items: items,
      sortField: MediaLibrarySortField.title,
      descending: true,
      filter: const MediaLibraryFilter(),
    );

    expect(ascending.map((i) => i.id), ['b', 'a', 'c']);
    expect(descending.map((i) => i.id), ['c', 'a', 'b']);
  });

  test('评分排序相同评分保留原始顺序', () {
    final result = MediaLibraryQuery.apply(
      items: items,
      sortField: MediaLibrarySortField.rating,
      descending: true,
      filter: const MediaLibraryFilter(),
    );

    expect(result.map((i) => i.id), ['b', 'a', 'c']);
  });

  test('分类、类型、年份、观看状态和文件夹按 AND 关系筛选', () {
    final result = MediaLibraryQuery.apply(
      items: items,
      sortField: MediaLibrarySortField.addedDate,
      descending: true,
      filter: const MediaLibraryFilter(
        category: '电影',
        genre: '剧情',
        decade: 2020,
        watched: false,
        folder: '未分类',
      ),
    );

    expect(result.map((i) => i.id), ['c']);
  });

  test('文件夹列表提取父目录并包含未分类媒体', () {
    expect(MediaLibraryQuery.folders(items), ['Beta', 'Alpha', '未分类']);
  });
}
