import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../config/annual_report_texts.dart';
import '../../models/advanced_analytics_data.dart';

class AnnualReportHtmlRenderer {
  static Map<String, String>? _fontCache;

  static num _parseNum(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value;
    if (value is String) return num.tryParse(value) ?? 0;
    return 0;
  }

  static Future<String> build({
    required Map<String, dynamic> reportData,
    int? year,
  }) async {
    _fontCache ??= await _loadFonts();
    final fonts = _fontCache!;

    final yearText = year != null ? '${year}年' : '历史以来';
    final reportFileName = year != null ? 'report_$year.png' : 'report_all.png';
    final numberFormat = NumberFormat.decimalPattern();

    // --- 数据准备 ---
    final totalMessages = _parseNum(reportData['totalMessages']).toInt();
    final totalFriends = _parseNum(reportData['totalFriends']).toInt();

    final List<dynamic> coreFriendsJson = reportData['coreFriends'] ?? [];
    final coreFriends = coreFriendsJson
        .map((e) => FriendshipRanking.fromJson(e))
        .toList();
    final topFriend = coreFriends.isNotEmpty ? coreFriends.first : null;

    final List<dynamic> confidantJson = reportData['confidant'] ?? [];
    final confidants = confidantJson
        .map((e) => FriendshipRanking.fromJson(e))
        .toList();
    final topConfidant = confidants.isNotEmpty ? confidants.first : null;

    final List<dynamic> listenersJson = reportData['listeners'] ?? [];
    final listeners = listenersJson
        .map((e) => FriendshipRanking.fromJson(e))
        .toList();
    final topListener = listeners.isNotEmpty ? listeners.first : null;

    final List<dynamic> monthlyTopFriends =
        (reportData['monthlyTopFriends'] as List?) ?? [];
    final selfAvatarUrl = reportData['selfAvatarUrl'] as String? ?? '';

    final List<dynamic> mutualFriendsJson = reportData['mutualFriends'] ?? [];
    final mutualFriends = mutualFriendsJson
        .map((e) => FriendshipRanking.fromJson(e))
        .toList();

    final socialDataJson = reportData['socialInitiative'];
    final socialData = socialDataJson is Map<String, dynamic>
        ? SocialStyleData.fromJson(socialDataJson)
        : SocialStyleData(initiativeRanking: []);
    final socialTop = socialData.initiativeRanking.isNotEmpty
        ? socialData.initiativeRanking.first
        : null;

    final peakDayJson = reportData['peakDay'];
    final ChatPeakDay? peakDay = peakDayJson is Map<String, dynamic>
        ? ChatPeakDay.fromJson(peakDayJson)
        : null;

    final checkIn = reportData['checkIn'] as Map<String, dynamic>? ?? {};
    final checkInDays = _parseNum(checkIn['days']).toInt();
    final checkInName = checkIn['displayName'] ?? '未知';
    final checkInStart = _formatDate(checkIn['startDate'] as String?);
    final checkInEnd = _formatDate(checkIn['endDate'] as String?);

    final activityJson = reportData['activityPattern'];
    final ActivityHeatmap? activity = activityJson is Map<String, dynamic>
        ? ActivityHeatmap.fromJson(activityJson)
        : null;
    final mostActive = activity?.getMostActiveTime();
    final mostActiveHour = mostActive?['hour'];
    final mostActiveWeekday = mostActive?['weekday'];

    final midnightKing =
        reportData['midnightKing'] as Map<String, dynamic>? ?? {};
    final midnightName = midnightKing['displayName'] ?? '未知';
    final midnightCount = _parseNum(midnightKing['count']).toInt();
    final midnightPctVal = _parseNum(midnightKing['percentage']);
    final midnightPercentage = midnightPctVal.toStringAsFixed(1);

    final whoRepliesFastest = (reportData['whoRepliesFastest'] as List?) ?? [];
    final myFastestReplies = (reportData['myFastestReplies'] as List?) ?? [];

    final wordCloudData =
        reportData['wordCloud'] as Map<String, dynamic>? ?? {};
    final wordCloudWords = (wordCloudData['words'] as List?) ?? [];

    final formerFriends = (reportData['formerFriends'] as List?) ?? [];
    final formerFriendsStats =
        reportData['formerFriendsStats'] as Map<String, dynamic>?;
    final includeFormerFriends = year == null;

    // --- HTML 构建 ---
    final buffer = StringBuffer();
    buffer.writeln('<!doctype html>');
    buffer.writeln('<html lang="zh-CN">');
    buffer.writeln('<head>');
    buffer.writeln('<meta charset="utf-8" />');
    buffer.writeln(
      '<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover" />',
    );
    buffer.writeln(
      '<script src="https://cdnjs.cloudflare.com/ajax/libs/html2canvas/1.4.1/html2canvas.min.js"></script>',
    );
    buffer.writeln('<style>');
    buffer.writeln(_buildCss(fonts['regular']!, fonts['bold']!));
    buffer.writeln('</style>');
    buffer.writeln('</head>');
    buffer.writeln('<body>');

    buffer.writeln('<main class="main-container" id="capture">');
    buffer.writeln(_buildNav(reportFileName));

    buffer.writeln(_section('cover', 'cover', _buildCoverBody(yearText)));

    buffer.writeln(
      _section(
        'intro',
        'intro',
        _buildIntroBody(numberFormat, totalFriends, totalMessages),
      ),
    );

    buffer.writeln(
      _section(
        'friendship',
        'friendship',
        _buildFriendshipBody(
          numberFormat,
          topFriend,
          topConfidant,
          topListener,
        ),
      ),
    );

    buffer.writeln(
      _section(
        'monthly',
        'monthly',
        _buildMonthlyBody(yearText, monthlyTopFriends, selfAvatarUrl),
      ),
    );

    buffer.writeln(
      _section(
        'mutual',
        'mutual',
        _buildMutualBody(numberFormat, mutualFriends),
      ),
    );

    buffer.writeln(
      _section('initiative', 'initiative', _buildSocialBody(socialTop)),
    );

    buffer.writeln(
      _section('peak', 'peak-day', _buildPeakBody(numberFormat, peakDay)),
    );

    buffer.writeln(
      _section(
        'checkin',
        'checkin',
        _buildCheckInBody(
          numberFormat,
          checkInName,
          checkInDays,
          checkInStart,
          checkInEnd,
        ),
      ),
    );

    final activityText = (mostActiveHour != null && mostActiveWeekday != null)
        ? '在 <span class="hl">${_weekdayName(mostActiveWeekday)} ${mostActiveHour.toString().padLeft(2, '0')}:00</span> 最活跃'
        : '暂无作息数据';
    buffer.writeln(
      _section(
        'activity',
        'activity',
        _buildActivityBody(activityText, activity),
      ),
    );

    buffer.writeln(
      _section(
        'midnight',
        'midnight',
        _buildMidnightBody(
          numberFormat,
          midnightName,
          midnightCount,
          midnightPercentage,
        ),
      ),
    );

    buffer.writeln(
      _section(
        'response',
        'response',
        _buildResponseHtml(whoRepliesFastest, myFastestReplies),
      ),
    );

    buffer.writeln(
      _section(
        'wordcloud',
        'wordcloud',
        _buildWordCloudBody(wordCloudWords, year),
      ),
    );

    if (includeFormerFriends) {
      buffer.writeln(
        _section(
          'former',
          'former',
          _buildFormerBody(formerFriends, formerFriendsStats, numberFormat),
        ),
      );
    }

    buffer.writeln(_section('ending', 'ending', _buildEndingBody()));

    buffer.writeln('</main>');

    buffer.writeln('''
      <div id="modal" class="modal">
        <div class="modal-content">
          <div class="modal-header">长按下方图片保存到相册</div>
          <div style="overflow:auto; max-height:80vh; width:100%;">
            <img id="result-img" />
          </div>
          <button class="close-btn" onclick="document.getElementById('modal').style.display='none'">关闭</button>
        </div>
      </div>
      <div id="loading" class="loading-mask">
        <div class="spinner"></div>
        <div style="margin-top:12px; font-size:14px; color:#fff;">正在生成长图...</div>
      </div>
    ''');

    buffer.writeln('</body>');
    buffer.writeln('</html>');

    return buffer.toString();
  }

