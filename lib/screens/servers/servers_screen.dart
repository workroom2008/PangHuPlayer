import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:uuid/uuid.dart';
import 'package:go_router/go_router.dart';
import '../../theme/app_theme.dart';
import '../../models/media_models.dart';
import '../../services/media_server_service.dart';
import '../../providers/app_providers.dart';
import '../../widgets/server_icons.dart';
import 'media_library_screen.dart';

class ServersScreen extends ConsumerStatefulWidget {
  ServersScreen({super.key});

  @override
  ConsumerState<ServersScreen> createState() => _ServersScreenState();
}

class _ServersScreenState extends ConsumerState<ServersScreen> {
  @override
  Widget build(BuildContext context) {
    final servers = ref.watch(mediaServersProvider);

    return Scaffold(
      backgroundColor: context.bgColor,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 120,
            pinned: true,
            backgroundColor: context.bgColor,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                '媒体服务器',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: context.textPrimary,
                ),
              ),
              titlePadding: EdgeInsets.only(left: 16, bottom: 16),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: _buildAppBarAddButton(),
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  if (servers.isEmpty)
                    _buildEmptyState()
                  else
                    ...servers.map((server) => _ServerCard(
                      server: server,
                      onDelete: () => _deleteServer(server.id),
                      onEdit: () => _editServer(server),
                      onSetDefault: () => _setDefaultServer(server.id),
                      onTap: () => _openServerMedia(server),
                    )),
                  SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBarAddButton() {
    return PopupMenuButton<ServerType>(
      color: context.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      offset: const Offset(0, 8),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: ServerType.emby,
          child: Row(children: [
            ServerIcons.forType('emby', size: 24),
            SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(ServerIcons.nameForType('emby'), style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.w600)),
              Text(ServerIcons.descForType('emby'), style: TextStyle(color: context.textSecondary, fontSize: 11)),
            ]),
          ]),
        ),
        PopupMenuItem(
          value: ServerType.jellyfin,
          child: Row(children: [
            ServerIcons.forType('jellyfin', size: 24),
            SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(ServerIcons.nameForType('jellyfin'), style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.w600)),
              Text(ServerIcons.descForType('jellyfin'), style: TextStyle(color: context.textSecondary, fontSize: 11)),
            ]),
          ]),
        ),
        PopupMenuItem(
          value: ServerType.fnos,
          child: Row(children: [
            ServerIcons.forType('fnos', size: 24),
            SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(ServerIcons.nameForType('fnos'), style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.w600)),
              Text(ServerIcons.descForType('fnos'), style: TextStyle(color: context.textSecondary, fontSize: 11)),
            ]),
          ]),
        ),
      ],
      onSelected: (type) => context.push('/add-server', extra: {'type': type}),
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: 0.12),
          shape: BoxShape.circle,
          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
        ),
        child: Icon(Icons.add_rounded, color: AppTheme.primary, size: 20),
      ),
    ).animate().fadeIn();
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: context.surfaceColor,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.dns_rounded, color: context.textSecondary, size: 48),
          ),
          SizedBox(height: 24),
          Text(
            '暂无服务器',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: context.textPrimary,
            ),
          ),
          SizedBox(height: 8),
          Text(
            '添加Emby、Jellyfin或飞牛影视服务器',
            style: TextStyle(
              fontSize: 14,
              color: context.textSecondary,
            ),
          ),
        ],
      ),
    ).animate().fadeIn();
  }

  void _editServer(MediaServer server) {
    showDialog(
      context: context,
      builder: (_) => EditServerDialog(
        existingServer: server,
        onSave: (updatedServer) async {
          // 清除旧缓存，确保重新创建 service 时使用新的认证信息
          clearServiceCache(server.id);
          await ref.read(mediaServersProvider.notifier).updateServer(updatedServer);
        },
      ),
    );
  }

  void _deleteServer(String id) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: context.surfaceColor,
        title: Text('删除服务器', style: TextStyle(color: context.textPrimary)),
        content: Text('确定要删除此服务器吗？', style: TextStyle(color: context.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消', style: TextStyle(color: context.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              ref.read(mediaServersProvider.notifier).removeServer(id);
              Navigator.pop(context);
            },
            child: Text('删除', style: TextStyle(color: AppTheme.error)),
          ),
        ],
      ),
    );
  }

  void _setDefaultServer(String id) {
    ref.read(mediaServersProvider.notifier).setDefaultServer(id);
  }

  void _openServerMedia(MediaServer server) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => MediaLibraryScreen(server: server),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.1, 0),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              )),
              child: child,
            ),
          );
        },
      ),
    );
  }
}

class _ServerCard extends StatelessWidget {
  final MediaServer server;
  final VoidCallback onDelete;
  final VoidCallback onEdit;
  final VoidCallback onSetDefault;
  final VoidCallback onTap;

  _ServerCard({
    required this.server,
    required this.onDelete,
    required this.onEdit,
    required this.onSetDefault,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: server.isDefault
            ? Border.all(color: AppTheme.primary, width: 2)
            : null,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: ServerIcons.colorForType(server.type.name).withValues(alpha:0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: ServerIcons.forType(server.type.name, size: 28),
          ),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      server.name,
                      style: TextStyle(
                        color: context.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (server.isDefault) ...[
                      SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.primary,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '默认',
                          style: TextStyle(color: context.textPrimary, fontSize: 10),
                        ),
                      ),
                    ],
                  ],
                ),
                SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: server.isConnected
                            ? AppTheme.success.withValues(alpha:0.1)
                            : AppTheme.error.withValues(alpha:0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        server.isConnected ? '已连接' : '未连接',
                        style: TextStyle(
                          color: server.isConnected ? AppTheme.success : AppTheme.error,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert_rounded, color: context.textSecondary),
            color: context.cardColor,
            onSelected: (value) {
              switch (value) {
                case 'edit':
                  onEdit();
                  break;
                case 'default':
                  onSetDefault();
                  break;
                case 'delete':
                  onDelete();
                  break;
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'edit',
                child: Text('编辑', style: TextStyle(color: context.textPrimary)),
              ),
              PopupMenuItem(
                value: 'default',
                child: Text('设为默认', style: TextStyle(color: context.textPrimary)),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Text('删除', style: TextStyle(color: AppTheme.error)),
              ),
            ],
          ),
        ],
      ),
    ),
  ).animate().fadeIn().slideX(begin: 0.1);
  }

  }

