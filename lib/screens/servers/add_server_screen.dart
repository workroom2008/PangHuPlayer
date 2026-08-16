import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../theme/app_theme.dart';
import '../../models/media_models.dart';
import '../../services/media_server_service.dart';
import '../../providers/app_providers.dart';
import '../../widgets/server_icons.dart';

class AddServerScreen extends ConsumerStatefulWidget {
  final ServerType? initialType;

  const AddServerScreen({super.key, this.initialType});

  @override
  ConsumerState<AddServerScreen> createState() => _AddServerScreenState();
}

class _AddServerScreenState extends ConsumerState<AddServerScreen> {
  final _nameController = TextEditingController();
  final _urlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  late ServerType _selectedType;
  bool _isLoading = false;
  bool _isConnected = false;
  bool _useHttps = false;

  @override
  void initState() {
    super.initState();
    _selectedType = widget.initialType ?? ServerType.emby;
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
    return Scaffold(
      backgroundColor: context.bgColor,
      appBar: AppBar(
        backgroundColor: context.bgColor,
        title: Text('添加服务器', style: TextStyle(color: context.textPrimary)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: context.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildServerTypeSelector(),
            SizedBox(height: 24),
            _buildInputFields(),
            SizedBox(height: 24),
            _buildTestConnectionButton(),
            SizedBox(height: 24),
            _buildSaveButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildServerTypeSelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('选择服务器类型', style: TextStyle(color: context.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
          SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildTypeOption(ServerType.emby)),
              SizedBox(width: 10),
              Expanded(child: _buildTypeOption(ServerType.jellyfin)),
              SizedBox(width: 10),
              Expanded(child: _buildTypeOption(ServerType.fnos)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTypeOption(ServerType type) {
    final isSelected = _selectedType == type;
    return GestureDetector(
      onTap: () => setState(() => _selectedType = type),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? ServerIcons.colorForType(type.name).withValues(alpha: 0.15)
              : context.cardColor,
          borderRadius: BorderRadius.circular(12),
          border: isSelected
              ? Border.all(color: ServerIcons.colorForType(type.name), width: 2)
              : null,
        ),
        child: Column(
          children: [
            ServerIcons.forType(type.name, size: 32),
            SizedBox(height: 8),
            Text(ServerIcons.nameForType(type.name), style: TextStyle(color: context.textPrimary, fontSize: 13, fontWeight: FontWeight.w500)),
            SizedBox(height: 4),
            Text(ServerIcons.descForType(type.name), style: TextStyle(color: context.textPrimary38, fontSize: 10), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildInputFields() {
    return Column(
      children: [
        _buildTextField('服务器名称', _nameController, hintText: '例如：家庭媒体库'),
        SizedBox(height: 14),
        _buildTextField('服务器地址', _urlController, hintText: _selectedType == ServerType.fnos ? 'http://192.168.1.1:8005' : 'http://192.168.1.1:8096'),
        SizedBox(height: 10),
        Row(
          children: [
            Text('使用 HTTPS', style: TextStyle(color: context.textSecondary, fontSize: 14)),
            Spacer(),
            Switch(
              value: _useHttps,
              onChanged: (v) => setState(() => _useHttps = v),
              activeThumbColor: AppTheme.primary,
            ),
          ],
        ),
        SizedBox(height: 14),
        _buildTextField('用户名', _usernameController),
        SizedBox(height: 14),
        _buildTextField('密码', _passwordController, obscureText: true),
      ],
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, {String? hintText, bool obscureText = false}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        style: TextStyle(color: context.textPrimary),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: context.textSecondary),
          hintText: hintText,
          hintStyle: TextStyle(color: context.textPrimary38),
          border: InputBorder.none,
        ),
      ),
    );
  }

  Widget _buildTestConnectionButton() {
    return ElevatedButton.icon(
      onPressed: _isLoading ? null : _testConnection,
      style: ElevatedButton.styleFrom(
        backgroundColor: _isConnected ? AppTheme.success : AppTheme.primary,
        foregroundColor: context.textPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      icon: _isLoading
          ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(_isConnected ? Icons.check_circle_rounded : Icons.wifi_find_rounded, size: 22),
      label: Text(_isConnected ? '连接成功' : '测试连接', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildSaveButton() {
    return ElevatedButton(
      onPressed: _isLoading ? null : _saveServer,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppTheme.primary,
        foregroundColor: context.textPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: Text('保存服务器', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
    );
  }

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
    final server = MediaServer(
      id: const Uuid().v4(),
      name: _nameController.text,
      url: _fixUrl(_urlController.text),
      apiKey: null,
      username: _usernameController.text.isNotEmpty ? _usernameController.text : null,
      password: _passwordController.text.isNotEmpty ? _passwordController.text : null,
      type: _selectedType,
      isConnected: _isConnected,
      isDefault: false,
    );

    await ref.read(mediaServersProvider.notifier).addServer(server);
    if (mounted) Navigator.pop(context);
  }
}