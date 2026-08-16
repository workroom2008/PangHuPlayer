import 'package:intl/intl.dart';

class TimeHelper {
  static String formatDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;

    if (hours >= 1) {
      return '${hours.toInt()}h ${minutes.toInt()}m';
    } else if (minutes >= 1) {
      return '${minutes.toInt()}m ${secs}s';
    } else {
      return '${secs}s';
    }
  }

  static String formatDurationMs(int milliseconds) {
    return formatDuration(milliseconds ~/ 1000);
  }
}

class DateHelper {
  static String formatDate(DateTime date) {
    return DateFormat('yyyy-MM-dd').format(date);
  }

  static String formatDateTime(DateTime date) {
    return DateFormat('yyyy-MM-dd HH:mm').format(date);
  }

  static String formatRelativeTime(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays > 365) {
      return '${diff.inDays / 365}年前';
    } else if (diff.inDays > 30) {
      return '${diff.inDays / 30}个月前';
    } else if (diff.inDays > 0) {
      return '${diff.inDays}天前';
    } else if (diff.inHours > 0) {
      return '${diff.inHours}小时前';
    } else if (diff.inMinutes > 0) {
      return '${diff.inMinutes}分钟前';
    } else {
      return '刚刚';
    }
  }
}

class ColorHelper {
  static String colorToHex(int color) {
    return '#${(color & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  static int hexToColor(String hex) {
    return int.parse(hex.replaceFirst('#', ''), radix: 16) + 0xFF000000;
  }
}