class EditServerDialog extends StatefulWidget {
  final MediaServer existingServer;
  final Function(MediaServer) onSave;

  EditServerDialog({
    required this.existingServer,
    required this.onSave,
  });

  @override
  State<EditServerDialog> createState() => EditServerDialogState();
}

class EditServerDialogState extends State<EditServerDialog> {
  final _nameController = TextEditingController();
  final _urlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  ServerType _selectedType = ServerType.emby;
  bool _isLoading = false;
  bool _isConnected = false;
  bool _useHttps = false;

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.existingServer.name;
    _urlController.text = widget.existingServer.url;
    _useHttps = widget.existingServer.url.startsWith('https://');
    _selectedType = widget.existingServer.type;
    _usernameController.text = widget.existingServer.username ?? '';
    _passwordController.text = widget.existingServer.password ?? '';
    _isConnected = widget.existingServer.isConnected;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: context.surfaceColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('编辑服务器', style: TextStyle(color: context.textPrimary)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              style: TextStyle(color: context.textPrimary),
              decoration: InputDecoration(
                labelText: '服务器名称',
                labelStyle: TextStyle(color: context.textSecondary),
              ),
            ),
            SizedBox(height: 12),
            TextField(
              controller: _urlController,
              style: TextStyle(color: context.textPrimary),
              decoration: InputDecoration(
                labelText: '服务器地址',
                labelStyle: TextStyle(color: context.textSecondary),
              ),
            ),
            SizedBox(height: 6),
            Row(children: [
              Text('HTTPS', style: TextStyle(color: context.textSecondary, fontSize: 14)),
              Switch(value: _useHttps, onChanged: (v) => setState(() => _useHttps = v), activeThumbColor: AppTheme.primary),
            ]),
            SizedBox(height: 6),
            TextField(
              controller: _usernameController,
              style: TextStyle(color: context.textPrimary),
              decoration: InputDecoration(labelText: '用户名', labelStyle: TextStyle(color: context.textSecondary)),
            ),
            SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              style: TextStyle(color: context.textPrimary),
              decoration: InputDecoration(labelText: '密码', labelStyle: TextStyle(color: context.textSecondary)),
              obscureText: true,
            ),
            SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _testConnection,
              style: ElevatedButton.styleFrom(backgroundColor: _isConnected ? AppTheme.success : AppTheme.primary),
              icon: _isLoading
                  ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(_isConnected ? Icons.check_rounded : Icons.wifi_find_rounded, color: context.textPrimary),
              label: Text(_isConnected ? '已连接' : '测试连接', style: TextStyle(color: context.textPrimary)),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text('取消', style: TextStyle(color: context.textSecondary))),
        ElevatedButton(onPressed: _isLoading ? null : _saveServer, style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary), child: Text('保存', style: TextStyle(color: context.textPrimary))),
      ],
    );
  }

  MediaServerService? _testedService;

  Future<void> _testConnection() async {
    setState(() => _isLoading = true);
    final url = _fixUrl(_urlController.text);
    MediaServerService? svc;
    switch (_selectedType) {
      case ServerType.emby:
        svc = EmbyService(baseUrl: url, username: _usernameController.text, password: _passwordController.text);
        break;
      case ServerType.jellyfin:
        svc = JellyfinService(baseUrl: url, username: _usernameController.text, password: _passwordController.text);
        break;
      case ServerType.fnos:
        svc = FnOSService(baseUrl: url, username: _usernameController.text, password: _passwordController.text);
        break;
      default:
        svc = EmbyService(baseUrl: url, username: _usernameController.text, password: _passwordController.text);
    }
    final ok = await svc.testConnection();
    if (ok) _testedService = svc;
    setState(() { _isLoading = false; _isConnected = ok; });
  }

  String _fixUrl(String u) {
    u = u.trim();
    u = u.replaceFirst(RegExp(r'^https?://'), '');
    u = '${_useHttps ? "https" : "http"}://$u';
    while (u.endsWith('/')) u = u.substring(0, u.length - 1);
    return u;
  }

  Future<void> _saveServer() async {
    // 从测试成功的 service 获取认证信息
    String? apiKey;
    String? userId;
    if (_testedService != null) {
      final authInfo = _testedService!.getAuthInfo();
      apiKey = authInfo['apiKey'];
      userId = authInfo['userId'];
    }
    final server = MediaServer(
      id: widget.existingServer.id,
      name: _nameController.text,
      url: _fixUrl(_urlController.text),
      apiKey: apiKey,
      username: _usernameController.text.isNotEmpty ? _usernameController.text : null,
      password: _passwordController.text.isNotEmpty ? _passwordController.text : null,
      type: _selectedType,
      isConnected: _isConnected,
      isDefault: widget.existingServer.isDefault,
    );
    await widget.onSave(server);
    if (mounted) Navigator.pop(context);
  }
}

class ServersPage extends ServersScreen {
  ServersPage({super.key});
}

