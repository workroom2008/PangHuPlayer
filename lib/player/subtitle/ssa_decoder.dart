import 'subtitle_cue.dart';
import 'subtitle_decoder.dart';

/// SSA / ASS 字幕解码器
///
/// 解析 SubStation Alpha 字幕格式，包含：
/// - `[Script Info]` 段：脚本元信息
/// - `[V4+ Styles]` 段：样式定义
/// - `[Events]` 段：对话行（Dialogue）
///
/// 将 SSA 样式与内联覆盖标签映射到 [SubtitleCue] 的
/// styleName / color / bold / italic / fontSize 字段。
class SsaDecoder extends SubtitleDecoder {
  @override
  String get formatName => 'ssa';

  /// 从字符串解析 SSA/ASS 字幕
  @override
  List<SubtitleCue> decode(String content) {
    final cues = <SubtitleCue>[];
    final lines = content.split(RegExp(r'\r?\n'));

    // 按段落分割内容
    final sections = _splitSections(lines);

    // 解析样式定义
    final styles = _parseStyles(_findStylesSection(sections));

    // 解析事件
    final eventsLines = sections.entries
        .firstWhere(
          (e) => e.key.toLowerCase().contains('events'),
          orElse: () => const MapEntry('', <String>[]),
        )
        .value;

    // 解析 Events 段的 Format 行，确定各字段下标
    Map<String, int>? formatMap;
    int cueIndex = 0;
    for (final line in eventsLines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('Format:')) {
        formatMap = _parseFormatLine(trimmed);
        continue;
      }
      if (trimmed.startsWith('Dialogue:')) {
        final fields = _splitDialogueFields(
          trimmed.substring('Dialogue:'.length),
          formatMap,
        );
        if (fields == null) continue;
        final cue = _buildCue(fields, formatMap, styles, cueIndex);
        if (cue != null) {
          cues.add(cue);
          cueIndex++;
        }
      }
    }
    return cues;
  }

  // ------------------------------------------------------------------
  // 段落分割
  // ------------------------------------------------------------------

  /// 按 [Section] 头分割内容
  /// 返回 Map<sectionHeader, lines>，sectionHeader 形如 `[Events]`
  Map<String, List<String>> _splitSections(List<String> lines) {
    final sections = <String, List<String>>{};
    String currentSection = '';
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
        currentSection = trimmed;
        sections.putIfAbsent(currentSection, () => []);
      } else {
        sections.putIfAbsent(currentSection, () => []).add(line);
      }
    }
    return sections;
  }

  /// 查找 [V4+ Styles] / [V4 Styles] 段
  List<String> _findStylesSection(Map<String, List<String>> sections) {
    for (final entry in sections.entries) {
      final key = entry.key.toLowerCase();
      if (key.contains('v4') && key.contains('style')) {
        return entry.value;
      }
    }
    return const [];
  }

  // ------------------------------------------------------------------
  // 样式解析
  // ------------------------------------------------------------------

  /// 解析 [V4+ Styles] 段，返回样式名 → 样式属性 的映射
  Map<String, _SsaStyle> _parseStyles(List<String> lines) {
    final styles = <String, _SsaStyle>{};
    List<String>? format;
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('Format:')) {
        format = trimmed
            .substring('Format:'.length)
            .split(',')
            .map((s) => s.trim().toLowerCase())
            .toList();
      } else if (trimmed.startsWith('Style:')) {
        final values = trimmed.substring('Style:'.length).split(',');
        if (format == null || format.length != values.length) continue;
        final style = _SsaStyle.fromFields(format, values);
        styles[style.name] = style;
      }
    }
    return styles;
  }

  // ------------------------------------------------------------------
  // Dialogue 行解析
  // ------------------------------------------------------------------

  /// 解析 Format 行，返回 字段名 → 下标 映射
  Map<String, int> _parseFormatLine(String formatLine) {
    final fields = formatLine
        .substring('Format:'.length)
        .split(',')
        .map((s) => s.trim().toLowerCase())
        .toList();
    final map = <String, int>{};
    for (int i = 0; i < fields.length; i++) {
      map[fields[i]] = i;
    }
    return map;
  }

  /// 分割 Dialogue 行字段
  /// Text 字段（最后一个）可能包含逗号，因此按 Text 之前的字段数分割，
  /// 其余部分合并为 Text。
  List<String>? _splitDialogueFields(
    String content,
    Map<String, int>? formatMap,
  ) {
    final textIndex = formatMap?['text'] ?? 9; // 默认 Text 在第 10 个字段
    final parts = content.split(',');
    if (textIndex >= parts.length) {
      // 兜底：Text 字段下标超出范围，按标准 10 字段处理
      if (parts.length < 10) return null;
      final before = parts.sublist(0, 9);
      final text = parts.sublist(9).join(',');
      return [...before, text];
    }
    final before = parts.sublist(0, textIndex);
    final text = parts.sublist(textIndex).join(',');
    return [...before, text];
  }

  /// 根据字段构建 [SubtitleCue]
  SubtitleCue? _buildCue(
    List<String> fields,
    Map<String, int>? formatMap,
    Map<String, _SsaStyle> styles,
    int cueIndex,
  ) {
    String? field(String name) {
      final idx = formatMap?[name];
      if (idx == null || idx >= fields.length) return null;
      return fields[idx].trim();
    }

    final startStr = field('start');
    final endStr = field('end');
    if (startStr == null || endStr == null) return null;
    final start = _parseSsaTime(startStr);
    final end = _parseSsaTime(endStr);
    if (start == null || end == null) return null;

    final styleName = field('style') ?? '';
    final rawText = field('text') ?? '';
    if (rawText.isEmpty) return null;

    // 查找样式定义
    final style = styles[styleName];

    // 处理覆盖标签，提取内联样式与纯文本
    final result = _processText(rawText, style);

    return SubtitleCue(
      index: cueIndex,
      start: start,
      end: end,
      text: result.text,
      styleName: styleName.isEmpty ? null : styleName,
      color: result.color,
      bold: result.bold,
      italic: result.italic,
      fontSize: result.fontSize,
    );
  }

  // ------------------------------------------------------------------
  // 文本与覆盖标签处理
  // ------------------------------------------------------------------

  /// 处理 SSA 文本：解析内联覆盖标签，剥离标签并保留换行
  _SsaTextResult _processText(String rawText, _SsaStyle? style) {
    String text = rawText;

    bool? bold = style?.bold;
    bool? italic = style?.italic;
    double? fontSize = style?.fontSize;
    int? color = style?.primaryColor;

    // 处理硬换行 {\N} 与软换行 {\n}
    text = text.replaceAll(RegExp(r'\{\\N\}', caseSensitive: false), '\n');

    // 提取并应用内联样式覆盖标签 {...}
    final overrideRegex = RegExp(r'\{([^}]*)\}');
    for (final match in overrideRegex.allMatches(text)) {
      final tag = match.group(1) ?? '';
      // 加粗：\b1 / \b-1 为开启，\b0 为关闭
      final bMatch = RegExp(r'\\b(-?\d+)').firstMatch(tag);
      if (bMatch != null) {
        bold = (int.tryParse(bMatch.group(1)!) ?? 0) != 0;
      }
      // 斜体：\i1 开启，\i0 关闭
      final iMatch = RegExp(r'\\i(-?\d+)').firstMatch(tag);
      if (iMatch != null) {
        italic = (int.tryParse(iMatch.group(1)!) ?? 0) != 0;
      }
      // 字号：\fsN
      final fsMatch = RegExp(r'\\fs(\d+)').firstMatch(tag);
      if (fsMatch != null) {
        fontSize = double.tryParse(fsMatch.group(1)!);
      }
      // 颜色：\c&HBBGGRR& 或 \1c&HBBGGRR&
      final cMatch = RegExp(r'\\1?c&H([0-9A-Fa-f]+)&').firstMatch(tag);
      if (cMatch != null) {
        final parsed = _parseSsaColor('&H${cMatch.group(1)}');
        if (parsed != null) color = parsed;
      }
    }

    // 移除所有覆盖标签（{\N} 已替换为换行）
    text = text.replaceAll(overrideRegex, '');
    // 处理硬空格 \h
    text = text.replaceAll(RegExp(r'\\h'), ' ');

    return _SsaTextResult(
      text: text,
      bold: bold,
      italic: italic,
      fontSize: fontSize,
      color: color,
    );
  }

  // ------------------------------------------------------------------
  // SSA 时间解析
  // ------------------------------------------------------------------

  /// 解析 SSA 时间字符串：H:MM:SS.cc（cc 为厘秒，1/100 秒）
  static Duration? _parseSsaTime(String time) {
    final parts = time.trim().split(':');
    if (parts.length != 3) return null;
    final hours = int.tryParse(parts[0]) ?? 0;
    final minutes = int.tryParse(parts[1]) ?? 0;
    final secParts = parts[2].split('.');
    final seconds = int.tryParse(secParts[0]) ?? 0;
    final centiRaw = secParts.length > 1 ? secParts[1] : '';
    // 厘秒可能为 1 位或 2 位，统一补齐到 2 位后解析
    final centiStr = centiRaw.padRight(2, '0').substring(0, 2);
    final centiseconds = int.tryParse(centiStr) ?? 0;
    final ms = centiseconds * 10; // 厘秒转毫秒
    return Duration(
      hours: hours,
      minutes: minutes,
      seconds: seconds,
      milliseconds: ms,
    );
  }

  // ------------------------------------------------------------------
  // SSA 颜色解析
  // ------------------------------------------------------------------

  /// 解析 SSA 颜色字符串为 ARGB int
  ///
  /// SSA 格式：`&HAABBGGRR` 或 `&HBBGGRR`
  /// - AA 为 alpha（注意 SSA 中 00=不透明，FF=透明，与 ARGB 相反）
  /// - 转换为标准 ARGB int（FF=不透明，00=透明）
  static int? _parseSsaColor(String ssa) {
    var hex = ssa
        .replaceAll('&H', '')
        .replaceAll('&', '')
        .replaceAll('h', '')
        .toUpperCase()
        .trim();
    if (hex.isEmpty) return null;
    try {
      int alpha = 255; // 默认不透明
      if (hex.length >= 8) {
        // 含 alpha 分量
        alpha = 255 - int.parse(hex.substring(0, 2), radix: 16);
        hex = hex.substring(2);
      }
      if (hex.length < 6) return null;
      final b = int.parse(hex.substring(0, 2), radix: 16);
      final g = int.parse(hex.substring(2, 4), radix: 16);
      final r = int.parse(hex.substring(4, 6), radix: 16);
      return (alpha << 24) | (r << 16) | (g << 8) | b;
    } catch (_) {
      return null;
    }
  }
}

