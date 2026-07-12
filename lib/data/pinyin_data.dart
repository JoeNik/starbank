enum PinyinSection {
  initials,
  finals,
  wholeSyllables,
}

class PinyinItem {
  final String text;
  final String audioBase;
  final String tip;
  final String example;
  final PinyinSection section;
  final int defaultTone;
  final bool isExampleAudio;

  const PinyinItem({
    required this.text,
    required this.audioBase,
    required this.tip,
    required this.example,
    required this.section,
    this.defaultTone = 1,
    this.isExampleAudio = false,
  });

  String audioKey([int? tone]) => '$audioBase${tone ?? defaultTone}';
}

class PinyinWord {
  final String text;
  final String pinyin;
  final List<String> audioKeys;
  final String tip;

  const PinyinWord({
    required this.text,
    required this.pinyin,
    required this.audioKeys,
    required this.tip,
  });
}

class PinyinData {
  static const initials = <PinyinItem>[
    PinyinItem(
        text: 'b',
        audioBase: 'bo',
        tip: '双唇轻轻闭上，再打开',
        example: '玻璃的 bo',
        section: PinyinSection.initials),
    PinyinItem(
        text: 'p',
        audioBase: 'po',
        tip: '送气要明显，像轻轻吹纸片',
        example: '山坡的 po',
        section: PinyinSection.initials),
    PinyinItem(
        text: 'm',
        audioBase: 'mo',
        tip: '嘴巴闭上，声音从鼻子出来',
        example: '摸一摸的 mo',
        section: PinyinSection.initials),
    PinyinItem(
        text: 'f',
        audioBase: 'fo',
        tip: '上牙轻轻碰下唇',
        example: '佛像的 fo',
        section: PinyinSection.initials),
    PinyinItem(
        text: 'd',
        audioBase: 'de',
        tip: '舌尖抵住上牙后面',
        example: '得到的 de',
        section: PinyinSection.initials),
    PinyinItem(
        text: 't',
        audioBase: 'te',
        tip: '和 d 一样，但要送气',
        example: '特别的 te',
        section: PinyinSection.initials),
    PinyinItem(
        text: 'n',
        audioBase: 'ne',
        tip: '鼻音要出来',
        example: '哪吒的 ne',
        section: PinyinSection.initials),
    PinyinItem(
        text: 'l',
        audioBase: 'le',
        tip: '舌尖轻弹，声音清亮',
        example: '快乐的 le',
        section: PinyinSection.initials),
    PinyinItem(
        text: 'g',
        audioBase: 'ge',
        tip: '舌根抬起，声音短',
        example: '哥哥的 ge',
        section: PinyinSection.initials),
    PinyinItem(
        text: 'k',
        audioBase: 'ke',
        tip: '和 g 一样，但要送气',
        example: '一颗的 ke',
        section: PinyinSection.initials),
    PinyinItem(
        text: 'h',
        audioBase: 'he',
        tip: '像轻轻哈气',
        example: '喝水的 he',
        section: PinyinSection.initials),
    PinyinItem(
        text: 'j',
        audioBase: 'ji',
        tip: '舌面抬起，声音轻短',
        example: '积木的 ji',
        section: PinyinSection.initials),
    PinyinItem(
        text: 'q',
        audioBase: 'qi',
        tip: '和 j 一样，但要送气',
        example: '气球的 qi',
        section: PinyinSection.initials),
    PinyinItem(
        text: 'x',
        audioBase: 'xi',
        tip: '像轻轻笑出来的气声',
        example: '西瓜的 xi',
        section: PinyinSection.initials),
    PinyinItem(
        text: 'zh',
        audioBase: 'zhi',
        tip: '翘舌，舌尖抬起来',
        example: '知道的 zhi',
        section: PinyinSection.initials),
    PinyinItem(
        text: 'ch',
        audioBase: 'chi',
        tip: '翘舌，还要送气',
        example: '吃饭的 chi',
        section: PinyinSection.initials),
    PinyinItem(
        text: 'sh',
        audioBase: 'shi',
        tip: '翘舌，像轻轻说“诗”',
        example: '狮子的 shi',
        section: PinyinSection.initials),
    PinyinItem(
        text: 'r',
        audioBase: 'ri',
        tip: '翘舌，声音柔一点',
        example: '日出的 ri',
        section: PinyinSection.initials),
    PinyinItem(
        text: 'z',
        audioBase: 'zi',
        tip: '平舌，牙齿靠近',
        example: '自己的 zi',
        section: PinyinSection.initials),
    PinyinItem(
        text: 'c',
        audioBase: 'ci',
        tip: '平舌，要送气',
        example: '刺猬的 ci',
        section: PinyinSection.initials),
    PinyinItem(
        text: 's',
        audioBase: 'si',
        tip: '平舌，像小蛇嘶嘶声',
        example: '丝带的 si',
        section: PinyinSection.initials),
    PinyinItem(
        text: 'y',
        audioBase: 'yi',
        tip: '像整体认读 yi 的开头音',
        example: '衣服的 yi',
        section: PinyinSection.initials),
    PinyinItem(
        text: 'w',
        audioBase: 'wu',
        tip: '嘴巴拢圆一点',
        example: '乌云的 wu',
        section: PinyinSection.initials),
  ];

