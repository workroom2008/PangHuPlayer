import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/app_providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/server_icons.dart';
import '../../models/media_models.dart';
import '../servers/servers_screen.dart' show EditServerDialog;

class ResourcesPage extends ConsumerStatefulWidget {
  const ResourcesPage({super.key});

  @override
  ConsumerState<ResourcesPage> createState() => _ResourcesPageState();
}

class _ResourcesPageState extends ConsumerState<ResourcesPage> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final servers = ref.watch(mediaServersProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 60, 16, 100),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(
            children: [
              Expanded(
                child: Text('资源', style: TextStyle(color: context.textPrimary, fontSize: 28, fontWeight: FontWeight.bold)),
              ),
              _buildAddButton(context),
            ],
          ),
          SizedBox(height: 8),
          Text('管理媒体服务器和网络资源', style: TextStyle(color: context.textSecondary, fontSize: 14)),
          SizedBox(height: 28),
          Expanded(child: servers.isEmpty ? _emptyState(context) : _serverGrid(context, servers)),
        ]),
      ),
    );
  }

  Widget _emptyState(BuildContext context) => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: context.textPrimary.withValues(alpha: 0.06), shape: BoxShape.circle), child: Icon(Icons.dns_rounded, color: context.textPrimary38, size: 48)),
    SizedBox(height: 20),
    Text('暂无媒体服务器', style: TextStyle(color: context.textSecondary, fontSize: 16)),
    SizedBox(height: 8),
    Text('点击添加 Emby / Jellyfin / 飞牛影视', style: TextStyle(color: context.textPrimary24, fontSize: 13)),
    SizedBox(height: 24),
    ElevatedButton.icon(onPressed: () => context.push('/add-server'), icon: Icon(Icons.add, size: 20), label: Text('添加服务器'), style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: context.textPrimary, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)))),
  ]));

  Widget _serverGrid(BuildContext context, List<MediaServer> servers) => GridView.count(
    crossAxisCount: 2,
    crossAxisSpacing: 12,
    mainAxisSpacing: 12,
    padding: EdgeInsets.zero,
    children: [
      ...servers.map((server) => _buildServerCard(context, server)),
    ],
  );

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

  void _deleteServer(MediaServer server) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: context.surfaceColor,
        title: Text('删除服务器', style: TextStyle(color: context.textPrimary)),
        content: Text('确定要删除「${server.name}」吗？', style: TextStyle(color: context.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消', style: TextStyle(color: context.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(mediaServersProvider.notifier).removeServer(server.id);
            },
            child: Text('删除', style: TextStyle(color: AppTheme.error)),
          ),
        ],
      ),
    );
  }

  Widget _buildServerCard(BuildContext context, MediaServer server) {
    return GestureDetector(
      onTap: () => context.push('/library/${server.id}', extra: {'srv': server}),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.surfaceColor,
          borderRadius: BorderRadius.circular(16),
          border: server.isDefault
              ? Border.all(color: AppTheme.primary, width: 2)
              : Border.all(color: context.textPrimary.withValues(alpha: 0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: ServerIcons.colorForType(server.type.name).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: ServerIcons.forType(server.type.name, size: 28),
                ),
                const Spacer(),
                // 卡片右上角更多菜单：编辑 / 删除
                PopupMenuButton<String>(
                  color: context.cardColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  offset: const Offset(0, 4),
                  padding: EdgeInsets.zero,
                  icon: Icon(Icons.more_vert_rounded, color: context.textSecondary, size: 20),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'edit',
                      child: Row(children: [
                        Icon(Icons.edit_rounded, size: 18, color: context.textPrimary),
                        SizedBox(width: 10),
                        Text('编辑', style: TextStyle(color: context.textPrimary)),
                      ]),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(children: [
                        Icon(Icons.delete_outline_rounded, size: 18, color: AppTheme.error),
                        SizedBox(width: 10),
                        Text('删除', style: TextStyle(color: AppTheme.error)),
                      ]),
                    ),
                  ],
                  onSelected: (v) {
                    if (v == 'edit') {
                      _editServer(server);
                    } else if (v == 'delete') {
                      _deleteServer(server);
                    }
                  },
                ),
              ],
            ),
            SizedBox(height: 12),
            Text(server.name, style: TextStyle(color: context.textPrimary, fontSize: 14, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
            SizedBox(height: 8),
            Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: server.isConnected ? AppTheme.success : AppTheme.error,
                    shape: BoxShape.circle,
                  ),
                ),
                SizedBox(width: 6),
                Text(server.isConnected ? '在线' : '离线', style: TextStyle(color: server.isConnected ? AppTheme.success : AppTheme.error, fontSize: 10)),
                if (server.isDefault) ...[
                  SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)),
                    child: Text('默认', style: TextStyle(color: AppTheme.primary, fontSize: 10)),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddButton(BuildContext context) {
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
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: 0.12),
          shape: BoxShape.circle,
          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
        ),
        child: Icon(Icons.add_rounded, color: AppTheme.primary, size: 22),
      ),
    );
  }
}
