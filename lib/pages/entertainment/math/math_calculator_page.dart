import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../../../services/tts_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/toast_utils.dart';
import 'math_tts_config.dart';
import 'math_tts_settings_page.dart';

enum _MathOp { add, subtract, multiply, divide }

enum _ProblemKind { normal, percentOf }

const Color _mathInk = Color(0xFF28324F);
const Color _mathPaper = Color(0xFFFFFDF7);
const Color _mathMist = Color(0xFFF7FBFF);
const Color _mathSky = Color(0xFFC8EEFF);
const Color _mathSea = Color(0xFF2388E8);
const Color _mathCoral = Color(0xFFFF8B86);
const Color _mathMint = Color(0xFF72E6BE);
const Color _mathButter = Color(0xFFFFD96A);
const Color _mathLavender = Color(0xFFB8A7FF);
const int _maxCalculatorDigits = 12;
const int _maxPracticeDigits = 10;
const int _maxDecimalPlaces = 2;
const int _maxButtonSpeechQueueLength = 72;

class _MathProblem {
  const _MathProblem({
    required this.left,
    required this.right,
    required this.op,
    required this.answer,
    this.kind = _ProblemKind.normal,
  });

  final double left;
  final double right;
  final _MathOp op;
  final double answer;
  final _ProblemKind kind;

  bool get usesDecimal => left % 1 != 0 || right % 1 != 0 || answer % 1 != 0;

  bool get supportsVertical =>
      kind == _ProblemKind.normal &&
      (op == _MathOp.add || op == _MathOp.subtract) &&
      !usesDecimal &&
      left >= 0 &&
      right >= 0;
}

class _PracticeResult {
  const _PracticeResult({
    required this.isCorrect,
    required this.revealExplanation,
  });

  final bool isCorrect;
  final bool revealExplanation;

  _PracticeResult copyWith({bool? revealExplanation}) {
    return _PracticeResult(
      isCorrect: isCorrect,
      revealExplanation: revealExplanation ?? this.revealExplanation,
    );
  }
}

class _VerticalMark {
  const _VerticalMark({
    required this.text,
    required this.color,
    this.background,
  });

  final String text;
  final Color color;
  final Color? background;
}

class MathCalculatorPage extends StatefulWidget {
  const MathCalculatorPage({super.key});

  @override
  State<MathCalculatorPage> createState() => _MathCalculatorPageState();
}