  static const finals = <PinyinItem>[
    PinyinItem(
        text: 'a',
        audioBase: 'a',
        tip: '嘴巴张大，声音放出来',
        example: 'ā á ǎ à',
        section: PinyinSection.finals),
    PinyinItem(
        text: 'o',
        audioBase: 'o',
        tip: '嘴巴圆圆，声音稳住',
        example: 'ō ó ǒ ò',
        section: PinyinSection.finals),
    PinyinItem(
        text: 'e',
        audioBase: 'e',
        tip: '嘴巴半开，舌头放松',
        example: 'ē é ě è',
        section: PinyinSection.finals),
    PinyinItem(
        text: 'i',
        audioBase: 'yi',
        tip: '牙齿靠近，嘴角展开',
        example: '衣服的 yi',
        section: PinyinSection.finals),
    PinyinItem(
        text: 'u',
        audioBase: 'wu',
        tip: '嘴巴拢圆，往前送',
        example: '乌云的 wu',
        section: PinyinSection.finals),
    PinyinItem(
        text: 'ü',
        audioBase: 'yu',
        tip: '先发 i，再把嘴唇拢圆',
        example: '小鱼的 yu',
        section: PinyinSection.finals),
    PinyinItem(
        text: 'ai',
        audioBase: 'ai',
        tip: '从 a 滑到 i',
        example: '挨着的 ai',
        section: PinyinSection.finals),
    PinyinItem(
        text: 'ei',
        audioBase: 'ei',
        tip: '从 e 滑到 i',
        example: '诶，听一听',
        section: PinyinSection.finals),
    PinyinItem(
        text: 'ui',
        audioBase: 'wei',
        tip: '课本写 ui，单独读像 wei',
        example: '微笑的 wei',
        section: PinyinSection.finals),
    PinyinItem(
        text: 'ao',
        audioBase: 'ao',
        tip: '从 a 滑到 o',
        example: '凹进去的 ao',
        section: PinyinSection.finals),
    PinyinItem(
        text: 'ou',
        audioBase: 'ou',
        tip: '从 o 滑到 u',
        example: '海鸥的 ou',
        section: PinyinSection.finals),
    PinyinItem(
        text: 'iu',
        audioBase: 'you',
        tip: '课本写 iu，单独读像 you',
        example: '优秀的 you',
        section: PinyinSection.finals),
    PinyinItem(
        text: 'ie',
        audioBase: 'ye',
        tip: '从 i 滑到 e',
        example: '叶子的 ye',
        section: PinyinSection.finals),
    PinyinItem(
        text: 'üe',
        audioBase: 'yue',
        tip: 'ü 和 e 连起来',
        example: '月亮的 yue',
        section: PinyinSection.finals),
    PinyinItem(
        text: 'er',
        audioBase: 'er',
        tip: '舌头轻轻卷起来',
        example: '耳朵的 er',
        section: PinyinSection.finals),
    PinyinItem(
        text: 'an',
        audioBase: 'an',
        tip: '嘴巴打开，再收到鼻音 n',
        example: '安全的 an',
        section: PinyinSection.finals),
    PinyinItem(
        text: 'en',
        audioBase: 'en',
        tip: '短短收住鼻音 n',
        example: '恩，听到了',
        section: PinyinSection.finals),
    PinyinItem(
        text: 'in',
        audioBase: 'yin',
        tip: '课本写 in，单独读像 yin',
        example: '音乐的 yin',
        section: PinyinSection.finals),
    PinyinItem(
        text: 'un',
        audioBase: 'wen',
        tip: '课本写 un，单独读像 wen',
        example: '温暖的 wen',
        section: PinyinSection.finals),
    PinyinItem(
        text: 'ün',
        audioBase: 'yun',
        tip: 'ü 加鼻音 n',
        example: '云朵的 yun',
        section: PinyinSection.finals),
    PinyinItem(
        text: 'ang',
        audioBase: 'ang',
        tip: '后鼻音 ng 要打开',
        example: '昂首的 ang',
        section: PinyinSection.finals),
    PinyinItem(
        text: 'eng',
        audioBase: 'eng',
        tip: '后鼻音 ng，声音靠后',
        example: '嗯，明白了',
        section: PinyinSection.finals),
    PinyinItem(
        text: 'ing',
        audioBase: 'ying',
        tip: '课本写 ing，单独读像 ying',
        example: '影子的 ying',
        section: PinyinSection.finals),
    PinyinItem(
        text: 'ong',
        audioBase: 'zhong',
        tip: '单独不好发时，听 zhong 里的 ong',
        example: '中国的 zhong',
        section: PinyinSection.finals,
        isExampleAudio: true),
  ];

