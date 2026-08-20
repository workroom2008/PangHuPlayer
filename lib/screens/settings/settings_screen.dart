import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import '../../theme/app_theme.dart';
import '../../providers/app_providers.dart';
import '../../services/storage_service.dart';
import '../../services/moviepilot_service.dart';
import '../../services/opensubtitles_service.dart';
import '../../services/favorite_service.dart';
import '../../utils/animation_config.dart';
import '../../utils/screen_adapter.dart';
import '../../utils/glass_quality.dart';
import '../subscriptions/subscriptions_screen.dart';
import '../danmaku/danmaku_screen.dart';
import '../log/log_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bgColor,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 120,
            pinned: true,
            floating: true,
            backgroundColor: context.bgColor,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: EdgeInsets.zero,
              expandedTitleScale: 1.0,
              title: Padding(
                padding: const EdgeInsets.fromLTRB(20, 48, 20, 12),
                child: Text(
                  '设置',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: context.textPrimary,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Column(
                children: [
                  _buildSection('服务器配置', [
                    _SettingsItem(
                      icon: Icons.cloud_download_rounded, iconColor: const Color(0xFF10B981),
                      title: 'MoviePilot',
                      subtitle: '配置订阅下载服务',
                      onTap: () => _showMoviePilotConfig(),
                    ),
                    _SettingsItem(
                      icon: Icons.movie_rounded, iconColor: const Color(0xFFF59E0B),
                      title: 'TMDB',
                      subtitle: '配置 TMDB API Key 获取电影信息',
                      onTap: () => _showTMDBConfig(),
                    ),
                  ]).animate().fadeIn(delay: 100.ms).slideY(begin: 0.1, end: 0),
                  SizedBox(height: 20),
                  _buildSection('播放设置', [
                    _SettingsItem(
                      icon: Icons.comment_rounded, iconColor: AppTheme.accent,
                      title: '弹幕配置',
                      subtitle: '管理弹幕服务器和显示设置',
                      onTap: () => _navigateTo(DanmakuScreen()),
                    ),
                    _SettingsItem(
                      icon: Icons.video_settings_rounded, iconColor: AppTheme.primary,
                      title: '播放器设置',
                      subtitle: '画质、解码、字幕等',
                      onTap: () => _showPlayerSettings(),
                    ),
                    _SettingsItem(
                      icon: Icons.subtitles_rounded, iconColor: const Color(0xFFF59E0B),
                      title: '在线字幕 (OpenSubtitles)',
                      subtitle: OpenSubtitlesService.isConfigured ? '已配置 · 播放器内搜索下载字幕' : '配置账号与 API Key 以搜索下载字幕',
                      onTap: () => _showOpenSubtitlesConfig(),
                    ),
                  ]).animate().fadeIn(delay: 150.ms).slideY(begin: 0.1, end: 0),
                  SizedBox(height: 20),
                  _buildSection('数据管理', [
                    _SettingsItem(
                      icon: Icons.history_rounded, iconColor: const Color(0xFF8B5CF6),
                      title: '观看历史',
                      subtitle: '清除或导出观看记录',
                      onTap: () => _showWatchHistorySettings(),
                    ),
                    _SettingsItem(
                      icon: Icons.favorite_rounded, iconColor: Colors.red,
                      title: '收藏管理',
                      subtitle: '查看或清除收藏列表',
                      onTap: () => _showFavoritesSettings(),
                    ),
                    _SettingsItem(
                      icon: Icons.subscriptions_rounded, iconColor: const Color(0xFF06B6D4),
                      title: '订阅管理',
                      subtitle: '查看和管理订阅',
                      onTap: () => _navigateTo(SubscriptionsPage()),
                    ),
                  ]).animate().fadeIn(delay: 200.ms).slideY(begin: 0.1, end: 0),
                  SizedBox(height: 20),
                  _buildSection('外观设置', [
                    _SettingsItem(
                      icon: Icons.palette_rounded, iconColor: const Color(0xFFEC4899),
                      title: '主题颜色',
                      subtitle: '自定义应用主题',
                      onTap: () => _showThemeSettings(),
                    ),
                    _SettingsItem(
                      icon: Icons.photo_size_select_large_rounded, iconColor: const Color(0xFF10B981),
                      title: '卡片大小',
                      subtitle: '调整首页海报卡片尺寸',
                      trailing: _CardSizeSelector(),
                      onTap: () {},
                    ),
                    _SettingsItem(
                      icon: Icons.blur_on_rounded, iconColor: const Color(0xFF06B6D4),
                      title: '玻璃效果等级',
                      subtitle: '高=完整模糊 / 低=省电降级 / 关=仅半透明',
                      trailing: _GlassLevelSelector(),
                      onTap: () {},
                    ),
                    _SettingsItem(
                      icon: Icons.dark_mode_rounded, iconColor: const Color(0xFF6366F1),
                      title: '深色模式',
                      subtitle: '切换深色/浅色模式',
                      trailing: Consumer(builder: (_, ref, __) => Switch(
                        value: ref.watch(darkModeProvider),
                        onChanged: (v) => ref.read(darkModeProvider.notifier).set(v),
                        activeThumbColor: AppTheme.primary,
                      )),
                      onTap: () {},
                    ),
                  ]).animate().fadeIn(delay: 250.ms).slideY(begin: 0.1, end: 0),
                  SizedBox(height: 20),
                  _buildSection('其他', [
                    _SettingsItem(
                      icon: Icons.info_rounded, iconColor: context.textSecondary,
                      title: '关于',
                      subtitle: '版本信息与开发者',
                      onTap: () => _showAboutDialog(),
                    ),
                    _SettingsItem(
                      icon: Icons.bug_report_rounded, iconColor: AppTheme.warning,
                      title: '日志查看',
                      subtitle: '查看API调用和错误日志',
                      onTap: () => _navigateTo(LogScreen()),
                    ),
                  ]).animate().fadeIn(delay: 300.ms).slideY(begin: 0.1, end: 0),
                  SizedBox(height: MediaQuery.paddingOf(context).bottom + 80),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<_SettingsItem> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 20, top: 28, bottom: 8),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: context.textTertiary,
              letterSpacing: 0.2,
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: context.isDark
                ? AppTheme.darkSurfaceHigh.withValues(alpha: 0.5)
                : Colors.white,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              for (int i = 0; i < items.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 0.5,
                    thickness: 0.5,
                    indent: 52,
                    color: context.dividerColor,
                  ),
                items[i],
              ],
            ],
          ),
        ),
      ],
    );
  }

  void _navigateTo(Widget screen) {
    Navigator.push(
      context,
      AppAnimations.buildPageRoute(
        page: screen,
        type: PageTransitionType.slideRight,
      ),
    );
  }

  void _showMoviePilotConfig() {
    showDialog(
      context: context,
      builder: (_) => _MoviePilotConfigDialog(),
    );
  }

  void _showTMDBConfig() {
    showDialog(
      context: context,
      builder: (_) => _TMDBConfigDialog(),
    );
  }

  void _showOpenSubtitlesConfig() {
    showDialog(
      context: context,
      builder: (_) => const _OpenSubtitlesConfigDialog(),
    );
  }

  void _showPlayerSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _PlayerSettingsSheet(),
    );
  }

  void _showWatchHistorySettings() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const _HistoryPage()));
  }

  void _showFavoritesSettings() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const _FavoritesPage()));
  }

  void _showThemeSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _ThemeSettingsSheet(),
    );
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: context.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppTheme.primary, AppTheme.secondary],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.play_arrow_rounded, color: context.textPrimary, size: 20),
            ),
            SizedBox(width: 12),
            Text('LAN Player', style: TextStyle(color: context.textPrimary)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('版本: 0.135', style: TextStyle(color: context.textPrimary38)),
            SizedBox(height: 16),
            Text('一款美观易用的影视播放器，支持多种媒体服务器集成和弹幕功能',
                style: TextStyle(color: context.textPrimary38)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('确定', style: TextStyle(color: AppTheme.primary)),
          ),
        ],
      ),
    );
  }
}

