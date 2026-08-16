import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../utils/app_log.dart';
import '../../theme/app_theme.dart';

class LogScreen extends StatefulWidget {
  const LogScreen({super.key});
  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  String _levelFilter = 'ALL';
  String _search = '';
  bool _autoRefresh = true;
  Timer? _timer;
  final _levels = ['ALL', 'INFO', 'WARN', 'ERROR', 'DEBUG'];

  List<Map<String, dynamic>> get _filtered {
    var all = AppLog.logs;
    if (_levelFilter != 'ALL') all = all.where((l) => l['level'] == _levelFilter).toList();
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      all = all.where((l) => l['msg'].toString().toLowerCase().contains(q) || l['tag'].toString().toLowerCase().contains(q)).toList();
    }
    return all;
  }

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) { if (_autoRefresh && mounted) setState(() {}); });
  }

  @override
  void dispose() { _timer?.cancel(); super.dispose(); }

  Color _bg(String l) => switch (l) { 'ERROR' => const Color(0x33EF4444), 'WARN' => const Color(0x33F59E0B), 'DEBUG' => const Color(0x336366F1), _ => const Color(0x3310B981) };
  Color _fg(String l) => switch (l) { 'ERROR' => const Color(0xFFEF4444), 'WARN' => const Color(0xFFF59E0B), 'DEBUG' => const Color(0xFF818CF8), _ => const Color(0xFF34D399) };

  void _copyLogs(List<Map<String, dynamic>> logs) {
    final text = logs.map((l) => '[${l['time']}] ${l['level']}/${l['tag']}: ${l['msg']}').join('\n');
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)));
  }

  @override
  Widget build(BuildContext context) {
    final logs = _filtered;
    return Scaffold(backgroundColor: context.bgColor, body: SafeArea(child: Column(children: [
      // Header
      Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 4), child: Row(children: [
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: context.textPrimary.withValues(alpha:0.10)),
            child: Icon(Icons.arrow_back_rounded, color: context.textPrimary, size: 20))),
        SizedBox(width: 12),
        Text('应用日志', style: TextStyle(color: context.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
        const Spacer(),
        _iconBtn(Icons.refresh, _autoRefresh ? AppTheme.primary : context.textPrimary38, '自动刷新', () => setState(() => _autoRefresh = !_autoRefresh)),
        SizedBox(width: 6),
        _iconBtn(Icons.copy, context.textSecondary, '复制', () => _copyLogs(logs)),
        SizedBox(width: 6),
        _iconBtn(Icons.delete_outline, const Color(0xFFEF4444), '清除', () { AppLog.clear(); setState(() {}); }),
      ])),
      // Search
      Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: SizedBox(height: 34, child: TextField(
          style: TextStyle(color: context.textPrimary, fontSize: 13),
          decoration: InputDecoration(hintText: '搜索...', hintStyle: TextStyle(color: context.textPrimary24),
            prefixIcon: Icon(Icons.search, color: context.textPrimary24, size: 18), border: InputBorder.none,
            filled: true, fillColor: context.surfaceColor, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8), isDense: true),
          onChanged: (v) => setState(() => _search = v)))),
      // Level chips
      SizedBox(height: 32,
        child: ListView.builder(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 8), itemCount: _levels.length,
          itemBuilder: (_, i) {
            final lv = _levels[i]; final sel = _levelFilter == lv; final c = _fg(lv);
            return Padding(padding: const EdgeInsets.symmetric(horizontal: 4),
              child: GestureDetector(onTap: () => setState(() => _levelFilter = lv),
                child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5), decoration: BoxDecoration(color: sel ? c.withValues(alpha:0.15) : context.textPrimary.withValues(alpha:0.06), borderRadius: BorderRadius.circular(16), border: sel ? Border.all(color: c.withValues(alpha:0.4)) : null),
                  child: Text(lv, style: TextStyle(color: sel ? c : context.textPrimary38, fontSize: 11, fontWeight: FontWeight.w600))))); })),
      // Counter
      Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
        child: Text(logs.length == AppLog.logs.length ? '共 ${logs.length} 条' : '${logs.length} / ${AppLog.logs.length} 条', style: TextStyle(color: context.textPrimary24, fontSize: 11))),
      // List
      Expanded(child: logs.isEmpty
        ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.terminal, size: 48, color: Color(0x1AFFFFFF)), SizedBox(height: 12),
            Text('暂无日志', style: TextStyle(color: context.textPrimary24, fontSize: 14)),
            Text('运行应用后将自动记录', style: TextStyle(color: Color(0x1AFFFFFF), fontSize: 12))]))
        : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: logs.length, itemBuilder: (_, i) {
            final l = logs[i]; final lv = l['level'] ?? 'INFO';
            return Padding(padding: const EdgeInsets.only(bottom: 3),
              child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: _bg(lv), borderRadius: BorderRadius.circular(8)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1), decoration: BoxDecoration(color: _fg(lv).withValues(alpha:0.25), borderRadius: BorderRadius.circular(4)),
                      child: Text(lv, style: TextStyle(color: _fg(lv), fontSize: 9, fontWeight: FontWeight.w700, fontFamily: 'monospace'))),
                    SizedBox(width: 8),
                    Text(l['time'] ?? '', style: const TextStyle(color: Color(0x33FFFFFF), fontSize: 10, fontFamily: 'monospace')),
                    const Spacer(),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1), decoration: BoxDecoration(color: context.textPrimary.withValues(alpha:0.06), borderRadius: BorderRadius.circular(4)),
                      child: Text(l['tag'] ?? '', style: const TextStyle(color: Color(0x3DFFFFFF), fontSize: 9, fontFamily: 'monospace'))),
                  ]),
                  SizedBox(height: 4),
                  Text(l['msg'] ?? '', style: TextStyle(color: lv == 'ERROR' ? const Color(0xFFFCA5A5) : context.textPrimary70, fontSize: 12, fontFamily: 'monospace')),
                ])));
          })),
    ])));
  }

  Widget _iconBtn(IconData icon, Color color, String tooltip, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: color.withValues(alpha:0.15), borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, size: 16, color: color)));
  }
}


