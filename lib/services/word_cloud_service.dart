// 文件: lib/services/word_cloud_service.dart
// 统一的词云/常用语分析服务

/// 分析模式
enum WordCloudMode {
  /// 句子模式：统计完整句子的出现频率（适用于年度常用语、双人报告）
  sentence,

  /// 词语模式：使用二元分词统计词频（适用于群聊词云）
  word,
}

/// 分析结果
class WordCloudResult {
  /// 词频列表，每项包含 word 和 count
  final List<Map<String, dynamic>> words;

  /// 不同词/句子的总数
  final int totalUniqueCount;

  /// 处理的消息总数
  final int totalMessages;

  WordCloudResult({
    required this.words,
    required this.totalUniqueCount,
    required this.totalMessages,
  });

  Map<String, dynamic> toJson() => {
        'words': words,
        'totalWords': totalUniqueCount,
        'totalMessages': totalMessages,
      };

  bool get isEmpty => words.isEmpty;
}

/// 统一的词云/常用语分析服务
class WordCloudService {
  static WordCloudService? _instance;
  static WordCloudService get instance => _instance ??= WordCloudService._();

  WordCloudService._();

  /// 中文停用词表（扩充版，约200个常用停用词）
  static final Set<String> chineseStopwords = {
    // === 代词 ===
    '我', '你', '他', '她', '它', '们', '我们', '你们', '他们', '她们', '它们',
    '自己', '人家', '咱', '咱们', '大家', '别人', '谁', '某', '某人', '某些',
    '这', '那', '这个', '那个', '这些', '那些', '这里', '那里', '这儿', '那儿',
    '什么', '怎么', '哪', '哪个', '哪些', '哪里', '哪儿', '多少', '几', '几个',

    // === 助词 ===
    '的', '地', '得', '了', '着', '过', '吗', '呢', '吧', '啊', '呀', '啦',
    '哦', '嗯', '哈', '嘿', '哼', '哎', '唉', '额', '呃', '嘛', '噢', '喔',
    '呵', '嘻', '嗨', '哟', '诶', '欸', '咦', '呐', '嘞', '咯', '哩', '嘎',

    // === 连词介词 ===
    '和', '与', '或', '但', '但是', '而', '而且', '并', '并且', '不但', '不仅',
    '因为', '所以', '因此', '如果', '假如', '要是', '虽然', '虽', '即使', '尽管',
    '然后', '接着', '于是', '既然', '无论', '不论', '不管', '只要', '只有', '除非',
    '就', '就是', '也', '都', '还', '又', '再', '才', '便', '却', '倒', '反而',
    '在', '从', '到', '对', '向', '把', '被', '给', '跟', '比', '按', '照', '为',
    '以', '用', '让', '拿', '替', '经', '由', '将', '当', '作为', '关于', '至于',

    // === 副词 ===
    '很', '非常', '太', '更', '最', '挺', '真', '好', '特别', '相当', '十分', '极',
    '不', '没', '没有', '别', '未', '无', '莫', '勿', '休',
    '是', '有', '会', '能', '可以', '可能', '应该', '必须', '需要', '要', '想', '去',
    '来', '做', '干', '搞', '弄', '整', '办', '行', '算', '成',
    '已', '已经', '正在', '正', '刚', '刚才', '曾', '曾经', '将要', '快', '快要',
    '大概', '或许', '一定', '肯定', '当然', '果然', '确实', '的确', '究竟', '到底',

    // === 量词 ===
    '个', '些', '点', '下', '次', '回', '遍', '趟', '番', '场', '阵',
    '只', '条', '张', '件', '本', '支', '块', '片', '根', '棵', '颗',

    // === 时间词 ===
    '时候', '之后', '之前', '以后', '以前', '后来', '当时', '那时', '这时',
    '现在', '目前', '今天', '明天', '昨天', '前天', '后天', '今年', '明年', '去年',
    '早上', '上午', '中午', '下午', '晚上', '半夜', '凌晨',

    // === 方位词 ===
    // ignore: equal_elements_in_set
    '上', '下', '左', '右', '前', '后', '里', '外', '中', '内', '间', '旁', '边',
    '上面', '下面', '前面', '后面', '里面', '外面', '中间', '旁边', '这边', '那边',

    // === 其他常见无意义词 ===
    '一', '一个', '一些', '一样', '一下', '一点', '一起', '一直', '一边',
    '这样', '那样', '这么', '那么', '怎样', '如何', '怎么样', '什么样',
    '还是', '或者', '不是', '知道', '觉得', '感觉', '认为', '发现', '看到', '听到',
    '的话', '东西', '事情', '问题', '情况', '方面', '地方', '样子', '意思',
    '起来', '过来', '过去', '出来', '进来', '回来', '上来', '下来', '出去', '进去',
    '说', '讲', '问', '答', '看', '听', '写', '读', '说道', '告诉',

    // === 网络用语/脏话（过滤）===
    '卧槽', '我靠', '淦', '艹', '尼玛', '妈的', '草', '靠', '操', '日',
    '傻逼', '牛逼', '装逼', '逼', '屌', '滚', '妈', '爹', '爸',
  };

