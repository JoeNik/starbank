import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get/get.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'services/storage_service.dart';
import 'services/webdav_service.dart';
import 'services/update_service.dart';
import 'services/tts_service.dart';
import 'services/pinyin_audio_service.dart';
import 'controllers/user_controller.dart';
import 'controllers/shop_controller.dart';
import 'controllers/app_mode_controller.dart';
import 'services/tunehub_service.dart';
import 'services/music_service.dart';
import 'services/music_cache_service.dart';
import 'controllers/music_player_controller.dart';
import 'services/openai_service.dart';
import 'services/quiz_service.dart';
import 'services/encyclopedia_service.dart';
import 'services/story_management_service.dart';
import 'services/ai_generation_service.dart';
import 'models/quiz_config.dart';
import 'models/quiz_question.dart';
import 'models/hanzi_learning_config.dart';
import 'models/openai_tts_config.dart';
import 'models/encyclopedia_question.dart';
import 'models/encyclopedia_config.dart';
import 'models/encyclopedia_explanation_cache.dart';
import 'services/hanzi_learning_service.dart';
import 'services/baby_cloud_service.dart';
// import 'package:just_audio_background/just_audio_background.dart';

import 'pages/home_page.dart';
import 'theme/app_theme.dart';
import 'pages/bank_page.dart';
import 'pages/shop_page.dart';
import 'pages/entertainment_page.dart';
import 'pages/record_page.dart';
import 'navigation/app_route_observer.dart';

// 版本号位置
// 两个地方需要同步更新：

// pubspec.yaml
//  第 19 行：version: 2.0.0
// lib/pages/settings_page.dart
//  第 9 行：const String appVersion = '2.0.0';
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // JustAudioBackground is DISABLED to fix Android 14 Crashes.
  // Do not initialize it.

  // 初始化 Hive
  await Hive.initFlutter();
  debugPrint('🔧 Hive 初始化完成');

  // 立即注册关键适配器,确保在任何服务使用前完成
  // QuizConfig 和 QuizQuestion 使用 typeId 30/31 (避免与音乐模型 20/21 冲突)
  if (!Hive.isAdapterRegistered(30)) {
    Hive.registerAdapter(QuizConfigAdapter());
    debugPrint('✅ QuizConfigAdapter registered (typeId: 30)');
  } else {
    debugPrint('⚠️ QuizConfigAdapter already registered (typeId: 30)');
  }
  if (!Hive.isAdapterRegistered(31)) {
    Hive.registerAdapter(QuizQuestionAdapter());
    debugPrint('✅ QuizQuestionAdapter registered (typeId: 31)');
  } else {
    debugPrint('⚠️ QuizQuestionAdapter already registered (typeId: 31)');
  }
  // 汉字学习配置适配器
  if (!Hive.isAdapterRegistered(40)) {
    Hive.registerAdapter(HanziLearningConfigAdapter());
    debugPrint('✅ HanziLearningConfigAdapter registered (typeId: 40)');
  } else {
    debugPrint('⚠️ HanziLearningConfigAdapter already registered (typeId: 40)');
  }
  if (!Hive.isAdapterRegistered(42)) {
    Hive.registerAdapter(OpenAITtsConfigAdapter());
    debugPrint('✅ OpenAITtsConfigAdapter registered (typeId: 42)');
  } else {
    debugPrint('⚠️ OpenAITtsConfigAdapter already registered (typeId: 42)');
  }
  if (!Hive.isAdapterRegistered(43)) {
    Hive.registerAdapter(EncyclopediaQuestionAdapter());
    debugPrint('✅ EncyclopediaQuestionAdapter registered (typeId: 43)');
  } else {
    debugPrint(
        '⚠️ EncyclopediaQuestionAdapter already registered (typeId: 43)');
  }
  if (!Hive.isAdapterRegistered(44)) {
    Hive.registerAdapter(EncyclopediaConfigAdapter());
    debugPrint('✅ EncyclopediaConfigAdapter registered (typeId: 44)');
  } else {
    debugPrint('⚠️ EncyclopediaConfigAdapter already registered (typeId: 44)');
  }
  if (!Hive.isAdapterRegistered(45)) {
    Hive.registerAdapter(EncyclopediaExplanationCacheAdapter());
    debugPrint('✅ EncyclopediaExplanationCacheAdapter registered (typeId: 45)');
  } else {
    debugPrint(
        '⚠️ EncyclopediaExplanationCacheAdapter already registered (typeId: 45)');
  }

  debugPrint('📦 准备初始化 StorageService...');

  Object? startupError;
  StackTrace? startupStack;

  try {
    final storageService = StorageService();
    await storageService.init();
    Get.put(storageService, permanent: true);

    ensureCoreBindingsForStartup();
    debugPrint('Core services and controllers initialized');
  } catch (e, stack) {
    startupError = e;
    startupStack = stack;
    debugPrint('Critical core initialization error: $e');
    debugPrint('Stack trace: $stack');
  }

  if (startupError == null) {
    try {
      final ttsService = TtsService();
      await ttsService.init();
      Get.put(ttsService);
    } catch (e, stack) {
      debugPrint('TtsService init failed: $e');
      debugPrint('Stack: $stack');
    }

    try {
      final pinyinAudioService = PinyinAudioService();
      await pinyinAudioService.init();
      Get.put(pinyinAudioService);
    } catch (e, stack) {
      debugPrint('PinyinAudioService init failed: $e');
      debugPrint('Stack: $stack');
    }

    try {
      final babyCloudService = BabyCloudService();
      Get.put(babyCloudService, permanent: true);
      await babyCloudService.init();
    } catch (e, stack) {
      debugPrint('BabyCloudService init failed: $e');
      debugPrint('Stack: $stack');
      if (!Get.isRegistered<BabyCloudService>()) {
        Get.put(BabyCloudService(), permanent: true);
      }
    }

    try {
      final openAIService = OpenAIService();
      Get.put(openAIService);
      await openAIService.init();

      final quizService = QuizService();
      Get.put(quizService);
      await quizService.init();

      final encyclopediaService = EncyclopediaService();
      Get.put(encyclopediaService);
      await encyclopediaService.init();

      final storyManagementService = StoryManagementService.instance;
      await storyManagementService.init();

      Get.put(AIGenerationService());

      final hanziService = HanziLearningService();
      Get.put(hanziService);
      await hanziService.init();

      debugPrint('Quiz, Story and Hanzi services initialized');
    } catch (e, stack) {
      debugPrint('Quiz/Story services init failed: $e');
      debugPrint('Stack: $stack');
    }

    try {
      await Get.put(MusicService(), permanent: true).init();

      final musicCacheService = Get.put(MusicCacheService(), permanent: true);
      await musicCacheService.initialize();

      Get.put(MusicPlayerController(), permanent: true);
      debugPrint('Music services initialized');
    } catch (e, stack) {
      debugPrint('Music services init failed: $e');
      debugPrint('Stack: $stack');
    }
  }

  // 4. Global Error Handling for Release Mode
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.white,
        body: SingleChildScrollView(
          // Allow scrolling for long stack traces
          padding: const EdgeInsets.all(20),
          child: SafeArea(
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 10),
              const Text("应用遇到错误 (Application Error)",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Text(details.exception.toString(),
                  style: const TextStyle(
                      color: Colors.red, fontWeight: FontWeight.bold)),
              const Divider(),
              Text(details.stack.toString(),
                  style: const TextStyle(fontSize: 12, color: Colors.black54)),
            ],
          )),
        ),
      ),
    );
  };

  runApp(MyApp(startupError: startupError, startupStack: startupStack));
}

