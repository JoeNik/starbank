import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'services/storage_service.dart';
import 'services/webdav_service.dart';
import 'services/update_service.dart';
import 'controllers/user_controller.dart';
import 'controllers/shop_controller.dart';
import 'controllers/app_mode_controller.dart';
import 'pages/home_page.dart';
import 'theme/app_theme.dart';
import 'pages/bank_page.dart';
import 'pages/shop_page.dart';
import 'pages/settings_page.dart';
import 'pages/entertainment_page.dart';

// 版本号位置
// 两个地方需要同步更新：

// pubspec.yaml
//  第 19 行：version: 1.5.0
// lib/pages/settings_page.dart
//  第 9 行：const String appVersion = '1.5.0';
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Storage Service
  await Get.putAsync(() => StorageService().init());

  // Initialize Other Services and Controllers
  Get.put(WebDavService());
  Get.put(UpdateService());
  Get.put(UserController());
  Get.put(ShopController());
  Get.put(AppModeController());

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
          title: 'Star Bank',
          theme: AppTheme.theme,
          initialRoute: '/',
          getPages: [
            GetPage(name: '/', page: () => const MainNavigationShell()),
            // Other pages will be added as shells or subpages
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

  final List<Widget> _pages = [
    const HomePage(),
    const BankPage(),
    const ShopPage(),
    const EntertainmentPage(),
    const SettingsPage(),
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
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: '设置'),
        ],
      ),
    );
  }
}
