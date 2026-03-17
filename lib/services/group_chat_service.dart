// 文件: lib/services/group_chat_service.dart

import 'dart:core';
import 'package:intl/intl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/message.dart';
import 'database_service.dart';
import 'word_cloud_service.dart';

class GroupChatInfo {
  final String username;
  final String displayName;
  final int memberCount;
  final String? avatarUrl;

  GroupChatInfo({
    required this.username,
    required this.displayName,
    required this.memberCount,
    this.avatarUrl,
  });
}

class GroupMember {
  final String username;
  final String displayName;
  final String? avatarUrl;
  GroupMember({required this.username, required this.displayName, this.avatarUrl});
  Map<String, dynamic> toJson() => {'username': username, 'displayName': displayName, 'avatarUrl': avatarUrl};
}

class GroupMessageRank {
  final GroupMember member;
  final int messageCount;
  GroupMessageRank({required this.member, required this.messageCount});
}

class DailyMessageCount {
  final DateTime date;
  final int count;
  DailyMessageCount({required this.date, required this.count});
}

class GroupChatService {
  final DatabaseService _databaseService;
  
  GroupChatService(this._databaseService);

  Future<Map<int, int>> getGroupMediaTypeStats({
    required String chatroomId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    // --- 服务层日志 ---
    
    return await _databaseService.getGroupMediaTypeStats(
      chatroomId: chatroomId,
      startDate: startDate,
      endDate: endDate,
    );
  }

  // 新增：群聊活跃时段分析
  Future<Map<int, int>> getGroupActiveHours({
    required String chatroomId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    // 直接调用底层的 DatabaseService 方法
    return await _databaseService.getGroupActiveHours(
      chatroomId: chatroomId,
      startDate: startDate,
      endDate: endDate,
    );
  }

  /// 获取群成员词频（使用统一词云服务）
  Future<Map<String, int>> getMemberWordFrequency({
    required String chatroomId,
    required String memberUsername,
    required DateTime startDate,
    required DateTime endDate,
    int topN = 100,
  }) async {
    final endOfDay = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59);

    try {
      final messages = await _databaseService.getMessagesByDate(
        chatroomId,
        startDate.millisecondsSinceEpoch ~/ 1000,
        endOfDay.millisecondsSinceEpoch ~/ 1000,
      );

      // 提取指定成员的文本消息
      final textContents = messages
          .where((m) =>
              m.senderUsername == memberUsername &&
              (m.isTextMessage || m.localType == 244813135921) &&
              m.displayContent.isNotEmpty)
          .map((m) => m.displayContent)
          .toList();

      if (textContents.isEmpty) {
        return {};
      }

      // 使用统一词云服务（词语模式，使用 jieba 分词）
      final result = await WordCloudService.instance.analyze(
        texts: WordCloudService.filterTextMessages(textContents),
        mode: WordCloudMode.word,
        topN: topN,
        minCount: 1,
        minLength: 2,
      );

      // 转换为 Map<String, int> 格式
      return {
        for (final item in result.words)
          item['word'] as String: item['count'] as int
      };
    } catch (e) {
      return {};
    }
  }

  Future<List<GroupChatInfo>> getGroupChats() async {
    final sessions = await _databaseService.getSessions();
    final groupSessions = sessions.where((s) => s.isGroup).toList();
    final List<GroupChatInfo> result = [];
    final usernames = groupSessions.map((s) => s.username).toList();
    final displayNames = await _databaseService.getDisplayNames(usernames);

    Map<String, String> avatarUrls = {};
    try {
      avatarUrls = await _databaseService.getAvatarUrls(usernames);
    } catch (e) {
      // 忽略头像获取错误
    }

    for (final session in groupSessions) {
      final memberCount = await _getGroupMemberCount(session.username);
      result.add(
        GroupChatInfo(
          username: session.username,
          displayName: displayNames[session.username] ?? session.username,
          memberCount: memberCount,
          avatarUrl: avatarUrls[session.username],
        ),
      );
    }
    result.sort((a, b) => b.memberCount.compareTo(a.memberCount));
    return result;
  }

  Future<int> _getGroupMemberCount(String chatroomId) async {
    try {
      final contactDbPath = await _databaseService.getContactDatabasePath();
      if (contactDbPath == null) return 0;
      final db = await databaseFactoryFfi.openDatabase(contactDbPath, options: OpenDatabaseOptions(readOnly: true));
      try {
        final result = await db.rawQuery(
          '''
          SELECT COUNT(*) as count FROM chatroom_member 
          WHERE room_id = (SELECT rowid FROM name2id WHERE username = ?)
          ''',
          [chatroomId],
        );
        return (result.first['count'] as int?) ?? 0;
      } finally {
        await db.close();
      }
    } catch (e) {
      return 0;
    }
  }

  Future<List<GroupMember>> getGroupMembers(String chatroomId) async {
    final List<GroupMember> members = [];
    try {
      final contactDbPath = await _databaseService.getContactDatabasePath();
      if (contactDbPath == null) return [];

      final db = await databaseFactoryFfi.openDatabase(contactDbPath,
          options: OpenDatabaseOptions(readOnly: true));
      
      try {
        final memberRows = await db.rawQuery(
          '''
          SELECT n.username, c.small_head_url FROM chatroom_member m
          JOIN name2id n ON m.member_id = n.rowid
          LEFT JOIN contact c ON n.username = c.username
          WHERE m.room_id = (SELECT rowid FROM name2id WHERE username = ?)
          ''',
          [chatroomId],
        );

        if (memberRows.isEmpty) return [];
        
        final usernames = memberRows
          .where((row) => row['username'] != null)
          .map((row) => row['username'] as String)
          .toList();
        
        final displayNames = await _databaseService.getDisplayNames(usernames);

        final avatarMap = {
          for (var row in memberRows) 
            if (row['username'] != null) 
              row['username'] as String: row['small_head_url'] as String?
        };

        for (final username in usernames) {
           members.add(GroupMember(
             username: username, 
             displayName: displayNames[username] ?? username,
             avatarUrl: avatarMap[username],
           ));
        }
      } finally {
        await db.close();
      }
    } catch (e) {
    }
    return members;
  }

  Future<List<GroupMessageRank>> getGroupMessageRanking({
    required String chatroomId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final endOfDay = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59);
    final messages = await _databaseService.getMessagesByDate(
        chatroomId, startDate.millisecondsSinceEpoch ~/ 1000, endOfDay.millisecondsSinceEpoch ~/ 1000);
    final Map<String, int> messageCounts = {};
    final Set<String> senderUsernames = {};
    for (final Message message in messages) {
      if (message.senderUsername != null && message.senderUsername!.isNotEmpty) {
        final username = message.senderUsername!;
        messageCounts[username] = (messageCounts[username] ?? 0) + 1;
        senderUsernames.add(username);
      }
    }
    if (senderUsernames.isEmpty) return [];

    final allMembers = await getGroupMembers(chatroomId);
    final memberMap = {for (var m in allMembers) m.username: m};

    final List<GroupMessageRank> ranking = [];
    messageCounts.forEach((username, count) {
      final member = memberMap[username] ?? GroupMember(username: username, displayName: username);
      ranking.add(GroupMessageRank(member: member, messageCount: count));
    });
    ranking.sort((a, b) => b.messageCount.compareTo(a.messageCount));
    return ranking;
  }
  
  Future<List<DailyMessageCount>> getMemberDailyMessageCount({
    required String chatroomId,
    required String memberUsername,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final endOfDay = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59);
    final messages = await _databaseService.getMessagesByDate(
      chatroomId, startDate.millisecondsSinceEpoch ~/ 1000, endOfDay.millisecondsSinceEpoch ~/ 1000);
    final memberMessages = messages.where((m) => m.senderUsername == memberUsername);
    final Map<String, int> dailyCounts = {};
    final dateFormat = DateFormat('yyyy-MM-dd');
    for (final message in memberMessages) {
       final dateStr = dateFormat.format(DateTime.fromMillisecondsSinceEpoch(message.createTime * 1000));
       dailyCounts[dateStr] = (dailyCounts[dateStr] ?? 0) + 1;
    }
    final result = dailyCounts.entries.map((entry) {
        return DailyMessageCount(date: DateTime.parse(entry.key), count: entry.value);
    }).toList();
    result.sort((a,b) => a.date.compareTo(b.date));
    return result;
  }
}