class _SettingsItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback onTap;
  final Color? iconColor;

  const _SettingsItem({required this.icon, required this.title, required this.subtitle, this.trailing, required this.onTap, this.iconColor});

  @override
  Widget build(BuildContext context) {
    final ic = iconColor ?? AppTheme.primary;
    final bg = ic.withValues(alpha: 0.15);
    return InkWell(
      onTap: onTap,
      highlightColor: Colors.transparent,
      splashColor: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // 图标容器：更圆润，颜色更柔和
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: ic, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: context.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                      letterSpacing: -0.1,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: context.textTertiary,
                        fontSize: 12,
                        letterSpacing: -0.1,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null)
              trailing!
            else
              Icon(
                Icons.chevron_right_rounded,
                color: context.textTertiary,
                size: 18,
              ),
          ],
        ),
      ),
    );
  }
}

class _MoviePilotConfigDialog extends StatefulWidget {
  @override
  State<_MoviePilotConfigDialog> createState() => _MoviePilotConfigDialogState();
}

class _MoviePilotConfigDialogState extends State<_MoviePilotConfigDialog> {
  final _urlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _apiKeyController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _useApiKey = false;

  @override
  void initState() {
    super.initState();
    _urlController.text = StorageService.getString(StorageService.moviePilotUrlKey) ?? '';
    _usernameController.text = StorageService.getString('moviepilot_username') ?? '';
    _loadCredentials();
  }