  static const wholeSyllables = <PinyinItem>[
    PinyinItem(
        text: 'zhi',
        audioBase: 'zhi',
        tip: '整体认读，不拼读',
        example: '知道的 zhi',
        section: PinyinSection.wholeSyllables),
    PinyinItem(
        text: 'chi',
        audioBase: 'chi',
        tip: '整体认读，不拼读',
        example: '吃饭的 chi',
        section: PinyinSection.wholeSyllables),
    PinyinItem(
        text: 'shi',
        audioBase: 'shi',
        tip: '整体认读，不拼读',
        example: '狮子的 shi',
        section: PinyinSection.wholeSyllables),
    PinyinItem(
        text: 'ri',
        audioBase: 'ri',
        tip: '整体认读，不拼读',
        example: '日出的 ri',
        section: PinyinSection.wholeSyllables),
    PinyinItem(
        text: 'zi',
        audioBase: 'zi',
        tip: '整体认读，不拼读',
        example: '自己的 zi',
        section: PinyinSection.wholeSyllables),
    PinyinItem(
        text: 'ci',
        audioBase: 'ci',
        tip: '整体认读，不拼读',
        example: '刺猬的 ci',
        section: PinyinSection.wholeSyllables),
    PinyinItem(
        text: 'si',
        audioBase: 'si',
        tip: '整体认读，不拼读',
        example: '丝带的 si',
        section: PinyinSection.wholeSyllables),
    PinyinItem(
        text: 'yi',
        audioBase: 'yi',
        tip: '整体认读，不拼读',
        example: '衣服的 yi',
        section: PinyinSection.wholeSyllables),
    PinyinItem(
        text: 'wu',
        audioBase: 'wu',
        tip: '整体认读，不拼读',
        example: '乌云的 wu',
        section: PinyinSection.wholeSyllables),
    PinyinItem(
        text: 'yu',
        audioBase: 'yu',
        tip: '整体认读，不拼读',
        example: '小鱼的 yu',
        section: PinyinSection.wholeSyllables),
    PinyinItem(
        text: 'ye',
        audioBase: 'ye',
        tip: '整体认读，不拼读',
        example: '叶子的 ye',
        section: PinyinSection.wholeSyllables),
    PinyinItem(
        text: 'yue',
        audioBase: 'yue',
        tip: '整体认读，不拼读',
        example: '月亮的 yue',
        section: PinyinSection.wholeSyllables),
    PinyinItem(
        text: 'yuan',
        audioBase: 'yuan',
        tip: '整体认读，不拼读',
        example: '圆圆的 yuan',
        section: PinyinSection.wholeSyllables),
    PinyinItem(
        text: 'yin',
        audioBase: 'yin',
        tip: '整体认读，不拼读',
        example: '音乐的 yin',
        section: PinyinSection.wholeSyllables),
    PinyinItem(
        text: 'yun',
        audioBase: 'yun',
        tip: '整体认读，不拼读',
        example: '云朵的 yun',
        section: PinyinSection.wholeSyllables),
    PinyinItem(
        text: 'ying',
        audioBase: 'ying',
        tip: '整体认读，不拼读',
        example: '影子的 ying',
        section: PinyinSection.wholeSyllables),
  ];