  static Future<Map<String, String>> _loadFonts() async {
    final regular = await rootBundle.load(
      'assets/HarmonyOS_SansSC/HarmonyOS_SansSC_Regular.ttf',
    );
    final bold = await rootBundle.load(
      'assets/HarmonyOS_SansSC/HarmonyOS_SansSC_Bold.ttf',
    );
    return {
      'regular': base64Encode(regular.buffer.asUint8List()),
      'bold': base64Encode(bold.buffer.asUint8List()),
    };
  }

  static String _buildCss(String regularFont, String boldFont) {
    return '''
@font-face { font-family: "H"; src: url("data:font/ttf;base64,$regularFont") format("truetype"); font-weight: 400; }
@font-face { font-family: "H"; src: url("data:font/ttf;base64,$boldFont") format("truetype"); font-weight: 700; }

:root {
  --primary: #07C160; 
  --accent: #F2AA00; 
  --text-main: #222222;
  --text-sub: #555555;
  --bg-color: #F9F8F6;
  --line-color: rgba(0,0,0,0.06);
}

* { box-sizing: border-box; margin: 0; padding: 0; }
html { min-height: 100%; scroll-behavior: smooth; }
body {
  min-height: 100vh;
  width: 100%;
  background-color: var(--bg-color);
  font-family: "H", "PingFang SC", sans-serif;
  color: var(--text-main);
  overflow-y: auto;
  overflow-x: hidden;
}
.main-container {
  width: 100%;
  scroll-snap-type: y mandatory;
  background-color: var(--bg-color); 
}
body::before {
  content: "";
  position: fixed;
  inset: 0;
  background: 
    radial-gradient(circle at 90% 5%, rgba(242, 170, 0, 0.06), transparent 50%),
    radial-gradient(circle at 5% 90%, rgba(7, 193, 96, 0.08), transparent 50%);
  pointer-events: none;
  z-index: -1;
}

section.page {
  min-height: 100vh;
  width: 100%;
  scroll-snap-align: start;
  display: flex;
  flex-direction: column;
  justify-content: center;
  padding: 80px max(8%, 30px);
  position: relative;
}

.content-wrapper {
  max-width: 1000px;
  width: 100%;
  margin: 0 auto;
  opacity: 1; 
  transform: translateY(0);
}

section.page.visible .content-wrapper {
  animation: fadeUp 1s cubic-bezier(0.2, 0.8, 0.2, 1) forwards;
}
@keyframes fadeUp {
  from { opacity: 0; transform: translateY(40px); }
  to { opacity: 1; transform: translateY(0); }
}


.label-text { font-size: 13px; letter-spacing: 3px; text-transform: uppercase; color: #888; margin-bottom: 16px; font-weight: 600; }
.hero-title { font-size: clamp(36px, 5vw, 64px); font-weight: 700; line-height: 1.1; margin-bottom: 24px; }
.hero-desc { font-size: 18px; line-height: 1.7; color: var(--text-sub); max-width: 650px; }
.big-stat { display: flex; align-items: baseline; flex-wrap: wrap; gap: 8px; margin: 30px 0; }
.stat-num { font-size: clamp(48px, 8vw, 96px); font-weight: 700; color: var(--primary); line-height: 1; font-feature-settings: "tnum"; }
.stat-unit { font-size: 20px; color: var(--text-sub); }
.divider { width: 80px; height: 3px; background: var(--accent); margin: 36px 0; border: none; opacity: 0.8; }
.hl { color: var(--primary); font-weight: 700; }
.gold { color: var(--accent); font-weight: 700; }

.data-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); gap: 32px; margin-top: 40px; }
.data-grid > div { transition: transform 0.25s ease, box-shadow 0.25s ease; }
.data-grid > div:hover { transform: translateY(-4px); box-shadow: 0 12px 24px rgba(0,0,0,0.08); }
.list-item { border-bottom: 1px solid var(--line-color); padding-bottom: 12px; margin-bottom: 16px; display: flex; justify-content: space-between; align-items: baseline; }
.item-name { font-size: 18px; font-weight: 600; color: var(--text-main); }
.item-val { font-size: 15px; color: var(--text-sub); }

.monthly-orbit {
  --radius: 210px;
  position: relative;
  width: min(720px, 100%);
  height: 560px;
  margin: 40px auto 0;
}
.monthly-center {
  position: absolute;
  left: 50%;
  top: 50%;
  transform: translate(-50%, -50%);
  text-align: center;
  z-index: 2;
}
.monthly-item {
  position: absolute;
  left: 50%;
  top: 50%;
  width: 120px;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 6px;
  text-align: center;
  transform: translate(-50%, -50%) rotate(calc(var(--i) * 30deg)) translateY(calc(-1 * var(--radius))) rotate(calc(var(--i) * -30deg));
  z-index: 1;
  transition: transform 0.35s ease;
}
.monthly-item:hover {
  transform: translate(-50%, -50%) rotate(calc(var(--i) * 30deg)) translateY(calc(-1 * var(--radius))) rotate(calc(var(--i) * -30deg)) scale(1.05);
}
.month-label { font-size: 12px; color: #999; letter-spacing: 1px; line-height: 1.1; }
.month-name {
  margin-top: 8px;
  font-size: 12px;
  color: var(--text-sub);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  width: 100%;
  line-height: 1.2;
}
.monthly-note { position: absolute; right: 0; bottom: 0; font-size: 13px; color: #777; text-align: right; line-height: 1.6; }

.avatar {
  width: 56px;
  height: 56px;
  border-radius: 50%;
  background: #EEE;
  display: flex;
  align-items: center;
  justify-content: center;
  overflow: hidden;
  border: 2px solid #fff;
  box-shadow: 0 8px 20px rgba(0,0,0,0.08);
  transition: transform 0.25s ease, box-shadow 0.25s ease;
}
.avatar:hover { transform: translateY(-2px); box-shadow: 0 12px 24px rgba(0,0,0,0.12); }
.avatar img { width: 100%; height: 100%; object-fit: cover; display: block; }
.avatar span { font-size: 18px; color: #666; font-weight: 700; }
.avatar.lg {
  width: 90px;
  height: 90px;
  border: 3px solid #fff;
  box-shadow: 0 10px 30px rgba(7, 193, 96, 0.25);
}

.heatmap-wrapper {
  margin-top: 36px;
  width: 100%;
  max-width: 900px;
  --gap: 3px; 
}
.heatmap-header {
  display: grid;
  grid-template-columns: 24px 1fr; 
  gap: var(--gap);
  margin-bottom: 8px;
  color: #999;
  font-size: 11px;
}
.time-labels {
  display: grid;
  grid-template-columns: repeat(24, 1fr);
  gap: var(--gap);
  position: relative;
}
.time-labels span {
  grid-column-end: span 4; 
  white-space: nowrap;
  text-align: left; 
  font-family: monospace; 
  transform: translateX(-1px); 
}
.heatmap {
  display: grid;
  grid-template-columns: 24px 1fr;
  gap: var(--gap);
  align-items: stretch;
}
.heatmap-week-col {
  display: grid;
  grid-template-rows: repeat(7, 1fr);
  gap: var(--gap);
  text-align: left;
  font-size: 11px;
  color: #999;
}
.week-label { display: flex; align-items: center; }
.heatmap-grid {
  display: grid;
  grid-template-columns: repeat(24, 1fr); 
  gap: var(--gap);
  width: 100%;
}
.h-cell {
  aspect-ratio: 1;
  background: rgba(0,0,0,0.03);
  border-radius: 2px;
}
.heatmap-tag-row {
  display: flex;
  justify-content: flex-end;
  margin-top: 12px;
  font-size: 10px;
  color: #bbb;
  letter-spacing: 1px;
  text-transform: uppercase;
}

.word-cloud-wrapper {
  margin: 16px auto 0;
  padding: 0;
  border: none;
  box-shadow: none;
  max-width: 920px;
  display: flex;
  justify-content: center;
  --cloud-scale: clamp(0.72, 80vw / 520, 1);
}

.word-cloud-inner {
  position: relative;
  width: 520px;
  height: 520px;
  margin: 0;
  border-radius: 50%;
  transform: scale(var(--cloud-scale));
  transform-origin: center;
}

.word-cloud-inner::before {
  content: "";
  position: absolute;
  inset: -6%;
  background:
    radial-gradient(circle at 35% 45%, rgba(7, 193, 96, 0.12), transparent 55%),
    radial-gradient(circle at 65% 50%, rgba(242, 170, 0, 0.1), transparent 58%),
    radial-gradient(circle at 50% 65%, rgba(0, 0, 0, 0.04), transparent 60%);
  filter: blur(18px);
  border-radius: 50%;
  pointer-events: none;
  z-index: 0;
}

.word-tag {
  display: inline-block;
  padding: 0;
  background: transparent;
  border-radius: 0;
  border: none;
  line-height: 1.2;
  white-space: nowrap;
  transition: transform 0.2s ease, color 0.2s ease;
  cursor: default;
  color: #2F3437;
  font-weight: 600;
  opacity: 0;
  animation: popIn 0.55s ease forwards;
  position: absolute;
  z-index: 1;
  left: 50%;
  top: 50%;
  transform: translate(-50%, -50%) scale(0.8);
}

.word-tag:hover {
  transform: translate(-50%, -50%) scale(1.08);
  color: var(--primary);
  z-index: 2;
  opacity: 1;
}

@keyframes popIn {
  0% {
    opacity: 0;
    transform: translate(-50%, -50%) scale(0.6);
  }
  100% {
    opacity: var(--final-opacity, 1);
    transform: translate(-50%, -50%) scale(1);
  }
}

.sentence-cloud-container {
  display: flex;
  flex-direction: column;
  gap: 12px;
  padding: 30px 20px;
  background: linear-gradient(135deg, rgba(7, 193, 96, 0.03) 0%, rgba(242, 170, 0, 0.03) 100%);
  border-radius: 20px;
  max-width: 900px;
  margin: 0 auto;
  max-height: 600px;
  overflow-y: auto;
}
.sentence-item {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 12px 16px;
  background: rgba(255, 255, 255, 0.6);
  border-radius: 12px;
  transition: all 0.3s ease;
  cursor: help;
  border-left: 4px solid currentColor;
}
.sentence-item:hover {
  background: rgba(255, 255, 255, 0.9);
  transform: translateX(4px);
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.1);
}
.sentence-text {
  flex: 1;
  font-weight: 500;
  line-height: 1.6;
  word-break: break-word;
}
.sentence-count {
  margin-left: 16px;
  font-size: 0.7em;
  opacity: 0.7;
  font-weight: 600;
  white-space: nowrap;
}

.capture-btn { margin-top: 40px; padding: 14px 28px; border-radius: 99px; background: var(--primary); color: white; border: none; font-size: 16px; font-weight: 600; box-shadow: 0 4px 12px rgba(7, 193, 96, 0.3); cursor: pointer; width: 100%; max-width: 240px; transition: all 0.3s ease; }
.capture-btn:hover { transform: translateY(-2px); box-shadow: 0 6px 16px rgba(7, 193, 96, 0.4); }
.capture-btn:disabled { opacity: 0.6; cursor: not-allowed; transform: none; }
.capture-btn:active { transform: translateY(1px) scale(0.98); box-shadow: 0 2px 8px rgba(7, 193, 96, 0.3); }
.capture-btn.module-btn { margin-top: 0; background: var(--accent); box-shadow: 0 4px 12px rgba(242, 170, 0, 0.3); }
.capture-btn.module-btn:hover { box-shadow: 0 6px 16px rgba(242, 170, 0, 0.4); }

.module-progress { position: fixed; top: 50%; left: 50%; transform: translate(-50%, -50%); background: white; padding: 32px 48px; border-radius: 16px; box-shadow: 0 20px 60px rgba(0,0,0,0.2); z-index: 10001; text-align: center; min-width: 280px; }
.module-progress h3 { margin: 0 0 16px; font-size: 18px; color: var(--text-main); }
.module-progress .progress-bar { height: 8px; background: #eee; border-radius: 4px; overflow: hidden; margin-bottom: 12px; }
.module-progress .progress-fill { height: 100%; background: var(--primary); transition: width 0.3s ease; }
.module-progress .progress-text { font-size: 14px; color: var(--text-sub); }

.module-selector-modal { position: fixed; inset: 0; background: rgba(0,0,0,0.6); z-index: 10001; display: flex; justify-content: center; align-items: center; }
.module-selector-content { background: white; padding: 28px 32px; border-radius: 16px; box-shadow: 0 20px 60px rgba(0,0,0,0.3); max-width: 400px; width: 90%; max-height: 80vh; display: flex; flex-direction: column; }
.module-selector-content h3 { margin: 0 0 20px; font-size: 20px; color: var(--text-main); text-align: center; }
.module-list { display: flex; flex-direction: column; gap: 8px; max-height: 400px; overflow-y: auto; padding-right: 8px; margin-bottom: 20px; }
.module-item { display: flex; align-items: center; gap: 12px; padding: 10px 14px; background: #f8f8f8; border-radius: 8px; cursor: pointer; transition: all 0.2s; }
.module-item:hover { background: #f0f0f0; }
.module-item input[type="checkbox"] { width: 18px; height: 18px; accent-color: var(--primary); cursor: pointer; }
.module-item span { font-size: 14px; color: var(--text-main); }
.module-selector-actions { display: flex; gap: 10px; justify-content: center; }
.select-action-btn { padding: 6px 16px; border: 1px solid #ddd; background: white; border-radius: 6px; font-size: 13px; color: #666; cursor: pointer; transition: all 0.2s; }
.select-action-btn:hover { background: #f5f5f5; border-color: #ccc; }
.module-selector-buttons { display: flex; gap: 12px; justify-content: center; }
.module-selector-buttons .cancel-btn { padding: 12px 28px; border: 1px solid #ddd; background: white; border-radius: 99px; font-size: 15px; color: #666; cursor: pointer; transition: all 0.2s; }
.module-selector-buttons .cancel-btn:hover { background: #f5f5f5; }
.module-selector-buttons .confirm-btn { padding: 12px 28px; border: none; background: var(--primary); border-radius: 99px; font-size: 15px; color: white; font-weight: 600; cursor: pointer; box-shadow: 0 4px 12px rgba(7, 193, 96, 0.3); transition: all 0.2s; }
.module-selector-buttons .confirm-btn:hover { transform: translateY(-2px); box-shadow: 0 6px 16px rgba(7, 193, 96, 0.4); }

.modal { display: none; position: fixed; inset: 0; background: rgba(0,0,0,0.85); z-index: 9999; justify-content: center; align-items: center; }
.modal-content { background: #fff; padding: 20px; border-radius: 12px; width: 90%; max-width: 500px; display: flex; flex-direction: column; align-items: center; }
.modal-header { margin-bottom: 12px; font-weight: bold; color: #333; }
#result-img { max-width: 100%; display: block; border: 1px solid #eee; }
.close-btn { margin-top: 16px; padding: 8px 24px; background: #eee; border: none; border-radius: 4px; color: #333; cursor: pointer; }

.loading-mask { display: none; position: fixed; inset: 0; background: rgba(0,0,0,0.7); z-index: 10000; flex-direction: column; justify-content: center; align-items: center; }
.spinner { width: 40px; height: 40px; border: 4px solid #fff; border-top-color: transparent; border-radius: 50%; animation: spin 1s linear infinite; }
@keyframes spin { to { transform: rotate(360deg); } }

@media (max-width: 768px) {
  section.page { padding: 60px 24px; min-height: 100vh; }
  .hero-title { font-size: 40px; }
  .stat-num { font-size: 60px; }
  .heatmap-header, .heatmap-week-col { font-size: 9px; }
  .monthly-orbit { --radius: 150px; height: 460px; }
  .monthly-item { width: 90px; gap: 4px; }
  .avatar { width: 44px; height: 44px; }
  .avatar.lg { width: 72px; height: 72px; }
  .month-name { font-size: 11px; }
  .monthly-note { font-size: 12px; }
}

@media (prefers-reduced-motion: reduce) {
  * { animation-duration: 0.001ms !important; animation-iteration-count: 1 !important; transition-duration: 0.001ms !important; scroll-behavior: auto !important; }
  .main-container { scroll-snap-type: none; }
}
    ''';
  }