  Future<void> _loadCredentials() async {
    final apiKey = await StorageService.getSecure(StorageService.moviePilotApiKey);
    if (apiKey != null && apiKey.isNotEmpty) {
      setState(() {
        _apiKeyController.text = apiKey;
        _useApiKey = true;
      });
    } else {
      // 尝试加载密码
      final password = await StorageService.getSecure('moviepilot_password');
      if (password != null) {
        _passwordController.text = password;
      }
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: context.surfaceColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha:0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.cloud_download_rounded, color: AppTheme.primary, size: 24),
          ),
          SizedBox(width: 12),
          Text('配置MoviePilot', style: TextStyle(color: context.textPrimary)),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 认证方式切换
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: context.cardColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _useApiKey = false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: !_useApiKey ? AppTheme.primary : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Center(
                          child: Text(
                            '用户名密码',
                            style: TextStyle(
                              color: !_useApiKey ? context.textPrimary : context.textPrimary38,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _useApiKey = true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _useApiKey ? AppTheme.primary : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Center(
                          child: Text(
                            'API Key',
                            style: TextStyle(
                              color: _useApiKey ? context.textPrimary : context.textPrimary38,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 20),
            TextField(
              controller: _urlController,
              style: TextStyle(color: context.textPrimary),
              decoration: InputDecoration(
                labelText: '服务器地址',
                labelStyle: TextStyle(color: context.textPrimary38),
                hintText: 'http://192.168.1.100:3001',
                hintStyle: TextStyle(color: context.textPrimary38),
                prefixIcon: Icon(Icons.link_rounded, color: context.textPrimary38),
              ),
            ),
            SizedBox(height: 16),
            
            // 用户名密码认证
            if (!_useApiKey) ...[
              TextField(
                controller: _usernameController,
                style: TextStyle(color: context.textPrimary),
                decoration: InputDecoration(
                  labelText: '用户名',
                  labelStyle: TextStyle(color: context.textPrimary38),
                  prefixIcon: Icon(Icons.person_rounded, color: context.textPrimary38),
                ),
              ),
              SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                style: TextStyle(color: context.textPrimary),
                decoration: InputDecoration(
                  labelText: '密码',
                  labelStyle: TextStyle(color: context.textPrimary38),
                  prefixIcon: Icon(Icons.lock_rounded, color: context.textPrimary38),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                      color: context.textPrimary38,
                    ),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
              ),
            ],
            
            // API Key 认证
            if (_useApiKey) ...[
              TextField(
                controller: _usernameController,
                style: TextStyle(color: context.textPrimary),
                decoration: InputDecoration(
                  labelText: '用户名',
                  labelStyle: TextStyle(color: context.textPrimary38),
                  hintText: 'MoviePilot 登录用户名',
                  hintStyle: TextStyle(color: context.textPrimary38),
                  prefixIcon: Icon(Icons.person_rounded, color: context.textPrimary38),
                ),
              ),
              SizedBox(height: 16),
              TextField(
                controller: _apiKeyController,
                style: TextStyle(color: context.textPrimary),
                decoration: InputDecoration(
                  labelText: 'API Key',
                  labelStyle: TextStyle(color: context.textPrimary38),
                  hintText: '输入您的 API Key',
                  hintStyle: TextStyle(color: context.textPrimary38),
                  prefixIcon: Icon(Icons.key_rounded, color: context.textPrimary38),
                ),
              ),
              SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.warning.withValues(alpha:0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.warning.withValues(alpha:0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: AppTheme.warning, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'API Key 可在 MoviePilot 设置 -> API 中生成',
                        style: TextStyle(color: AppTheme.warning, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('取消', style: TextStyle(color: context.textPrimary38)),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _saveConfig,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primary,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          child: _isLoading
              ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: context.textPrimary))
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.save_rounded, color: context.textPrimary, size: 18),
                    SizedBox(width: 8),
                    Text('保存并连接', style: TextStyle(color: context.textPrimary)),
                  ],
                ),
        ),
      ],
    );
  }

  Future<void> _saveConfig() async {
    if (_urlController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('请输入服务器地址'), backgroundColor: AppTheme.warning),
      );
      return;
    }

    if (_useApiKey && _apiKeyController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('请输入 API Key'), backgroundColor: AppTheme.warning),
      );
      return;
    }

    if (!_useApiKey && (_usernameController.text.isEmpty || _passwordController.text.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('请输入用户名和密码'), backgroundColor: AppTheme.warning),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 保存配置
      final url = _fixMpUrl(_urlController.text.trim().isNotEmpty ? _urlController.text.trim() : 'http://localhost:3001');
      await StorageService.setString(StorageService.moviePilotUrlKey, url);
      
      if (_useApiKey) {
        await StorageService.setString(StorageService.moviePilotApiKey, _apiKeyController.text);
        await StorageService.remove('moviepilot_password');
        await StorageService.remove('moviepilot_username');
      } else {
        await StorageService.setString('moviepilot_username', _usernameController.text);
        await StorageService.setSecure('moviepilot_password', _passwordController.text);
        await StorageService.remove(StorageService.moviePilotApiKey);
      }

      // 测试连接
      MoviePilotService mpService;
      if (_useApiKey) {
        mpService = MoviePilotService(baseUrl: url, apiKey: _apiKeyController.text);
      } else {
        mpService = MoviePilotService(baseUrl: url, username: _usernameController.text, password: _passwordController.text);
        final loginOk = await mpService.login();
        if (!loginOk) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('登录失败，请检查用户名密码'), backgroundColor: AppTheme.error),
            );
          }
          setState(() => _isLoading = false);
          return;
        }
      }

      final success = await mpService.testConnection();

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('连接成功'), backgroundColor: AppTheme.success),
          );
          Navigator.pop(context);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('连接失败，请检查配置'), backgroundColor: AppTheme.error),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('连接错误: $e'), backgroundColor: AppTheme.error),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _fixMpUrl(String u) {
    u = u.trim();
    if (!u.startsWith('http://') && !u.startsWith('https://')) u = 'http://$u';
    while (u.endsWith('/')) u = u.substring(0, u.length - 1);
    return u;
  }
}