  static const toneLabels = ['一声', '二声', '三声', '四声'];

  static const words = <PinyinWord>[
    PinyinWord(
      text: '小猫',
      pinyin: 'xiǎo māo',
      audioKeys: ['xiao3', 'mao1'],
      tip: '先三声，再一声：xiǎo māo',
    ),
    PinyinWord(
      text: '小狗',
      pinyin: 'xiǎo gǒu',
      audioKeys: ['xiao3', 'gou3'],
      tip: '两个三声分开读清楚',
    ),
    PinyinWord(
      text: '小牛',
      pinyin: 'xiǎo niú',
      audioKeys: ['xiao3', 'niu2'],
      tip: '听清 niú 的二声往上扬',
    ),
    PinyinWord(
      text: '小鸟',
      pinyin: 'xiǎo niǎo',
      audioKeys: ['xiao3', 'niao3'],
      tip: '两个三声分开读清楚',
    ),
    PinyinWord(
      text: '白兔',
      pinyin: 'bái tù',
      audioKeys: ['bai2', 'tu4'],
      tip: '二声接四声：bái tù',
    ),
    PinyinWord(
      text: '西瓜',
      pinyin: 'xī guā',
      audioKeys: ['xi1', 'gua1'],
      tip: '两个一声平稳读',
    ),
    PinyinWord(
      text: '苹果',
      pinyin: 'píng guǒ',
      audioKeys: ['ping2', 'guo3'],
      tip: '二声接三声：píng guǒ',
    ),
    PinyinWord(
      text: '牛奶',
      pinyin: 'niú nǎi',
      audioKeys: ['niu2', 'nai3'],
      tip: '二声接三声：niú nǎi',
    ),
    PinyinWord(
      text: '面包',
      pinyin: 'miàn bāo',
      audioKeys: ['mian4', 'bao1'],
      tip: '四声接一声：miàn bāo',
    ),
    PinyinWord(
      text: '花朵',
      pinyin: 'huā duǒ',
      audioKeys: ['hua1', 'duo3'],
      tip: '一声接三声：huā duǒ',
    ),
    PinyinWord(
      text: '小鱼',
      pinyin: 'xiǎo yú',
      audioKeys: ['xiao3', 'yu2'],
      tip: '听清 yú 里的 ü 音',
    ),
    PinyinWord(
      text: '太阳',
      pinyin: 'tài yáng',
      audioKeys: ['tai4', 'yang2'],
      tip: '四声接二声：tài yáng',
    ),
    PinyinWord(
      text: '云朵',
      pinyin: 'yún duǒ',
      audioKeys: ['yun2', 'duo3'],
      tip: 'yún 是整体认读音节',
    ),
    PinyinWord(
      text: '大山',
      pinyin: 'dà shān',
      audioKeys: ['da4', 'shan1'],
      tip: '四声接一声：dà shān',
    ),
    PinyinWord(
      text: '小河',
      pinyin: 'xiǎo hé',
      audioKeys: ['xiao3', 'he2'],
      tip: '三声接二声：xiǎo hé',
    ),
    PinyinWord(
      text: '上学',
      pinyin: 'shàng xué',
      audioKeys: ['shang4', 'xue2'],
      tip: '翘舌 shàng 接 xué',
    ),
    PinyinWord(
      text: '回家',
      pinyin: 'huí jiā',
      audioKeys: ['hui2', 'jia1'],
      tip: '二声接一声：huí jiā',
    ),
    PinyinWord(
      text: '看书',
      pinyin: 'kàn shū',
      audioKeys: ['kan4', 'shu1'],
      tip: '四声接一声：kàn shū',
    ),
    PinyinWord(
      text: '画画',
      pinyin: 'huà huà',
      audioKeys: ['hua4', 'hua4'],
      tip: '两个四声连起来读',
    ),
    PinyinWord(
      text: '开门',
      pinyin: 'kāi mén',
      audioKeys: ['kai1', 'men2'],
      tip: '一声接二声：kāi mén',
    ),
    PinyinWord(
      text: '洗手',
      pinyin: 'xǐ shǒu',
      audioKeys: ['xi3', 'shou3'],
      tip: '两个三声分开读清楚',
    ),
    PinyinWord(
      text: '汽车',
      pinyin: 'qì chē',
      audioKeys: ['qi4', 'che1'],
      tip: 'qì 接翘舌 chē',
    ),
    PinyinWord(
      text: '飞机',
      pinyin: 'fēi jī',
      audioKeys: ['fei1', 'ji1'],
      tip: '两个一声平稳读',
    ),
  ];

