/// 根据可用宽度计算媒体卡片列数，适配手机、平板和电视宽屏。
int adaptiveMediaColumnCount(
  double width, {
  double minItemWidth = 132,
  double horizontalPadding = 40,
  double spacing = 12,
  int minColumns = 2,
  int maxColumns = 8,
}) {
  final available = width - horizontalPadding;
  if (available <= 0) return minColumns;
  final columns = ((available + spacing) / (minItemWidth + spacing)).floor();
  return columns.clamp(minColumns, maxColumns);
}