class _MathCalculatorPageState extends State<MathCalculatorPage>
    with TickerProviderStateMixin {
  final TtsService _tts = Get.find<TtsService>();
  final Random _random = Random();

  late TabController _tabController;
  late AnimationController _backgroundController;
  late _MathProblem _problem;

  String _display = '0';
  double? _storedValue;
  _MathOp? _pendingOp;
  bool _startFresh = false;

  int _grade = 1;
  String _answerInput = '';
  _PracticeResult? _practiceResult;
  int _totalCount = 0;
  int _correctCount = 0;
  int _streak = 0;
  final List<_MathOp> _recentPracticeOps = [];
  final List<String> _buttonSpeechQueue = [];
  bool _isPlayingButtonSpeech = false;
  int _buttonSpeechVersion = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _backgroundController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat(reverse: true);
    _problem = _generateProblem(_grade);
    unawaited(_warmUpMathAudio());
  }

  @override
  void dispose() {
    _tabController.dispose();
    _backgroundController.dispose();
    _buttonSpeechQueue.clear();
    _tts.stop();
    super.dispose();
  }

  Future<void> _speak(String text) async {
    _stopButtonSpeechQueue();
    await _tts.speak(text, featureKey: mathCalculatorTtsFeatureKey);
  }

  void _enqueueButtonSpeech(String text) {
    _buttonSpeechQueue.add(text);
    if (_buttonSpeechQueue.length > _maxButtonSpeechQueueLength) {
      _buttonSpeechQueue.removeAt(0);
    }
    if (!_isPlayingButtonSpeech) {
      unawaited(_playButtonSpeechQueue(_buttonSpeechVersion));
    }
  }

  void _stopButtonSpeechQueue() {
    _buttonSpeechVersion++;
    _buttonSpeechQueue.clear();
    _isPlayingButtonSpeech = false;
  }

  Future<void> _playButtonSpeechQueue(int version) async {
    _isPlayingButtonSpeech = true;
    while (_buttonSpeechQueue.isNotEmpty && version == _buttonSpeechVersion) {
      final pendingCount = _buttonSpeechQueue.length;
      final text = _buttonSpeechQueue.removeAt(0);
      final audioBased = _tts.shouldUseAudioBasedPlayback(
        featureKey: mathCalculatorTtsFeatureKey,
      );
      final rate = _buttonSpeechRate(pendingCount, audioBased: audioBased);

      try {
        await _tts.speak(
          text,
          featureKey: mathCalculatorTtsFeatureKey,
          rate: rate,
        );
        await _waitForButtonSpeech(
          text,
          pendingCount,
          version,
          audioBased: audioBased,
        );
      } catch (e) {
        debugPrint('Math button TTS failed for "$text": $e');
      }
    }
    if (version == _buttonSpeechVersion) {
      _isPlayingButtonSpeech = false;
    }
  }

  double _buttonSpeechRate(int pendingCount, {required bool audioBased}) {
    if (audioBased) {
      if (pendingCount >= 18) return 1.75;
      if (pendingCount >= 10) return 1.45;
      if (pendingCount >= 5) return 1.2;
      return 1;
    }

    if (pendingCount >= 18) return 0.98;
    if (pendingCount >= 10) return 0.9;
    if (pendingCount >= 5) return 0.78;
    return 0.62;
  }

  Future<void> _waitForButtonSpeech(String text, int pendingCount, int version,
      {required bool audioBased}) async {
    final minMs = audioBased
        ? 80
        : pendingCount >= 10
            ? 20
            : 45;
    final maxMs = audioBased
        ? (pendingCount >= 18
            ? 720
            : pendingCount >= 10
                ? 900
                : 1200)
        : 260;
    final startedAt = DateTime.now();
    await Future.delayed(Duration(milliseconds: minMs + text.length * 25));

    while (_tts.isSpeaking.value &&
        version == _buttonSpeechVersion &&
        DateTime.now().difference(startedAt).inMilliseconds < maxMs) {
      await Future.delayed(const Duration(milliseconds: 40));
    }
  }

  Future<void> _warmUpMathAudio() async {
    for (final text in mathWarmupSpeechTexts.toSet()) {
      try {
        await _tts.prefetchCftts(
          text,
          featureKey: mathCalculatorTtsFeatureKey,
        );
      } catch (e) {
        debugPrint('Math TTS warmup failed for "$text": $e');
      }
    }
  }

  String _buttonSpeech(String key) => mathKeySpeechMap[key] ?? key;

  Future<void> _openTtsSettings() async {
    await Get.to(() => const MathTtsSettingsPage());
    unawaited(_warmUpMathAudio());
  }

  void _pressNumber(String value, {bool forPractice = false}) {
    setState(() {
      if (forPractice) {
        if (value == '.' && _answerInput.contains('.')) return;
        if (!_canAppendDigit(_answerInput, value, _maxPracticeDigits)) {
          _showInputTooLongTip();
          return;
        }
        _enqueueButtonSpeech(_buttonSpeech(value));
        if (_answerInput == '0' && value != '.') {
          _answerInput = value;
        } else {
          _answerInput += value;
        }
        return;
      }

      if (_startFresh) {
        if (!_canAppendDigit('', value, _maxCalculatorDigits)) {
          _showInputTooLongTip();
          return;
        }
        _enqueueButtonSpeech(_buttonSpeech(value));
        _display = value == '.' ? '0.' : value;
        _startFresh = false;
        return;
      }

      if (value == '.' && _display.contains('.')) return;
      if (!_canAppendDigit(_display, value, _maxCalculatorDigits)) {
        _showInputTooLongTip();
        return;
      }
      _enqueueButtonSpeech(_buttonSpeech(value));
      if (_display == '0' && value != '.') {
        _display = value;
      } else {
        _display += value;
      }
    });
  }

  bool _canAppendDigit(String current, String value, int maxDigits) {
    if (value == '.') {
      return current.isEmpty || !current.contains('.');
    }

    final next = current == '0' ? value : '$current$value';
    final parts = next.split('.');
    final digitCount = parts.join().length;
    final decimalPlaces = parts.length > 1 ? parts.last.length : 0;
    return digitCount <= maxDigits && decimalPlaces <= _maxDecimalPlaces;
  }

  void _showInputTooLongTip() {
    if (Get.isSnackbarOpen) return;
    ToastUtils.showInfo('数字太长啦，先算这一小步吧。');
  }

  void _pressOperator(_MathOp op) {
    _enqueueButtonSpeech(_buttonSpeech(_opSymbol(op)));

    setState(() {
      final current = double.tryParse(_display) ?? 0;
      if (_pendingOp != null && !_startFresh) {
        final next = _calculate(_storedValue ?? 0, current, _pendingOp!);
        if (next == null) {
          _display = '不能除以0';
          _storedValue = null;
          _pendingOp = null;
          _startFresh = true;
          return;
        }
        _storedValue = next;
        _display = _formatNumber(next);
      } else {
        _storedValue = current;
      }
      _pendingOp = op;
      _startFresh = true;
    });
  }

  void _pressEquals() {
    if (_pendingOp == null || _storedValue == null) return;

    setState(() {
      final right = double.tryParse(_display) ?? 0;
      final result = _calculate(_storedValue!, right, _pendingOp!);
      if (result == null) {
        _display = '不能除以0';
        _speak('除数不能是零哦');
      } else {
        _display = _formatNumber(result);
        _speak('等于 $_display');
      }
      _storedValue = null;
      _pendingOp = null;
      _startFresh = true;
    });
  }

  void _clearCalculator() {
    _enqueueButtonSpeech(_buttonSpeech('C'));
    setState(() {
      _display = '0';
      _storedValue = null;
      _pendingOp = null;
      _startFresh = false;
    });
  }

  void _backspaceCalculator() {
    setState(() {
      if (_display.length <= 1 || _display == '不能除以0') {
        _display = '0';
      } else {
        _display = _display.substring(0, _display.length - 1);
      }
    });
  }

  void _clearPracticeInput() {
    _enqueueButtonSpeech(_buttonSpeech('清空'));
    setState(() => _answerInput = '');
  }

  void _backspacePracticeInput() {
    setState(() {
      if (_answerInput.isNotEmpty) {
        _answerInput = _answerInput.substring(0, _answerInput.length - 1);
      }
    });
  }

  void _changeGrade(int grade) {
    _speak('$grade年级');
    setState(() {
      _grade = grade;
      _problem = _generateProblem(grade);
      _answerInput = '';
      _practiceResult = null;
    });
  }

  void _submitAnswer() {
    if (_answerInput.isEmpty || _practiceResult != null) return;

    final answer = double.tryParse(_answerInput);
    if (answer == null) return;

    final isCorrect = (answer - _problem.answer).abs() < 0.01;
    setState(() {
      _totalCount++;
      if (isCorrect) {
        _correctCount++;
        _streak++;
      } else {
        _streak = 0;
      }
      _practiceResult = _PracticeResult(
        isCorrect: isCorrect,
        revealExplanation: isCorrect,
      );
    });

    if (isCorrect) {
      _speak('答对啦，真棒！${_shortExplanation(_problem)}');
    } else {
      _speak('差一点点，再想一想。可以点看提示。');
    }
  }

  void _revealHint() {
    setState(() {
      _practiceResult = _practiceResult?.copyWith(revealExplanation: true);
    });
    _speak(_shortExplanation(_problem));
  }

  void _nextProblem() {
    _stopButtonSpeechQueue();
    _tts.stop();
    setState(() {
      _problem = _generateProblem(_grade);
      _answerInput = '';
      _practiceResult = null;
    });
  }

  void _speakProblem() {
    _speak('请计算：${_questionSpeech(_problem)}');
  }

  void _speakExplanation() {
    _speak(_fullExplanation(_problem));
  }

  double? _calculate(double left, double right, _MathOp op) {
    switch (op) {
      case _MathOp.add:
        return left + right;
      case _MathOp.subtract:
        return left - right;
      case _MathOp.multiply:
        return left * right;
      case _MathOp.divide:
        if (right == 0) return null;
        return left / right;
    }
  }

  _MathProblem _generateProblem(int grade) {
    final problem = switch (grade) {
      1 => _gradeOneProblem(),
      2 => _gradeTwoProblem(),
      3 => _gradeThreeProblem(),
      4 => _gradeFourProblem(),
      5 => _gradeFiveProblem(),
      _ => _gradeSixProblem(),
    };
    _rememberPracticeOp(problem.op);
    return problem;
  }

  _MathOp _pickPracticeOp(List<_MathOp> options) {
    final lastOp = _recentPracticeOps.isEmpty ? null : _recentPracticeOps.last;
    final candidates =
        lastOp == null ? options : options.where((op) => op != lastOp).toList();
    final pool = candidates.isEmpty ? options : candidates;
    return pool[_random.nextInt(pool.length)];
  }

  void _rememberPracticeOp(_MathOp op) {
    _recentPracticeOps.add(op);
    if (_recentPracticeOps.length > 4) {
      _recentPracticeOps.removeAt(0);
    }
  }

  _MathProblem _gradeOneProblem() {
    final op = _pickPracticeOp([_MathOp.add, _MathOp.subtract]);
    if (op == _MathOp.add) {
      final left = _random.nextInt(16);
      final right = _random.nextInt(21 - left);
      return _problemOf(left, right, op);
    }
    final left = 5 + _random.nextInt(16);
    final right = _random.nextInt(left + 1);
    return _problemOf(left, right, op);
  }

  _MathProblem _gradeTwoProblem() {
    final op =
        _pickPracticeOp([_MathOp.add, _MathOp.subtract, _MathOp.multiply]);
    if (op == _MathOp.multiply) {
      final left = 2 + _random.nextInt(8);
      final right = 2 + _random.nextInt(8);
      return _problemOf(left, right, op);
    }
    if (op == _MathOp.add) {
      final left = 10 + _random.nextInt(70);
      final right = _random.nextInt(101 - left);
      return _problemOf(left, right, op);
    }
    final left = 20 + _random.nextInt(81);
    final right = _random.nextInt(left + 1);
    return _problemOf(left, right, op);
  }

  _MathProblem _gradeThreeProblem() {
    final op = _pickPracticeOp(
        [_MathOp.add, _MathOp.subtract, _MathOp.multiply, _MathOp.divide]);
    if (op == _MathOp.multiply) {
      final left = 12 + _random.nextInt(78);
      final right = 2 + _random.nextInt(8);
      return _problemOf(left, right, op);
    }
    if (op == _MathOp.divide) {
      final right = 2 + _random.nextInt(8);
      final answer = 2 + _random.nextInt(18);
      return _problemOf(right * answer, right, op);
    }
    if (op == _MathOp.add) {
      final left = 100 + _random.nextInt(600);
      final right = _random.nextInt(1000 - left);
      return _problemOf(left, right, op);
    }
    final left = 100 + _random.nextInt(900);
    final right = _random.nextInt(left + 1);
    return _problemOf(left, right, op);
  }

  _MathProblem _gradeFourProblem() {
    final op = _pickPracticeOp(
        [_MathOp.add, _MathOp.subtract, _MathOp.multiply, _MathOp.divide]);
    if (op == _MathOp.multiply) {
      final left = 20 + _random.nextInt(80);
      final right = 10 + _random.nextInt(40);
      return _problemOf(left, right, op);
    }
    if (op == _MathOp.divide) {
      final right = 4 + _random.nextInt(16);
      final answer = 10 + _random.nextInt(90);
      return _problemOf(right * answer, right, op);
    }
    if (op == _MathOp.add) {
      final left = 500 + _random.nextInt(4000);
      final right = _random.nextInt(9000 - left);
      return _problemOf(left, right, op);
    }
    final left = 500 + _random.nextInt(8500);
    final right = _random.nextInt(left + 1);
    return _problemOf(left, right, op);
  }

  _MathProblem _gradeFiveProblem() {
    final op = _pickPracticeOp(
        [_MathOp.add, _MathOp.subtract, _MathOp.multiply, _MathOp.divide]);
    if (op == _MathOp.divide) {
      final right = 2 + _random.nextInt(8);
      final answer = _oneDecimal(1 + _random.nextInt(80));
      return _problemOf(answer * right, right, op);
    }
    final left = _oneDecimal(10 + _random.nextInt(900));
    final right = _oneDecimal(10 + _random.nextInt(400));
    if (op == _MathOp.subtract && right > left) {
      return _problemOf(right, left, op);
    }
    return _problemOf(left, right, op);
  }

  _MathProblem _gradeSixProblem() {
    if (_random.nextInt(4) == 0 &&
        !_recentPracticeOps.reversed.take(2).contains(_MathOp.multiply)) {
      final whole = [40, 50, 60, 80, 100, 120, 150, 200][_random.nextInt(8)];
      final percent = [10, 20, 25, 50, 75][_random.nextInt(5)];
      return _MathProblem(
        left: whole.toDouble(),
        right: percent.toDouble(),
        op: _MathOp.multiply,
        answer: whole * percent / 100,
        kind: _ProblemKind.percentOf,
      );
    }

    final op = _pickPracticeOp(
        [_MathOp.add, _MathOp.subtract, _MathOp.multiply, _MathOp.divide]);
    if (op == _MathOp.divide) {
      final right = _oneDecimal(2 + _random.nextInt(30));
      final answer = _oneDecimal(10 + _random.nextInt(90));
      return _problemOf(answer * right, right, op);
    }
    final left = _oneDecimal(20 + _random.nextInt(1200));
    final right = _oneDecimal(10 + _random.nextInt(800));
    if (op == _MathOp.subtract && right > left) {
      return _problemOf(right, left, op);
    }
    return _problemOf(left, right, op);
  }

  _MathProblem _problemOf(num left, num right, _MathOp op) {
    final l = left.toDouble();
    final r = right.toDouble();
    return _MathProblem(
      left: l,
      right: r,
      op: op,
      answer: _roundForKids(_calculate(l, r, op) ?? 0),
    );
  }

  double _oneDecimal(int tenths) => tenths / 10;

  double _roundForKids(double value) => (value * 100).round() / 100;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _mathMist,
      appBar: AppBar(
        title: const Text('数学乐园'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: '语音设置',
            onPressed: _openTtsSettings,
            icon: const Icon(Icons.record_voice_over_rounded),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(child: _buildAnimatedBackground()),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 10.h),
                  child: _buildTabBar(),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildCalculatorTab(),
                      _buildPracticeTab(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnimatedBackground() {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _backgroundController,
        builder: (context, child) {
          final t = _backgroundController.value;
          return DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFFF7FBFF),
                  Color(0xFFEAF8FF),
                  Color(0xFFFFF5E1),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Stack(
              children: [
                _floatingText(
                  text: '🐟',
                  left: 18.w + sin(t * pi) * 18,
                  top: 108.h,
                  size: 36.sp,
                  opacity: 0.2,
                  blur: 1.2,
                ),
                _floatingText(
                  text: '🐾',
                  right: 28.w,
                  top: 154.h + cos(t * pi) * 16,
                  size: 32.sp,
                  opacity: 0.18,
                  blur: 1.5,
                ),
                _floatingText(
                  text: '❄',
                  left: 64.w,
                  bottom: 220.h + t * 18,
                  size: 30.sp,
                  opacity: 0.18,
                  blur: 1.0,
                ),
                _floatingText(
                  text: '🐱',
                  right: 34.w + cos(t * pi * 1.4) * 12,
                  bottom: 100.h,
                  size: 34.sp,
                  opacity: 0.16,
                  blur: 1.4,
                ),
                Positioned(
                  left: -40.w + sin(t * pi) * 10,
                  top: 250.h,
                  child: _blurBlob(
                    _mathMint.withValues(alpha: 0.18),
                    150.w,
                  ),
                ),
                Positioned(
                  right: -50.w,
                  top: 360.h + cos(t * pi) * 14,
                  child: _blurBlob(
                    _mathCoral.withValues(alpha: 0.16),
                    170.w,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _floatingText({
    required String text,
    double? left,
    double? top,
    double? right,
    double? bottom,
    required double size,
    required double opacity,
    required double blur,
  }) {
    return Positioned(
      left: left,
      top: top,
      right: right,
      bottom: bottom,
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Text(
          text,
          style: TextStyle(
            color: Colors.black.withValues(alpha: opacity),
            fontSize: size,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }

  Widget _blurBlob(Color color, double size) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(size / 2),
        ),
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      padding: EdgeInsets.all(5.w),
      decoration: BoxDecoration(
        color: _mathPaper.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(22.r),
        border: Border.all(color: _mathSky.withValues(alpha: 0.7), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: _mathSea.withValues(alpha: 0.1),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: TabBar(
        controller: _tabController,
        dividerColor: Colors.transparent,
        dividerHeight: 0,
        overlayColor: WidgetStateProperty.all(Colors.transparent),
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          color: _mathButter,
          borderRadius: BorderRadius.circular(18.r),
        ),
        labelColor: _mathInk,
        unselectedLabelColor: _mathInk.withValues(alpha: 0.55),
        labelStyle: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w900),
        tabs: const [
          Tab(text: '小小计算器'),
          Tab(text: '数学练习'),
        ],
      ),
    );
  }

  Widget _buildCalculatorTab() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 18.h),
      child: Column(
        children: [
          _buildHeroBoard(
            title: '星星算盘',
            subtitle: '一步一步算，数字会说话',
            color: _mathSea,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _display,
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: _display.length > 10 ? 34.sp : 46.sp,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
                SizedBox(height: 8.h),
                Text(
                  _pendingOp == null
                      ? '按数字开始'
                      : '${_formatNumber(_storedValue ?? 0)} ${_opSymbol(_pendingOp!)}',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.82),
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 14.h),
          _buildCalculatorKeys(),
        ],
      ),
    );
  }

  Widget _buildPracticeTab() {
    final result = _practiceResult;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 18.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildGradePicker(),
          SizedBox(height: 12.h),
          _buildPracticeHeader(),
          SizedBox(height: 12.h),
          _buildProblemCard(),
          SizedBox(height: 12.h),
          _buildPracticeKeys(),
          if (result != null) ...[
            SizedBox(height: 14.h),
            _buildResultPanel(result),
          ],
        ],
      ),
    );
  }

  Widget _buildHeroBoard({
    required String title,
    required String subtitle,
    required Color color,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(18.w),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(26.r),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.24),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42.w,
                height: 42.w,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(14.r),
                ),
                alignment: Alignment.center,
                child: Text('★', style: TextStyle(fontSize: 22.sp)),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20.sp,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.84),
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 16.h),
          child,
        ],
      ),
    );
  }

  Widget _buildCalculatorKeys() {
    return Column(
      children: [
        _keyRow([
          _keySpec('C', _mathCoral, onTap: _clearCalculator),
          _keySpec('⌫', _mathButter,
              foreground: _mathInk, onTap: _backspaceCalculator),
          _keySpec('÷', _mathSea, onTap: () => _pressOperator(_MathOp.divide)),
          _keySpec('×', _mathSea,
              onTap: () => _pressOperator(_MathOp.multiply)),
        ]),
        _keyRow([
          _numberKey('7'),
          _numberKey('8'),
          _numberKey('9'),
          _keySpec('-', _mathSea,
              onTap: () => _pressOperator(_MathOp.subtract)),
        ]),
        _keyRow([
          _numberKey('4'),
          _numberKey('5'),
          _numberKey('6'),
          _keySpec('+', _mathSea, onTap: () => _pressOperator(_MathOp.add)),
        ]),
        _keyRow([
          _numberKey('1'),
          _numberKey('2'),
          _numberKey('3'),
          _keySpec('=', _mathLavender, onTap: _pressEquals),
        ]),
        _keyRow([
          _numberKey('0', flex: 2),
          _numberKey('.'),
          _keySpec('读', _mathSea, onTap: () => _speak(_display)),
        ]),
      ],
    );
  }

  Widget _buildPracticeKeys() {
    return Column(
      children: [
        _keyRow([
          _practiceNumberKey('7'),
          _practiceNumberKey('8'),
          _practiceNumberKey('9')
        ]),
        _keyRow([
          _practiceNumberKey('4'),
          _practiceNumberKey('5'),
          _practiceNumberKey('6')
        ]),
        _keyRow([
          _practiceNumberKey('1'),
          _practiceNumberKey('2'),
          _practiceNumberKey('3')
        ]),
        _keyRow([
          _practiceNumberKey('0', flex: 2),
          _practiceNumberKey('.'),
        ]),
        _keyRow([
          _keySpec('清空', _mathButter,
              foreground: _mathInk, onTap: _clearPracticeInput),
          _keySpec('删除', _mathSea, onTap: _backspacePracticeInput),
          _keySpec('提交', _mathCoral, onTap: _submitAnswer),
        ]),
      ],
    );
  }

  _KeySpec _numberKey(String label, {int flex = 1}) {
    return _keySpec(
      label,
      _mathPaper,
      foreground: _mathInk,
      flex: flex,
      onTap: () => _pressNumber(label),
    );
  }

  _KeySpec _practiceNumberKey(String label, {int flex = 1}) {
    return _keySpec(
      label,
      _mathPaper,
      foreground: _mathInk,
      flex: flex,
      onTap: () => _pressNumber(label, forPractice: true),
    );
  }

  _KeySpec _keySpec(
    String label,
    Color color, {
    required VoidCallback onTap,
    Color foreground = Colors.white,
    int flex = 1,
  }) {
    return _KeySpec(
      label: label,
      color: color,
      foreground: foreground,
      onTap: onTap,
      flex: flex,
    );
  }

  Widget _keyRow(List<_KeySpec> specs) {
    return Padding(
      padding: EdgeInsets.only(bottom: 10.h),
      child: Row(
        children: [
          for (int i = 0; i < specs.length; i++) ...[
            Expanded(
              flex: specs[i].flex,
              child: _MathKeyButton(spec: specs[i]),
            ),
            if (i != specs.length - 1) SizedBox(width: 10.w),
          ],
        ],
      ),
    );
  }

  Widget _buildGradePicker() {
    return SizedBox(
      height: 46.h,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: 6,
        separatorBuilder: (_, __) => SizedBox(width: 8.w),
        itemBuilder: (context, index) {
          final grade = index + 1;
          final selected = grade == _grade;
          final colors = [
            _mathButter,
            _mathMint,
            _mathSea,
            _mathCoral,
            _mathLavender,
            const Color(0xFFFFA6CF),
          ];
          return GestureDetector(
            onTap: () => _changeGrade(grade),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: EdgeInsets.symmetric(horizontal: 16.w),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? colors[index] : Colors.white,
                borderRadius: BorderRadius.circular(18.r),
                border: Border.all(color: colors[index], width: 2),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: colors[index].withValues(alpha: 0.22),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                      ]
                    : null,
              ),
              child: Text(
                '${_gradeName(grade)}年级',
                style: TextStyle(
                  color: selected ? Colors.white : _mathInk,
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPracticeHeader() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
      decoration: BoxDecoration(
        color: _mathPaper.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(color: _mathSky.withValues(alpha: 0.65), width: 1.5),
      ),
      child: Row(
        children: [
          _statChip('答对', '$_correctCount/$_totalCount', _mathMint),
          SizedBox(width: 8.w),
          _statChip('连对', '$_streak', _mathButter),
          const Spacer(),
          _SmallActionButton(
            icon: Icons.volume_up_rounded,
            label: '读题',
            color: _mathSea,
            onTap: _speakProblem,
          ),
          SizedBox(width: 8.w),
          _SmallActionButton(
            icon: Icons.arrow_forward_rounded,
            label: _practiceResult == null ? '换一题' : '下一题',
            color: _mathCoral,
            onTap: _nextProblem,
          ),
        ],
      ),
    );
  }

  Widget _statChip(String label, String value, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 7.h),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14.r),
      ),
      child: Text(
        '$label $value',
        style: TextStyle(
          color: AppTheme.textMain,
          fontSize: 12.sp,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildProblemCard() {
    return _buildHeroBoard(
      title: '$_gradeLabel 小挑战',
      subtitle: _gradeHint(_grade),
      color: _mathSea,
      child: _buildInlineProblem(),
    );
  }

  Widget _buildInlineProblem() {
    final expression = _questionText(_problem);
    final answer = _answerInput.isEmpty ? '?' : _answerInput;
    final totalLength = expression.length + answer.length;
    final fontSize = totalLength > 18
        ? 23.sp
        : totalLength > 14
            ? 27.sp
            : 32.sp;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 14.h),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8.w,
        runSpacing: 8.h,
        children: [
          Text(
            expression,
            style: TextStyle(
              color: Colors.white,
              fontSize: fontSize,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            constraints: BoxConstraints(minWidth: 52.w, maxWidth: 190.w),
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 7.h),
            decoration: BoxDecoration(
              color: _answerInput.isEmpty ? _mathButter : Colors.white,
              borderRadius: BorderRadius.circular(16.r),
            ),
            child: Text(
              answer,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _answerInput.isEmpty
                    ? _mathInk.withValues(alpha: 0.55)
                    : _mathInk,
                fontSize: answer.length > 9 ? 20.sp : 26.sp,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultPanel(_PracticeResult result) {
    final showExplanation = result.revealExplanation;
    final color = result.isCorrect ? _mathMint : _mathButter;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24.r),
        border: Border.all(color: color, width: 2),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.16),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                result.isCorrect ? '★ 答对啦！' : '再试一次，差一点点',
                style: TextStyle(
                  color: _mathInk,
                  fontSize: 18.sp,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              if (!showExplanation)
                _SmallActionButton(
                  icon: Icons.lightbulb_rounded,
                  label: '看提示',
                  color: _mathButter,
                  onTap: _revealHint,
                ),
            ],
          ),
          if (showExplanation) ...[
            SizedBox(height: 12.h),
            _buildConclusion(),
            SizedBox(height: 12.h),
            _buildWorkSheet(),
            SizedBox(height: 12.h),
            _buildTeacherTalk(),
            SizedBox(height: 12.h),
            Row(
              children: [
                Expanded(
                  child: _SmallActionButton(
                    icon: Icons.volume_up_rounded,
                    label: '再听一遍',
                    color: _mathSea,
                    onTap: _speakExplanation,
                  ),
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: _SmallActionButton(
                    icon: Icons.arrow_forward_rounded,
                    label: '下一题',
                    color: _mathCoral,
                    onTap: _nextProblem,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildConclusion() {
    return _noteCard(
      title: '结论',
      color: _mathMint,
      child: Text(
        '${_questionText(_problem)} ${_formatNumber(_problem.answer)}',
        style: TextStyle(
          color: AppTheme.textMain,
          fontSize: 18.sp,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _buildWorkSheet() {
    return _noteCard(
      title: _problem.supportsVertical ? '竖式' : '想法',
      color: _mathButter,
      child: _problem.supportsVertical
          ? _buildVerticalWork(_problem)
          : Text(
              _thinkingText(_problem),
              style: TextStyle(
                color: AppTheme.textMain,
                fontSize: 15.sp,
                height: 1.45,
                fontWeight: FontWeight.w700,
              ),
            ),
    );
  }

  Widget _buildTeacherTalk() {
    return _noteCard(
      title: '小老师讲一讲',
      color: _mathSea,
      child: Text(
        _fullExplanation(_problem),
        style: TextStyle(
          color: AppTheme.textMain,
          fontSize: 15.sp,
          height: 1.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _noteCard({
    required String title,
    required Color color,
    required Widget child,
  }) {
    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18.r),
        border: Border.all(color: color.withValues(alpha: 0.55), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: AppTheme.textSub,
              fontSize: 12.sp,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 8.h),
          child,
        ],
      ),
    );
  }

  Widget _buildVerticalWork(_MathProblem problem) {
    final left = problem.left.round();
    final right = problem.right.round();
    final answer = problem.answer.round();
    final digitCount = max(
      max(left.toString().length, right.toString().length),
      answer.toString().length,
    );
    final carryCells = problem.op == _MathOp.add
        ? _additionCarryCells(left, right, digitCount)
        : List<String>.filled(digitCount, '');
    final borrowMarks = problem.op == _MathOp.subtract
        ? _subtractionBorrowMarks(left, right, digitCount)
        : List<_VerticalMark?>.filled(digitCount, null);
    final hasCarry = carryCells.any((cell) => cell.isNotEmpty);
    final hasBorrow = borrowMarks.any((mark) => mark != null);

    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (hasCarry) _verticalMarkRow(carryCells, digitCount),
            _verticalNumberRow(left, digitCount),
            if (hasBorrow) ...[
              SizedBox(height: 3.h),
              _verticalBorrowRow(borrowMarks),
            ],
            _verticalNumberRow(
              right,
              digitCount,
              operator: _opSymbol(problem.op),
            ),
            Container(
              width: 30.w + digitCount * 38.w,
              height: 3.h,
              margin: EdgeInsets.symmetric(vertical: 5.h),
              decoration: BoxDecoration(
                color: _mathInk.withValues(alpha: 0.62),
                borderRadius: BorderRadius.circular(99.r),
              ),
            ),
            _verticalNumberRow(answer, digitCount),
          ],
        ),
      ),
    );
  }

  Widget _verticalNumberRow(int value, int width, {String operator = ''}) {
    final cells = value
        .toString()
        .padLeft(width, ' ')
        .split('')
        .map((char) => char.trim())
        .toList();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 30.w,
          child: Text(
            operator,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _mathInk,
              fontSize: 26.sp,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
        ),
        ...cells.map((cell) => _verticalDigitCell(cell)),
      ],
    );
  }

  Widget _verticalDigitCell(String text) {
    return SizedBox(
      width: 38.w,
      height: 34.h,
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _mathInk,
            fontSize: 27.sp,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }

  Widget _verticalMarkRow(List<String> cells, int width) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(width: 30.w),
        ...List.generate(width, (index) {
          final text = cells[index];
          return SizedBox(
            width: 38.w,
            height: 24.h,
            child: Center(
              child: text.isEmpty
                  ? const SizedBox.shrink()
                  : _verticalMarkChip(
                      _VerticalMark(
                        text: text,
                        color: _mathSea,
                        background: _mathSky.withValues(alpha: 0.72),
                      ),
                    ),
            ),
          );
        }),
      ],
    );
  }

  Widget _verticalBorrowRow(List<_VerticalMark?> marks) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(width: 30.w),
        ...marks.map(
          (mark) => SizedBox(
            width: 38.w,
            height: 26.h,
            child: Center(
              child: mark == null
                  ? const SizedBox.shrink()
                  : _verticalMarkChip(mark),
            ),
          ),
        ),
      ],
    );
  }

  Widget _verticalMarkChip(_VerticalMark mark) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 2.h),
      decoration: BoxDecoration(
        color: mark.background ?? mark.color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8.r),
        border: Border.all(color: mark.color.withValues(alpha: 0.55)),
      ),
      child: Text(
        mark.text,
        maxLines: 1,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: mark.color,
          fontSize: mark.text.length > 2 ? 8.5.sp : 12.sp,
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
        ),
      ),
    );
  }

  List<_VerticalMark?> _subtractionBorrowMarks(
    int left,
    int right,
    int width,
  ) {
    final working =
        left.toString().padLeft(width, '0').split('').map(int.parse).toList();
    final rightDigits =
        right.toString().padLeft(width, '0').split('').map(int.parse).toList();
    final markers = List<_VerticalMark?>.filled(width, null);

    for (var i = width - 1; i >= 0; i--) {
      if (working[i] < rightDigits[i]) {
        var borrowFrom = i - 1;
        while (borrowFrom >= 0 && working[borrowFrom] == 0) {
          working[borrowFrom] = 9;
          markers[borrowFrom] = _VerticalMark(
            text: '9',
            color: _mathSea,
            background: _mathSky.withValues(alpha: 0.7),
          );
          borrowFrom--;
        }
        if (borrowFrom >= 0) {
          working[borrowFrom] -= 1;
          markers[borrowFrom] = _VerticalMark(
            text: working[borrowFrom].toString(),
            color: _mathSea,
            background: _mathSky.withValues(alpha: 0.7),
          );
          working[i] += 10;
          markers[i] = _VerticalMark(
            text: working[i].toString(),
            color: _mathCoral,
            background: const Color(0xFFFFE2DE),
          );
        }
      }
    }

    return markers;
  }

  List<String> _additionCarryCells(int left, int right, int width) {
    var carry = 0;
    final markers = List<String>.filled(width, '');
    final leftDigits = left.toString().padLeft(width, '0');
    final rightDigits = right.toString().padLeft(width, '0');

    for (var i = width - 1; i >= 0; i--) {
      final sum = int.parse(leftDigits[i]) + int.parse(rightDigits[i]) + carry;
      if (sum >= 10 && i > 0) {
        markers[i - 1] = '1';
        carry = 1;
      } else {
        carry = 0;
      }
    }

    return markers;
  }

  bool _hasAdditionCarry(int left, int right) {
    final width = max(
      max(left.toString().length, right.toString().length),
      (left + right).toString().length,
    );
    return _additionCarryCells(left, right, width)
        .any((cell) => cell.isNotEmpty);
  }

  bool _hasSubtractionBorrow(int left, int right) {
    final width = max(left.toString().length, right.toString().length);
    return _subtractionBorrowMarks(left, right, width)
        .any((mark) => mark != null);
  }

  String _thinkingText(_MathProblem problem) {
    if (problem.kind == _ProblemKind.percentOf) {
      return '${_formatNumber(problem.right)}% 就是把 100 份分成 ${_formatNumber(problem.right)} 份。'
          '${_formatNumber(problem.left)} × ${_formatNumber(problem.right)} ÷ 100 = ${_formatNumber(problem.answer)}。';
    }

    switch (problem.op) {
      case _MathOp.multiply:
        return '${_formatNumber(problem.left)} × ${_formatNumber(problem.right)} '
            '可以想成 ${_formatNumber(problem.right)} 个 ${_formatNumber(problem.left)} 合在一起。';
      case _MathOp.divide:
        return '${_formatNumber(problem.left)} ÷ ${_formatNumber(problem.right)} '
            '就是把 ${_formatNumber(problem.left)} 平均分成 ${_formatNumber(problem.right)} 份。';
      case _MathOp.add:
      case _MathOp.subtract:
        return problem.usesDecimal
            ? '先把小数点对齐，再从右往左算，最后把小数点放回同一列。'
            : '个位对个位，十位对十位，从右往左一列一列算。';
    }
  }

  String _shortExplanation(_MathProblem problem) {
    return '${_questionText(problem)} ${_formatNumber(problem.answer)}。';
  }

  String _fullExplanation(_MathProblem problem) {
    if (problem.kind == _ProblemKind.percentOf) {
      return '${_formatNumber(problem.right)}% 的意思是百分之 ${_formatNumber(problem.right)}。'
          '所以先算 ${_formatNumber(problem.left)} × ${_formatNumber(problem.right)}，'
          '再除以 100，答案是 ${_formatNumber(problem.answer)}。';
    }

    if (problem.op == _MathOp.add) {
      if (problem.usesDecimal) {
        return '小数加法先把小数点对齐，也就是相同数位对齐；再从最右边开始逐位相加，满 10 就向左边一位进 1。答案是 ${_formatNumber(problem.answer)}。'
            '验算时，用答案减其中一个加数，能得到另一个加数。';
      }
      final left = problem.left.round();
      final right = problem.right.round();
      final carry = _hasAdditionCarry(left, right);
      return carry
          ? '相同数位对齐，从个位算起。某一列相加满 10，就把个位数字写在本列，向左边一列进 1；下一列计算时要把进来的 1 一起加上。'
              '所以 ${_formatNumber(problem.left)} + ${_formatNumber(problem.right)} = ${_formatNumber(problem.answer)}。'
              '验算：${_formatNumber(problem.answer)} - ${_formatNumber(problem.right)} = ${_formatNumber(problem.left)}。'
          : '相同数位对齐，从个位算起。这题每一列相加都不满 10，不需要进位，逐列相加就能得到 ${_formatNumber(problem.answer)}。'
              '验算：${_formatNumber(problem.answer)} - ${_formatNumber(problem.right)} = ${_formatNumber(problem.left)}。';
    }

    if (problem.op == _MathOp.subtract) {
      if (problem.usesDecimal) {
        return '小数减法也要先把小数点对齐，也就是相同数位对齐；再从最右边开始逐位相减。哪一位不够减，就向左边借 1，当前位多 10 再减。'
            '答案是 ${_formatNumber(problem.answer)}。验算时，用差加减数，能得到被减数。';
      }
      final left = problem.left.round();
      final right = problem.right.round();
      final borrow = _hasSubtractionBorrow(left, right);
      return borrow
          ? '相同数位对齐，从个位算起。遇到某一位不够减，就从左边一位借 1；借来的 1 在当前位相当于 10，左边那一位要少 1。'
              '所以 ${_formatNumber(problem.left)} - ${_formatNumber(problem.right)} = ${_formatNumber(problem.answer)}。'
              '验算：${_formatNumber(problem.answer)} + ${_formatNumber(problem.right)} = ${_formatNumber(problem.left)}。'
          : '相同数位对齐，从个位算起。这题每一列都够减，不需要借位，逐列相减就能得到 ${_formatNumber(problem.answer)}。'
              '验算：${_formatNumber(problem.answer)} + ${_formatNumber(problem.right)} = ${_formatNumber(problem.left)}。';
    }

    if (problem.op == _MathOp.multiply) {
      return '乘法可以看成“几个几”。${_formatNumber(problem.left)} × ${_formatNumber(problem.right)} '
          '就是 ${_formatNumber(problem.right)} 个 ${_formatNumber(problem.left)}，答案是 ${_formatNumber(problem.answer)}。'
          '验算时，用答案除以其中一个因数，能得到另一个因数。';
    }

    return '除法可以看成平均分。把 ${_formatNumber(problem.left)} 平均分成 ${_formatNumber(problem.right)} 份，'
        '每份是 ${_formatNumber(problem.answer)}。也可以用乘法检查：${_formatNumber(problem.answer)} × ${_formatNumber(problem.right)} = ${_formatNumber(problem.left)}。';
  }

  String _questionText(_MathProblem problem) {
    if (problem.kind == _ProblemKind.percentOf) {
      return '${_formatNumber(problem.left)} 的 ${_formatNumber(problem.right)}% =';
    }
    return '${_formatNumber(problem.left)} ${_opSymbol(problem.op)} ${_formatNumber(problem.right)} =';
  }

  String _questionSpeech(_MathProblem problem) {
    if (problem.kind == _ProblemKind.percentOf) {
      return '${_formatNumber(problem.left)} 的百分之 ${_formatNumber(problem.right)} 是多少';
    }
    return '${_formatNumber(problem.left)} ${_opSpeech(problem.op)} ${_formatNumber(problem.right)} 等于多少';
  }

  String _formatNumber(num value) {
    final rounded = (value * 100).round() / 100;
    if ((rounded - rounded.round()).abs() < 0.0001) {
      return rounded.round().toString();
    }
    return rounded
        .toStringAsFixed(2)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
  }

  String _opSymbol(_MathOp op) {
    switch (op) {
      case _MathOp.add:
        return '+';
      case _MathOp.subtract:
        return '-';
      case _MathOp.multiply:
        return '×';
      case _MathOp.divide:
        return '÷';
    }
  }

  String _opSpeech(_MathOp op) {
    switch (op) {
      case _MathOp.add:
        return '加';
      case _MathOp.subtract:
        return '减';
      case _MathOp.multiply:
        return '乘';
      case _MathOp.divide:
        return '除以';
    }
  }

  String _gradeName(int grade) => ['一', '二', '三', '四', '五', '六'][grade - 1];

  String get _gradeLabel => '${_gradeName(_grade)}年级';

  String _gradeHint(int grade) {
    switch (grade) {
      case 1:
        return '20以内加减法';
      case 2:
        return '100以内加减和口诀乘法';
      case 3:
        return '三位数与表内乘除';
      case 4:
        return '多位数四则运算';
      case 5:
        return '小数和整数四则';
      default:
        return '小数、百分数和综合口算';
    }
  }
}

