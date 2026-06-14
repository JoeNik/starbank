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
import '../models/encyclopedia_question.dart';
import '../models/encyclopedia_config.dart';
import '../models/encyclopedia_explanation_cache.dart';
import '../models/growth_record.dart';
import '../models/milestone_record.dart';
import '../models/baby_cloud_source.dart';
import '../models/baby_cloud_media.dart';
import '../models/baby_cloud_upload_task.dart';
import '../models/baby_cloud_entry.dart';

class StorageService extends GetxService {
  late Box<UserProfile> userBox;
  late Box<ActionItem> actionBox;
  late Box<Log> logBox;
  late Box<Product> productBox;
  late Box<Baby> babyBox;
  late Box<Playlist> playlistBox;
  late Box<GrowthRecord> growthRecordBox;
  late Box<MilestoneRecord> milestoneRecordBox;
  late Box<BabyCloudSource> babyCloudSourceBox;
  late Box<BabyCloudMedia> babyCloudMediaBox;
  late Box<BabyCloudEntry> babyCloudEntryBox;
  late Box<BabyCloudUploadTask> babyCloudUploadTaskBox;
  Box get settingsBox => Hive.box('settings');

  dynamic getValue(String key) => settingsBox.get(key);
  Future<void> saveValue(String key, dynamic value) =>
      settingsBox.put(key, value);

  Future<StorageService> init() async {
    // Hive.initFlutter() 已在 main.dart 中调用,这里不需要重复初始化
    // 重复初始化会导致之前注册的适配器失效
    debugPrint('📦 StorageService.init() 开始...');

    _registerAdapter(UserProfileAdapter(), 'UserProfileAdapter');
    _registerAdapter(ActionItemAdapter(), 'ActionItemAdapter');
    _registerAdapter(LogAdapter(), 'LogAdapter');
    _registerAdapter(ProductAdapter(), 'ProductAdapter');
    _registerAdapter(BabyAdapter(), 'BabyAdapter');
    _registerAdapter(MusicTrackAdapter(), 'MusicTrackAdapter');
    _registerAdapter(PlaylistAdapter(), 'PlaylistAdapter');
    debugPrint('✅ 基础适配器注册完成');

    // Quiz and Story Adapters (安全注册,避免重复)
    // QuizConfig 和 QuizQuestion 使用 typeId 30/31
    if (!Hive.isAdapterRegistered(30)) {
      Hive.registerAdapter(QuizConfigAdapter());
      debugPrint('✅ StorageService: QuizConfigAdapter registered (typeId: 30)');
    } else {
      debugPrint('⏭️ StorageService: QuizConfigAdapter 已注册,跳过');
    }
    if (!Hive.isAdapterRegistered(31)) {
      Hive.registerAdapter(QuizQuestionAdapter());
      debugPrint(
          '✅ StorageService: QuizQuestionAdapter registered (typeId: 31)');
    } else {
      debugPrint('⏭️ StorageService: QuizQuestionAdapter 已注册,跳过');
    }
    if (!Hive.isAdapterRegistered(22)) {
      Hive.registerAdapter(NewYearStoryAdapter());
      debugPrint('✅ StorageService: NewYearStoryAdapter registered');
    } else {
      debugPrint('⏭️ StorageService: NewYearStoryAdapter 已注册,跳过');
    }
    if (!Hive.isAdapterRegistered(43)) {
      Hive.registerAdapter(EncyclopediaQuestionAdapter());
      debugPrint(
          '✅ StorageService: EncyclopediaQuestionAdapter registered (typeId: 43)');
    } else {
      debugPrint('⏭️ StorageService: EncyclopediaQuestionAdapter 已注册,跳过');
    }
    if (!Hive.isAdapterRegistered(44)) {
      Hive.registerAdapter(EncyclopediaConfigAdapter());
      debugPrint(
          '✅ StorageService: EncyclopediaConfigAdapter registered (typeId: 44)');
    } else {
      debugPrint('⏭️ StorageService: EncyclopediaConfigAdapter 已注册,跳过');
    }
    if (!Hive.isAdapterRegistered(45)) {
      Hive.registerAdapter(EncyclopediaExplanationCacheAdapter());
      debugPrint(
          '✅ StorageService: EncyclopediaExplanationCacheAdapter registered (typeId: 45)');
    } else {
      debugPrint(
          '⏭️ StorageService: EncyclopediaExplanationCacheAdapter 已注册,跳过');
    }
    if (!Hive.isAdapterRegistered(46)) {
      Hive.registerAdapter(GrowthRecordAdapter());
      debugPrint(
          '✅ StorageService: GrowthRecordAdapter registered (typeId: 46)');
    }
    if (!Hive.isAdapterRegistered(47)) {
      Hive.registerAdapter(MilestoneRecordAdapter());
      debugPrint(
          '✅ StorageService: MilestoneRecordAdapter registered (typeId: 47)');
    }
    if (!Hive.isAdapterRegistered(48)) {
      Hive.registerAdapter(BabyCloudSourceAdapter());
      debugPrint(
          '✅ StorageService: BabyCloudSourceAdapter registered (typeId: 48)');
    }
    if (!Hive.isAdapterRegistered(49)) {
      Hive.registerAdapter(BabyCloudMediaAdapter());
      debugPrint(
          '✅ StorageService: BabyCloudMediaAdapter registered (typeId: 49)');
    }
    if (!Hive.isAdapterRegistered(50)) {
      Hive.registerAdapter(BabyCloudUploadTaskAdapter());
      debugPrint(
          '✅ StorageService: BabyCloudUploadTaskAdapter registered (typeId: 50)');
    }
    if (!Hive.isAdapterRegistered(51)) {
      Hive.registerAdapter(BabyCloudEntryAdapter());
      debugPrint(
          '✅ StorageService: BabyCloudEntryAdapter registered (typeId: 51)');
    }

    userBox = await Hive.openBox<UserProfile>('userBox');
    actionBox = await Hive.openBox<ActionItem>('actionBox');
    logBox = await Hive.openBox<Log>('logBox');
    productBox = await Hive.openBox<Product>('productBox');
    babyBox = await Hive.openBox<Baby>('babyBox');
    playlistBox = await Hive.openBox<Playlist>('playlistBox');

    // Generic settings box must be available before optional feature boxes,
    // because optional boxes can switch to a recovered box name if old local
    // test data is unreadable after model changes.
    await Hive.openBox('settings');

    growthRecordBox = await _openRecoverableBox<GrowthRecord>('growth_records');
    milestoneRecordBox =
        await _openRecoverableBox<MilestoneRecord>('milestone_records');
    babyCloudSourceBox =
        await _openRecoverableBox<BabyCloudSource>('baby_cloud_sources');
    babyCloudMediaBox =
        await _openRecoverableBox<BabyCloudMedia>('baby_cloud_media');
    babyCloudEntryBox =
        await _openRecoverableBox<BabyCloudEntry>('baby_cloud_entries');
    babyCloudUploadTaskBox = await _openRecoverableBox<BabyCloudUploadTask>(
      'baby_cloud_upload_tasks',
    );

    await _initDefaultData();

    return this;
  }