  static List<PinyinItem> bySection(PinyinSection section) {
    switch (section) {
      case PinyinSection.initials:
        return initials;
      case PinyinSection.finals:
        return finals;
      case PinyinSection.wholeSyllables:
        return wholeSyllables;
    }
  }

  /// 教学呼读名：给 TTS 用中文读，避免把声母字母读成英文（如 f 读成 ef）。
  static const Map<String, String> _initialSpokenNames = {
    'b': '玻',
    'p': '坡',
    'm': '摸',
    'f': '佛',
    'd': '得',
    't': '特',
    'n': '讷',
    'l': '勒',
    'g': '哥',
    'k': '科',
    'h': '喝',
    'j': '基',
    'q': '欺',
    'x': '希',
    'zh': '知',
    'ch': '吃',
    'sh': '诗',
    'r': '日',
    'z': '资',
    'c': '雌',
    's': '思',
    'y': '衣',
    'w': '乌',
  };

  /// 常见韵母 / 音节的中文近似读法，供 TTS 播报。
  static const Map<String, String> _syllableSpokenNames = {
    'a': '啊',
    'o': '喔',
    'e': '鹅',
    'i': '衣',
    'u': '乌',
    'ü': '迂',
    'v': '迂',
    'ai': '爱',
    'ei': '诶',
    'ui': '威',
    'ao': '奥',
    'ou': '欧',
    'iu': '优',
    'ie': '耶',
    'üe': '约',
    'ue': '约',
    'er': '儿',
    'an': '安',
    'en': '恩',
    'in': '因',
    'un': '温',
    'ün': '晕',
    'vn': '晕',
    'ang': '昂',
    'eng': '鞥',
    'ing': '英',
    'ong': '翁',
    'bo': '玻',
    'po': '坡',
    'mo': '摸',
    'fo': '佛',
    'de': '得',
    'te': '特',
    'ne': '讷',
    'le': '勒',
    'ge': '哥',
    'ke': '科',
    'he': '喝',
    'ji': '基',
    'qi': '欺',
    'xi': '西',
    'zhi': '知',
    'chi': '吃',
    'shi': '诗',
    'ri': '日',
    'zi': '资',
    'ci': '刺',
    'si': '思',
    'yi': '衣',
    'wu': '乌',
    'yu': '鱼',
    'ye': '叶',
    'yue': '月',
    'yuan': '圆',
    'yin': '音',
    'yun': '云',
    'ying': '影',
    'wei': '威',
    'you': '优',
    'wen': '温',
    'zhong': '中',
    'ng': '嗯',
  };

  static String spokenName(PinyinItem item) {
    switch (item.section) {
      case PinyinSection.initials:
        final name = _initialSpokenNames[item.text];
        if (name == null) {
          throw StateError('缺少声母呼读名: ${item.text}');
        }
        return name;
      case PinyinSection.finals:
      case PinyinSection.wholeSyllables:
        final name = _syllableSpokenNames[item.text];
        if (name == null) {
          throw StateError('缺少音节呼读名: ${item.text}');
        }
        return name;
    }
  }

  static String sectionSpeechLabel(PinyinSection section) {
    switch (section) {
      case PinyinSection.initials:
        return '声母';
      case PinyinSection.finals:
        return '韵母';
      case PinyinSection.wholeSyllables:
        return '整体认读音节';
    }
  }

