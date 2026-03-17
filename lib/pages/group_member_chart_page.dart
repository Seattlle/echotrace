import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:math';
import '../providers/app_state.dart';
import '../services/database_service.dart';
import '../services/group_chat_service.dart';

// 无需导入任何词云第三方包

class GroupMemberChartPage extends StatefulWidget {
  final GroupChatInfo groupInfo;
  const GroupMemberChartPage({super.key, required this.groupInfo});

  @override
  State<GroupMemberChartPage> createState() => _GroupMemberChartPageState();
}

class _GroupMemberChartPageState extends State<GroupMemberChartPage> {
  late final GroupChatService _groupChatService;
  late final DatabaseService _databaseService;
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 15));
  DateTime _endDate = DateTime.now();
  DateTime _latestMessageDate = DateTime.now();
  DateTime? _earliestMessageDate;
  List<GroupMember> _members = [];
  GroupMember? _selectedMember;
  List<DailyMessageCount>? _chartData;
  Map<String, int>? _wordFrequencies;
  bool _isLoadingMembers = true;
  bool _isGenerating = false;
  bool _isWordCloudReady = false;

  @override
  void initState() {
    super.initState();
    final appState = Provider.of<AppState>(context, listen: false);
    _databaseService = appState.databaseService;
    _groupChatService = GroupChatService(_databaseService);
    _syncDateBounds();
    _loadMembers();
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

  Future<void> _loadMembers() async {
    final members = await _groupChatService.getGroupMembers(widget.groupInfo.username);
    setState(() {
      _members = members;
      _isLoadingMembers = false;
      if (_members.isNotEmpty) {
        _selectedMember = _members.first;
      }
    });
  }

  // 合并生成柱状图和词云数据
  Future<void> _generateChartAndWordCloud() async {
    if (_selectedMember == null) return;
    setState(() {
      _isGenerating = true;
      _chartData = null;
      _wordFrequencies = null;
      _isWordCloudReady = false;
    });

    try {
      // 并行请求数据
      final futureChartData = _groupChatService.getMemberDailyMessageCount(
        chatroomId: widget.groupInfo.username,
        memberUsername: _selectedMember!.username,
        startDate: _startDate,
        endDate: _endDate,
      );
      final futureWordFreq = _groupChatService.getMemberWordFrequency(
        chatroomId: widget.groupInfo.username,
        memberUsername: _selectedMember!.username,
        startDate: _startDate,
        endDate: _endDate,
      );

      final results = await Future.wait([futureChartData, futureWordFreq]);
      setState(() {
        _chartData = results[0] as List<DailyMessageCount>;
        _wordFrequencies = results[1] as Map<String, int>;
        _isGenerating = false;
        _isWordCloudReady = true; // 数据就绪，直接标记
      });
    } catch (e) {
      setState(() => _isGenerating = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('生成数据失败: $e')),
        );
      }
    }
  }

  // ########## 核心：自定义词云组件（无第三方依赖） ##########
  Widget _buildCustomWordCloud() {
    if (_wordFrequencies == null || _wordFrequencies!.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(20.0),
        child: Center(child: Text('该成员在此期间无有效词汇数据')),
      );
    }

    // 1. 处理词频数据：按词频排序，取前30个（避免密集）
    final sortedWords = _wordFrequencies!.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value))
      ..take(30);

    // 2. 计算字体大小范围（词频越高，字体越大）
    final minCount = sortedWords.last.value.toDouble();
    final maxCount = sortedWords.first.value.toDouble();
    const minFontSize = 12.0;
    const maxFontSize = 40.0;

    // 3. 配置词云容器尺寸
    final screenWidth = MediaQuery.of(context).size.width - 40;
    final cloudHeight = 300.0;
    final random = Random();

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '词云分析',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          // 圆形词云容器（裁剪为圆形）
          ClipOval(
            child: Container(
              width: screenWidth,
              height: cloudHeight,
              color: Colors.grey[50],
              child: Stack(
                children: sortedWords.map((entry) {
                  final word = entry.key;
                  final count = entry.value.toDouble();

                  // 按词频映射字体大小（线性缩放）
                  final fontSize = minFontSize +
                      ((count - minCount) / (maxCount - minCount)) *
                          (maxFontSize - minFontSize);

                  // 随机位置（限制在容器内，避免超出）
                  final left = random.nextDouble() *
                      (screenWidth - fontSize * word.length * 0.5);
                  final top = random.nextDouble() * (cloudHeight - fontSize);

                  // 随机颜色（从主题色中选取，视觉统一）
                  final color =
                      Colors.primaries[random.nextInt(Colors.primaries.length)];

                  return Positioned(
                    left: left,
                    top: top,
                    child: Text(
                      word,
                      style: TextStyle(
                        fontSize: fontSize,
                        color: color,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'sans-serif', // 支持中文默认字体
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 日期选择器
  Future<void> _selectDate(BuildContext context, bool isStart) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : _endDate,
      firstDate: _earliestMessageDate ?? DateTime(2000),
      lastDate: _latestMessageDate,
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
        } else {
          _endDate = picked;
        }
      });
    }
  }

  // 构建柱状图
  Widget _buildChart() {
    if (_chartData == null || _chartData!.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(20.0),
        child: Center(child: Text('该成员在此期间无发言记录')),
      );
    }

    final dateFormat = DateFormat('MM-dd');
    final barGroups = _chartData!.asMap().entries.map((entry) {
      final index = entry.key;
      final data = entry.value;
      return BarChartGroupData(
        x: index,
        barRods: [
          BarChartRodData(
            toY: data.count.toDouble(),
            color: Colors.green,
            width: 16,
            borderRadius: BorderRadius.circular(4),
          ),
        ],
      );
    }).toList();

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '每日发言数量',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 300.0,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                barGroups: barGroups,
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      getTitlesWidget: (double value, TitleMeta meta) {
                        final index = value.toInt();
                        if (index < _chartData!.length) {
                          // 数据过多时，每隔N个显示一个日期（避免拥挤）
                          if (_chartData!.length > 10 &&
                              index % (_chartData!.length ~/ 5) != 0) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 6.0),
                            child: Text(
                              dateFormat.format(_chartData![index].date),
                              style: const TextStyle(
                                  fontSize: 10, color: Colors.grey),
                            ),
                          );
                        }
                        return const Text('');
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (double value, TitleMeta meta) {
                        // 只显示整数刻度
                        if (value % 1 == 0) {
                          return Text(
                            value.toInt().toString(),
                            style: const TextStyle(
                                fontSize: 10, color: Colors.grey),
                            textAlign: TextAlign.left,
                          );
                        }
                        return const Text('');
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                gridData: const FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 1,
                ),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    tooltipBgColor: Colors.blueGrey,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final data = _chartData![group.x.toInt()];
                      return BarTooltipItem(
                        '${DateFormat('yyyy-MM-dd').format(data.date)}\n',
                        const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        children: <TextSpan>[
                          TextSpan(
                            text: data.count.toString(),
                            style: const TextStyle(
                              color: Colors.yellow,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('yyyy-MM-dd');
    return Scaffold(
      appBar: AppBar(
        title: const Text('单人发言分析'),
        backgroundColor: Colors.green,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // 筛选条件卡片
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      _isLoadingMembers
                          ? const CircularProgressIndicator()
                          : DropdownButtonFormField<GroupMember>(
                              initialValue: _selectedMember,
                              items: _members.map((member) => DropdownMenuItem(
                                value: member,
                                child: Text(member.displayName),
                              )).toList(),
                              onChanged: (value) {
                                setState(() {
                                  _selectedMember = value;
                                });
                              },
                              decoration: const InputDecoration(labelText: '选择成员'),
                            ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          ElevatedButton(
                            onPressed: () => _selectDate(context, true),
                            child: Text(dateFormat.format(_startDate)),
                          ),
                          const Text('至'),
                          ElevatedButton(
                            onPressed: () => _selectDate(context, false),
                            child: Text(dateFormat.format(_endDate)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: (_isGenerating || _selectedMember == null)
                            ? null
                            : _generateChartAndWordCloud,
                        child: const Text('生成分析'),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // 加载中提示
            if (_isGenerating)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: CircularProgressIndicator(),
              ),

            // 柱状图
            if (_chartData != null) _buildChart(),

            // 自定义词云（无第三方依赖，无emit错误）
            if (_isWordCloudReady) _buildCustomWordCloud(),
          ],
        ),
      ),
    );
  }
}