void ensureCoreBindingsForStartup() {
  if (!Get.isRegistered<StorageService>()) {
    throw StateError('StorageService 未注册，无法启动核心控制器');
  }
  if (!Get.isRegistered<WebDavService>()) {
    Get.put(WebDavService(), permanent: true);
  }
  if (!Get.isRegistered<UpdateService>()) {
    Get.put(UpdateService(), permanent: true);
  }
  if (!Get.isRegistered<UserController>()) {
    Get.put(UserController(), permanent: true);
  }
  if (!Get.isRegistered<ShopController>()) {
    Get.put(ShopController(), permanent: true);
  }
  if (!Get.isRegistered<AppModeController>()) {
    Get.put(AppModeController(), permanent: true);
  }
  if (!Get.isRegistered<TuneHubService>()) {
    Get.put(TuneHubService(), permanent: true);
  }
}

class MyApp extends StatelessWidget {
  const MyApp({
    super.key,
    this.startupError,
    this.startupStack,
  });

  final Object? startupError;
  final StackTrace? startupStack;

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(375, 812),
      minTextAdapt: true,
      splitScreenMode: false,
      builder: (context, child) {
        return GetMaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'StarBank',
          theme: AppTheme.theme,
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [
            Locale('zh', 'CN'),
            Locale('en', 'US'),
          ],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          navigatorObservers: [appRouteObserver],
          initialRoute: '/',
          getPages: [
            GetPage(
              name: '/',
              page: () => startupError == null
                  ? const MainNavigationShell()
                  : StartupFailurePage(
                      error: startupError!,
                      stack: startupStack,
                    ),
            ),
          ],
        );
      },
    );
  }
}

class StartupFailurePage extends StatelessWidget {
  const StartupFailurePage({
    super.key,
    required this.error,
    this.stack,
  });

  final Object error;
  final StackTrace? stack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 12),
              const Text(
                '启动初始化失败',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Text(
                error.toString(),
                style: const TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Divider(height: 28),
              Text(
                stack?.toString() ?? '无堆栈信息',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MainNavigationShell extends StatefulWidget {
  const MainNavigationShell({super.key});

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    // 启动时延迟检查更新，避免影响启动体验
    Future.delayed(const Duration(seconds: 2), () {
      Get.find<UpdateService>().checkForUpdate();
    });
  }

  @override
  Widget build(BuildContext context) {
    ensureCoreBindingsForStartup();
    final pages = [
      const HomePage(),
      const BankPage(),
      RecordPage(isActive: _currentIndex == 2),
      const EntertainmentPage(),
      const ShopPage(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: List.generate(
          pages.length,
          (index) => TickerMode(
            enabled: _currentIndex == index,
            child: pages[index],
          ),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: AppTheme.primaryDark,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: '主页'),
          BottomNavigationBarItem(
              icon: Icon(Icons.account_balance), label: '银行'),
          BottomNavigationBarItem(icon: Icon(Icons.photo_album), label: '亲宝宝'),
          BottomNavigationBarItem(
              icon: Icon(Icons.sports_esports), label: '娱乐'),
          BottomNavigationBarItem(icon: Icon(Icons.shopping_cart), label: '商店'),
        ],
      ),
    );
  }
}