  /// 把界面里的拼音字母/音节转成适合中文 TTS 的读法。
  static String toChineseSpeech(String text) {
    if (text.isEmpty) return text;

    final tokens = _syllableSpokenNames.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    // 也替换带调元音为对应无调读法
    final toneMap = {
      'ā': 'a',
      'á': 'a',
      'ǎ': 'a',
      'à': 'a',
      'ō': 'o',
      'ó': 'o',
      'ǒ': 'o',
      'ò': 'o',
      'ē': 'e',
      'é': 'e',
      'ě': 'e',
      'è': 'e',
      'ī': 'i',
      'í': 'i',
      'ǐ': 'i',
      'ì': 'i',
      'ū': 'u',
      'ú': 'u',
      'ǔ': 'u',
      'ù': 'u',
      'ǖ': 'ü',
      'ǘ': 'ü',
      'ǚ': 'ü',
      'ǜ': 'ü',
    };

    final buffer = StringBuffer();
    var i = 0;
    final source = text;
    while (i < source.length) {
      final ch = source[i];
      if (toneMap.containsKey(ch)) {
        final base = toneMap[ch]!;
        final spoken = _syllableSpokenNames[base] ?? base;
        buffer.write(spoken);
        i += 1;
        continue;
      }

      final lower = source.substring(i).toLowerCase();
      var matched = false;
      for (final token in tokens) {
        if (lower.startsWith(token)) {
          // 仅替换独立拼音 token：前后不是拉丁字母
          final end = i + token.length;
          final beforeOk = i == 0 || !_isLatinLetter(source[i - 1]);
          final afterOk = end >= source.length || !_isLatinLetter(source[end]);
          if (beforeOk && afterOk) {
            buffer.write(_syllableSpokenNames[token]!);
            i = end;
            matched = true;
            break;
          }
        }
      }
      if (matched) continue;

      // 单独声母字母（含多字母 zh/ch/sh 已在 tokens 更长优先覆盖）
      if (_isLatinLetter(ch)) {
        final lowerCh = ch.toLowerCase();
        // 尝试 2 字母声母
        if (i + 1 < source.length && _isLatinLetter(source[i + 1])) {
          final two = (lowerCh + source[i + 1].toLowerCase());
          if (_initialSpokenNames.containsKey(two)) {
            final end = i + 2;
            final afterOk = end >= source.length || !_isLatinLetter(source[end]);
            if (afterOk) {
              buffer.write(_initialSpokenNames[two]!);
              i = end;
              continue;
            }
          }
        }
        if (_initialSpokenNames.containsKey(lowerCh)) {
          final end = i + 1;
          final afterOk = end >= source.length || !_isLatinLetter(source[end]);
          if (afterOk) {
            buffer.write(_initialSpokenNames[lowerCh]!);
            i = end;
            continue;
          }
        }
      }

      buffer.write(ch);
      i += 1;
    }
    return buffer.toString();
  }

  static bool _isLatinLetter(String ch) {
    if (ch.isEmpty) return false;
    final code = ch.codeUnitAt(0);
    return (code >= 65 && code <= 90) ||
        (code >= 97 && code <= 122) ||
        ch == 'ü' ||
        ch == 'Ü';
  }

  /// 发音方法播报：用中文呼读，避免 TTS 把 f/b/p 读成英文。
  static String toTipSpeech(PinyinItem item) {
    final label = sectionSpeechLabel(item.section);
    final name = spokenName(item);
    final tip = toChineseSpeech(item.tip);
    if (item.isExampleAudio) {
      return '$label$name，读作$name。$tip。';
    }
    final example = toChineseSpeech(item.example);
    return '$label$name，读作$name。$tip。$example。';
  }

  static String markTone(String pinyin, int tone) {
    if (tone < 1 || tone > 4) return pinyin;
    const marks = {
      'a': ['ā', 'á', 'ǎ', 'à'],
      'o': ['ō', 'ó', 'ǒ', 'ò'],
      'e': ['ē', 'é', 'ě', 'è'],
      'i': ['ī', 'í', 'ǐ', 'ì'],
      'u': ['ū', 'ú', 'ǔ', 'ù'],
      'ü': ['ǖ', 'ǘ', 'ǚ', 'ǜ'],
      'v': ['ǖ', 'ǘ', 'ǚ', 'ǜ'],
    };

    final normalized = pinyin.replaceAll('v', 'ü');
    final target = _toneTarget(normalized);
    if (target == null) return normalized;

    final toneMark = marks[target]![tone - 1];
    return normalized.replaceFirst(target, toneMark);
  }

  static String? _toneTarget(String pinyin) {
    for (final vowel in const ['a', 'o', 'e']) {
      if (pinyin.contains(vowel)) return vowel;
    }
    if (pinyin.contains('iu')) return 'u';
    if (pinyin.contains('ui')) return 'i';
    for (final vowel in const ['i', 'u', 'ü']) {
      if (pinyin.contains(vowel)) return vowel;
    }
    return null;
  }
}