  static String _section(String id, String className, String content) {
    return '<section class="page $className" id="$id"><div class="content-wrapper">$content</div></section>';
  }

  static String _buildCoverBody(String yearText) {
    return '''
<div class="label-text">ECHO TRACE · ANNUAL REPORT</div>
<div class="hero-title">$yearText<br/>微信聊天报告</div>
<hr class="divider">
<div class="hero-desc">${_escapeHtmlWithBreaks(AnnualReportTexts.coverPoem1)}<br/>${_escapeHtmlWithBreaks(AnnualReportTexts.coverPoem2)}</div>
''';
  }

  static String _buildIntroBody(NumberFormat fmt, int friends, int messages) {
    return '''
<div class="label-text">年度概览</div>
<div class="hero-title">你和你的朋友们<br>互相发过</div>
<div class="big-stat">
  <div class="stat-num">${fmt.format(messages)}</div>
  <div class="stat-unit">条消息</div>
</div>
<div class="hero-desc">在这段时光里，你与 <span class="hl">${fmt.format(friends)}</span> 位好友交换过喜怒哀乐。<br>每一个对话，都是一段故事的开始。</div>
''';
  }

  static String _buildFriendshipBody(
    NumberFormat fmt,
    FriendshipRanking? top,
    FriendshipRanking? confidant,
    FriendshipRanking? listener,
  ) {
    if (top == null) return '<div class="hero-title">暂无数据</div>';
    final confidantSent = confidant?.count ?? 0;
    final confidantReceived = confidant?.details?['receivedCount'] as int? ?? 0;
    final listenerReceived = listener?.count ?? 0;
    final listenerSent = listener?.details?['sentCount'] as int? ?? 0;
    return '''
<div class="label-text">年度挚友</div>
<div class="hero-title">${_escapeHtml(top.displayName)}</div>
<div class="big-stat"><div class="stat-num">${fmt.format(top.count)}</div><div class="stat-unit">条消息</div></div>
<div class="hero-desc">在一起，就可以</div>
<div class="data-grid">
  <div><div class="label-text">倾诉对象</div><div class="item-name">${_escapeHtml(confidant?.displayName ?? '-')}</div><div class="item-val">你发出 ${fmt.format(confidantSent)} 条 · TA发来 ${fmt.format(confidantReceived)} 条</div></div>
  <div><div class="label-text">倾听对象</div><div class="item-name">${_escapeHtml(listener?.displayName ?? '-')}</div><div class="item-val">TA发来 ${fmt.format(listenerReceived)} 条 · 你回复 ${fmt.format(listenerSent)} 条</div></div>
</div>
''';
  }

