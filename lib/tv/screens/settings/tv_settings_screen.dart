import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../theme/app_theme.dart';
import '../../../providers/app_providers.dart';
import '../../../models/player_settings.dart';
import '../../../services/storage_service.dart';
import '../../../utils/app_log.dart';
import '../../../utils/animation_config.dart';
import '../../widgets/focusable_widgets.dart';

// ─── Sidebar item data ────────────────────────────────────────────

enum _SettingType { nav, options, toggle, toggles, form, info, action }

class _ToggleGroupItem {
  final String label;
  final bool Function(PlayerSettings) value;
  final VoidCallback onToggle;

  const _ToggleGroupItem({
    required this.label,
    required this.value,
    required this.onToggle,
  });
}

class _SettingItem {
  final String title;
  final _SettingType type;
  final String? category; // null = 不显示分组标题
  final List<String>? options;
  final String Function(PlayerSettings)? valueLabel;
  final void Function(WidgetRef, String)? onOptionSelected;
  final VoidCallback? onToggle;
  final bool Function(PlayerSettings)? toggleValue;
  final List<_ToggleGroupItem>? toggles;
  final String? infoTitle;
  final String? infoDescription;

  const _SettingItem({
    required this.title,
    required this.type,
    this.category,
    this.options,
    this.valueLabel,
    this.onOptionSelected,
    this.onToggle,
    this.toggleValue,
    this.toggles,
    this.infoTitle,
    this.infoDescription,
  });
}

// ─── Screen ───────────────────────────────────────────────────────

class TvSettingsScreen extends ConsumerStatefulWidget {
  const TvSettingsScreen({super.key});

  @override
  ConsumerState<TvSettingsScreen> createState() => _TvSettingsScreenState();
}

class _TvSettingsScreenState extends ConsumerState<TvSettingsScreen> {
  int _selectedIndex = -1;
  final Map<int, FocusNode> _itemFocusNodes = {};

  // Danmaku form state (persisted while on this screen)
  final _danmakuUrlCtrl = TextEditingController();
  final _danmakuKeyCtrl = TextEditingController();
  bool _danmakuInitialized = false;

