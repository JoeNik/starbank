import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/user_profile.dart';
import '../models/action_item.dart';
import '../models/log.dart';
import '../models/product.dart';
import '../models/baby.dart';
import '../models/music/music_track.dart';
import '../models/music/playlist.dart';
import '../models/new_year_story.dart';
import '../models/quiz_question.dart';
import '../models/quiz_config.dart';

class StorageService extends GetxService {
  late Box<UserProfile> userBox;
  late Box<ActionItem> actionBox;
  late Box<Log> logBox;
  late Box<Product> productBox;
  late Box<Baby> babyBox;
  late Box<Playlist> playlistBox;
  Box get settingsBox => Hive.box('settings');

  dynamic getValue(String key) => settingsBox.get(key);
  Future<void> saveValue(String key, dynamic value) =>
      settingsBox.put(key, value);

  Future<StorageService> init() async {
    // Hive.initFlutter() 已在 main.dart 中调用,这里不需要重复初始化
    // 重复初始化会导致之前注册的适配器失效
    debugPrint('📦 StorageService.init() 开始...');

    Hive.registerAdapter(UserProfileAdapter());
    Hive.registerAdapter(ActionItemAdapter());
    Hive.registerAdapter(LogAdapter());
    Hive.registerAdapter(ProductAdapter());
    Hive.registerAdapter(BabyAdapter());
    Hive.registerAdapter(MusicTrackAdapter());
    Hive.registerAdapter(PlaylistAdapter());
    debugPrint('✅ 基础适配器注册完成');

    // Quiz and Story Adapters (安全注册,避免重复)
    if (!Hive.isAdapterRegistered(20)) {
      Hive.registerAdapter(QuizConfigAdapter());
      debugPrint('✅ StorageService: QuizConfigAdapter registered');
    } else {
      debugPrint('⏭️ StorageService: QuizConfigAdapter 已注册,跳过');
    }
    if (!Hive.isAdapterRegistered(21)) {
      Hive.registerAdapter(QuizQuestionAdapter());
      debugPrint('✅ StorageService: QuizQuestionAdapter registered');
    } else {
      debugPrint('⏭️ StorageService: QuizQuestionAdapter 已注册,跳过');
    }
    if (!Hive.isAdapterRegistered(22)) {
      Hive.registerAdapter(NewYearStoryAdapter());
      debugPrint('✅ StorageService: NewYearStoryAdapter registered');
    } else {
      debugPrint('⏭️ StorageService: NewYearStoryAdapter 已注册,跳过');
    }

    userBox = await Hive.openBox<UserProfile>('userBox');
    actionBox = await Hive.openBox<ActionItem>('actionBox');
    logBox = await Hive.openBox<Log>('logBox');
    productBox = await Hive.openBox<Product>('productBox');
    babyBox = await Hive.openBox<Baby>('babyBox');
    playlistBox = await Hive.openBox<Playlist>('playlistBox');

    // Generic settings box
    await Hive.openBox('settings');

    await _initDefaultData();

    return this;
  }

  Future<void> _initDefaultData() async {
    if (babyBox.isEmpty) {
      final defaultBaby = Baby(
        id: '1',
        name: '宝宝',
        avatarPath: '', // 使用默认 emoji 头像
        starCount: 10,
        piggyBankBalance: 100.0,
        pocketMoneyBalance: 20.0,
      );
      await babyBox.add(defaultBaby);
    }

    // User profile used for global settings/name
    if (userBox.isEmpty) {
      await userBox.add(UserProfile(name: '星球家长', avatarPath: ''));
    }

    if (actionBox.isEmpty) {
      await actionBox.addAll([
        ActionItem(name: '按时起床', type: 'reward', value: 1, iconName: '⏰'),
        ActionItem(name: '好好吃饭', type: 'reward', value: 1, iconName: '🍚'),
        ActionItem(name: '主动学习', type: 'reward', value: 2, iconName: '📚'),
        ActionItem(name: '收拾玩具', type: 'reward', value: 1, iconName: '🧸'),
        ActionItem(name: '看电视超时', type: 'punish', value: -1, iconName: '📺'),
        ActionItem(name: '淘气不听话', type: 'punish', value: -2, iconName: '👿'),
      ]);
    }
  }
}
