import 'package:flutter_test/flutter_test.dart';
import 'package:echotrace/models/analytics_data.dart';

void main() {
  group('ChatStatistics messageTypeCounts', () {
    test('aggregates known and unknown types', () {
      final stats = ChatStatistics(
        totalMessages: 0,
        textMessages: 0,
        imageMessages: 0,
        voiceMessages: 0,
        videoMessages: 0,
        otherMessages: 0,
        sentMessages: 0,
        receivedMessages: 0,
        activeDays: 0,
        messageTypeCounts: {
          1: 10,
          244813135921: 5,
          3: 2,
          999: 7,
        },
      );

      final dist = stats.messageTypeDistribution;
      expect(dist['\u6587\u672c'], 15);
      expect(dist['\u56fe\u7247'], 2);
      expect(dist['\u5176\u4ed6'], 7);
    });

    test('round-trip json preserves counts', () {
      final stats = ChatStatistics(
        totalMessages: 1,
        textMessages: 1,
        imageMessages: 0,
        voiceMessages: 0,
        videoMessages: 0,
        otherMessages: 0,
        sentMessages: 1,
        receivedMessages: 0,
        activeDays: 1,
        messageTypeCounts: {
          1: 1,
          42: 2,
        },
      );

      final restored = ChatStatistics.fromJson(stats.toJson());
      expect(restored.messageTypeCounts[1], 1);
      expect(restored.messageTypeCounts[42], 2);
    });
  });
}