  static String _buildMonthlyBody(
    String yearText,
    List<dynamic> monthlyTopFriends,
    String selfAvatarUrl,
  ) {
    final items = <String>[];

    for (var i = 0; i < 12; i++) {
      final month = i + 1;
      Map<String, dynamic> data = {};
      for (final entry in monthlyTopFriends) {
        if (entry is Map && _parseNum(entry['month']).toInt() == month) {
          data = Map<String, dynamic>.from(entry);
          break;
        }
      }
      final displayName = (data['displayName'] as String?)?.trim();
      final name = (displayName == null || displayName.isEmpty)
          ? '暂无'
          : displayName;
      final avatarUrl = (data['avatarUrl'] as String?) ?? '';
      final index = month - 1;
      items.add('''
<div class="monthly-item" style="--i: $index;">
  <div class="month-label">${month}月</div>
  ${_buildAvatarHtml(avatarUrl, name, sizeClass: '')}
  <div class="month-name">${_escapeHtml(name)}</div>
</div>
''');
    }

    return '''
<div class="label-text">月度好友</div>
<div class="hero-title">${_escapeHtml(yearText)}月度好友</div>
<div class="hero-desc">根据12个月的聊天习惯</div>

<div class="monthly-orbit">
  ${items.join()}
  <div class="monthly-center">
    ${_buildAvatarHtml(selfAvatarUrl, '我', sizeClass: 'lg')}
  </div>
  <div class="monthly-note">无论什么时候<br/>都有人陪你聊天</div>
</div>
''';
  }