class _TMDBConfigDialog extends StatefulWidget {
  @override
  State<_TMDBConfigDialog> createState() => _TMDBConfigDialogState();
}

class _TMDBConfigDialogState extends State<_TMDBConfigDialog> {
  final _apiKeyController = TextEditingController();
  bool _isLoading = false;
  bool _obscureKey = true;

  @override
  void initState() {
    super.initState();
    _loadApiKey();
  }

  Future<void> _loadApiKey() async {
    final apiKey = await StorageService.getSecure(StorageService.tmdbApiKey);
    if (apiKey != null) {
      setState(() {
        _apiKeyController.text = apiKey;
      });
    }
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _saveConfig() async {
    if (_apiKeyController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('请输入 TMDB API Key'), backgroundColor: AppTheme.warning),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await StorageService.setSecure(StorageService.tmdbApiKey, _apiKeyController.text);
      
      if (mounted) {
        final tmdbService = ProviderScope.containerOf(context).read(tmdbServiceProvider);
        await tmdbService.reloadApiKey();
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存成功'), backgroundColor: Colors.green),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e'), backgroundColor: AppTheme.error),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: context.surfaceColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha:0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.movie_rounded, color: AppTheme.primary, size: 24),
          ),
          SizedBox(width: 12),
          Text('配置 TMDB', style: TextStyle(color: context.textPrimary)),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'API Key',
              style: TextStyle(
                color: context.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: 8),
            TextField(
              controller: _apiKeyController,
              obscureText: _obscureKey,
              style: TextStyle(color: context.textPrimary),
              decoration: InputDecoration(
                hintText: '输入您的 TMDB API Key',
                hintStyle: TextStyle(color: context.textPrimary38.withValues(alpha:0.5)),
                filled: true,
                fillColor: context.cardColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureKey ? Icons.visibility_off : Icons.visibility,
                    color: context.textPrimary38,
                  ),
                  onPressed: () => setState(() => _obscureKey = !_obscureKey),
                ),
              ),
            ),
            SizedBox(height: 12),
            Text(
              '前往 https://www.themoviedb.org/settings/api 注册并获取 API Key',
              style: TextStyle(
                color: context.textPrimary38.withValues(alpha:0.7),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('取消', style: TextStyle(color: context.textPrimary38)),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _saveConfig,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primary,
            foregroundColor: context.textPrimary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: _isLoading
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: context.textPrimary,
                  ),
                )
              : Text('保存'),
        ),
      ],
    );
  }
}

