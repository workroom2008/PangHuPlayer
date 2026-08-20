import 'package:flutter/material.dart';

import '../services/media_server_service.dart';
import '../services/server_subtitle_service.dart';
import '../theme/app_theme.dart';

class ServerSubtitleSearchSheet extends StatefulWidget {
  final MediaServerService service;
  final String itemId;
  final String initialQuery;

  const ServerSubtitleSearchSheet({
    super.key,
    required this.service,
    required this.itemId,
    required this.initialQuery,
  });

  static Future<void> show({
    required BuildContext context,
    required MediaServerService service,
    required String itemId,
    required String initialQuery,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFF1C1C22),
      builder: (_) => ServerSubtitleSearchSheet(
        service: service,
        itemId: itemId,
        initialQuery: initialQuery,
      ),
    );
  }

  @override
  State<ServerSubtitleSearchSheet> createState() =>
      _ServerSubtitleSearchSheetState();
}

class _ServerSubtitleSearchSheetState extends State<ServerSubtitleSearchSheet> {
  late final TextEditingController _queryController;
  List<ServerSubtitleResult> _results = const [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController(text: widget.initialQuery);
    WidgetsBinding.instance.addPostFrameCallback((_) => _search());
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final input = _queryController.text.trim();
      final language = input.length <= 5 ? input : null;
      final results = await widget.service.searchSubtitles(
        widget.itemId,
        language: language?.isEmpty == true ? null : language,
      );
      if (!mounted) return;
      setState(() => _results = results);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.78,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    '搜索服务器字幕',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: '关闭',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: _queryController,
              onSubmitted: (_) => _search(),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: '影片名或语言代码',
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: IconButton(
                  tooltip: '搜索',
                  onPressed: _loading ? null : _search,
                  icon: const Icon(Icons.arrow_forward_rounded),
                ),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.07),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(_error!,
                    style:
                        const TextStyle(color: AppTheme.error, fontSize: 13)),
              ),
            ),
          const SizedBox(height: 12),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _results.isEmpty
                    ? const Center(
                        child: Text('没有找到可用字幕',
                            style: TextStyle(color: Colors.white54)),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                        itemCount: _results.length,
                        separatorBuilder: (_, __) =>
                            const Divider(color: Colors.white10),
                        itemBuilder: (context, index) {
                          final result = _results[index];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.subtitles_rounded,
                                color: AppTheme.primary),
                            title: Text(
                              result.displayTitle,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              '${result.language} · ${result.provider} · ${result.format.toUpperCase()}',
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 12),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
