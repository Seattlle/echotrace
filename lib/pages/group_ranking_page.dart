// 文件: group_ranking_page.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../services/database_service.dart';
import '../services/group_chat_service.dart';
import 'group_members_page.dart'; // 导入包含 UserAvatar 的文件

// 保留原页面
class GroupRankingPage extends StatelessWidget {
  final GroupChatInfo groupInfo;
  const GroupRankingPage({super.key, required this.groupInfo});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('发言排行'),
      ),
      body: GroupRankingContent(groupInfo: groupInfo),
    );
  }
}

// --- 新增：抽离出来的核心内容组件 ---
class GroupRankingContent extends StatefulWidget {
  final GroupChatInfo groupInfo;
  const GroupRankingContent({super.key, required this.groupInfo});

  @override
  State<GroupRankingContent> createState() => _GroupRankingContentState();
}

class _GroupRankingContentState extends State<GroupRankingContent> {
  late final GroupChatService _groupChatService;
  late final DatabaseService _databaseService;
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 15));
  DateTime _endDate = DateTime.now();
  DateTime _latestMessageDate = DateTime.now();
  DateTime? _earliestMessageDate;
  List<GroupMessageRank>? _ranking;
  bool _isGenerating = false;
  bool _isGeneratingWordCloud = false;

  @override
  void initState() {
    super.initState();
    final appState = Provider.of<AppState>(context, listen: false);
    _databaseService = appState.databaseService;
    _groupChatService = GroupChatService(_databaseService);
    _syncDateBounds();
  }

  Future<void> _syncDateBounds() async {
    try {
      final range =
          await _databaseService.getSessionTimeRange(widget.groupInfo.username);
      final first = range['first'];
      final last = range['last'];
      if (last == null || last <= 0) return;
      final latest = DateTime.fromMillisecondsSinceEpoch(last * 1000);
      final earliest = (first != null && first > 0)
          ? DateTime.fromMillisecondsSinceEpoch(first * 1000)
          : null;
      if (!mounted) return;
      setState(() {
        _latestMessageDate = latest;
        _earliestMessageDate = earliest;
        _endDate = latest;
        final defaultStart = latest.subtract(const Duration(days: 15));
        _startDate = (earliest != null && earliest.isAfter(defaultStart))
            ? earliest
            : defaultStart;
        if (_startDate.isAfter(_endDate)) {
          _startDate = _endDate;
        }
      });
    } catch (_) {}
  }

  Future<void> _selectDate(BuildContext context, bool isStart) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : _endDate,
      firstDate: _earliestMessageDate ?? DateTime(2000),
      lastDate: _latestMessageDate,
    );
    if (picked != null && mounted) {
      setState(() {
        if (isStart) {
          _startDate = picked;
        } else {
          _endDate = picked;
        }
      });
    }
  }

  Future<void> _generateRanking() async {
    if (!mounted) return;
    setState(() { _isGenerating = true; _ranking = null; });
    try {
      final ranking = await _groupChatService.getGroupMessageRanking(
        chatroomId: widget.groupInfo.username,
        startDate: _startDate,
        endDate: _endDate.add(const Duration(days: 1)), // 包含当天
      );
      if (!mounted) return;
      setState(() { _ranking = ranking; _isGenerating = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isGenerating = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('生成排行失败: $e')));
    }
  }

  Future<void> _generateWordFrequencyTable(GroupMember member) async {
    if (!mounted) return;
    setState(() => _isGeneratingWordCloud = true);
    try {
      final wordFrequencies = await _groupChatService.getMemberWordFrequency(
        chatroomId: widget.groupInfo.username,
        memberUsername: member.username,
        startDate: _startDate,
        endDate: _endDate.add(const Duration(days: 1)), // 包含当天
      );
      if (!mounted) return;
      setState(() => _isGeneratingWordCloud = false);
      if (wordFrequencies.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('该成员在此期间没有足够的数据生成词频统计')),
        );
      } else {
        _showWordFrequencyTableDialog(member.displayName, wordFrequencies);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isGeneratingWordCloud = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('生成词频统计失败: $e')));
    }
  }

  void _showWordFrequencyTableDialog(String memberName, Map<String, int> wordFrequencies) {
    final sortedWords = wordFrequencies.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topWords = sortedWords.take(50).toList();
    final maxFrequency = topWords.isNotEmpty ? topWords.first.value : 1;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('$memberName 的常用词汇'),
          content: SizedBox(
            width: 500, // 给对话框一个固定宽度
            child: topWords.isEmpty
                ? const Center(child: Text('没有可显示的词汇'))
                : SingleChildScrollView(
                    child: Table(
                      columnWidths: const {
                        0: IntrinsicColumnWidth(),
                        1: FlexColumnWidth(),
                        2: IntrinsicColumnWidth(),
                        3: FlexColumnWidth(2),
                      },
                      border: TableBorder.all(color: Colors.grey.shade300),
                      children: [
                        TableRow(
                          decoration: BoxDecoration(color: Colors.grey.shade100),
                          children: const [
                            Padding(padding: EdgeInsets.all(8.0), child: Text('排名', style: TextStyle(fontWeight: FontWeight.bold))),
                            Padding(padding: EdgeInsets.all(8.0), child: Text('词汇', style: TextStyle(fontWeight: FontWeight.bold))),
                            Padding(padding: EdgeInsets.all(8.0), child: Text('频率', style: TextStyle(fontWeight: FontWeight.bold))),
                            Padding(padding: EdgeInsets.all(8.0), child: Text('可视化', style: TextStyle(fontWeight: FontWeight.bold))),
                          ],
                        ),
                        ...List.generate(topWords.length, (index) {
                          final entry = topWords[index];
                          final widthPercentage = entry.value / maxFrequency;
                          return TableRow(
                            children: [
                              Padding(padding: const EdgeInsets.all(8.0), child: Text('${index + 1}')),
                              Padding(padding: const EdgeInsets.all(8.0), child: Text(entry.key)),
                              Padding(padding: const EdgeInsets.all(8.0), child: Text(entry.value.toString())),
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 8.0),
                                child: LinearProgressIndicator(
                                  value: widthPercentage,
                                  backgroundColor: Colors.grey.shade200,
                                  minHeight: 10,
                                ),
                              ),
                            ],
                          );
                        }),
                      ],
                    ),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('yyyy-MM-dd');
    final theme = Theme.of(context);
    return Column(
      children: [
        // --- 顶部工具栏 ---
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Wrap(
            spacing: 16,
            runSpacing: 16,
            alignment: WrapAlignment.center,
            children: [
              ActionChip(
                avatar: const Icon(Icons.calendar_today, size: 16),
                label: Text('开始: ${dateFormat.format(_startDate)}'),
                onPressed: () => _selectDate(context, true),
              ),
              ActionChip(
                avatar: const Icon(Icons.calendar_today, size: 16),
                label: Text('结束: ${dateFormat.format(_endDate)}'),
                onPressed: () => _selectDate(context, false),
              ),
              ElevatedButton.icon(
                icon: _isGenerating
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.analytics),
                label: const Text('生成排行'),
                onPressed: _isGenerating ? null : _generateRanking,
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.primaryColor,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // --- 状态与列表 ---
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _buildContent(),
          ),
        ),
      ],
    );
  }

  Widget _buildContent() {
    if (_isGenerating) {
      return const Center(key: ValueKey('loading'), child: CircularProgressIndicator());
    }
    if (_isGeneratingWordCloud) {
      return const Center(key: ValueKey('wordcloud'), child: Text('正在生成词频统计...'));
    }
    if (_ranking == null) {
      return const Center(key: ValueKey('initial'), child: Text('请选择日期范围并生成排行'));
    }
    if (_ranking!.isEmpty) {
      return const Center(key: ValueKey('empty'), child: Text('该时间段内无发言记录'));
    }
    return ListView.builder(
      key: const ValueKey('list'),
      itemCount: _ranking!.length,
      itemBuilder: (context, index) {
        final item = _ranking![index];
        return ListTile(
          leading: SizedBox(
            width: 24,
            child: Text(
              '${index + 1}',
              style: const TextStyle(fontSize: 16, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ),
          title: Row(
            children: [
              UserAvatar(member: item.member),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item.member.displayName,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          trailing: Text(
            '${item.messageCount} 条',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          onTap: () => _generateWordFrequencyTable(item.member),
        );
      },
    );
  }
}