class _PlayerSettingsSheet extends ConsumerWidget {
  const _PlayerSettingsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(playerSettingsProvider);
    final notifier = ref.read(playerSettingsProvider.notifier);

    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('播放器设置', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: context.textPrimary)),
            SizedBox(height: 20),

            // --- 跳过片头片尾 ---
            _buildSectionTitle('跳过片头片尾'),
            _buildSwitch(context, '自动跳过片头', s.autoSkipIntro, (v) => notifier.update((s) => s.copyWith(autoSkipIntro: v))),
            _buildSwitch(context, '自动跳过片尾', s.autoSkipOutro, (v) => notifier.update((s) => s.copyWith(autoSkipOutro: v))),
            _buildSwitch(context, '显示跳过按钮', s.showSkipButton, (v) => notifier.update((s) => s.copyWith(showSkipButton: v))),
            SizedBox(height: 16),

            // --- 播放 ---
            _buildSectionTitle('播放'),
            _buildSlider(context, '默认播放速度', s.defaultPlaybackSpeed, 0.5, 2.0, (v) => notifier.update((s) => s.copyWith(defaultPlaybackSpeed: v)), formatLabel: (v) => '${v.toStringAsFixed(2)}x'),
            _buildOption(context, '默认画质', ['auto', '1080p', '4k', 'original'], s.defaultQuality, (v) => notifier.update((s) => s.copyWith(defaultQuality: v)), labels: ['自动', '1080p', '4K', '原画']),
            _buildSwitch(context, '硬件加速', s.enableHardwareAcceleration, (v) => notifier.update((s) => s.copyWith(enableHardwareAcceleration: v))),
            _buildSwitch(context, '字幕烧录(Burn-in)', s.burnInSubtitle, (v) => notifier.update((s) => s.copyWith(burnInSubtitle: v))),
            if (s.burnInSubtitle)
              Padding(
                padding: const EdgeInsets.only(left: 16, bottom: 8),
                child: Text('开启后播放时请求服务器把字幕编码进视频画面（需转码）：截图/投屏带字幕，但字幕样式不可调、切进度更慢',
                    style: TextStyle(color: context.textPrimary38, fontSize: 11)),
              ),
            _buildSwitch(context, '后台播放', s.enableBackgroundPlay, (v) => notifier.update((s) => s.copyWith(enableBackgroundPlay: v))),
            _buildSwitch(context, '画中画(PiP)', s.enablePiP, (v) => notifier.update((s) => s.copyWith(enablePiP: v))),
            _buildSwitch(context, 'Emby/Jellyfin 进度同步', s.enableProgressSync, (v) => notifier.update((s) => s.copyWith(enableProgressSync: v))),
            SizedBox(height: 16),

            // --- 弹幕 ---
            _buildSectionTitle('弹幕默认设置'),
            _buildSwitch(context, '默认开启弹幕', s.enableDanmakuByDefault, (v) => notifier.update((s) => s.copyWith(enableDanmakuByDefault: v))),
            _buildSlider(context, '弹幕字体大小', s.danmakuFontSize.toDouble(), 16, 36, (v) => notifier.update((s) => s.copyWith(danmakuFontSize: v.toInt()))),
            _buildSlider(context, '弹幕透明度', s.danmakuOpacity, 0.3, 1.0, (v) => notifier.update((s) => s.copyWith(danmakuOpacity: v))),
            _buildSlider(context, '弹幕速度', s.danmakuSpeed, 8, 20, (v) => notifier.update((s) => s.copyWith(danmakuSpeed: v))),
            SizedBox(height: 16),

            // --- 手势 ---
            _buildSectionTitle('手势控制'),
            _buildSwitch(context, '手势快进快退', s.enableGestureSeek, (v) => notifier.update((s) => s.copyWith(enableGestureSeek: v))),
            _buildSwitch(context, '手势调节亮度', s.enableGestureBrightness, (v) => notifier.update((s) => s.copyWith(enableGestureBrightness: v))),
            _buildSwitch(context, '手势调节音量', s.enableGestureVolume, (v) => notifier.update((s) => s.copyWith(enableGestureVolume: v))),
            _buildSwitch(context, '双击快进快退', s.enableDoubleTapSeek, (v) => notifier.update((s) => s.copyWith(enableDoubleTapSeek: v))),
            if (s.enableDoubleTapSeek)
              _buildSlider(context, '双击跳转秒数', s.doubleTapSeekSeconds.toDouble(), 5, 30, (v) => notifier.update((s) => s.copyWith(doubleTapSeekSeconds: v.toInt())), formatLabel: (v) => '${v.toInt()}s'),
            SizedBox(height: 16),
            Center(
              child: TextButton.icon(
                onPressed: () {
                  notifier.reset();
                  Navigator.pop(context);
                },
                icon: Icon(Icons.refresh, color: AppTheme.error),
                label: Text('重置为默认设置', style: TextStyle(color: AppTheme.error)),
              ),
            ),
            SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.primary)),
    );
  }

  Widget _buildSwitch(BuildContext context, String label, bool value, Function(bool) onChanged) {
    return SwitchListTile(
      title: Text(label, style: TextStyle(color: context.textPrimary, fontSize: 14)),
      value: value,
      onChanged: onChanged,
      activeThumbColor: AppTheme.primary,
      contentPadding: EdgeInsets.zero,
      dense: true,
    );
  }

  Widget _buildSlider(BuildContext context, String label, double value, double min, double max, Function(double) onChanged, {String Function(double)? formatLabel}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(color: context.textPrimary, fontSize: 13)),
            Text(formatLabel != null ? formatLabel(value) : value.toStringAsFixed(1), style: TextStyle(color: AppTheme.primary, fontSize: 13)),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(thumbColor: AppTheme.primary, activeTrackColor: AppTheme.primary, inactiveTrackColor: context.textPrimary10),
          child: Slider(value: value, min: min, max: max, onChanged: onChanged),
        ),
      ],
    );
  }

  Widget _buildOption(BuildContext context, String title, List<String> options, String current, Function(String) onChanged, {List<String>? labels}) {
    return Padding(
      padding: EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Text(title, style: TextStyle(color: context.textPrimary, fontSize: 13)),
          Spacer(),
          DropdownButton<String>(
            value: current,
            dropdownColor: AppTheme.darkCard,
            style: TextStyle(color: context.textPrimary38, fontSize: 13),
            underline: Container(height: 1, color: context.textPrimary38),
            items: options.asMap().entries.map((e) => DropdownMenuItem(
              value: e.value,
              child: Text(labels != null ? labels[e.key] : e.value),
            )).toList(),
            onChanged: (v) { if (v != null) onChanged(v); },
          ),
        ],
      ),
    );
  }
}