  void _registerAdapter<T>(TypeAdapter<T> adapter, String label) {
    if (!Hive.isAdapterRegistered(adapter.typeId)) {
      Hive.registerAdapter<T>(adapter);
      debugPrint(
          '✅ StorageService: $label registered (typeId: ${adapter.typeId})');
    } else {
      debugPrint('⏭️ StorageService: $label 已注册,跳过');
    }
  }

  Future<Box<T>> _openRecoverableBox<T>(String boxName) async {
    final key = 'active_recovered_box_$boxName';
    final recoveredName = settingsBox.get(key) as String?;
    if (recoveredName != null && recoveredName.isNotEmpty) {
      try {
        return await Hive.openBox<T>(recoveredName);
      } catch (e, stack) {
        debugPrint('恢复盒子 $recoveredName 打开失败，将重新创建: $e');
        debugPrint('Stack: $stack');
      }
    }

    try {
      return await Hive.openBox<T>(boxName);
    } catch (e, stack) {
      debugPrint('可选盒子 $boxName 打开失败，保留原数据并切换到新盒子: $e');
      debugPrint('Stack: $stack');
      final fallbackName =
          '${boxName}_recovered_${DateTime.now().millisecondsSinceEpoch}';
      await settingsBox.put(key, fallbackName);
      return Hive.openBox<T>(fallbackName);
    }
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
