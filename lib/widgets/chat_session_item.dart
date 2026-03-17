import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/chat_session.dart';
import '../utils/string_utils.dart';
import '../providers/app_state.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// 会话列表项组件
class ChatSessionItem extends StatelessWidget {
  final ChatSession session;
  final bool isSelected;
  final VoidCallback onTap;
  final String? avatarUrl;
  final bool enableAvatarFade;

  const ChatSessionItem({
    super.key,
    required this.session,
    required this.isSelected,
    required this.onTap,
    this.avatarUrl,
    this.enableAvatarFade = true,
  });

  /// 安全获取头像文本
  String _getAvatarText(BuildContext context, ChatSession session) {
    final myWxid =
        context.read<AppState>().databaseService.currentAccountWxid ?? '';

    // 如果是当前账号，显示"我"
    if (session.username == myWxid) {
      return '我';
    }

    final displayName = session.displayName ?? session.username;

    // 使用 StringUtils 安全地获取第一个字符
    // 这个方法会正确处理 emoji 等占用多个 code units 的字符
    return StringUtils.getFirstChar(displayName, defaultChar: '?');
  }

  /// 安全获取显示名称
  String _getDisplayName(BuildContext context, ChatSession session) {
    final myWxid =
        context.read<AppState>().databaseService.currentAccountWxid ?? '';

    // 如果是当前账号，显示"我"
    if (session.username == myWxid) {
      return '我';
    }

    final displayName = session.displayName ?? session.username;

    // 使用 StringUtils 清理并验证
    return StringUtils.cleanOrDefault(displayName, '未知联系人');
  }

  /// 清理字符串（使用工具类）
  String _cleanString(String input) {
    return StringUtils.cleanUtf16(input);
  }




  @override
  Widget build(BuildContext context) {
    // 包装在 try-catch 中以捕获任何 UTF-16 错误
    try {
      return GestureDetector(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isSelected
                  ? Theme.of(
                      context,
                    ).colorScheme.primaryContainer.withValues(alpha: 0.5)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 头像
                if (avatarUrl != null && avatarUrl!.isNotEmpty)
                  CachedNetworkImage(
                    imageUrl: avatarUrl!,
                    fadeInDuration:
                        enableAvatarFade ? const Duration(milliseconds: 200) : Duration.zero,
                    fadeOutDuration:
                        enableAvatarFade ? const Duration(milliseconds: 200) : Duration.zero,
                    imageBuilder: (context, imageProvider) => CircleAvatar(
                      radius: 24,
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.2),
                      backgroundImage: imageProvider,
                    ),
                    placeholder: (context, url) => CircleAvatar(
                      radius: 24,
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.2),
                      child: Text(
                        _cleanString(_getAvatarText(context, session)),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    errorWidget: (context, url, error) => CircleAvatar(
                      radius: 24,
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.2),
                      child: Text(
                        _cleanString(_getAvatarText(context, session)),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  )
                else
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.2),
                    child: Text(
                      _cleanString(_getAvatarText(context, session)),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                const SizedBox(width: 12),

                // 会话信息
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 用户名和时间
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _getDisplayName(context, session),
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                              maxLines: 1,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _cleanString(session.formattedLastTime),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurface
                                      .withValues(alpha: 0.5),
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),

                      // 摘要
                      Text(
                        _cleanString(session.displaySummary),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                        maxLines: 1,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e, stackTrace) {
      // 捕获 UTF-16 错误并记录详细信息
      debugPrint('[ERROR] ChatSessionItem 渲染错误: $e');
      debugPrint('   会话ID: ${session.username}');
      debugPrint('   显示名称: ${session.displayName}');
      debugPrint('   摘要: ${session.displaySummary}');
      debugPrint('   堆栈跟踪: $stackTrace');

      // 返回一个安全的替代Widget
      return InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isSelected
                ? Theme.of(
                    context,
                  ).colorScheme.primaryContainer.withValues(alpha: 0.5)
                : Colors.transparent,
            border: Border(
              bottom: BorderSide(
                color: Theme.of(
                  context,
                ).colorScheme.outline.withValues(alpha: 0.1),
              ),
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.2),
                child: const Icon(Icons.error),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '会话加载错误',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    Text(
                      session.username,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
  }
}