class _ThemeSettingsSheet extends ConsumerWidget {
  const _ThemeSettingsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cur = ref.watch(themeColorProvider);
    final colors = [
      (const Color(0xFF6366F1), '默认'),
      (const Color(0xFFEF4444), '红色'),
      (const Color(0xFF3B82F6), '蓝色'),
      (const Color(0xFF10B981), '绿色'),
      (const Color(0xFFF59E0B), '橙色'),
    ];

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('主题颜色', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: context.textPrimary)),
        SizedBox(height: 20),
        Wrap(spacing: 16, runSpacing: 16, children: colors.map((c) {
          final sel = c.$1 == cur;
          return GestureDetector(
            onTap: () => ref.read(themeColorProvider.notifier).set(c.$1),
            child: Container(width: 52, height: 52, decoration: BoxDecoration(color: c.$1, shape: BoxShape.circle,
              border: sel ? Border.all(color: context.textPrimary, width: 3) : null),
              child: sel ? Icon(Icons.check, color: context.textPrimary, size: 24) : null));
        }).toList()),
        SizedBox(height: 20),
      ]),
    );
  }
}

class _FavoritesPage extends ConsumerWidget {
  const _FavoritesPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favs = ref.watch(favoriteMoviesProvider);

    return Scaffold(
      backgroundColor: context.bgColor,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 120,
            pinned: true,
            backgroundColor: context.bgColor,
            flexibleSpace: FlexibleSpaceBar(
              title: Text('收藏管理', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: context.textPrimary)),
              titlePadding: EdgeInsets.only(left: 16, bottom: 16),
            ),
          ),
          SliverToBoxAdapter(
            child: favs.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(32),
                            decoration: BoxDecoration(color: context.surfaceColor, shape: BoxShape.circle),
                            child: Icon(Icons.favorite_border_rounded, color: context.textSecondary, size: 48),
                          ),
                          SizedBox(height: 24),
                          Text('暂无收藏', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: context.textPrimary)),
                          SizedBox(height: 8),
                          Text('在电影详情页点击收藏按钮添加', style: TextStyle(fontSize: 14, color: context.textSecondary)),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: favs.length,
                    itemBuilder: (_, i) => Slidable(
                      key: ValueKey('fav-${favs[i].tmdbId}'),
                      endActionPane: ActionPane(
                        motion: const ScrollMotion(),
                        children: [
                          SlidableAction(
                            onPressed: (_) {
                              ref.read(favoriteMoviesProvider.notifier).removeFavorite(favs[i].tmdbId);
                            },
                            backgroundColor: AppTheme.error,
                            foregroundColor: context.textPrimary,
                            borderRadius: const BorderRadius.only(
                              topRight: Radius.circular(14),
                              bottomRight: Radius.circular(14),
                            ),
                            label: '取消收藏',
                            icon: Icons.favorite_border_rounded,
                          ),
                        ],
                      ),
                      child: _FavoriteListCard(fav: favs[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}



class _FavoriteListCard extends StatelessWidget {
  final FavoriteMovie fav;

  const _FavoriteListCard({required this.fav});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 100,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: context.surfaceColor,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(14),
                bottomLeft: Radius.circular(14),
              ),
              child: SizedBox(
                width: 70,
                height: 100,
                child: fav.posterPath != null && fav.posterPath!.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: 'https://image.tmdb.org/t/p/w342${fav.posterPath}',
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                        placeholder: (_, __) => Container(color: context.cardColor, child: Center(child: Icon(Icons.movie, color: context.textSecondary, size: 24))),
                        errorWidget: (_, __, ___) => Container(color: context.cardColor, child: Center(child: Icon(Icons.movie, color: context.textSecondary, size: 24))),
                      )
                    : Container(color: context.cardColor, child: Center(child: Icon(Icons.movie, color: context.textSecondary, size: 24))),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        fav.title.isNotEmpty ? fav.title : '未知标题',
                        style: TextStyle(
                          color: context.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    SizedBox(height: 6),
                    Row(
                      children: [
                        if (fav.releaseDate != null && fav.releaseDate!.isNotEmpty)
                          Text(
                            fav.releaseDate!.split('-')[0],
                            style: TextStyle(color: context.textSecondary, fontSize: 12),
                          ),
                        if (fav.voteAverage != null && fav.voteAverage! > 0) ...[
                          SizedBox(width: 8),
                          Icon(Icons.star_rounded, color: AppTheme.primary, size: 14),
                          SizedBox(width: 2),
                          Text(
                            fav.voteAverage!.toStringAsFixed(1),
                            style: TextStyle(color: context.textSecondary, fontSize: 12),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Icon(Icons.chevron_left_rounded, color: context.textSecondary.withValues(alpha: 0.5), size: 18),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryPage extends ConsumerWidget {
  const _HistoryPage();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(watchHistoryProvider);
    return Scaffold(backgroundColor: context.bgColor,
      appBar: AppBar(title: Text('观看历史'), backgroundColor: context.bgColor),
      body: history.isEmpty
          ? Center(child: Text('暂无观看历史', style: TextStyle(color: context.textSecondary)))
          : ListView.builder(padding: const EdgeInsets.all(16), itemCount: history.length,
              itemBuilder: (_, i) {
                final h = history[i];
                final t = h['title'] as String? ?? '';
                final p = h['progress'] as double?;
                return Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: context.surfaceColor, borderRadius: BorderRadius.circular(12)),
                  child: Row(children: [Expanded(child: Text(t, style: TextStyle(color: context.textPrimary, fontSize: 15))),
                    if (p != null) Text('${(p * 100).toInt()}%', style: TextStyle(color: context.textPrimary38, fontSize: 12))]));
              }),
    );
  }
}



/// 卡片尺寸三档选择器（小/标准/大），全局生效并持久化
/// 玻璃效果等级三档选择器（高/低/关，全局生效并持久化）
class _GlassLevelSelector extends ConsumerStatefulWidget {
  const _GlassLevelSelector();

  @override
  ConsumerState<_GlassLevelSelector> createState() => _GlassLevelSelectorState();
}

class _GlassLevelSelectorState extends ConsumerState<_GlassLevelSelector> {
  @override
  Widget build(BuildContext context) {
    final current = GlassQuality.current;
    return SegmentedButton<GlassQualityLevel>(
      segments: const [
        ButtonSegment(value: GlassQualityLevel.high, label: Text('高')),
        ButtonSegment(value: GlassQualityLevel.low, label: Text('低')),
        ButtonSegment(value: GlassQualityLevel.off, label: Text('关')),
      ],
      selected: {current},
      onSelectionChanged: (s) {
        GlassQuality.set(s.first);
        setState(() {});
      },
      showSelectedIcon: false,
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12)),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
      ),
    );
  }
}

/// OpenSubtitles 在线字幕配置对话框
class _OpenSubtitlesConfigDialog extends StatefulWidget {
  const _OpenSubtitlesConfigDialog();

  @override
  State<_OpenSubtitlesConfigDialog> createState() => _OpenSubtitlesConfigDialogState();
}

class _OpenSubtitlesConfigDialogState extends State<_OpenSubtitlesConfigDialog> {
  final _apiKeyController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _testing = false;
  String? _status;
  bool _statusOk = false;

  @override
  void initState() {
    super.initState();
    _apiKeyController.text = OpenSubtitlesService.apiKey ?? '';
    _usernameController.text = OpenSubtitlesService.username ?? '';
    _passwordController.text = OpenSubtitlesService.password ?? '';
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await OpenSubtitlesService.saveConfig(
      apiKey: _apiKeyController.text.trim(),
      username: _usernameController.text.trim(),
      password: _passwordController.text,
    );
    if (mounted) Navigator.pop(context);
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _status = null;
    });
    // 先保存再测试，保证测试用的是当前输入
    await OpenSubtitlesService.saveConfig(
      apiKey: _apiKeyController.text.trim(),
      username: _usernameController.text.trim(),
      password: _passwordController.text,
    );
    final token = await OpenSubtitlesService().login();
    if (!mounted) return;
    setState(() {
      _testing = false;
      _status = token != null ? '连接成功，可以搜索下载字幕' : '连接失败：请检查账号/密码/API Key';
      _statusOk = token != null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: context.surfaceColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.subtitles_rounded, color: AppTheme.primary, size: 24),
          ),
          const SizedBox(width: 12),
          Text('配置 OpenSubtitles', style: TextStyle(color: context.textPrimary)),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('免费注册于 opensubtitles.com，API Key 在「Account → Developers」页面生成。',
                style: TextStyle(color: context.textPrimary38, fontSize: 12)),
            const SizedBox(height: 16),
            _field('API Key', _apiKeyController, obscure: false),
            const SizedBox(height: 12),
            _field('用户名', _usernameController, obscure: false),
            const SizedBox(height: 12),
            _field('密码', _passwordController, obscure: _obscurePassword, onObscureToggle: () => setState(() => _obscurePassword = !_obscurePassword)),
            const SizedBox(height: 8),
            Text('字幕搜索入口在播放器的「更多」菜单 →「在线搜索字幕」，或字幕样式面板。',
                style: TextStyle(color: context.textPrimary38, fontSize: 12)),
            if (_status != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(_statusOk ? Icons.check_circle_rounded : Icons.error_rounded,
                      color: _statusOk ? const Color(0xFF10B981) : AppTheme.error, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_status!, style: TextStyle(color: _statusOk ? const Color(0xFF10B981) : AppTheme.error, fontSize: 13))),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _testing ? null : _test,
          child: Text(_testing ? '测试中…' : '测试连接', style: const TextStyle(color: AppTheme.primary)),
        ),
        TextButton(
          onPressed: _testing ? null : () {
            OpenSubtitlesService.clearCredentials();
            if (mounted) Navigator.pop(context);
          },
          child: Text('清除账号', style: TextStyle(color: AppTheme.error)),
        ),
        TextButton(
          onPressed: _testing ? null : _save,
          child: const Text('保存', style: TextStyle(color: AppTheme.primary)),
        ),
      ],
    );
  }

  Widget _field(String label, TextEditingController controller, {required bool obscure, VoidCallback? onObscureToggle}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: context.textPrimary38, fontSize: 12)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          obscureText: obscure,
          style: TextStyle(color: context.textPrimary),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: context.cardColor,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
            suffixIcon: onObscureToggle != null
                ? IconButton(icon: Icon(obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded, size: 18), onPressed: onObscureToggle)
                : null,
          ),
        ),
      ],
    );
  }
}

class _CardSizeSelector extends ConsumerStatefulWidget {
  const _CardSizeSelector();

  @override
  ConsumerState<_CardSizeSelector> createState() => _CardSizeSelectorState();
}

class _CardSizeSelectorState extends ConsumerState<_CardSizeSelector> {
  static const _key = 'card_size_scale';

  @override
  void initState() {
    super.initState();
    final saved = StorageService.getDouble(_key);
    if (saved != null) ScreenAdapter.cardScale = saved;
  }

  void _set(double scale) {
    ScreenAdapter.cardScale = scale;
    StorageService.setDouble(_key, scale);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final current = ScreenAdapter.cardScale;
    return SegmentedButton<double>(
      segments: const [
        ButtonSegment(value: 0.85, label: Text('小')),
        ButtonSegment(value: 1.0, label: Text('标准')),
        ButtonSegment(value: 1.15, label: Text('大')),
      ],
      selected: {current},
      onSelectionChanged: (s) => _set(s.first),
      showSelectedIcon: false,
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12)),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
      ),
    );
  }
}