  @override
  void dispose() {
    _danmakuUrlCtrl.dispose();
    _danmakuKeyCtrl.dispose();
    for (final node in _itemFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  // ─── Build item list ─────────────────────────────────────────

  List<_SettingItem> _buildItems(PlayerSettings settings) {
    return [
      const _SettingItem(title: '媒体服务器', type: _SettingType.nav, category: '服务器配置'),
      _SettingItem(
        title: '播放内核',
        type: _SettingType.options,
        category: '播放设置',
        options: ['auto', 'exo', 'mpv'],
        valueLabel: _kernelLabel,
        onOptionSelected: _onKernelChanged,
      ),
      _SettingItem(
        title: '硬件加速',
        type: _SettingType.toggle,
        toggleValue: (s) => s.enableHardwareAcceleration,
        onToggle: _onHardwareToggle,
      ),
      _SettingItem(
        title: '默认画质',
        type: _SettingType.options,
        options: ['auto', '1080p', '4k', 'original'],
        valueLabel: _qualityLabel,
        onOptionSelected: _onQualityChanged,
      ),
      _SettingItem(
        title: '跳过片头片尾',
        type: _SettingType.toggles,
        category: '播放设置',
        toggles: [
          _ToggleGroupItem(
            label: '自动跳过片头',
            value: (s) => s.autoSkipIntro,
            onToggle: _onAutoSkipIntroToggle,
          ),
          _ToggleGroupItem(
            label: '自动跳过片尾',
            value: (s) => s.autoSkipOutro,
            onToggle: _onAutoSkipOutroToggle,
          ),
          _ToggleGroupItem(
            label: '显示跳过按钮',
            value: (s) => s.showSkipButton,
            onToggle: _onShowSkipButtonToggle,
          ),
        ],
      ),
      const _SettingItem(title: '弹幕配置', type: _SettingType.form, category: ''),
      const _SettingItem(title: '观看历史', type: _SettingType.info, category: '数据管理',
        infoTitle: '观看历史', infoDescription: '观看历史记录由媒体服务器自动同步'),
      const _SettingItem(title: '清除缓存', type: _SettingType.action, category: '',
        infoTitle: '清除缓存', infoDescription: '将清除图片缓存和媒体库缓存数据'),
      const _SettingItem(title: '关于', type: _SettingType.info, category: '其他',
        infoTitle: 'LAN Player TV', infoDescription: '版本 0.130.0\n基于 Flutter 构建的电视端媒体播放器\n支持 Emby、Jellyfin、飞牛影视'),
      const _SettingItem(title: '日志', type: _SettingType.info, category: '',
        infoTitle: '应用日志', infoDescription: '日志已输出到 Android logcat\n使用 adb logcat -s flutter 查看'),
    ];
  }

  static String _kernelLabel(PlayerSettings s) {
    switch (s.playerKernel) {
      case 'exo': return 'ExoPlayer';
      case 'mpv': return 'MPV';
      default: return '自动';
    }
  }

  static String _qualityLabel(PlayerSettings s) {
    switch (s.defaultQuality) {
      case '1080p': return '1080P';
      case '4k': return '4K';
      case 'original': return '原画';
      default: return '自动';
    }
  }

  // ─── Callbacks ────────────────────────────────────────────────

  void _onKernelChanged(WidgetRef ref, String v) {
    ref.read(playerSettingsProvider.notifier).update((s) => s.copyWith(playerKernel: v));
  }

  void _onHardwareToggle() {
    ref.read(playerSettingsProvider.notifier).update((s) => s.copyWith(enableHardwareAcceleration: !s.enableHardwareAcceleration));
  }

  void _onAutoSkipIntroToggle() {
    ref.read(playerSettingsProvider.notifier).update((s) => s.copyWith(autoSkipIntro: !s.autoSkipIntro));
  }

  void _onAutoSkipOutroToggle() {
    ref.read(playerSettingsProvider.notifier).update((s) => s.copyWith(autoSkipOutro: !s.autoSkipOutro));
  }

  void _onShowSkipButtonToggle() {
    ref.read(playerSettingsProvider.notifier).update((s) => s.copyWith(showSkipButton: !s.showSkipButton));
  }

  void _onQualityChanged(WidgetRef ref, String v) {
    ref.read(playerSettingsProvider.notifier).update((s) => s.copyWith(defaultQuality: v));
  }

  void _selectItem(int index, _SettingItem item) {
    if (item.type == _SettingType.nav) {
      context.push('/servers');
      return;
    }
    if (item.type == _SettingType.toggle) {
      item.onToggle?.call();
      return;
    }
    if (item.type == _SettingType.form && !_danmakuInitialized) {
      _danmakuUrlCtrl.text = StorageService.getString(StorageService.danmakuUrlKey) ?? '';
      _danmakuKeyCtrl.text = StorageService.getString(StorageService.danmakuApiKey) ?? '';
      _danmakuInitialized = true;
    }
    if (item.type == _SettingType.action) {
      _confirmClearCache();
      return;
    }
    setState(() => _selectedIndex = _selectedIndex == index ? -1 : index);
  }

  void _confirmClearCache() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E3A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('清除缓存', style: TextStyle(color: Colors.white, fontSize: 18)),
        content: const Text('确定要清除图片缓存和媒体库缓存吗？',
            style: TextStyle(color: Colors.white70, fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              AppLog.i('TvSettings', '用户触发缓存清除');
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('缓存已清除')),
              );
            },
            child: const Text('清除', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  // ─── Build ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(playerSettingsProvider);
    final items = _buildItems(settings);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Full-screen gradient background (for BackdropFilter to blur)
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF0A0A14), Color(0xFF12122A), Color(0xFF0A0A14)],
              ),
            ),
          ),
          Row(
            children: [
              _buildSidebar(items, settings),
              Expanded(child: _buildRightPanel(items, settings)),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Sidebar ──────────────────────────────────────────────────

  Widget _buildSidebar(List<_SettingItem> items, PlayerSettings settings) {
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          width: 320,
          decoration: BoxDecoration(
            color: const Color(0xFF141428).withValues(alpha: 0.55),
            border: Border(
              right: BorderSide(
                color: Colors.white.withValues(alpha: 0.12),
                width: 0.5,
              ),
            ),
          ),
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 32),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              // Show category header if this item has one
              final showCategory = item.category != null && item.category!.isNotEmpty;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showCategory) ...[
                    if (index > 0) const SizedBox(height: 20),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(28, 0, 28, 6),
                      child: Text(
                        item.category!.toUpperCase(),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.35),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                  ],
                  _SidebarItem(
                    item: item,
                    index: index,
                    settings: settings,
                    isSelected: _selectedIndex == index,
                    onTap: () => _selectItem(index, item),
                    focusNode: _itemFocusNodes.putIfAbsent(
                      index,
                      () => FocusNode(debugLabel: 'setting_${item.title}'),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  // ─── Right Panel ──────────────────────────────────────────────

  Widget _buildRightPanel(List<_SettingItem> items, PlayerSettings settings) {
    if (_selectedIndex < 0 || _selectedIndex >= items.length) {
      return _buildDefaultPanel();
    }
    final item = items[_selectedIndex];
    return AnimatedSwitcher(
      duration: AppAnimations.medium,
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: _buildPanelContent(item, settings, key: ValueKey(_selectedIndex)),
    );
  }

  Widget _buildPanelContent(_SettingItem item, PlayerSettings settings, {Key? key}) {
    switch (item.type) {
      case _SettingType.options:
        return _buildOptionsPanel(item, settings, key: key);
      case _SettingType.toggle:
        return _buildTogglePanel(item, settings, key: key);
      case _SettingType.toggles:
        return _buildTogglesPanel(item, settings, key: key);
      case _SettingType.form:
        return _buildFormPanel(key: key);
      case _SettingType.info:
        return _buildInfoPanel(item, key: key);
      default:
        return _buildDefaultPanel(key: key);
    }
  }

  // Default: app logo
  Widget _buildDefaultPanel({Key? key}) {
    return Container(
      key: key,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppTheme.primary, AppTheme.secondary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(28),
              ),
              child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 48),
            ),
            const SizedBox(height: 24),
            const Text(
              'LAN Player TV',
              style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('版本 0.130.0',
                style: TextStyle(color: Colors.white38, fontSize: 14)),
          ],
        ),
      ),
    );
  }

  // Options: radio list
  Widget _buildOptionsPanel(_SettingItem item, PlayerSettings settings, {Key? key}) {
    final current = item.valueLabel != null ? item.valueLabel!(settings) : '';
    final options = item.options ?? [];
    return _PanelCard(
      key: key,
      title: item.title,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: options.map((opt) {
          final label = _optionDisplayName(opt);
          final selected = _optionValueMatch(opt, current);
          return _PanelOption(
            label: label,
            selected: selected,
            focusId: 'panel_opt_${item.title}_$opt',
            onTap: () {
              item.onOptionSelected?.call(ref, opt);
            },
          );
        }).toList(),
      ),
    );
  }

  String _optionDisplayName(String value) {
    switch (value) {
      case 'auto': return '自动（推荐）';
      case 'exo': return 'ExoPlayer';
      case 'mpv': return 'MPV';
      case '1080p': return '1080P';
      case '4k': return '4K';
      case 'original': return '原画';
      default: return value;
    }
  }

  bool _optionValueMatch(String opt, String current) {
    if (opt == 'auto' && (current == '自动' || current == 'auto')) return true;
    if (opt == 'exo' && current == 'ExoPlayer') return true;
    if (opt == 'mpv' && current == 'MPV') return true;
    if (opt == current) return true;
    return false;
  }

  // Toggle (single)
  Widget _buildTogglePanel(_SettingItem item, PlayerSettings settings, {Key? key}) {
    final isOn = item.toggleValue?.call(settings) ?? false;
    return _PanelCard(
      key: key,
      title: item.title,
      child: _PanelToggle(
        value: isOn,
        focusId: 'panel_toggle_${item.title}',
        onChanged: (_) => item.onToggle?.call(),
      ),
    );
  }

  // Toggles (group)
  Widget _buildTogglesPanel(_SettingItem item, PlayerSettings settings, {Key? key}) {
    final toggles = item.toggles ?? const [];
    return _PanelCard(
      key: key,
      title: item.title,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: toggles.asMap().entries.map((entry) {
          final i = entry.key;
          final t = entry.value;
          return Padding(
            padding: EdgeInsets.only(bottom: i == toggles.length - 1 ? 0 : 16),
            child: _PanelToggle(
              label: t.label,
              value: t.value(settings),
              focusId: 'panel_toggle_${item.title}_$i',
              onChanged: (_) => t.onToggle(),
            ),
          );
        }).toList(),
      ),
    );
  }

  // Form: danmaku config
  Widget _buildFormPanel({Key? key}) {
    return _PanelCard(
      key: key,
      title: '弹幕配置',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('弹幕服务器', style: TextStyle(color: Colors.white54, fontSize: 13)),
          const SizedBox(height: 8),
          _PanelTextField(
            controller: _danmakuUrlCtrl,
            hintText: 'https://api.danmaku.com',
            focusId: 'danmaku_url',
          ),
          const SizedBox(height: 24),
          const Text('API Key', style: TextStyle(color: Colors.white54, fontSize: 13)),
          const SizedBox(height: 8),
          _PanelTextField(
            controller: _danmakuKeyCtrl,
            hintText: '可选',
            focusId: 'danmaku_key',
          ),
          const SizedBox(height: 16),
          const Text('配置后可在播放界面加载弹幕',
              style: TextStyle(color: Colors.white24, fontSize: 12)),
          const SizedBox(height: 20),
          _PanelButton(
            label: '保存',
            focusId: 'save_danmaku',
            color: AppTheme.primary,
            onTap: () async {
              await StorageService.setString(
                  StorageService.danmakuUrlKey, _danmakuUrlCtrl.text.trim());
              await StorageService.setString(
                  StorageService.danmakuApiKey, _danmakuKeyCtrl.text.trim());
              AppLog.i('TvSettings', '弹幕配置已保存');
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('弹幕配置已保存')),
                );
              }
            },
          ),
          const SizedBox(height: 12),
          _PanelButton(
            label: '扫码配置（手机输入）',
            focusId: 'danmaku_qr',
            color: Colors.white24,
            onTap: _showDanmakuQrCode,
          ),
        ],
      ),
    );
  }

  /// 扫码配置弹幕服务器：启动临时 HTTP 服务，手机扫码后输入
  void _showDanmakuQrCode() async {
    // 获取本机局域网 IP
    String localIp = '127.0.0.1';
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback && addr.address.startsWith('192.168')) {
            localIp = addr.address;
            break;
          }
        }
      }
    } catch (_) {}

    const port = 18923;
    final url = 'http://$localIp:$port';

    // 启动临时 HTTP 服务器
    HttpServer? server;
    try {
      server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法启动服务: $e')),
        );
      }
      return;
    }

    // 监听请求
    server.listen((request) async {
      if (request.method == 'GET') {
        // 返回简单的 HTML 表单
        request.response
          ..headers.contentType = ContentType.html
          ..write('''
<!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>弹幕配置</title><style>
body{font-family:system-ui;background:#1a1a2e;color:#fff;display:flex;justify-content:center;align-items:center;min-height:100vh;margin:0}
.card{background:#2a2a4a;padding:32px;border-radius:16px;width:90%;max-width:360px}
h2{margin:0 0 24px;font-size:20px}
input{width:100%;padding:12px;margin:8px 0 16px;border:1px solid #555;border-radius:8px;background:#1a1a2e;color:#fff;font-size:16px;box-sizing:border-box}
button{width:100%;padding:14px;background:#6366f1;color:#fff;border:none;border-radius:8px;font-size:16px;cursor:pointer}
.ok{color:#4ade80;text-align:center;margin-top:16px;display:none}
</style></head><body><div class="card">
<h2>配置弹幕服务器</h2>
<form id="f"><label>服务器地址</label><input name="url" placeholder="https://api.danmaku.com" value="${_danmakuUrlCtrl.text}">
<label>API Key（可选）</label><input name="key" placeholder="留空即可" value="${_danmakuKeyCtrl.text}">
<button type="submit">保存</button></form>
<div class="ok" id="ok">✓ 已保存，可关闭此页面</div>
<script>document.getElementById('f').onsubmit=async e=>{e.preventDefault();
const d=new URLSearchParams(new FormData(e.target));
await fetch('/save?'+d);document.getElementById('ok').style.display='block';
document.getElementById('f').style.display='none';}</script>
</div></body></html>''');
        await request.response.close();
      } else if (request.method == 'GET' && request.uri.path == '/save') {
        final urlParam = request.uri.queryParameters['url'] ?? '';
        final keyParam = request.uri.queryParameters['key'] ?? '';
        await StorageService.setString(StorageService.danmakuUrlKey, urlParam.trim());
        await StorageService.setString(StorageService.danmakuApiKey, keyParam.trim());
        if (mounted) {
          setState(() {
            _danmakuUrlCtrl.text = urlParam.trim();
            _danmakuKeyCtrl.text = keyParam.trim();
          });
        }
        request.response
          ..headers.contentType = ContentType.text
          ..write('ok');
        await request.response.close();
        // 关闭对话框
        if (mounted && Navigator.canPop(context)) {
          Navigator.pop(context);
        }
        await server?.close();
      }
    });

    // 显示 QR 对话框
    if (!mounted) { await server.close(); return; }
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E3A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('手机扫码配置', style: TextStyle(color: Colors.white, fontSize: 18)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              QrImageView(
                data: url,
                version: QrVersions.auto,
                size: 200,
                backgroundColor: Colors.white,
              ),
              const SizedBox(height: 16),
              Text(url, style: const TextStyle(color: Colors.white54, fontSize: 13)),
              const SizedBox(height: 8),
              const Text('用手机扫描二维码，在浏览器中输入弹幕服务器地址',
                  style: TextStyle(color: Colors.white38, fontSize: 12), textAlign: TextAlign.center),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () { Navigator.pop(ctx); server?.close(); },
              child: const Text('关闭', style: TextStyle(color: Colors.white54)),
            ),
          ],
        );
      },
    ).then((_) => server?.close());
  }

  // Info display
  Widget _buildInfoPanel(_SettingItem item, {Key? key}) {
    return _PanelCard(
      key: key,
      title: item.infoTitle ?? item.title,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item.title == '关于')
            Center(
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppTheme.primary, AppTheme.secondary],
                  ),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 40),
              ),
            ),
          if (item.title == '关于') const SizedBox(height: 20),
          Text(
            item.infoDescription ?? '',
            style: const TextStyle(color: Colors.white60, fontSize: 14, height: 1.7),
          ),
        ],
      ),
    );
  }
}