  /// 表情类重复词（保留，不过滤）
  static final Set<String> _emotionalRepeatPatterns = {
    '哈', '呵', '嘿', '嘻', '呜', '唉', '哎', '嗯', '噢', '哦',
    '啊', '呀', '耶', '哟', '喂', '嘞', '咯', '嘎', '嗷', '喵',
  };

  /// 分析文本生成词云/常用语数据
  ///
  /// [texts] 待分析的文本列表
  /// [mode] 分析模式：句子模式或词语模式
  /// [topN] 返回前N个高频项
  /// [minCount] 最小出现次数
  /// [minLength] 最小长度（词语模式下为词长，句子模式下为句子长度）
  /// [maxLength] 最大长度（句子模式下有效）
  Future<WordCloudResult> analyze({
    required List<String> texts,
    WordCloudMode mode = WordCloudMode.sentence,
    int topN = 50,
    int minCount = 2,
    int minLength = 2,
    int maxLength = 200,
  }) async {
    if (texts.isEmpty) {
      return WordCloudResult(
        words: [],
        totalUniqueCount: 0,
        totalMessages: 0,
      );
    }

    final counts = <String, int>{};

    if (mode == WordCloudMode.sentence) {
      // 句子模式：统计完整句子
      for (final text in texts) {
        final normalized = _normalizeSentence(text);
        if (_isValidSentence(normalized, minLength, maxLength)) {
          counts[normalized] = (counts[normalized] ?? 0) + 1;
        }
      }
    } else {
      // 词语模式：使用二元分词

      for (final text in texts) {
        final words = _tokenize(text);
        for (final word in words) {
          if (word.length >= minLength && !chineseStopwords.contains(word)) {
            counts[word] = (counts[word] ?? 0) + 1;
          }
        }
      }
    }

    // 排序并过滤
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final topItems = sorted
        .where((e) => e.value >= minCount)
        .take(topN)
        .map((e) => {'word': e.key, 'count': e.value})
        .toList();

    return WordCloudResult(
      words: topItems,
      totalUniqueCount: counts.length,
      totalMessages: texts.length,
    );
  }

  /// 规范化句子
  String _normalizeSentence(String text) {
    text = text.trim();
    // 合并连续空白
    text = text.replaceAll(RegExp(r'\s+'), ' ');
    // 去除开头的 @ 提及
    text = text.replaceAll(RegExp(r'^@\S+\s*'), '');
    // 去除开头和结尾的方括号标记
    text = text.replaceAll(RegExp(r'^\[.*?\]\s*'), '');
    return text.trim();
  }

