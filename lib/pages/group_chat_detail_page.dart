import 'package:flutter/material.dart';
import '../services/group_chat_service.dart';
import 'group_members_page.dart';
import 'group_ranking_page.dart';
import 'group_member_chart_page.dart';

// 保留原来的页面结构，以备不时之需
class GroupChatDetailPage extends StatelessWidget {
  final GroupChatInfo groupInfo;

  const GroupChatDetailPage({super.key, required this.groupInfo});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(groupInfo.displayName, overflow: TextOverflow.ellipsis),
        backgroundColor: Colors.green,
      ),
      // 直接复用我们新创建的内容组件
      body: GroupChatDetailContent(groupInfo: groupInfo),
    );
  }
}


// --- 新增：这就是 GroupChatAnalysisPage 需要的组件 ---
// 我们将原来 Scaffold 的 body 部分抽离成一个独立的、可复用的组件
class GroupChatDetailContent extends StatelessWidget {
  final GroupChatInfo groupInfo;

  const GroupChatDetailContent({super.key, required this.groupInfo});

  @override
  Widget build(BuildContext context) {
    // 将原来的 ListView 完整地移到这里
    return ListView(
      // 增加一些内边距，使其在右侧面板中看起来更舒适
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      children: [
        ListTile(
          leading: const Icon(Icons.people_outline),
          title: const Text('群成员查看'),
          subtitle: const Text('查看所有群成员并导出'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            // 注意：在双栏布局中，直接 push 整个页面体验不佳。
            // 更好的做法是在右侧面板内切换内容。
            // 但为了先解决编译错误，我们暂时保留 push 逻辑。
            // 下一步我们会优化这个问题。
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => GroupMembersPage(groupInfo: groupInfo)),
            );
          },
        ),
        const Divider(indent: 16, endIndent: 16), // 使用 indent 美化分割线
        ListTile(
          leading: const Icon(Icons.bar_chart),
          title: const Text('群聊发言排行'),
          subtitle: const Text('统计时间段内成员发言次数'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
             Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => GroupRankingPage(groupInfo: groupInfo)),
            );
          },
        ),
        const Divider(indent: 16, endIndent: 16),
        ListTile(
          leading: const Icon(Icons.person_search),
          title: const Text('单人发言分析'),
          subtitle: const Text('查看指定成员每日发言柱状图'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => GroupMemberChartPage(groupInfo: groupInfo)),
            );
          },
        ),
      ],
    );
  }
}