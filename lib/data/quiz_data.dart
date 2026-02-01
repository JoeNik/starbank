/// 新年知识问答题库
class QuizData {
  /// 问答题目列表
  static List<Map<String, dynamic>> getAllQuestions() {
    return [
      // 美食习俗类
      {
        'question': '过年吃饺子寓意什么?',
        'emoji': '🥟',
        'options': ['财富', '睡觉', '跑步', '唱歌'],
        'correctIndex': 0,
        'explanation': '饺子形状像元宝,过年吃饺子寓意"招财进宝",希望新的一年财源滚滚!',
        'category': 'food',
      },
      {
        'question': '年夜饭为什么要吃鱼?',
        'emoji': '🐟',
        'options': ['年年有余', '游得快', '好吃', '便宜'],
        'correctIndex': 0,
        'explanation': '鱼和"余"谐音,吃鱼寓意"年年有余",希望每年都有富余和好运!',
        'category': 'food',
      },
      {
        'question': '过年吃年糕代表什么?',
        'emoji': '🍰',
        'options': ['年年高升', '长高', '变甜', '好吃'],
        'correctIndex': 0,
        'explanation': '年糕和"年高"谐音,吃年糕寓意"年年高升",希望学习进步、事业高升!',
        'category': 'food',
      },
      {
        'question': '汤圆象征着什么?',
        'emoji': '🍡',
        'options': ['团团圆圆', '圆圆的', '白白的', '甜甜的'],
        'correctIndex': 0,
        'explanation': '汤圆圆圆的,象征着"团团圆圆",代表家人团聚、和和美美!',
        'category': 'food',
      },

      // 年兽传说类
      {
        'question': '年兽最怕什么颜色?',
        'emoji': '🧧',
        'options': ['红色', '蓝色', '绿色', '黄色'],
        'correctIndex': 0,
        'explanation': '传说年兽最怕红色!所以过年时人们贴红对联、挂红灯笼、穿红衣服来驱赶年兽。',
        'category': 'legend',
      },
      {
        'question': '年兽最怕什么声音?',
        'emoji': '🧨',
        'options': ['鞭炮声', '音乐声', '说话声', '风声'],
        'correctIndex': 0,
        'explanation': '年兽最怕响亮的鞭炮声!所以过年要放鞭炮,把年兽吓跑,保护大家平安。',
        'category': 'legend',
      },
      {
        'question': '年兽害怕什么光?',
        'emoji': '🏮',
        'options': ['火光', '月光', '星光', '阳光'],
        'correctIndex': 0,
        'explanation': '年兽害怕明亮的火光!所以过年要点灯笼、放烟花,用光明驱赶黑暗中的年兽。',
        'category': 'legend',
      },
      {
        'question': '年兽什么时候出来?',
        'emoji': '🌙',
        'options': ['除夕夜', '白天', '中午', '早上'],
        'correctIndex': 0,
        'explanation': '传说年兽在除夕夜出来吓唬人,所以除夕夜要守岁、放鞭炮,一起赶走年兽!',
        'category': 'legend',
      },

      // 生肖知识类
      {
        'question': '十二生肖谁跑第一?',
        'emoji': '🐭',
        'options': ['老鼠', '牛', '老虎', '兔子'],
        'correctIndex': 0,
        'explanation': '聪明的小老鼠跳到牛背上,快到终点时跳下来,所以得了第一名!',
        'category': 'zodiac',
      },
      {
        'question': '十二生肖里最大的动物是?',
        'emoji': '🐉',
        'options': ['龙', '牛', '虎', '马'],
        'correctIndex': 0,
        'explanation': '龙是十二生肖中最大、最神奇的动物,是中国的吉祥象征!',
        'category': 'zodiac',
      },
      {
        'question': '十二生肖里谁最勤劳?',
        'emoji': '🐂',
        'options': ['牛', '猪', '狗', '鸡'],
        'correctIndex': 0,
        'explanation': '牛最勤劳!它每天辛勤耕地,帮助农民伯伯种粮食,是勤劳的代表。',
        'category': 'zodiac',
      },
      {
        'question': '十二生肖里谁最聪明?',
        'emoji': '🐵',
        'options': ['猴子', '猪', '羊', '鸡'],
        'correctIndex': 0,
        'explanation': '猴子最聪明!它会爬树、会模仿,还能学会很多本领,非常机灵!',
        'category': 'zodiac',
      },

      // 传统习俗类
      {
        'question': '过年为什么要贴春联?',
        'emoji': '📜',
        'options': ['祈福辟邪', '好看', '写字', '装饰'],
        'correctIndex': 0,
        'explanation': '贴春联可以祈福辟邪,红色的春联能赶走年兽,带来好运和祝福!',
        'category': 'custom',
      },
      {
        'question': '春节为什么要给压岁钱?',
        'emoji': '💰',
        'options': ['压住邪祟', '买东西', '存钱', '玩游戏'],
        'correctIndex': 0,
        'explanation': '压岁钱是长辈给晚辈的祝福,能"压住邪祟",保佑孩子平平安安长大!',
        'category': 'custom',
      },
      {
        'question': '除夕夜为什么要守岁?',
        'emoji': '⏰',
        'options': ['迎接新年', '不睡觉', '看电视', '玩游戏'],
        'correctIndex': 0,
        'explanation': '守岁是为了迎接新年的到来,也是珍惜时光,和家人一起度过旧年的最后时刻!',
        'category': 'custom',
      },
      {
        'question': '春节为什么要挂灯笼?',
        'emoji': '🏮',
        'options': ['照明驱邪', '好看', '装饰', '玩耍'],
        'correctIndex': 0,
        'explanation': '红灯笼能照明驱邪,象征着红红火火、光明吉祥,给新年带来喜庆气氛!',
        'category': 'custom',
      },
      {
        'question': '大年初一为什么要拜年?',
        'emoji': '🙏',
        'options': ['送祝福', '要红包', '玩耍', '吃饭'],
        'correctIndex': 0,
        'explanation': '拜年是向长辈和亲友送上新年祝福,表达尊敬和关心,增进感情!',
        'category': 'custom',
      },

      // 节日知识类
      {
        'question': '春节是农历的哪一天?',
        'emoji': '📅',
        'options': ['正月初一', '正月十五', '腊月三十', '二月初二'],
        'correctIndex': 0,
        'explanation': '春节是农历正月初一,是中国最重要的传统节日,也叫过年!',
        'category': 'festival',
      },
      {
        'question': '元宵节要吃什么?',
        'emoji': '🎊',
        'options': ['汤圆', '饺子', '年糕', '鱼'],
        'correctIndex': 0,
        'explanation': '元宵节要吃汤圆,圆圆的汤圆象征团团圆圆、甜甜蜜蜜!',
        'category': 'festival',
      },
      {
        'question': '小年是为了送谁上天?',
        'emoji': '🎭',
        'options': ['灶王爷', '财神爷', '门神', '福神'],
        'correctIndex': 0,
        'explanation': '小年要送灶王爷上天,向玉帝汇报这一年的情况,希望他多说好话!',
        'category': 'festival',
      },
    ];
  }

  /// 随机获取指定数量的题目
  static List<Map<String, dynamic>> getRandomQuestions(int count) {
    final all = getAllQuestions();
    all.shuffle();
    return all.take(count).toList();
  }

  /// 按分类获取题目
  static List<Map<String, dynamic>> getQuestionsByCategory(String category) {
    return getAllQuestions().where((q) => q['category'] == category).toList();
  }
}
