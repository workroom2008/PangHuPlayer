import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:uuid/uuid.dart';
import '../../theme/app_theme.dart';
import '../../models/media_models.dart';
import '../../providers/app_providers.dart';

class DanmakuScreen extends ConsumerStatefulWidget {
  DanmakuScreen({super.key});

  @override
  ConsumerState<DanmakuScreen> createState() => _DanmakuScreenState();
}

class _DanmakuScreenState extends ConsumerState<DanmakuScreen> {
  @override
  Widget build(BuildContext context) {
    final configs = ref.watch(danmakuConfigsProvider);
    final display = ref.watch(danmakuDisplayProvider);
    final dn = ref.read(danmakuDisplayProvider.notifier);

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
                '弹幕设置',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: context.textPrimary,
                ),
              ),
              titlePadding: const EdgeInsets.only(left: 16, bottom: 16),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Section 1: 弹幕源 ──
                  _sectionTitle('弹幕源'),
                  const SizedBox(height: 12),
                  _buildServerSection(configs),
                  const SizedBox(height: 24),

                  // ── Section 2: 弹幕过滤 ──
                  _sectionTitle('弹幕过滤'),
                  const SizedBox(height: 12),
                  _buildBlockKeywordsCard(display, dn),
                  const SizedBox(height: 24),

                  // ── Section 3: 字符处理 ──
                  _sectionTitle('字符处理'),
                  const SizedBox(height: 12),
                  _buildCharConversionCard(display, dn),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────── Section Title ───────────────

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: context.textSecondary,
        letterSpacing: 0.5,
      ),
    ).animate().fadeIn();
  }

  // ─────────────── Section 1: 弹幕源 ───────────────

  Widget _buildServerSection(List<DanmakuConfig> configs) {
    return Container(
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          // 服务器列表
          if (configs.isEmpty)
            _buildEmptyServerHint()
          else
            ...configs.asMap().entries.map((entry) {
              final i = entry.key;
              final config = entry.value;
              return _ServerRow(
                config: config,
                isFirst: i == 0,
                isLast: i == configs.length - 1,
                onToggle: (enabled) => _toggleConfig(config, enabled),
                onEdit: () => _showAddBottomSheet(existingConfig: config),
                onDelete: () => _confirmDelete(config),
              );
            }),
          // 添加按钮
          GestureDetector(
            onTap: () => _showAddBottomSheet(),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                border: configs.isNotEmpty
                    ? Border(top: BorderSide(color: context.textSecondary.withValues(alpha: 0.1)))
                    : null,
                borderRadius: configs.isEmpty
                    ? BorderRadius.circular(16)
                    : const BorderRadius.vertical(bottom: Radius.circular(16)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_rounded, color: AppTheme.accent, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    '添加弹幕源',
                    style: TextStyle(
                      color: AppTheme.accent,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn().slideY(begin: 0.05);
  }

  Widget _buildEmptyServerHint() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(Icons.comment_bank_outlined, color: context.textSecondary.withValues(alpha: 0.5), size: 36),
          const SizedBox(height: 8),
          Text(
            '暂无弹幕源，点击下方添加',
            style: TextStyle(color: context.textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }

  // ─────────────── Section 2: 屏蔽关键词 ───────────────

  Widget _buildBlockKeywordsCard(DanmakuDisplaySettings display, DanmakuDisplayNotifier dn) {
    final keywords = display.blockKeywords;
    return Container(
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Icon(Icons.block_rounded, size: 18, color: context.textSecondary),
                const SizedBox(width: 8),
                Text(
                  '屏蔽关键词',
                  style: TextStyle(color: context.textPrimary, fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                Text(
                  '${keywords.length} 条',
                  style: TextStyle(color: context.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          // 关键词标签流
          if (keywords.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: keywords.map((kw) => _KeywordChip(
                  keyword: kw,
                  onRemove: () {
                    final updated = List<String>.from(keywords)..remove(kw);
                    dn.update(display.copyWith(blockKeywords: updated));
                  },
                )).toList(),
              ),
            ),
          // 输入行
          Padding(
            padding: const EdgeInsets.all(12),
            child: _BlockKeywordInput(
              onAdd: (kw) {
                if (kw.isNotEmpty && !keywords.contains(kw)) {
                  final updated = [...keywords, kw];
                  dn.update(display.copyWith(blockKeywords: updated));
                }
              },
            ),
          ),
        ],
      ),
    ).animate().fadeIn();
  }

  // ─────────────── Section 3: 字符转换 ───────────────

  Widget _buildCharConversionCard(DanmakuDisplaySettings display, DanmakuDisplayNotifier dn) {
    const options = [
      ('none', '不转换'),
      ('s2t', '简体 → 繁体'),
      ('t2s', '繁体 → 简体'),
    ];
    final current = options.firstWhere((o) => o.$1 == display.charConversion, orElse: () => options[0]);
    return Container(
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showCharConversionPicker(display, dn),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(Icons.translate_rounded, size: 18, color: context.textSecondary),
              const SizedBox(width: 8),
              Text(
                '简繁转换',
                style: TextStyle(color: context.textPrimary, fontSize: 15),
              ),
              const Spacer(),
              Text(
                current.$2,
                style: TextStyle(color: AppTheme.accent, fontSize: 14),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, color: context.textSecondary, size: 20),
            ],
          ),
        ),
      ),
    ).animate().fadeIn();
  }

  void _showCharConversionPicker(DanmakuDisplaySettings display, DanmakuDisplayNotifier dn) {
    const options = [
      ('none', '不转换'),
      ('s2t', '简体 → 繁体'),
      ('t2s', '繁体 → 简体'),
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: context.surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: context.textSecondary.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('简繁转换', style: TextStyle(color: context.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
              ),
              ...options.map((o) {
                final isSelected = o.$1 == display.charConversion;
                return ListTile(
                  title: Text(
                    o.$2,
                    style: TextStyle(
                      color: isSelected ? AppTheme.accent : context.textPrimary,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  trailing: isSelected
                      ? Icon(Icons.check_rounded, color: AppTheme.accent, size: 20)
                      : null,
                  onTap: () {
                    dn.update(display.copyWith(charConversion: o.$1));
                    Navigator.pop(ctx);
                  },
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────── Actions ───────────────

  void _showAddBottomSheet({DanmakuConfig? existingConfig}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _AddDanmakuSheet(
        existingConfig: existingConfig,
        onSave: (config) async {
          if (existingConfig != null) {
            await ref.read(danmakuConfigsProvider.notifier).updateConfig(config);
          } else {
            await ref.read(danmakuConfigsProvider.notifier).addConfig(config);
          }
        },
      ),
    );
  }

  void _confirmDelete(DanmakuConfig config) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('删除弹幕源', style: TextStyle(color: context.textPrimary, fontSize: 16)),
        content: Text('确定要删除「${config.name}」吗？', style: TextStyle(color: context.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('取消', style: TextStyle(color: context.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              ref.read(danmakuConfigsProvider.notifier).removeConfig(config.id);
              Navigator.pop(ctx);
            },
            child: Text('删除', style: TextStyle(color: AppTheme.error)),
          ),
        ],
      ),
    );
  }

  void _toggleConfig(DanmakuConfig config, bool enabled) {
    ref.read(danmakuConfigsProvider.notifier).updateConfig(
      config.copyWith(isEnabled: enabled),
    );
  }
}

// ═══════════════════════════════════════════════════
// Sub-widgets
// ═══════════════════════════════════════════════════

/// 弹幕源列表行
class _ServerRow extends StatelessWidget {
  final DanmakuConfig config;
  final bool isFirst;
  final bool isLast;
  final Function(bool) onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ServerRow({
    required this.config,
    required this.isFirst,
    required this.isLast,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onEdit,
      borderRadius: BorderRadius.vertical(
        top: isFirst ? const Radius.circular(16) : Radius.zero,
        bottom: isLast ? const Radius.circular(16) : Radius.zero,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: isLast
              ? null
              : Border(bottom: BorderSide(color: context.textSecondary.withValues(alpha: 0.08))),
        ),
        child: Row(
          children: [
            // 状态指示灯
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: config.isEnabled ? Colors.green : context.textSecondary.withValues(alpha: 0.3),
              ),
            ),
            const SizedBox(width: 12),
            // 名称 + URL
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    config.name,
                    style: TextStyle(
                      color: context.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (config.url.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        config.url,
                        style: TextStyle(color: context.textSecondary, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
            // 开关
            Switch.adaptive(
              value: config.isEnabled,
              onChanged: onToggle,
              activeTrackColor: AppTheme.accent,
            ),
            // 删除
            GestureDetector(
              onTap: onDelete,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.close_rounded, color: context.textSecondary.withValues(alpha: 0.5), size: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 屏蔽关键词标签
class _KeywordChip extends StatelessWidget {
  final String keyword;
  final VoidCallback onRemove;

  const _KeywordChip({required this.keyword, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.error.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            keyword,
            style: TextStyle(color: AppTheme.error, fontSize: 13),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: Icon(Icons.close_rounded, size: 14, color: AppTheme.error.withValues(alpha: 0.7)),
          ),
        ],
      ),
    );
  }
}

/// 屏蔽关键词输入框
class _BlockKeywordInput extends StatefulWidget {
  final ValueChanged<String> onAdd;

  const _BlockKeywordInput({required this.onAdd});

  @override
  State<_BlockKeywordInput> createState() => _BlockKeywordInputState();
}

class _BlockKeywordInputState extends State<_BlockKeywordInput> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isNotEmpty) {
      widget.onAdd(text);
      _controller.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            style: TextStyle(color: context.textPrimary, fontSize: 14),
            decoration: InputDecoration(
              hintText: '输入屏蔽词后回车或点击添加',
              hintStyle: TextStyle(color: context.textSecondary.withValues(alpha: 0.5), fontSize: 13),
              filled: true,
              fillColor: context.cardColor,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              isDense: true,
            ),
            onSubmitted: (_) => _submit(),
            inputFormatters: [LengthLimitingTextInputFormatter(20)],
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _submit,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.add_rounded, color: AppTheme.accent, size: 18),
          ),
        ),
      ],
    );
  }
}

/// 添加/编辑弹幕源 BottomSheet
class _AddDanmakuSheet extends StatefulWidget {
  final DanmakuConfig? existingConfig;
  final Function(DanmakuConfig) onSave;

  const _AddDanmakuSheet({
    this.existingConfig,
    required this.onSave,
  });

  @override
  State<_AddDanmakuSheet> createState() => _AddDanmakuSheetState();
}

class _AddDanmakuSheetState extends State<_AddDanmakuSheet> {
  final _nameController = TextEditingController();
  final _urlController = TextEditingController();
  final _apiKeyController = TextEditingController();
  bool _isEnabled = true;

  @override
  void initState() {
    super.initState();
    if (widget.existingConfig != null) {
      _nameController.text = widget.existingConfig!.name;
      _urlController.text = widget.existingConfig!.url;
      _apiKeyController.text = widget.existingConfig!.apiKey ?? '';
      _isEnabled = widget.existingConfig!.isEnabled;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existingConfig != null;
    return Container(
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 拖动条
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.textSecondary.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // 标题
              Text(
                isEdit ? '编辑弹幕源' : '添加弹幕源',
                style: TextStyle(
                  color: context.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 20),
              // 名称
              _sheetField(
                controller: _nameController,
                label: '名称',
                hint: '如：弹弹Play',
              ),
              const SizedBox(height: 12),
              // URL
              _sheetField(
                controller: _urlController,
                label: 'API 地址',
                hint: 'https://api.danmaku.com',
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 12),
              // API Key
              _sheetField(
                controller: _apiKeyController,
                label: 'API 密钥（可选）',
                hint: '输入 API Key',
                obscure: true,
              ),
              const SizedBox(height: 16),
              // 启用开关
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('创建后启用', style: TextStyle(color: context.textPrimary, fontSize: 15)),
                  Switch.adaptive(
                    value: _isEnabled,
                    onChanged: (v) => setState(() => _isEnabled = v),
                    activeTrackColor: AppTheme.accent,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // 保存按钮
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saveConfig,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: Text(isEdit ? '保存修改' : '添加', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sheetField({
    required TextEditingController controller,
    required String label,
    required String hint,
    TextInputType? keyboardType,
    bool obscure = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: context.textSecondary, fontSize: 12)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          style: TextStyle(color: context.textPrimary, fontSize: 15),
          keyboardType: keyboardType,
          obscureText: obscure,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: context.textSecondary.withValues(alpha: 0.5), fontSize: 14),
            filled: true,
            fillColor: context.cardColor,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            isDense: true,
          ),
        ),
      ],
    );
  }

  Future<void> _saveConfig() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: const Text('请输入名称'), backgroundColor: AppTheme.error),
      );
      return;
    }
    final config = DanmakuConfig(
      id: widget.existingConfig?.id ?? const Uuid().v4(),
      name: _nameController.text.trim(),
      url: _urlController.text.trim(),
      apiKey: _apiKeyController.text.isEmpty ? null : _apiKeyController.text.trim(),
      isEnabled: _isEnabled,
    );
    await widget.onSave(config);
    if (mounted) Navigator.pop(context);
  }
}