class _KeySpec {
  const _KeySpec({
    required this.label,
    required this.color,
    required this.foreground,
    required this.onTap,
    required this.flex,
  });

  final String label;
  final Color color;
  final Color foreground;
  final VoidCallback onTap;
  final int flex;
}

class _MathKeyButton extends StatefulWidget {
  const _MathKeyButton({required this.spec});

  final _KeySpec spec;

  @override
  State<_MathKeyButton> createState() => _MathKeyButtonState();
}

class _MathKeyButtonState extends State<_MathKeyButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(20.r);
    final splashColor = widget.spec.foreground == Colors.white
        ? Colors.white.withValues(alpha: 0.38)
        : _mathSea.withValues(alpha: 0.24);

    return AnimatedScale(
      scale: _pressed ? 0.92 : 1,
      duration: const Duration(milliseconds: 95),
      curve: Curves.easeOutBack,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: 58.h,
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          boxShadow: [
            BoxShadow(
              color:
                  widget.spec.color.withValues(alpha: _pressed ? 0.14 : 0.26),
              blurRadius: _pressed ? 5 : 12,
              offset: Offset(0, _pressed ? 2 : 7),
            ),
          ],
        ),
        child: Material(
          color: _pressed
              ? widget.spec.color.withValues(alpha: 0.86)
              : widget.spec.color,
          borderRadius: borderRadius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.spec.onTap,
            onTapDown: (_) => setState(() => _pressed = true),
            onTapCancel: () => setState(() => _pressed = false),
            onTapUp: (_) => setState(() => _pressed = false),
            borderRadius: borderRadius,
            splashColor: splashColor,
            highlightColor: splashColor.withValues(alpha: 0.18),
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: borderRadius,
                border: Border.all(
                  color: widget.spec.foreground == Colors.white
                      ? Colors.white.withValues(alpha: 0.34)
                      : const Color(0xFFF2C66B),
                  width: 2,
                ),
              ),
              child: Center(
                child: Text(
                  widget.spec.label,
                  maxLines: 1,
                  style: TextStyle(
                    color: widget.spec.foreground,
                    fontSize: widget.spec.label.length > 1 ? 16.sp : 26.sp,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SmallActionButton extends StatefulWidget {
  const _SmallActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  State<_SmallActionButton> createState() => _SmallActionButtonState();
}

class _SmallActionButtonState extends State<_SmallActionButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.94 : 1,
        duration: const Duration(milliseconds: 90),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 9.h),
          decoration: BoxDecoration(
            color:
                _pressed ? widget.color.withValues(alpha: 0.86) : widget.color,
            borderRadius: BorderRadius.circular(16.r),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: _pressed ? 0.12 : 0.22),
                blurRadius: _pressed ? 5 : 10,
                offset: Offset(0, _pressed ? 2 : 5),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(widget.icon, color: Colors.white, size: 17.sp),
              SizedBox(width: 5.w),
              Flexible(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