  static String _buildMutualBody(
    NumberFormat fmt,
    List<FriendshipRanking> friends,
  ) {
    if (friends.isEmpty) return '<div class="hero-title">暂无数据</div>';
    final f = friends.first;
    final ratio = f.details?['ratio'] ?? '1.0';
    return '''
<div class="label-text">双向奔赴</div>
<div class="hero-title">默契与平衡</div>
<div class="big-stat"><div class="stat-num">${_escapeHtml(f.displayName)}</div></div>
<div class="hero-desc">你们的互动比例接近 <span class="hl">$ratio</span>。<br>最好的关系，就像你来我往，势均力敌。</div>
''';
  }

  static String _buildSocialBody(FriendshipRanking? social) {
    if (social == null) return '<div class="hero-title">暂无数据</div>';
    final rate = (social.percentage * 100).toStringAsFixed(1);
    return '''
<div class="label-text">社交主动性</div>
<div class="hero-title">主动才有故事</div>
<div class="big-stat"><div class="stat-num">$rate</div><div class="stat-unit">% 主动率</div></div>
<div class="hero-desc">面对 <span class="hl">${_escapeHtml(social.displayName)}</span> 的时候，你总是那个先开口的人。</div>
''';
  }

  static String _buildPeakBody(NumberFormat fmt, ChatPeakDay? peak) {
    if (peak == null) return '<div class="hero-title">暂无数据</div>';
    return '''
<div class="label-text">巅峰时刻</div>
<div class="hero-title">${peak.formattedDate}</div>
<div class="big-stat">一天里你一共发了 <div class="stat-num">${fmt.format(peak.messageCount)}</div><div class="stat-unit">条消息</div></div>
<div class="hero-desc">在这个快节奏的世界，有人正陪在你身边听你慢慢地讲<br>那天，你和 <span class="hl">${_escapeHtml(peak.topFriendDisplayName ?? '好友')}</span> 的 ${fmt.format(peak.topFriendMessageCount)} 条消息见证着这一切<br>有些话，只想对你说</div>
''';
  }

  static String _buildCheckInBody(
    NumberFormat fmt,
    String name,
    int days,
    String? start,
    String? end,
  ) {
    return '''
<div class="label-text">持之以恒</div>
<div class="hero-title">聊天火花</div>

<div class="hero-desc" style="margin-bottom: -10px;">
  与 <span class="hl">${_escapeHtml(name)}</span> 持续了
</div>

<div class="big-stat">
  <div class="stat-num">${fmt.format(days)}</div>
  <div class="stat-unit">天</div>
</div>

<div class="hero-desc">
  从 ${_escapeHtml(start ?? '-')} 到 ${_escapeHtml(end ?? '-')}
</div>

<div class="hero-desc" style="margin-top: 50px; font-weight: 700; letter-spacing: 2px;">
  陪伴，是最长情的告白
</div>
''';
  }

  static String _buildActivityBody(String text, ActivityHeatmap? activity) {
    final heatmap = activity != null ? _buildHeatmapHtml(activity) : '';
    return '''
<div class="label-text">作息规律</div>
<div class="hero-title">时间的痕迹</div>
<div class="hero-desc" style="font-size: 22px; color: var(--text-main); margin-bottom: 30px;">$text</div>
$heatmap
''';
  }

  static String _buildMidnightBody(
    NumberFormat fmt,
    String name,
    int count,
    String pct,
  ) {
    return '''
<div class="label-text">深夜好友</div>
<div class="hero-title">当城市睡去</div>
<div class="big-stat">你却有<div class="stat-num">$count</div><div class="stat-unit">次深夜对话</div></div>
<div class="hero-desc">其中 <span class="hl">${_escapeHtml(name)}</span> 常常在深夜中陪着你。<br>你和Ta的对话占深夜期间聊天的 <span class="gold">$pct%</span>。</div>
''';
  }

  static String _buildResponseHtml(List fastest, List myFastest) {
    String buildList(List items, String title) {
      if (items.isEmpty) return '';
      final rows = items
          .take(3)
          .map((e) {
            final name = _escapeHtml(e['displayName'] ?? '-');
            final min = _parseNum(e['avgResponseTimeMinutes']).toDouble();
            String timeStr;
            if (min < 1.0) {
              final seconds = (min * 60).round();
              timeStr = '${seconds}秒';
            } else {
              timeStr = '${min.toStringAsFixed(0)}分钟';
            }
            return '<div class="list-item"><div class="item-name">$name</div><div class="item-val">$timeStr</div></div>';
          })
          .join('');
      return '<div><div class="label-text" style="margin-bottom:20px;">$title</div>$rows</div>';
    }

    return '''
<div class="label-text">回应速度</div>
<div class="hero-title">念念不忘，必有回响</div>
<div class="data-grid">${buildList(fastest, "秒回你的人")}${buildList(myFastest, "你最在意的人")}</div>
''';
  }

  static String _buildWordCloudBody(List words, int? year) {
    final isAllTime = year == null;
    final titleText = isAllTime ? '你历史以来的常用语' : '你在${year}年的年度常用语';
    final subtitleText = isAllTime ? '历史以来，你说得最多的是：' : '这一年，你说得最多的是：';

    if (words.isEmpty) {
      return '''
<div class="label-text">年度常用语</div>
<div class="hero-title">暂无数据</div>
<div class="hero-desc">需要足够的文本消息才能生成</div>
''';
    }

    // 获取最大句子频率用于计算字体大小
    final maxCount = words.isNotEmpty
        ? _parseNum((words.first as Map)['count']).toInt()
        : 1;

    final topWords = words.take(32).toList();
    final rng = Random(42);
    final placed = <Map<String, double>>[];
    const baseSize = 520.0;

    bool canPlace(double x, double y, double w, double h) {
      final halfW = w / 2;
      final halfH = h / 2;
      final dx = x - 50;
      final dy = y - 50;
      final dist = sqrt(dx * dx + dy * dy);
      final maxR = 49 - max(halfW, halfH);
      if (dist > maxR) return false;
      const pad = 1.8;
      for (final p in placed) {
        final px = p['x']!;
        final py = p['y']!;
        final pw = p['w']!;
        final ph = p['h']!;
        if ((x - halfW - pad) < (px + pw / 2) &&
            (x + halfW + pad) > (px - pw / 2) &&
            (y - halfH - pad) < (py + ph / 2) &&
            (y + halfH + pad) > (py - ph / 2)) {
          return false;
        }
      }
      return true;
    }

    // 构建词云标签（显示前32个，避免重叠）
    final wordItems = <String>[];
    for (var i = 0; i < topWords.length; i++) {
      final item = topWords[i] as Map;
      final rawWord = item['word']?.toString() ?? '';
      final sentence = _escapeHtml(rawWord);
      final count = _parseNum(item['count']).toInt();

      // 根据频率计算字体大小 (12px - 32px)
      final ratio = count / maxCount;
      final fontSize = (12 + pow(ratio, 0.65) * 20).round();
      final opacity = (0.35 + ratio * 0.65).clamp(0.35, 1.0);
      final delay = (i * 0.04).toStringAsFixed(2);

      final charCount = max(1, rawWord.runes.length);
      final hasCjk = RegExp(r'[\u4e00-\u9fff]').hasMatch(rawWord);
      final hasLatin = RegExp(r'[A-Za-z0-9]').hasMatch(rawWord);
      final widthFactor = hasCjk && hasLatin
          ? 0.85
          : hasCjk
              ? 0.98
              : 0.6;
      final widthPx = fontSize * (charCount * widthFactor);
      final heightPx = fontSize * 1.1;
      final widthPct = (widthPx / baseSize) * 100;
      final heightPct = (heightPx / baseSize) * 100;

      double x = 50;
      double y = 50;
      bool placedOk = false;
      final tries = i == 0 ? 1 : 420;
      for (var t = 0; t < tries; t++) {
        if (i == 0) {
          x = 50;
          y = 50;
        } else {
          final idx = i + t * 0.28;
          final radius = sqrt(idx) * 7.6 + (rng.nextDouble() * 1.2 - 0.6);
          final angle = idx * 2.399963 + rng.nextDouble() * 0.35;
          x = 50 + radius * cos(angle);
          y = 50 + radius * sin(angle);
        }
        if (canPlace(x, y, widthPct, heightPct)) {
          placedOk = true;
          break;
        }
      }
      if (!placedOk) continue;
      placed.add({'x': x, 'y': y, 'w': widthPct, 'h': heightPct});

      wordItems.add('''
<span class="word-tag" style="--final-opacity: $opacity; left: ${x.toStringAsFixed(2)}%; top: ${y.toStringAsFixed(2)}%; font-size: ${fontSize}px; animation-delay: ${delay}s;" title="$sentence (出现 $count 次)">$sentence</span>''');
    }

    // 获取前3个高频句子展示
    final topThree = words
        .take(3)
        .map((item) {
          final sentence = _escapeHtml((item as Map)['word'] ?? '');
          return sentence;
        })
        .join('、');

    return '''
<div class="label-text">年度常用语</div>
<div class="hero-title">$titleText</div>
<div class="hero-desc" style="margin-bottom: 30px;">$subtitleText<br><span class="hl" style="font-size: 20px;">$topThree</span></div>
<div class="word-cloud-wrapper"><div class="word-cloud-inner">${wordItems.join()}</div></div>
<div class="hero-desc" style="margin-top: 30px; font-size: 14px; color: #999;">颜色越深代表出现频率越高</div>
''';
  }

