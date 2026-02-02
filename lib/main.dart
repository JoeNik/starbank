import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'services/storage_service.dart';
import 'services/webdav_service.dart';
import 'services/update_service.dart';
import 'services/tts_service.dart';
import 'controllers/user_controller.dart';
import 'controllers/shop_controller.dart';
import 'controllers/app_mode_controller.dart';
import 'services/tunehub_service.dart';
import 'services/music_service.dart';
import 'services/music_cache_service.dart';
import 'controllers/music_player_controller.dart';
import 'services/openai_service.dart';
import 'services/quiz_service.dart';
import 'services/story_management_service.dart';
import 'services/quiz_management_service.dart';
import 'models/quiz_config.dart';
import 'models/quiz_question.dart';
// import 'package:just_audio_background/just_audio_background.dart';

import 'pages/home_page.dart';
import 'theme/app_theme.dart';
import 'pages/bank_page.dart';
import 'pages/shop_page.dart';
import 'pages/entertainment_page.dart';
import 'pages/record_page.dart';

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

  // 立即注册关键适配器,确保在任何服务使用前完成
  // 这样可以避免 HiveError: Cannot write, unknown type
  if (!Hive.isAdapterRegistered(20)) {
    Hive.registerAdapter(QuizConfigAdapter());
    debugPrint('✅ QuizConfigAdapter registered (typeId: 20)');
  }
  if (!Hive.isAdapterRegistered(21)) {
    Hive.registerAdapter(QuizQuestionAdapter());
    debugPrint('✅ QuizQuestionAdapter registered (typeId: 21)');
  }

  try {
    // 1. Initialize Storage Service (Essential)
    final storageService = StorageService();
    await storageService.init();
    Get.put(storageService);

    // 2. Initialize TTS Service (Crucial for some features)
    final ttsService = TtsService();
    await ttsService.init();
    Get.put(ttsService);

    // 3. Initialize Other Services and Controllers
    Get.put(WebDavService());
    Get.put(UpdateService());
    Get.put(UserController());
    Get.put(ShopController());
    Get.put(AppModeController());
    Get.put(TuneHubService());

    // Initialize Quiz and Story Services (with error handling)
    try {
      // 先初始化并注册 OpenAIService
      final openAIService = OpenAIService();
      Get.put(openAIService); // 必须先 put，QuizService 构造时需要
      await openAIService.init();

      // QuizService 依赖 OpenAIService，所以必须在其后创建
      final quizService = QuizService();
      Get.put(quizService);
      await quizService.init();

      final storyManagementService = StoryManagementService.instance;
      await storyManagementService.init();

      final quizManagementService = QuizManagementService.instance;
      await quizManagementService.init();

      debugPrint('Quiz and Story services initialized');
    } catch (e, stack) {
      debugPrint('Quiz/Story services init failed: $e');
      debugPrint('Stack: $stack');
    }

    // Core Music Engine (Singleton) - Solves "Multiple Player Instance" crash
    // Initialize AudioService for Android 14 Background support
    await Get.put(MusicService(), permanent: true).init();

    // Initialize Music Cache Service
    final musicCacheService = Get.put(MusicCacheService(), permanent: true);
    await musicCacheService.initialize();

    // Initialize MusicPlayerController as a permanent singleton.
    // This ensures it is always available and persists across navigation,
    // which is critical for a music player that plays in the background.
    Get.put(MusicPlayerController(), permanent: true);

    debugPrint('All services initialized successfully');
  } catch (e, stack) {
    debugPrint('Critical initialization error: $e');
    debugPrint('Stack trace: $stack');
    // We still try to run the app, but some features might be broken.
    // However, if Storage fails, most likely anything touching UI will crash.
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

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

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
          initialRoute: '/',
          getPages: [
            GetPage(name: '/', page: () => const MainNavigationShell()),
          ],
        );
      },
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

  // 导航栏页面：主页、银行、商店、娱乐、记录（设置移到主页右上角）
  final List<Widget> _pages = [
    const HomePage(),
    const BankPage(),
    const ShopPage(),
    const EntertainmentPage(),
    const RecordPage(),
  ];

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
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
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
          BottomNavigationBarItem(icon: Icon(Icons.shopping_cart), label: '商店'),
          BottomNavigationBarItem(
              icon: Icon(Icons.sports_esports), label: '娱乐'),
          BottomNavigationBarItem(icon: Icon(Icons.edit_note), label: '记录'),
        ],
      ),
    );
  }
}
