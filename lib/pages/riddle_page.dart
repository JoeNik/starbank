import 'dart:math';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:hive/hive.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../data/riddle_data.dart';
import '../theme/app_theme.dart';
import '../services/tts_service.dart';
import 'tts_settings_page.dart';

/// 脑筋急转弯页面
class RiddlePage extends StatefulWidget {
  const RiddlePage({super.key});

  @override
  State<RiddlePage> createState() => _RiddlePageState();
}

class _RiddlePageState extends State<RiddlePage> {
  // 使用全局 TTS 服务
  // 使用全局 TTS 服务
  final TtsService _tts = Get.find<TtsService>();

  // Hive Box for custom riddles
  late Box _customRiddlesBox;
  bool _isLoading = true;

  // 题目列表
  late List<Map<String, String>> _riddles;

  // 当前题目索引
  final RxInt _currentIndex = 0.obs;

  // 是否显示答案
  final RxBool _showAnswer = false.obs;

  // 页面控制器
  late PageController _pageController;

  // 随机历史记录，用于支持上一题
  final List<int> _history = [];
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _initData();
  }

  Future<void> _initData() async {
    _customRiddlesBox = await Hive.openBox('custom_riddles');
    _loadRiddles();
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  /// 加载题目
  void _loadRiddles() {
    if (_customRiddlesBox.isNotEmpty) {
      try {
        final customList = _customRiddlesBox.values.toList();
        _riddles = customList
            .map((e) {
              // Ensure it's a map and convert to Map<String, String>
              if (e is Map) {
                return {
                  'q': e['q']?.toString() ?? '',
                  'a': e['a']?.toString() ?? '',
                };
              }
              return {'q': 'Invalid', 'a': 'Invalid'};
            })
            .where((e) => e['q']!.isNotEmpty)
            .toList();

        if (_riddles.isEmpty) {
          _riddles = RiddleData.getAllRiddles();
        }
      } catch (e) {
        debugPrint('Failed to load custom riddles: $e');
        _riddles = RiddleData.getAllRiddles();
      }
    } else {
      _riddles = RiddleData.getAllRiddles();
    }
    // 使用当前时间作为随机种子，确保每次进入顺序完全不同
    _riddles.shuffle(Random(DateTime.now().millisecondsSinceEpoch));
  }

  /// 播放题目语音
  Future<void> _speakQuestion() async {
    if (_tts.isSpeaking.value) {
      await _tts.stop();
      return;
    }
    final question = _riddles[_currentIndex.value]['q']!;
    await _tts.speak(question);
  }

  /// 播放答案语音
  Future<void> _speakAnswer() async {
    if (_tts.isSpeaking.value) {
      await _tts.stop();
      return;
    }
    final answer = _riddles[_currentIndex.value]['a']!;
    await _tts.speak('答案是：$answer');
  }

  /// 下一题 (改为完全随机获取)
  void _nextRiddle() {
    _tts.stop();
    _showAnswer.value = false;

    if (_riddles.isEmpty) return;

    // 记录当前索引到历史
    _history.add(_currentIndex.value);
    if (_history.length > 50) _history.removeAt(0); // 限制历史长度

    // 随机选择一个新索引（不与当前相同）
    int nextIndex;
    if (_riddles.length > 1) {
      do {
        nextIndex = _random.nextInt(_riddles.length);
      } while (nextIndex == _currentIndex.value);
    } else {
      nextIndex = 0;
    }

    _currentIndex.value = nextIndex;
    // 使用 jumpToPage 配合随机，避免翻页动画穿过过多不相关的题目
    _pageController.jumpToPage(nextIndex);
  }

  /// 换一批 (重新洗牌)
  void _refreshRiddles() {
    _tts.stop();
    _loadRiddles();
    _currentIndex.value = 0;
    _showAnswer.value = false;
    _history.clear();
    _pageController.jumpToPage(0);
  }

  /// 上一题 (从历史记录返回)
  void _prevRiddle() {
    _tts.stop();
    _showAnswer.value = false;

    if (_history.isNotEmpty) {
      final lastIndex = _history.removeLast();
      _currentIndex.value = lastIndex;
      _pageController.jumpToPage(lastIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFFFF8E1),
      appBar: AppBar(
        title: const Text('脑筋急转弯'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          // 菜单
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'import') {
                _showImportDialog();
              } else if (value == 'reset') {
                _resetRiddles();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'import',
                child: Text('导入题库'),
              ),
              const PopupMenuItem(
                value: 'reset',
                child: Text('恢复默认'),
              ),
            ],
          ),
          // 题目计数
          Obx(() => Container(
                margin: EdgeInsets.only(right: 16.w),
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                decoration: BoxDecoration(
                  color: Colors.amber.shade100,
                  borderRadius: BorderRadius.circular(20.r),
                ),
                child: Text(
                  '随机题库中',
                  style: TextStyle(
                    color: Colors.amber.shade800,
                    fontWeight: FontWeight.bold,
                    fontSize: 12.sp,
                  ),
                ),
              )),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // 主内容区域
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (index) {
                  _currentIndex.value = index;
                  _showAnswer.value = false;
                  _tts.stop();
                },
                itemCount: _riddles.length,
                itemBuilder: (context, index) {
                  return _buildRiddleCard(index);
                },
              ),
            ),

            // 底部控制区域
            _buildControlPanel(),
          ],
        ),
      ),
    );
  }

  /// 题目卡片
  Widget _buildRiddleCard(int index) {
    final riddle = _riddles[index];

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.all(20.w),
      child: Column(
        children: [
          // 题目卡片
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(24.w),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28.r),
              boxShadow: [
                BoxShadow(
                  color: Colors.amber.withOpacity(0.15),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              children: [
                // 问题图标
                Container(
                  width: 80.w,
                  height: 80.w,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.amber.shade300,
                        Colors.orange.shade300,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24.r),
                  ),
                  child: Center(
                    child: Text(
                      '🤔',
                      style: TextStyle(fontSize: 40.sp),
                    ),
                  ),
                ),
                SizedBox(height: 20.h),

                // 问题文本
                Text(
                  riddle['q']!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22.sp,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textMain,
                    height: 1.5,
                  ),
                ),
                SizedBox(height: 16.h),

                // 语音播放按钮 - 题目
                Obx(() => ElevatedButton.icon(
                      onPressed: _speakQuestion,
                      icon: Icon(
                        _tts.isSpeaking.value ? Icons.stop : Icons.volume_up,
                        size: 20.sp,
                      ),
                      label: Text(_tts.isSpeaking.value ? '停止' : '读题目'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(
                          horizontal: 20.w,
                          vertical: 10.h,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20.r),
                        ),
                      ),
                    )),
              ],
            ),
          ),
          SizedBox(height: 20.h),

          // 答案区域
          Obx(() => AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: _showAnswer.value
                    ? _buildAnswerCard(riddle['a']!)
                    : _buildShowAnswerButton(),
              )),
        ],
      ),
    );
  }

  /// 显示答案按钮
  Widget _buildShowAnswerButton() {
    return GestureDetector(
      onTap: () => _showAnswer.value = true,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(20.w),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24.r),
          border: Border.all(
            color: Colors.green.withOpacity(0.3),
            width: 2,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.lightbulb_outline,
              color: Colors.green,
              size: 24.sp,
            ),
            SizedBox(width: 8.w),
            Text(
              '点击查看答案',
              style: TextStyle(
                fontSize: 16.sp,
                color: Colors.green,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 答案卡片
  Widget _buildAnswerCard(String answer) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(24.w),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.green.shade50,
            Colors.teal.shade50,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24.r),
        border: Border.all(
          color: Colors.green.shade200,
          width: 2,
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.check_circle,
                color: Colors.green,
                size: 24.sp,
              ),
              SizedBox(width: 8.w),
              Text(
                '答案揭晓',
                style: TextStyle(
                  fontSize: 16.sp,
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          SizedBox(height: 16.h),
          Text(
            answer,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20.sp,
              fontWeight: FontWeight.bold,
              color: Colors.green.shade800,
              height: 1.5,
            ),
          ),
          SizedBox(height: 16.h),
          // 语音播放按钮 - 答案
          Obx(() => OutlinedButton.icon(
                onPressed: _speakAnswer,
                icon: Icon(
                  _tts.isSpeaking.value ? Icons.stop : Icons.volume_up,
                  size: 18.sp,
                ),
                label: Text(_tts.isSpeaking.value ? '停止' : '读答案'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.green,
                  side: BorderSide(color: Colors.green.shade300),
                  padding: EdgeInsets.symmetric(
                    horizontal: 16.w,
                    vertical: 8.h,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16.r),
                  ),
                ),
              )),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _tts.stop();
    _pageController.dispose();
    super.dispose();
  }

  void _showImportDialog() {
    final controller = TextEditingController();
    Get.dialog(
      AlertDialog(
        title: const Text('导入脑筋急转弯'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('支持直接粘贴 JSON 列表，或输入 URL 获取。',
                  style: TextStyle(fontSize: 12.sp, color: Colors.black87)),
              SizedBox(height: 4.h),
              Container(
                padding: EdgeInsets.all(8.w),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(4.r),
                ),
                child: Text(
                  '数据格式要求：\n[{"q":"问题", "a":"答案"}, ...]',
                  style: TextStyle(
                      fontSize: 11.sp,
                      fontFamily: 'monospace',
                      color: Colors.grey[800]),
                ),
              ),
              SizedBox(height: 10.h),
              TextField(
                controller: controller,
                maxLines: 5,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: '粘贴 JSON 内容或 http://... 链接',
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('取消')),
          ElevatedButton(
            onPressed: () => _handleImport(controller.text),
            child: const Text('导入'),
          ),
        ],
      ),
    );
  }

  void _handleImport(String input) async {
    if (input.trim().isEmpty) {
      Get.snackbar('提示', '请输入内容', snackPosition: SnackPosition.BOTTOM);
      return;
    }

    String jsonStr = input;

    // Check if it is a URL
    if (input.trim().startsWith('http')) {
      try {
        Get.dialog(const Center(child: CircularProgressIndicator()),
            barrierDismissible: false);
        final response = await http.get(Uri.parse(input.trim()));
        Get.back(); // close loading

        if (response.statusCode == 200) {
          jsonStr = utf8.decode(response.bodyBytes);
        } else {
          throw Exception('HTTP ${response.statusCode}');
        }
      } catch (e) {
        if (Get.isDialogOpen ?? false) Get.back();
        Get.snackbar('下载失败', '无法从链接获取数据: $e',
            snackPosition: SnackPosition.BOTTOM);
        return;
      }
    }

    try {
      final List<dynamic> list = jsonDecode(jsonStr);
      if (list.isEmpty) throw Exception('数据为空');

      final validRiddles = <Map<String, String>>[];
      for (var item in list) {
        if (item is Map && item['q'] != null && item['a'] != null) {
          validRiddles.add({
            'q': item['q'].toString(),
            'a': item['a'].toString(),
          });
        }
      }

      if (validRiddles.isEmpty) throw Exception('没有有效的题目数据 (需包含 q 和 a 字段)');

      // Save to Hive
      // 显式先清空
      await _customRiddlesBox.clear();
      // 再添加
      await _customRiddlesBox.addAll(validRiddles);
      // 强制立即同步到磁
      await _customRiddlesBox.flush();

      Get.back(); // close dialog
      _loadRiddles();
      // Reset index
      _currentIndex.value = 0;
      if (_pageController.hasClients) _pageController.jumpToPage(0);

      Get.snackbar('导入成功', '已成功导入 ${validRiddles.length} 道题目',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.green.shade100);
    } catch (e) {
      Get.snackbar('导入失败', '数据格式错误: $e\n请确保格式为 [{"q":"..","a":".."}]',
          snackPosition: SnackPosition.BOTTOM,
          duration: const Duration(seconds: 4),
          backgroundColor: Colors.red.shade100);
    }
  }

  void _resetRiddles() async {
    await _customRiddlesBox.clear();
    _loadRiddles();
    _currentIndex.value = 0;
    if (_pageController.hasClients) _pageController.jumpToPage(0);
    Get.snackbar('已恢复', '已使用默认题库', snackPosition: SnackPosition.BOTTOM);
  }

  /// 底部控制面板
  Widget _buildControlPanel() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28.r)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 语速和引擎设置
          Row(
            children: [
              // 语速调节
              Expanded(
                child: Obx(() => Row(
                      children: [
                        Icon(Icons.speed, size: 18.sp, color: Colors.grey),
                        SizedBox(width: 4.w),
                        Text(
                          '${_tts.speechRate.value.toStringAsFixed(1)}x',
                          style: TextStyle(
                            fontSize: 11.sp,
                            color: Colors.amber.shade700,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Expanded(
                          child: Slider(
                            value: _tts.speechRate.value,
                            min: 0.5,
                            max: 2.0,
                            divisions: 15,
                            activeColor: Colors.amber,
                            onChanged: (value) => _tts.setSpeechRate(value),
                          ),
                        ),
                      ],
                    )),
              ),
              // 语音设置按钮
              GestureDetector(
                onTap: () async {
                  await Get.to(() => const TtsSettingsPage());
                  // 设置页面会自动保存，不需要重新加载
                },
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12.r),
                    border: Border.all(color: Colors.blue.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.settings_voice,
                          size: 14.sp, color: Colors.blue),
                      SizedBox(width: 4.w),
                      Text(
                        '语音设置',
                        style: TextStyle(
                          fontSize: 10.sp,
                          color: Colors.blue,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 8.h),
          // 控制按钮
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // 上一题
              Obx(() => _buildControlButton(
                    icon: Icons.arrow_back_ios,
                    label: '上一题',
                    onTap: _history.isNotEmpty ? _prevRiddle : null,
                  )),
              // 换一批
              _buildControlButton(
                icon: Icons.refresh,
                label: '换一批',
                color: Colors.amber,
                onTap: _refreshRiddles,
              ),
              // 下一题
              _buildControlButton(
                icon: Icons.arrow_forward_ios,
                label: '下一题',
                color: Colors.green,
                onTap: _nextRiddle,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    Color? color,
    VoidCallback? onTap,
  }) {
    final isDisabled = onTap == null;
    final buttonColor =
        isDisabled ? Colors.grey.shade300 : (color ?? AppTheme.primary);

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56.w,
            height: 56.w,
            decoration: BoxDecoration(
              color: buttonColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(18.r),
            ),
            child: Icon(
              icon,
              color: buttonColor,
              size: 24.sp,
            ),
          ),
          SizedBox(height: 6.h),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.sp,
              color: isDisabled ? Colors.grey : buttonColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