  static String _buildFormerBody(List former, Map? stats, NumberFormat fmt) {
    if (former.isEmpty) {
      String message = AnnualReportTexts.formerFriendNoData;
      if (stats != null) {
        final totalSessions = stats['totalSessions'] as int? ?? 0;
        final sessionsWithMessages = stats['sessionsWithMessages'] as int? ?? 0;
        final sessionsUnder14Days = stats['sessionsUnder14Days'] as int? ?? 0;
        if (totalSessions > 0 && sessionsWithMessages > 0) {
          if (sessionsUnder14Days == sessionsWithMessages) {
            message =
                '${AnnualReportTexts.formerFriendInsufficientData}<br/>${AnnualReportTexts.formerFriendInsufficientDataDetail}';
          } else if (sessionsUnder14Days > 0) {
            message =
                '${AnnualReportTexts.formerFriendNoQualified}<br/>有 $sessionsUnder14Days 个好友聊天记录不足14天<br/>其他好友未符合条件';
          } else {
            message =
                '${AnnualReportTexts.formerFriendNoQualified}<br/>${AnnualReportTexts.formerFriendAllGoodRelations}';
          }
        }
      }
      return '<div class="label-text">旧日足迹</div><div class="hero-title">无需追忆</div><div class="hero-desc">$message</div>';
    }
    final d = former.first as Map<String, dynamic>;
    final activeDays = _parseNum(d['activeDays']).toInt();
    final activeDaysCount = _parseNum(d['activeDaysCount']).toInt();
    final messageCount = _parseNum(d['activeMessageCount']).toInt();
    final daysSince = _parseNum(d['daysSinceActive']).toInt();
    return '''
<div class="label-text">曾经的好朋友</div>
<div class="hero-title">时间都带我遇见了谁<br>又留下了些什么？</div>
<div class="hero-desc"><br>你与 <span class="hl">${_escapeHtml(d['displayName'])}</span> 曾经连续聊了 ${fmt.format(activeDays)} 天<br>（${_formatDate(d['activeStartDate'])} 至 ${_formatDate(d['activeEndDate'])}）<br><br>只要好友还在，我们还记得彼此<br>总有一天，我们会再次相见</div>
<div class="data-grid">
  <div><div class="label-text">曾经</div><div class="item-name">${fmt.format(activeDaysCount)} 天</div><div class="item-val">产生 ${fmt.format(messageCount)} 条回忆</div></div>
  <div><div class="label-text">离别已</div><div class="item-name">${fmt.format(daysSince)} 天</div><div class="item-val">最后一次对话于 ${_formatDate(d['lastMessageDate'] ?? d['activeEndDate'])}</div></div>
</div>
''';
  }

  static String _buildEndingBody() {
    return '''
<div class="hero-title">尾声</div>
<div class="hero-desc" style="max-width: 100%; margin-top: 40px;">我们总是在向前走<br>却很少有机会回头看看<br>如果这份报告让你有所触动，不妨把它分享给你在意的人<br>愿新的一年，<br>所有期待，皆有回声。</div>
<hr class="divider" style="margin: 60px 0 30px;">
<div class="label-text" style="color: var(--text-main);">ECHO TRACE</div>
<div style="text-align: center; margin-bottom: 40px; display: flex; flex-direction: column; align-items: center; gap: 12px;">
  <button class="capture-btn" onclick="takeScreenshot()">生成年度长图报告</button>
  <button class="capture-btn module-btn" onclick="takeModuleScreenshots()">分模块导出图片</button>
</div>
''';
  }

  static String _buildHeatmapHtml(ActivityHeatmap activity) {
    final cells = <String>[];
    for (var w = 1; w <= 7; w++) {
      for (var h = 0; h < 24; h++) {
        final val = activity.getNormalizedValue(h, w);
        final alpha = (val * 0.9 + 0.05).clamp(0.05, 1.0);
        cells.add(
          '<div class="h-cell" style="background: rgba(7, 193, 96, $alpha)"></div>',
        );
      }
    }

    final weeks = [
      '周一',
      '周二',
      '周三',
      '周四',
      '周五',
      '周六',
      '周日',
    ].map((e) => '<div class="week-label">$e</div>').join('');

    return '''
<div class="heatmap-wrapper">
  <div class="heatmap-header">
     <div></div> 
     <div class="time-labels">
        <span style="grid-column: 1 / span 4">00:00</span>
        <span style="grid-column: 7 / span 4">06:00</span>
        <span style="grid-column: 13 / span 4">12:00</span>
        <span style="grid-column: 19 / span 4">18:00</span>
     </div>
  </div>
  
  <div class="heatmap">
    <div class="heatmap-week-col">$weeks</div>
    <div class="heatmap-grid">${cells.join()}</div>
  </div>
  
  <div class="heatmap-tag-row">
     <span>24H × 7Days</span>
  </div>
</div>
''';
  }