// ─── Sidebar Item Widget ─────────────────────────────────────────

class _SidebarItem extends StatefulWidget {
  final _SettingItem item;
  final int index;
  final PlayerSettings settings;
  final bool isSelected;
  final VoidCallback onTap;
  final FocusNode focusNode;

  const _SidebarItem({
    required this.item,
    required this.index,
    required this.settings,
    required this.isSelected,
    required this.onTap,
    required this.focusNode,
  });

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _isFocused = false;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    if (mounted) setState(() => _isFocused = widget.focusNode.hasFocus);
  }

  String _valueText() {
    final item = widget.item;
    if (item.type == _SettingType.toggle) {
      final on = item.toggleValue?.call(widget.settings) ?? false;
      return on ? '开启' : '关闭';
    }
    if (item.valueLabel != null) return item.valueLabel!(widget.settings);
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final value = _valueText();
    final hasValue = item.type == _SettingType.toggle ||
        (item.type == _SettingType.options && value.isNotEmpty);

    return GestureDetector(
      onTap: () {
        setState(() => _isPressed = true);
        widget.onTap();
        Future.delayed(const Duration(milliseconds: 120), () {
          if (mounted) setState(() => _isPressed = false);
        });
      },
      child: Focus(
        focusNode: widget.focusNode,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              (event.logicalKey == LogicalKeyboardKey.select ||
                  event.logicalKey == LogicalKeyboardKey.enter ||
                  event.logicalKey == LogicalKeyboardKey.gameButtonA)) {
            setState(() => _isPressed = true);
            widget.onTap();
            Future.delayed(const Duration(milliseconds: 120), () {
              if (mounted) setState(() => _isPressed = false);
            });
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: AnimatedScale(
          scale: _isPressed ? 0.97 : 1.0,
          duration: AppAnimations.fast,
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: AppAnimations.normal,
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: _isFocused || widget.isSelected
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.transparent,
            ),
            child: Row(
              children: [
                // Left selection bar
                AnimatedContainer(
                  duration: AppAnimations.normal,
                  curve: Curves.easeOutCubic,
                  width: 3,
                  height: widget.isSelected ? 28 : 0,
                  decoration: BoxDecoration(
                    color: AppTheme.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 12),
                // Title
                Expanded(
                  child: Text(
                    item.title,
                    style: TextStyle(
                      color: widget.isSelected
                          ? AppTheme.primary
                          : Colors.white.withValues(alpha: 0.9),
                      fontSize: 15,
                      fontWeight: widget.isSelected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
                // Value / chevron
                if (hasValue)
                  Text(
                    value,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 13,
                    ),
                  ),
                if (!hasValue)
                  Icon(
                    Icons.chevron_right,
                    color: Colors.white.withValues(alpha: 0.25),
                    size: 18,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Right Panel Widgets ─────────────────────────────────────────

class _PanelCard extends StatelessWidget {
  final Widget child;
  final String title;
  const _PanelCard({super.key, required this.child, required this.title});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        margin: const EdgeInsets.all(48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 28),
            child,
          ],
        ),
      ),
    );
  }
}

class _PanelOption extends StatefulWidget {
  final String label;
  final bool selected;
  final String focusId;
  final VoidCallback onTap;

  const _PanelOption({
    required this.label,
    required this.selected,
    required this.focusId,
    required this.onTap,
  });

  @override
  State<_PanelOption> createState() => _PanelOptionState();
}

class _PanelOptionState extends State<_PanelOption> {
  late FocusNode _fn;
  bool _focused = false;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _fn = FocusNode(debugLabel: widget.focusId);
    _fn.addListener(() {
      if (mounted) setState(() => _focused = _fn.hasFocus);
    });
  }

  @override
  void dispose() {
    _fn.removeListener(() {});
    _fn.dispose();
    super.dispose();
  }

  void _handleTap() {
    setState(() => _pressed = true);
    widget.onTap();
    Future.delayed(const Duration(milliseconds: 120), () {
      if (mounted) setState(() => _pressed = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleTap,
      child: Focus(
        focusNode: _fn,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              (event.logicalKey == LogicalKeyboardKey.select ||
                  event.logicalKey == LogicalKeyboardKey.enter)) {
            _handleTap();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1.0,
          duration: AppAnimations.fast,
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: AppAnimations.normal,
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.symmetric(vertical: 3),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: _focused || widget.selected
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.transparent,
            ),
            child: Row(
              children: [
                Icon(
                  widget.selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  color: widget.selected ? AppTheme.primary : Colors.white38,
                  size: 20,
                ),
                const SizedBox(width: 14),
                Text(
                  widget.label,
                  style: TextStyle(
                    color: widget.selected ? AppTheme.primary : Colors.white.withValues(alpha: 0.85),
                    fontSize: 16,
                    fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                const Spacer(),
                if (_focused)
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: AppTheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PanelToggle extends StatefulWidget {
  final bool value;
  final String focusId;
  final ValueChanged<bool> onChanged;
  final String? label;

  const _PanelToggle({
    required this.value,
    required this.focusId,
    required this.onChanged,
    this.label,
  });

  @override
  State<_PanelToggle> createState() => _PanelToggleState();
}

class _PanelToggleState extends State<_PanelToggle> {
  late FocusNode _fn;
  bool _focused = false;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _fn = FocusNode(debugLabel: widget.focusId);
    _fn.addListener(() {
      if (mounted) setState(() => _focused = _fn.hasFocus);
    });
  }

  @override
  void dispose() {
    _fn.removeListener(() {});
    _fn.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _pressed = true);
    widget.onChanged(!widget.value);
    Future.delayed(const Duration(milliseconds: 120), () {
      if (mounted) setState(() => _pressed = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _toggle,
      child: Focus(
        focusNode: _fn,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              (event.logicalKey == LogicalKeyboardKey.select ||
                  event.logicalKey == LogicalKeyboardKey.enter)) {
            _toggle();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1.0,
          duration: AppAnimations.fast,
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: AppAnimations.medium,
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: _focused ? Colors.white.withValues(alpha: 0.06) : Colors.transparent,
            ),
            child: Row(
              children: [
                Text(
                  widget.label ?? (widget.value ? '已开启' : '已关闭'),
                  style: TextStyle(
                    color: widget.label != null
                        ? Colors.white
                        : (widget.value ? AppTheme.primary : Colors.white38),
                    fontSize: 16,
                    fontWeight: widget.label != null ? FontWeight.w500 : FontWeight.w500,
                  ),
                ),
                const Spacer(),
                AnimatedContainer(
                  duration: AppAnimations.medium,
                  curve: Curves.easeOutCubic,
                  width: 52,
                  height: 30,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(15),
                    color: widget.value ? AppTheme.primary : Colors.white.withValues(alpha: 0.15),
                    border: _focused
                        ? Border.all(color: Colors.white.withValues(alpha: 0.5), width: 2)
                        : null,
                  ),
                  child: Stack(
                    children: [
                      AnimatedAlign(
                        duration: AppAnimations.medium,
                        curve: Curves.easeOutCubic,
                        alignment: widget.value ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          width: 26,
                          height: 26,
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PanelTextField extends StatefulWidget {
  final TextEditingController controller;
  final String hintText;
  final String focusId;

  const _PanelTextField({
    required this.controller,
    required this.hintText,
    required this.focusId,
  });

  @override
  State<_PanelTextField> createState() => _PanelTextFieldState();
}

class _PanelTextFieldState extends State<_PanelTextField> {
  late FocusNode _fn;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _fn = FocusNode(debugLabel: widget.focusId);
    _fn.addListener(() {
      if (mounted) setState(() => _focused = _fn.hasFocus);
    });
  }

  @override
  void dispose() {
    _fn.removeListener(() {});
    _fn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _fn.requestFocus(),
      child: AnimatedContainer(
        duration: AppAnimations.normal,
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _focused ? AppTheme.primary : Colors.white.withValues(alpha: 0.12),
            width: _focused ? 2 : 1,
          ),
        ),
        child: TextField(
          focusNode: _fn,
          controller: widget.controller,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: widget.hintText,
            hintStyle: const TextStyle(color: Colors.white24),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: InputBorder.none,
          ),
          onTapOutside: (_) => _fn.unfocus(),
        ),
      ),
    );
  }
}

class _PanelButton extends StatefulWidget {
  final String label;
  final String focusId;
  final Color color;
  final VoidCallback onTap;

  const _PanelButton({
    required this.label,
    required this.focusId,
    required this.color,
    required this.onTap,
  });

  @override
  State<_PanelButton> createState() => _PanelButtonState();
}

class _PanelButtonState extends State<_PanelButton> {
  late FocusNode _fn;
  bool _focused = false;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _fn = FocusNode(debugLabel: widget.focusId);
    _fn.addListener(() {
      if (mounted) setState(() => _focused = _fn.hasFocus);
    });
  }

  @override
  void dispose() {
    _fn.removeListener(() {});
    _fn.dispose();
    super.dispose();
  }

  void _handleTap() {
    setState(() => _pressed = true);
    widget.onTap();
    Future.delayed(const Duration(milliseconds: 120), () {
      if (mounted) setState(() => _pressed = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleTap,
      child: Focus(
        focusNode: _fn,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              (event.logicalKey == LogicalKeyboardKey.select ||
                  event.logicalKey == LogicalKeyboardKey.enter)) {
            _handleTap();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: AnimatedScale(
          scale: _pressed ? 0.96 : 1.0,
          duration: AppAnimations.fast,
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: AppAnimations.normal,
            curve: Curves.easeOutCubic,
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: widget.color,
              borderRadius: BorderRadius.circular(14),
              boxShadow: _focused
                  ? [BoxShadow(color: widget.color.withValues(alpha: 0.5), blurRadius: 16, offset: const Offset(0, 4))]
                  : [],
            ),
            child: Center(
              child: Text(
                widget.label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}