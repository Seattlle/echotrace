// 文件: lib/pages/group_active_hours_page.dart

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../services/database_service.dart';
import '../services/group_chat_service.dart';

class GroupActiveHoursContent extends StatefulWidget {
  final GroupChatInfo groupInfo;
  const GroupActiveHoursContent({super.key, required this.groupInfo});

  @override
  State<GroupActiveHoursContent> createState() => _GroupActiveHoursContentState();
}

class _GroupActiveHoursContentState extends State<GroupActiveHoursContent> {
  late final GroupChatService _groupChatService;
  late final DatabaseService _databaseService;
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();
  DateTime _latestMessageDate = DateTime.now();
  DateTime? _earliestMessageDate;
  bool _isLoading = false;
  Map<int, int>? _hourlyData;

  @override
  void initState() {
    super.initState();
    final appState = Provider.of<AppState>(context, listen: false);
    _databaseService = appState.databaseService;
    _groupChatService = GroupChatService(_databaseService);
    _initializeRange();
  }

  Future<void> _initializeRange() async {
    await _syncDateBounds();
    await _fetchActiveHours();
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
        final defaultStart = latest.subtract(const Duration(days: 30));
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

  Future<void> _fetchActiveHours() async {
    if (!mounted) return;
    setState(() { _isLoading = true; _hourlyData = null; });
    
    
    try {
      final data = await _groupChatService.getGroupActiveHours(
        chatroomId: widget.groupInfo.username,
        startDate: _startDate,
        endDate: _endDate.add(const Duration(days: 1)),
      );

      if (!mounted) return;
      setState(() { _hourlyData = data; _isLoading = false; });
    } catch (e) {
      // 打印错误
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('生成图表失败: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('yyyy-MM-dd');
    final theme = Theme.of(context);
    return Column(
      children: [
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
                icon: _isLoading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.analytics_outlined),
                label: const Text('生成图表'),
                onPressed: _isLoading ? null : _fetchActiveHours,
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.primaryColor,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _buildContent(),
          ),
        ),
      ],
    );
  }
// 文件: lib/pages/group_active_hours_page.dart

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(key: ValueKey('loading'), child: CircularProgressIndicator());
    }
    if (_hourlyData == null) {
      // 确保这里的 Key 是 'initial'
      return const Center(key: ValueKey('initial'), child: Text('请选择日期范围并生成图表'));
    }
    if (_hourlyData!.values.every((count) => count == 0)) {
      // 确保这里的 Key 是 'empty'
      return const Center(key: ValueKey('empty'), child: Text('该时间段内无发言记录'));
    }

    // 找到数据中的最大值，用于Y轴的动态范围
    final maxY = (_hourlyData!.values.reduce((a, b) => a > b ? a : b)).toDouble();

    return Padding(
      // 确保这里的 Key 是 'chart'
      key: const ValueKey('chart'),
      padding: const EdgeInsets.fromLTRB(16, 24, 24, 16),
      child: BarChart(
        BarChartData(
          maxY: maxY * 1.2, // Y轴顶部留出20%空间
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final hour = group.x.toInt();
                return BarTooltipItem(
                  '$hour点 ~ ${hour + 1}点\n',
                  const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  children: <TextSpan>[
                    TextSpan(
                      text: '${rod.toY.round()} 条消息',
                      style: const TextStyle(color: Colors.yellow, fontWeight: FontWeight.w500),
                    ),
                  ],
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final hour = value.toInt();
                  if (hour % 2 == 0) { // 每隔2小时显示一个标签
                    return SideTitleWidget(axisSide: meta.axisSide, child: Text(hour.toString()));
                  }
                  return const SizedBox.shrink();
                },
                reservedSize: 30,
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                interval: maxY > 10 ? (maxY / 5).ceilToDouble() : 2,
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: maxY > 10 ? (maxY / 5).ceilToDouble() : 2,
          ),
          barGroups: _hourlyData!.entries.map((entry) {
            return BarChartGroupData(
              x: entry.key,
              barRods: [
                BarChartRodData(
                  toY: entry.value.toDouble(),
                  color: Colors.teal,
                  width: 16,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}