  static String _formatDate(String? s) => s?.split('T').first ?? '-';
  static String _weekdayName(int? w) =>
      const {
        1: '周一',
        2: '周二',
        3: '周三',
        4: '周四',
        5: '周五',
        6: '周六',
        7: '周日',
      }[w] ??
      '';
  static String _escapeHtml(String s) =>
      const HtmlEscape(HtmlEscapeMode.element).convert(s);
  static String _escapeHtmlWithBreaks(String s) =>
      _escapeHtml(s).replaceAll('\n', '<br/>');

  static String _buildAvatarHtml(
    String? url,
    String name, {
    String sizeClass = '',
  }) {
    final cls = sizeClass.isNotEmpty ? 'avatar $sizeClass' : 'avatar';
    final fallback = _escapeHtml(_initial(name));
    if (url == null || url.trim().isEmpty) {
      return '<div class="$cls"><span>$fallback</span></div>';
    }
    final safeUrl = _escapeHtml(url.trim());
    return '<div class="$cls"><img src="$safeUrl" alt="$fallback" loading="lazy" decoding="async"/></div>';
  }

  static String _initial(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '友';
    final firstRune = trimmed.runes.first;
    return String.fromCharCode(firstRune);
  }

  static String _buildNav(String reportFileName) {
    return '''
<script>
  const moduleNames = {
    'cover': '封面',
    'intro': '年度概览',
    'friendship': '年度挚友',
    'monthly': '月度好友',
    'mutual': '双向奔赴',
    'initiative': '社交主动性',
    'peak': '巅峰时刻',
    'checkin': '聊天火花',
    'activity': '作息规律',
    'midnight': '深夜好友',
    'response': '回应速度',
    'wordcloud': '年度常用语',
    'former': '曾经的好朋友',
    'ending': '尾声'
  };

  try {
    const sections = document.querySelectorAll('section.page');
    const observer = new IntersectionObserver((entries) => {
      entries.forEach(entry => {
        if (entry.isIntersecting) {
          entry.target.classList.add('visible');
        }
      });
    }, { threshold: 0.35 });
    sections.forEach(s => observer.observe(s));
  } catch(e) { console.error(e); }

  function takeScreenshot() {
    const target = document.getElementById('capture');
    const btn = document.querySelector('.capture-btn');
    const loading = document.getElementById('loading');
    
    loading.style.display = 'flex';
    if(btn) btn.style.display = 'none';

    const originalStyle = target.style.cssText;
    target.style.height = 'auto';
    target.style.overflow = 'visible';
    target.style.scrollSnapType = 'none';
    
    const pages = document.querySelectorAll('section.page');
    pages.forEach(p => {
       p.dataset.wasVisible = p.classList.contains('visible') ? '1' : '0';
       p.classList.add('visible');
       p.dataset.originalStyle = p.style.cssText;
       p.style.minHeight = 'auto';
       p.style.height = 'auto';
       p.style.paddingBottom = '60px';
       const wrapper = p.querySelector('.content-wrapper');
       if(wrapper) {
         wrapper.dataset.originalStyle = wrapper.style.cssText;
         wrapper.style.opacity = '1';
         wrapper.style.transform = 'translateY(0)';
         wrapper.style.animation = 'none';
       }
    });

    html2canvas(target, {
      scale: 2, 
      useCORS: true,
      backgroundColor: '#F9F8F6',
      allowTaint: true, 
      logging: false
    }).then(canvas => {
      const imgData = canvas.toDataURL('image/png');
      const isMobile = /Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i.test(navigator.userAgent);
      
      if (!isMobile) {
        const link = document.createElement('a');
        link.download = '$reportFileName';
        link.href = imgData;
        link.click();
        alert('年度报告已生成并下载！');
      } else {
        document.getElementById('result-img').src = imgData;
        document.getElementById('modal').style.display = 'flex';
      }
      cleanup();
    }).catch(err => {
      console.error(err);
      alert('生成失败：' + err.message);
      cleanup();
    });

    function cleanup() {
      loading.style.display = 'none';
      if(btn) btn.style.display = 'inline-block';
      target.style.cssText = originalStyle;
      pages.forEach(p => {
         if (p.dataset.originalStyle !== undefined) {
           p.style.cssText = p.dataset.originalStyle;
           delete p.dataset.originalStyle;
         } else {
           p.style.minHeight = '100vh';
           p.style.height = '';
           p.style.paddingBottom = '';
         }
         if (p.dataset.wasVisible === '1') {
           p.classList.add('visible');
         } else {
           p.classList.remove('visible');
         }
         delete p.dataset.wasVisible;
         const wrapper = p.querySelector('.content-wrapper');
         if (wrapper && wrapper.dataset.originalStyle !== undefined) {
           wrapper.style.cssText = wrapper.dataset.originalStyle;
           delete wrapper.dataset.originalStyle;
         }
      });
    }
  }

  // 显示模块选择弹窗
  function showModuleSelector() {
    const sections = document.querySelectorAll('section.page');
    const sectionIds = Array.from(sections).map(s => s.id);
    
    const modal = document.createElement('div');
    modal.className = 'module-selector-modal';
    modal.innerHTML = \`
      <div class="module-selector-content">
        <h3>选择要导出的模块</h3>
        <div class="module-selector-actions" style="margin-bottom: 16px;">
          <button type="button" onclick="toggleAllModules(true)" class="select-action-btn">全选</button>
          <button type="button" onclick="toggleAllModules(false)" class="select-action-btn">全不选</button>
        </div>
        <div class="module-list">
          \${sectionIds.map((id, index) => \`
            <label class="module-item">
              <input type="checkbox" value="\${id}" checked>
              <span>\${(index + 1).toString().padStart(2, '0')}. \${moduleNames[id] || id}</span>
            </label>
          \`).join('')}
        </div>
        <div class="module-selector-buttons">
          <button type="button" onclick="closeModuleSelector()" class="cancel-btn">取消</button>
          <button type="button" onclick="startModuleExport()" class="confirm-btn">开始导出</button>
        </div>
      </div>
    \`;
    document.body.appendChild(modal);
    
    window.toggleAllModules = (checked) => {
      modal.querySelectorAll('input[type="checkbox"]').forEach(cb => cb.checked = checked);
    };
    
    window.closeModuleSelector = () => {
      modal.remove();
      delete window.toggleAllModules;
      delete window.closeModuleSelector;
      delete window.startModuleExport;
    };
    
    window.startModuleExport = async () => {
      const selectedIds = Array.from(modal.querySelectorAll('input[type="checkbox"]:checked')).map(cb => cb.value);
      modal.remove();
      delete window.toggleAllModules;
      delete window.closeModuleSelector;
      delete window.startModuleExport;
      
      if (selectedIds.length === 0) {
        alert('请至少选择一个模块');
        return;
      }
      
      await exportSelectedModules(selectedIds);
    };
  }

  async function takeModuleScreenshots() {
    showModuleSelector();
  }
  
  async function exportSelectedModules(selectedIds) {
    const allSections = document.querySelectorAll('section.page');
    const sections = Array.from(allSections).filter(s => selectedIds.includes(s.id));
    const allBtns = document.querySelectorAll('.capture-btn');
    
    // 禁用所有按钮
    allBtns.forEach(btn => btn.disabled = true);
    
    // 创建进度提示
    const progressDiv = document.createElement('div');
    progressDiv.className = 'module-progress';
    progressDiv.innerHTML = '<h3>正在生成模块图片</h3><div class="progress-bar"><div class="progress-fill" style="width: 0%"></div></div><div class="progress-text">准备中...</div>';
    document.body.appendChild(progressDiv);
    
    const progressFill = progressDiv.querySelector('.progress-fill');
    const progressText = progressDiv.querySelector('.progress-text');
    
    const images = [];
    const total = sections.length;
    
    // 固定输出尺寸 1920x1080
    const TARGET_WIDTH = 1920;
    const TARGET_HEIGHT = 1080;
    const BG_COLOR = '#F9F8F6';
    
    try {
      for (let i = 0; i < total; i++) {
        const section = sections[i];
        const sectionId = section.id;
        const wasVisible = section.classList.contains('visible');
        section.dataset.wasVisible = wasVisible ? '1' : '0';
        section.classList.add('visible');
        const moduleIndex = selectedIds.indexOf(sectionId) + 1;
        const moduleName = moduleIndex.toString().padStart(2, '0') + '_' + (moduleNames[sectionId] || sectionId);
        
        progressText.textContent = '正在处理: ' + moduleNames[sectionId] + ' (' + (i + 1) + '/' + total + ')';
        progressFill.style.width = ((i / total) * 100) + '%';
        
        // 准备单个模块的截图
        const originalStyle = section.style.cssText;
        
        // 设置固定宽度（scale=2时实际输出为1920px）
        section.style.width = (TARGET_WIDTH / 2) + 'px';
        section.style.minHeight = 'auto';
        section.style.height = 'auto';
        section.style.paddingTop = '60px';
        section.style.paddingBottom = '60px';
        section.style.boxSizing = 'border-box';
        
        const wrapper = section.querySelector('.content-wrapper');
        const wrapperOriginalStyle = wrapper ? wrapper.style.cssText : '';
        if(wrapper) {
          wrapper.style.opacity = '1';
          wrapper.style.transform = 'translateY(0)';
          wrapper.style.animation = 'none';
          wrapper.style.maxWidth = '100%';
        }
        
        // 隐藏结尾页的按钮
        if(sectionId === 'ending') {
          const btnsContainer = section.querySelector('div[style*="flex-direction: column"]');
          if(btnsContainer) btnsContainer.style.display = 'none';
        }
        
        await new Promise(resolve => setTimeout(resolve, 100));
        
        // 先截取内容
        const contentCanvas = await html2canvas(section, {
          scale: 2,
          useCORS: true,
          backgroundColor: BG_COLOR,
          allowTaint: true,
          logging: false,
          width: TARGET_WIDTH / 2,
        });
        
        // 创建固定尺寸的画布 1920x1080
        const finalCanvas = document.createElement('canvas');
        finalCanvas.width = TARGET_WIDTH;
        finalCanvas.height = TARGET_HEIGHT;
        const ctx = finalCanvas.getContext('2d');
        
        // 填充背景色
        ctx.fillStyle = BG_COLOR;
        ctx.fillRect(0, 0, TARGET_WIDTH, TARGET_HEIGHT);
        
        // 计算内容在画布上的位置（居中显示）
        const contentHeight = contentCanvas.height;
        const contentWidth = contentCanvas.width;
        
        // 如果内容超出画布，需要缩放
        let drawWidth = contentWidth;
        let drawHeight = contentHeight;
        let scale = 1;
        
        // 计算缩放比例（保持宽高比）
        const scaleX = TARGET_WIDTH / contentWidth;
        const scaleY = TARGET_HEIGHT / contentHeight;
        scale = Math.min(scaleX, scaleY, 1); // 不放大，只缩小
        
        if (scale < 1) {
          drawWidth = contentWidth * scale;
          drawHeight = contentHeight * scale;
        }
        
        // 居中绘制
        const x = (TARGET_WIDTH - drawWidth) / 2;
        const y = (TARGET_HEIGHT - drawHeight) / 2;
        
        ctx.drawImage(contentCanvas, x, y, drawWidth, drawHeight);
        
        // 恢复样式
        section.style.cssText = originalStyle;
        if(wrapper) wrapper.style.cssText = wrapperOriginalStyle;
        if(sectionId === 'ending') {
          const btnsContainer = section.querySelector('div[style*="flex-direction: column"]');
          if(btnsContainer) btnsContainer.style.display = 'flex';
        }
        if (section.dataset.wasVisible === '1') {
          section.classList.add('visible');
        } else {
          section.classList.remove('visible');
        }
        delete section.dataset.wasVisible;
        
        images.push({
          name: moduleName + '.png',
          data: finalCanvas.toDataURL('image/png')
        });
      }
      
      progressText.textContent = '正在打包下载...';
      progressFill.style.width = '100%';
      
      // 检测是否为移动端
      const isMobile = /Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i.test(navigator.userAgent);
      
      if (isMobile) {
        progressDiv.remove();
        await showMobileImages(images);
      } else {
        for (let i = 0; i < images.length; i++) {
          const img = images[i];
          const link = document.createElement('a');
          link.download = img.name;
          link.href = img.data;
          link.click();
          await new Promise(resolve => setTimeout(resolve, 200));
        }
        
        progressDiv.remove();
        alert('已成功导出 ' + images.length + ' 张模块图片！\\n\\n图片尺寸: 1920x1080');
      }
      
    } catch (err) {
      console.error(err);
      progressDiv.remove();
      alert('生成失败：' + err.message);
    } finally {
      allBtns.forEach(btn => btn.disabled = false);
    }
  }
  
  async function showMobileImages(images) {
    let currentIndex = 0;
    
    const modal = document.createElement('div');
    modal.style.cssText = 'position:fixed;inset:0;background:rgba(0,0,0,0.9);z-index:9999;display:flex;flex-direction:column;align-items:center;padding:20px;';
    
    const updateModal = () => {
      const img = images[currentIndex];
      modal.innerHTML = '<div style="color:white;font-size:14px;margin-bottom:12px;">'+img.name+' ('+(currentIndex+1)+'/'+images.length+')</div><div style="flex:1;overflow:auto;width:100%;display:flex;justify-content:center;"><img src="'+img.data+'" style="max-width:100%;height:auto;border:1px solid #333;"/></div><div style="display:flex;gap:12px;margin-top:16px;"><button onclick="prevModule()" style="padding:10px 20px;border:none;border-radius:8px;background:#555;color:white;cursor:pointer;" '+(currentIndex===0?'disabled':'')+'>上一张</button><button onclick="nextModule()" style="padding:10px 20px;border:none;border-radius:8px;background:var(--primary);color:white;cursor:pointer;">'+(currentIndex===images.length-1?'完成':'下一张')+'</button></div><div style="color:#999;font-size:12px;margin-top:12px;">长按图片保存到相册</div>';
    };
    
    window.prevModule = () => {
      if(currentIndex > 0) {
        currentIndex--;
        updateModal();
      }
    };
    
    window.nextModule = () => {
      if(currentIndex < images.length - 1) {
        currentIndex++;
        updateModal();
      } else {
        modal.remove();
        delete window.prevModule;
        delete window.nextModule;
      }
    };
    
    updateModal();
    document.body.appendChild(modal);
  }
</script>
''';
  }
}