  /// 判断句子是否有效
  bool _isValidSentence(String sentence, int minLength, int maxLength) {
    if (sentence.isEmpty) return false;
    if (sentence.length < minLength || sentence.length > maxLength) return false;

    // === 1. 过滤系统/技术性内容 ===

    // 跳过包含 wxid 的句子（通常是引用消息）
    if (sentence.contains('wxid_') ||
        sentence.contains('wxid:') ||
        sentence.toLowerCase().contains('wxid')) {
      return false;
    }

    // 跳过 XML/HTML 消息
    if (sentence.startsWith('<?xml') ||
        sentence.contains('<msg>') ||
        sentence.contains('</msg>')) {
      return false;
    }
    if (sentence.startsWith('<') && sentence.endsWith('>')) return false;

    // 跳过 URL
    if (RegExp(r'https?://').hasMatch(sentence)) return false;

    // 跳过纯数字（电话号码、验证码等）
    if (RegExp(r'^[\d\s\-\+]+$').hasMatch(sentence)) return false;

    // === 2. 检查有意义字符比例 ===

    final chineseChars = RegExp(r'[\u4e00-\u9fa5]').allMatches(sentence).length;
    final englishChars = RegExp(r'[a-zA-Z]').allMatches(sentence).length;
    final digits = RegExp(r'\d').allMatches(sentence).length;
    final meaningfulChars = chineseChars + englishChars + digits;

    // 只要有至少1个有意义字符即接受
    if (meaningfulChars == 0) return false;

    if (RegExp(r'[\uE000-\uF8FF]').hasMatch(sentence)) {
      return false;
    }

    final totalChars = sentence.runes.length;
    if (totalChars == 0) return false;

    if (totalChars > 4) {
      if (chineseChars > 0) {
        if (chineseChars < 2) return false;
        if ((chineseChars / totalChars) < 0.35) return false;
      } else {
        if (englishChars < 3) return false;
        if (((englishChars + digits) / totalChars) < 0.5) return false;
      }
    }

    // === 3. 处理重复字符 ===

    if (sentence.length > 2) {
      final uniqueChars = sentence.split('').toSet();

      // 只有1种字符 - 这种通常是垃圾消息
      if (uniqueChars.length == 1) {
        final char = uniqueChars.first;

        // 如果是标点符号，过滤掉（如 "......"、"！！！"）
        if (RegExp(r'[。，！？、\.…\-\+~～!?.,]').hasMatch(char)) {
          return false;
        }

        // 如果是表情类字符（如 "哈哈哈哈"），保留！
        if (_emotionalRepeatPatterns.contains(char)) {
          return true;
        }

        // 其他单字符重复，超过5个字符就过滤（放宽条件）
        if (sentence.length > 5) {
          return false;
        }
      }
    }

    // === 4. 过滤无意义单字符 ===

    final meaninglessSingleChars = {'嗯', '哦', '啊', '额', '呃', '噢', '喔', '嗷'};
    if (sentence.length == 1 && meaninglessSingleChars.contains(sentence)) {
      return false;
    }

    // === 5. 过滤纯表情包描述 ===

    if (RegExp(r'^\[.+\]$').hasMatch(sentence)) {
      return false;
    }

    return true;
  }

  /// 分词（使用二元分词）
  List<String> _tokenize(String text) {
    // 使用二元分词
    return _tokenizeBigram(text);
  }

  /// 二元分词
  List<String> _tokenizeBigram(String text) {
    final words = <String>[];

    // 匹配中文字符块
    final chinesePattern = RegExp(r'[\u4e00-\u9fa5]+');
    final matches = chinesePattern.allMatches(text);

    for (final match in matches) {
      final segment = match.group(0)!;
      if (segment.length >= 2) {
        // 滑动窗口生成二元词组
        for (int i = 0; i < segment.length - 1; i++) {
          words.add(segment.substring(i, i + 2));
        }
      }
    }

    // 匹配英文和数字
    final englishPattern = RegExp(r'[a-zA-Z0-9]+');
    final englishMatches = englishPattern.allMatches(text);
    for (final match in englishMatches) {
      final word = match.group(0)!.toLowerCase();
      if (word.length >= 2) {
        words.add(word);
      }
    }

    return words;
  }

  /// 过滤文本消息内容
  /// 返回适合进行分析的文本列表
  static List<String> filterTextMessages(List<String> contents) {
    return contents
        .where((c) => c.isNotEmpty)
        .where((c) => !c.startsWith('['))
        .where((c) => !c.startsWith('<?xml'))
        .where((c) => !c.contains('<msg>'))
        .where((c) => c.length > 1)
        .where(_looksReadableForWordCloud)
        .toList();
  }

  static bool _looksReadableForWordCloud(String text) {
    if (text.isEmpty) return false;

    final compact = text.replaceAll(
      RegExp(r'[\s\u00A0\u2000-\u200B\u202F\u205F\u3000]'),
      '',
    );
    if (compact.isEmpty) return false;
    if (compact.contains('\uFFFD')) return false;

    final total = compact.runes.length;
    if (total == 0) return false;

    final meaningful = RegExp(r'[\u4e00-\u9fffA-Za-z0-9]')
        .allMatches(compact)
        .length;
    if (meaningful == 0) return false;

    final ratio = meaningful / total;
    if (total > 4 && ratio < 0.3) return false;

    final privateUse = RegExp(r'[\uE000-\uF8FF]').allMatches(compact).length;
    if (privateUse / total > 0.2) return false;

    return true;
  }
}
