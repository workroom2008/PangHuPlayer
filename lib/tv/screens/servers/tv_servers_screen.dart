import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../../models/media_models.dart';
import '../../../services/media_server_service.dart';
import '../../../providers/app_providers.dart';
import '../../../utils/app_log.dart';
import '../../widgets/focusable_widgets.dart';
import '../../widgets/tv_text_field.dart';
import '../../../widgets/server_icons.dart';
import '../../services/tv_pairing_server.dart';

class TvServersScreen extends ConsumerStatefulWidget {
  const TvServersScreen({super.key});

  @override
  ConsumerState<TvServersScreen> createState() => _TvServersScreenState();
}

class _TvServersScreenState extends ConsumerState<TvServersScreen> {
  @override
  Widget build(BuildContext context) {
    final servers = ref.watch(mediaServersProvider);

    return Theme(
      data: Theme.of(context).copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0A0A),
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A0A),
        body: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: servers.isEmpty ? _buildEmptyState() : _buildServerList(servers),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 64),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.8),
            Colors.transparent,
          ],
        ),
      ),
      child: Row(
        children: [
          const Text(
            '媒体服务器',
            style: TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w800,
            ),
          ),
          const Spacer(),
          FocusableCard(
            focusId: 'qr_pair',
            onTap: () => _showQrPairingDialog(),
            borderRadius: 8,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.qr_code_rounded, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text(
                  '扫码配置',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          FocusableCard(
            focusId: 'add_server',
            onTap: () => _showAddServerDialog(),
            borderRadius: 8,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add_rounded, color: Colors.black, size: 20),
                SizedBox(width: 8),
                Text(
                  '添加服务器',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            padding: const EdgeInsets.all(32),
            decoration: const BoxDecoration(
              color: Color(0xFF1E1E3A),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.dns_rounded, color: Colors.white38, size: 56),
          ),
          const SizedBox(height: 24),
          const Text(
            '暂无服务器',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '添加 Emby、Jellyfin 或飞牛影视服务器',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 32),
          FocusableCard(
            focusId: 'add_server_empty',
            onTap: () => _showAddServerDialog(),
            autoFocus: true,
            borderRadius: 8,
            padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add_rounded, color: Colors.black, size: 22),
                SizedBox(width: 10),
                Text(
                  '添加新服务器',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServerList(List<MediaServer> servers) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 64, vertical: 24),
      child: Column(
        children: servers.map((server) => _ServerCard(
          server: server,
          onDelete: () => _deleteServer(server.id),
          onEdit: () => _editServer(server),
          onSetDefault: () => _setDefaultServer(server.id),
        )).toList(),
      ),
    );
  }

  void _showAddServerDialog({MediaServer? existingServer}) {
    showDialog(
      context: context,
      builder: (_) => _AddServerDialog(
        existingServer: existingServer,
        onSave: (server) async {
          if (existingServer != null) {
            await ref.read(mediaServersProvider.notifier).updateServer(server);
          } else {
            await ref.read(mediaServersProvider.notifier).addServer(server);
          }
        },
      ),
    );
  }

  /// 显示二维码扫码配置对话框
  /// 在 TV 端启动 HTTP 服务器，手机扫码后通过浏览器填写并提交表单
  void _showQrPairingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _QrPairingDialog(),
    );
  }

  void _deleteServer(String id) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E3A),
        title: const Text('删除服务器', style: TextStyle(color: Colors.white)),
        content: const Text('确定要删除此服务器吗？', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () {
              ref.read(mediaServersProvider.notifier).removeServer(id);
              Navigator.pop(context);
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _editServer(MediaServer server) {
    _showAddServerDialog(existingServer: server);
  }

  void _setDefaultServer(String id) {
    ref.read(mediaServersProvider.notifier).setDefaultServer(id);
  }
}

class _ServerCard extends StatefulWidget {
  final MediaServer server;
  final VoidCallback onDelete;
  final VoidCallback onEdit;
  final VoidCallback onSetDefault;

  const _ServerCard({
    required this.server,
    required this.onDelete,
    required this.onEdit,
    required this.onSetDefault,
  });

  @override
  State<_ServerCard> createState() => _ServerCardState();
}

class _ServerCardState extends State<_ServerCard> {
  late FocusNode _focusNode;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: 'server_${widget.server.id}');
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (mounted) setState(() => _isFocused = _focusNode.hasFocus);
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.gameButtonA)) {
          widget.onEdit();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onEdit,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E3A),
            borderRadius: BorderRadius.circular(12),
            border: widget.server.isDefault
                ? Border.all(color: Colors.white, width: 3)
                : Border.all(color: _isFocused ? Colors.white38 : Colors.transparent, width: 2),
            boxShadow: _isFocused
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 16,
                      spreadRadius: 2,
                    ),
                  ]
                : [],
          ),
          child: Row(
            children: [
              Container(
                width: 64,
                height: 64,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _getTypeColor(widget.server.type).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ServerIcons.forType(widget.server.type.name, size: 36),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          widget.server.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (widget.server.isDefault) ...[
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              '默认',
                              style: TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.server.url,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: widget.server.isConnected
                                ? const Color(0xFF10B981).withValues(alpha: 0.15)
                                : const Color(0xFFEF4444).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            widget.server.isConnected ? '已连接' : '未连接',
                            style: TextStyle(
                              color: widget.server.isConnected ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.white10,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _getTypeName(widget.server.type),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              _buildActionButtons(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        _ActionButton(
          icon: Icons.edit_rounded,
          focusId: 'edit_${widget.server.id}',
          onTap: widget.onEdit,
          label: '编辑',
        ),
        const SizedBox(width: 8),
        if (!widget.server.isDefault)
          _ActionButton(
            icon: Icons.star_rounded,
            focusId: 'default_${widget.server.id}',
            onTap: widget.onSetDefault,
            label: '设为默认',
          ),
        const SizedBox(width: 8),
        _ActionButton(
          icon: Icons.delete_rounded,
          focusId: 'delete_${widget.server.id}',
          onTap: widget.onDelete,
          label: '删除',
          danger: true,
        ),
      ],
    );
  }

  Color _getTypeColor(ServerType type) {
    switch (type) {
      case ServerType.emby:
        return const Color(0xFF339AF0);
      case ServerType.jellyfin:
        return const Color(0xFF00A4DC);
      case ServerType.fnos:
        return const Color(0xFF10B981);
      case ServerType.plex:
        return const Color(0xFFE5A00D);
      default:
        return Colors.white70;
    }
  }

  IconData _getTypeIcon(ServerType type) {
    switch (type) {
      case ServerType.emby:
      case ServerType.jellyfin:
        return Icons.movie_rounded;
      case ServerType.fnos:
        return Icons.video_library_rounded;
      case ServerType.plex:
        return Icons.play_circle_rounded;
      default:
        return Icons.dns_rounded;
    }
  }

  String _getTypeName(ServerType type) {
    switch (type) {
      case ServerType.emby:
        return 'Emby';
      case ServerType.jellyfin:
        return 'Jellyfin';
      case ServerType.fnos:
        return '飞牛影视';
      case ServerType.plex:
        return 'Plex';
      default:
        return '未知';
    }
  }
}

class _ActionButton extends StatefulWidget {
  final IconData icon;
  final String focusId;
  final VoidCallback onTap;
  final String label;
  final bool danger;

  const _ActionButton({
    required this.icon,
    required this.focusId,
    required this.onTap,
    required this.label,
    this.danger = false,
  });

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  late FocusNode _focusNode;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: widget.focusId);
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (mounted) setState(() => _isFocused = _focusNode.hasFocus);
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.danger ? const Color(0xFFEF4444) : Colors.white70;
    final focusColor = widget.danger ? const Color(0xFFEF4444) : Colors.white;

    return Focus(
      focusNode: _focusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.gameButtonA)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: _isFocused ? color.withValues(alpha: 0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _isFocused ? focusColor : Colors.transparent,
              width: 2,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, color: _isFocused ? focusColor : color, size: 20),
              const SizedBox(height: 4),
              Text(
                widget.label,
                style: TextStyle(
                  color: _isFocused ? focusColor : color,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddServerDialog extends StatefulWidget {
  final MediaServer? existingServer;
  final Function(MediaServer) onSave;

  const _AddServerDialog({
    this.existingServer,
    required this.onSave,
  });

  @override
  State<_AddServerDialog> createState() => _AddServerDialogState();
}

class _AddServerDialogState extends State<_AddServerDialog> {
  final _nameController = TextEditingController();
  final _urlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isConnected = false;
  ServerType _selectedType = ServerType.emby;

  @override
  void initState() {
    super.initState();
    if (widget.existingServer != null) {
      _nameController.text = widget.existingServer!.name;
      _urlController.text = widget.existingServer!.url;
      _usernameController.text = widget.existingServer!.username ?? '';
      _passwordController.text = widget.existingServer!.password ?? '';
      _isConnected = widget.existingServer!.isConnected;
      _selectedType = widget.existingServer!.type;
    }
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
    return Dialog(
      backgroundColor: const Color(0xFF1E1E3A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: FocusScope(
        child: Container(
          width: 600,
          constraints: const BoxConstraints(maxHeight: 600),
          padding: const EdgeInsets.all(28),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.existingServer != null ? '编辑服务器' : '添加服务器',
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 20),
                _buildTypeSelector(),
                const SizedBox(height: 20),
                TvTextField(
                  controller: _nameController,
                  label: '服务器名称',
                  focusId: 'dlg_field_name',
                  hintText: '例如：我的媒体库',
                  autoFocus: true,
                ),
                const SizedBox(height: 14),
                TvTextField(
                  controller: _urlController,
                  label: '服务器地址',
                  focusId: 'dlg_field_url',
                  hintText: 'http://192.168.1.1:8096',
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 14),
                TvTextField(
                  controller: _usernameController,
                  label: '用户名',
                  focusId: 'dlg_field_username',
                ),
                const SizedBox(height: 14),
                TvTextField(
                  controller: _passwordController,
                  label: '密码',
                  focusId: 'dlg_field_password',
                  obscureText: true,
                ),
                const SizedBox(height: 24),
                _buildTestButton(),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _DialogButton(
                      label: '取消',
                      onTap: () => Navigator.pop(context),
                      secondary: true,
                    ),
                    const SizedBox(width: 12),
                    _DialogButton(
                      label: '保存',
                      onTap: _isLoading ? null : _saveServer,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTypeSelector() {
    final types = [
      (ServerType.emby, 'Emby', '功能丰富，可自部署'),
      (ServerType.jellyfin, 'Jellyfin', '免费开源，无会员限制'),
      (ServerType.fnos, '飞牛影视', '飞牛NAS自带影视管理'),
    ];
    return Row(
      children: types.map((t) {
        final isSelected = _selectedType == t.$1;
        final color = ServerIcons.colorForType(t.$1.name);
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              right: t.$1 == types.last.$1 ? 0 : 8,
            ),
            child: FocusableCard(
              focusId: 'type_${t.$1.name}',
              onTap: () => setState(() => _selectedType = t.$1),
              borderRadius: 10,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: isSelected ? color.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected ? color : Colors.white12,
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ServerIcons.forType(t.$1.name, size: 36),
                  const SizedBox(height: 10),
                  Text(
                    t.$2,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.white70,
                      fontSize: 14,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    t.$3,
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTestButton() {
    return FocusableCard(
      focusId: 'test_connection',
      onTap: _isLoading ? null : _testConnection,
      borderRadius: 8,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: BoxDecoration(
        color: _isConnected ? const Color(0xFF10B981) : const Color(0xFF6366F1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_isLoading)
            const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          else
            Icon(_isConnected ? Icons.check_rounded : Icons.wifi_find_rounded, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Text(
            _isConnected ? '已连接' : '测试连接',
            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Future<void> _testConnection() async {
    setState(() => _isLoading = true);
    final url = _fixUrl(_urlController.text);
    final svc = _createService(url);
    final ok = await svc?.testConnection() ?? false;
    setState(() { _isLoading = false; _isConnected = ok; });
  }

  MediaServerService? _createService(String url) {
    final username = _usernameController.text;
    final password = _passwordController.text;
    switch (_selectedType) {
      case ServerType.emby:
        return EmbyService(
          baseUrl: url,
          username: username.isNotEmpty ? username : null,
          password: password.isNotEmpty ? password : null,
        );
      case ServerType.jellyfin:
        return JellyfinService(
          baseUrl: url,
          username: username.isNotEmpty ? username : null,
          password: password.isNotEmpty ? password : null,
        );
      case ServerType.fnos:
        return FnOSService(
          baseUrl: url,
          username: username,
          password: password,
        );
      default:
        return null;
    }
  }

  String _fixUrl(String u) {
    u = u.trim();
    u = u.replaceFirst(RegExp(r'^https?://'), '');
    if (!u.startsWith('http://') && !u.startsWith('https://')) {
      u = 'http://$u';
    }
    while (u.endsWith('/')) { u = u.substring(0, u.length - 1); }
    return u;
  }

  Future<void> _saveServer() async {
    final url = _fixUrl(_urlController.text);
    final type = _selectedType;
    
    final server = MediaServer(
      id: widget.existingServer?.id ?? const Uuid().v4(),
      name: _nameController.text.isNotEmpty ? _nameController.text : url.replaceFirst(RegExp(r'^https?://'), '').split(':')[0],
      url: url,
      apiKey: null,
      username: _usernameController.text.isNotEmpty ? _usernameController.text : null,
      password: _passwordController.text.isNotEmpty ? _passwordController.text : null,
      type: type,
      isConnected: _isConnected,
      isDefault: widget.existingServer?.isDefault ?? false,
    );

    await widget.onSave(server);
    if (mounted) Navigator.pop(context);
  }
}

class _DialogButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool secondary;

  const _DialogButton({
    required this.label,
    this.onTap,
    this.secondary = false,
  });

  @override
  Widget build(BuildContext context) {
    return FocusableCard(
      focusId: 'dialog_$label',
      onTap: onTap,
      borderRadius: 8,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: secondary ? Colors.transparent : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: secondary ? Border.all(color: Colors.white38, width: 1) : null,
      ),
      child: Text(
        label,
        style: TextStyle(
          color: secondary ? Colors.white70 : Colors.black,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 二维码扫码配对对话框
///
/// 启动 HTTP 服务器并显示二维码，用户用手机扫码后在浏览器填写表单提交，
/// TV 端实时接收配置并保存到本地数据库，然后自动关闭对话框。
class _QrPairingDialog extends ConsumerStatefulWidget {
  const _QrPairingDialog();

  @override
  ConsumerState<_QrPairingDialog> createState() => _QrPairingDialogState();
}

class _QrPairingDialogState extends ConsumerState<_QrPairingDialog> {
  final TvPairingServer _pairingServer = TvPairingServer();
  StreamSubscription<PairingServerConfig>? _sub;
  String? _pairingUrl;
  String? _error;
  bool _saving = false;
  String? _savedMessage;

  @override
  void initState() {
    super.initState();
    _startPairing();
  }

  Future<void> _startPairing() async {
    try {
      final url = await _pairingServer.start();
      if (!mounted) return;
      setState(() {
        _pairingUrl = url;
        _error = url == null ? '无法获取 TV 端局域网 IP，请确保已连接 WiFi/有线网络' : null;
      });
      // 监听手机提交的配置
      _sub = _pairingServer.onConfigReceived.listen(_onConfigReceived);
    } catch (e) {
      AppLog.e('TvPair', '启动配对服务器失败', e);
      if (!mounted) return;
      setState(() => _error = '启动配对服务失败: $e');
    }
  }

  Future<void> _onConfigReceived(PairingServerConfig config) async {
    if (!mounted || _saving) return;
    setState(() => _saving = true);

    try {
      // 优先使用用户选择的类型，否则自动检测
      final type = _parseServerType(config.serverType) ?? _detectServerType(config.url);
      final server = MediaServer(
        id: const Uuid().v4(),
        name: config.name.isNotEmpty
            ? config.name
            : config.url.replaceFirst(RegExp(r'^https?://'), '').split(':').first,
        url: _fixUrl(config.url),
        apiKey: null,
        username: config.username.isNotEmpty ? config.username : null,
        password: config.password.isNotEmpty ? config.password : null,
        type: type,
        isConnected: false,
        isDefault: false,
      );
      await ref.read(mediaServersProvider.notifier).addServer(server);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _savedMessage = '已添加服务器：${server.name}';
      });
      // 2 秒后关闭对话框
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      AppLog.e('TvPair', '保存服务器配置失败', e);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '保存失败: $e';
      });
    }
  }

  ServerType? _parseServerType(String? typeStr) {
    if (typeStr == null || typeStr.isEmpty) return null;
    switch (typeStr.toLowerCase()) {
      case 'emby':
        return ServerType.emby;
      case 'jellyfin':
        return ServerType.jellyfin;
      case 'fnos':
        return ServerType.fnos;
      default:
        return null;
    }
  }

  String _fixUrl(String u) {
    u = u.trim();
    u = u.replaceFirst(RegExp(r'^https?://'), '');
    if (!u.startsWith('http://') && !u.startsWith('https://')) {
      u = 'http://$u';
    }
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  ServerType _detectServerType(String url) {
    if (url.contains('fnos') || url.contains('feiniu') || url.contains('飞牛')) {
      return ServerType.fnos;
    }
    if (url.contains('jellyfin')) {
      return ServerType.jellyfin;
    }
    return ServerType.emby;
  }

  @override
  void dispose() {
    _sub?.cancel();
    _pairingServer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E3A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.qr_code_rounded, color: Color(0xFF10B981), size: 24),
          SizedBox(width: 10),
          Text(
            '扫码配置',
            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
          ),
        ],
      ),
      contentPadding: const EdgeInsets.all(32),
      content: SizedBox(
        width: 480,
        child: _buildContent(),
      ),
      actions: [
        _DialogButton(
          label: _saving ? '保存中...' : '关闭',
          onTap: _saving ? null : () => Navigator.pop(context),
        ),
      ],
    );
  }

  Widget _buildContent() {
    if (_error != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFEF4444), size: 48),
          const SizedBox(height: 16),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 16),
          FocusableCard(
            focusId: 'retry_pair',
            onTap: () {
              setState(() => _error = null);
              _startPairing();
            },
            borderRadius: 8,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              '重试',
              style: TextStyle(color: Colors.black, fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      );
    }

    if (_savedMessage != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 64),
          const SizedBox(height: 16),
          Text(
            _savedMessage!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            '即将关闭...',
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
        ],
      );
    }

    if (_pairingUrl == null) {
      return const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: 40, height: 40, child: CircularProgressIndicator(color: Colors.white)),
          SizedBox(height: 16),
          Text('正在启动配对服务...', style: TextStyle(color: Colors.white70)),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '使用手机扫描下方二维码',
          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          '在手机浏览器中填写服务器信息并提交',
          style: const TextStyle(color: Colors.white54, fontSize: 13),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: QrImageView(
            data: _pairingUrl!,
            version: QrVersions.auto,
            size: 240,
            backgroundColor: Colors.white,
          ),
        ),
        const SizedBox(height: 16),
        // 同时显示 URL 作为备用方案
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            _pairingUrl!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
        if (_saving) ...[
          const SizedBox(height: 16),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Color(0xFF10B981), strokeWidth: 2)),
              SizedBox(width: 8),
              Text('正在保存配置...', style: TextStyle(color: Colors.white70, fontSize: 13)),
            ],
          ),
        ],
      ],
    );
  }
}
