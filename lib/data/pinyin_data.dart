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
        tip: '和 d 像，但要送气',
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
        tip: '和 g 像，但要送气',
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
        tip: '和 j 像，但要送气',
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
        tip: '像整体认读 yi 的开头',
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
        tip: 'audio-cmn 无纯 ong，这里听 zhong 中的 ong',
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