/// SSA 样式定义（解析 [V4+ Styles] 的结果）
class _SsaStyle {
  final String name;
  final double? fontSize;
  final int? primaryColor;
  final bool? bold;
  final bool? italic;

  _SsaStyle({
    this.name = '',
    this.fontSize,
    this.primaryColor,
    this.bold,
    this.italic,
  });

  /// 根据 Format 字段顺序与值列表构建样式
  factory _SsaStyle.fromFields(List<String> format, List<String> values) {
    String name = '';
    double? fontSize;
    int? primaryColor;
    bool? bold;
    bool? italic;
    for (int i = 0; i < format.length && i < values.length; i++) {
      final field = format[i].toLowerCase();
      final value = values[i].trim();
      switch (field) {
        case 'name':
          name = value;
          break;
        case 'fontsize':
          fontSize = double.tryParse(value);
          break;
        case 'primarycolour':
          primaryColor = SsaDecoder._parseSsaColor(value);
          break;
        case 'bold':
          final n = int.tryParse(value);
          if (n != null) bold = n != 0;
          break;
        case 'italic':
          final n = int.tryParse(value);
          if (n != null) italic = n != 0;
          break;
      }
    }
    return _SsaStyle(
      name: name,
      fontSize: fontSize,
      primaryColor: primaryColor,
      bold: bold,
      italic: italic,
    );
  }
}

/// SSA 文本处理结果（剥离覆盖标签后的纯文本与内联样式）
class _SsaTextResult {
  final String text;
  final bool? bold;
  final bool? italic;
  final double? fontSize;
  final int? color;

  _SsaTextResult({
    required this.text,
    this.bold,
    this.italic,
    this.fontSize,
    this.color,
  });
}
