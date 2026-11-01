import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:star_bank/controllers/app_mode_controller.dart';
import 'package:star_bank/controllers/music_player_controller.dart';
import 'package:star_bank/models/music/music_track.dart';
import 'package:star_bank/pages/entertainment/music/music_home_page.dart';
import 'package:star_bank/pages/entertainment/music/music_player_page.dart';
import 'package:star_bank/pages/entertainment/music/playlist_detail_page.dart';
import 'package:star_bank/services/chksz_music_service.dart';
import 'package:star_bank/services/music_cache_service.dart';
import 'package:star_bank/services/music_service.dart';
import 'package:star_bank/services/music_source.dart';
import 'package:star_bank/services/storage_service.dart';
import 'package:star_bank/services/tunehub_service.dart';

/// 音乐模块崩溃狩猎:按 main.dart 的依赖顺序注册服务,在多种屏幕尺寸下
/// 渲染音乐三页面并驱动队列操作,收集所有构建异常与 RenderFlex 溢出。
///
/// 注意:测试环境没有平台通道,MusicService 故意不调用 init()
/// (无音频引擎),只验证页面构建与控制器逻辑不崩溃。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('music_hunt');
    Hive.init(dir.path);
    final storage = StorageService();
    await storage.init();
    Get.put(storage, permanent: true);
    Get.put(AppModeController());
    Get.put(TuneHubService(), permanent: true);
    Get.put(ChkSzMusicService(), permanent: true);
    final registry = Get.put(MusicSourceRegistry(), permanent: true);
    registry.register(Get.find<TuneHubService>());
    registry.register(Get.find<ChkSzMusicService>());
    registry.restore();
    // 不调用 MusicService.init():测试 VM 无平台通道,页面构建不依赖播放器
    Get.put(MusicService(), permanent: true);
    Get.put(MusicCacheService(), permanent: true);
    Get.put(MusicPlayerController(), permanent: true);
  });

  tearDownAll(() async {
    await Get.delete<MusicPlayerController>(force: true);
    await Get.delete<MusicCacheService>(force: true);
    await Get.delete<MusicService>(force: true);
    await Get.delete<MusicSourceRegistry>(force: true);
    await Get.delete<ChkSzMusicService>(force: true);
    await Get.delete<TuneHubService>(force: true);
    await Get.delete<AppModeController>(force: true);
    await Get.delete<StorageService>(force: true);
  });

  MusicTrack track(String id) => MusicTrack(
        id: id,
        title: '测试歌曲 $id',
        artist: '测试歌手',
        album: '测试专辑',
        coverUrl: null,
        durationMs: 180000,
        platform: 'netease',
      );

  Future<List<String>> pumpAndCollect(
    WidgetTester tester,
    Widget page,
    Size size, {
    int pumps = 3,
  }) async {
    final errors = <String>[];
    final detailsById = <String, String>{};
    final original = FlutterError.onError;
    FlutterError.onError = (details) {
      final first = details.exceptionAsString().split('\n').first;
      final key = first;
      if (!errors.contains(key)) {
        errors.add(key);
        detailsById[key] = details.toString();
      }
    };
    try {
      // 先卸载上一棵组件树,再改视图尺寸,避免度量回调命中已停用节点。
      // 直接设 physicalSize + devicePixelRatio=1,保证 ScreenUtilInit 读到
      // 真实逻辑尺寸(setSurfaceSize 不影响 View,ScreenUtil 会拿到默认 800×600)
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(375, 812),
          builder: (context, child) => GetMaterialApp(home: page),
        ),
      );
      for (var i = 0; i < pumps; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
    } catch (e) {
      final key = 'THROWN: ${e.toString().split('\n').first}';
      if (!errors.contains(key)) errors.add(key);
    } finally {
      FlutterError.onError = original;
      await tester.pumpWidget(const SizedBox.shrink());
      // Get.snackbar 浮层带 ticker/3s 计时器,树拆除前必须清掉
      Get.closeAllSnackbars();
      await tester.pump(const Duration(seconds: 5));
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
    if (errors.isNotEmpty) {
      // 输出完整错误上下文(含出错组件定位),便于诊断
      // ignore: avoid_print
      print('════ 尺寸 $size 捕获 ${errors.length} 类异常 ════');
      for (final d in detailsById.values) {
        // ignore: avoid_print
        print(d);
      }
    }
    return errors;
  }

  final sizes = [
    const Size(375, 812),
    const Size(375, 667), // 矮屏(用户反馈溢出的场景)
    const Size(320, 568), // 更小的屏
  ];

  testWidgets('MusicHomePage 在多尺寸下构建无异常', (tester) async {
    final allErrors = <String, List<String>>{};
    for (final size in sizes) {
      final errors = await pumpAndCollect(
          tester, const MusicHomePage(), size);
      if (errors.isNotEmpty) allErrors['$size'] = errors;
    }
    expect(allErrors, isEmpty, reason: 'MusicHomePage 构建异常: $allErrors');
  });

  testWidgets('MusicPlayerPage 在多尺寸下构建无异常(含队列状态与歌词态)',
      (tester) async {
    final controller = Get.find<MusicPlayerController>();
    // 注入队列 + 歌词,覆盖播放页主要分支
    final list = [track('1'), track('2'), track('3')];
    controller.playlist.assignAll(list);
    controller.currentIndex.value = 0;
    controller.currentAudioQuality.value = 'exhigh';
    controller.lyrics.assignAll([
      LyricLine(const Duration(seconds: 1), '第一句歌词', translation: 'line one'),
      LyricLine(const Duration(seconds: 5), '第二句歌词'),
    ]);
    controller.currentLyricIndex.value = 0;
    controller.position.value = const Duration(seconds: 3);
    controller.duration.value = const Duration(minutes: 3);

    final allErrors = <String, List<String>>{};
    for (final size in sizes) {
      final errors = await pumpAndCollect(
          tester, const MusicPlayerPage(), size);
      if (errors.isNotEmpty) allErrors['$size'] = errors;
    }
    expect(allErrors, isEmpty, reason: 'MusicPlayerPage 构建异常: $allErrors');
  });

  testWidgets('PlaylistDetailPage 使用缓存数据构建无异常', (tester) async {
    PlaylistDetailPage.cache['99999999'] = {
      'name': '测试歌单',
      'cover': null,
      'tracks': [track('a'), track('b')],
    };
    final errors = await pumpAndCollect(
      tester,
      const PlaylistDetailPage(playlistId: '99999999', fallbackName: '测试歌单'),
      const Size(375, 667),
    );
    expect(errors, isEmpty, reason: 'PlaylistDetailPage 构建异常: $errors');
  });

  testWidgets('队列操作(下一首播放/移除/清空)不抛异常', (tester) async {
    // Get.snackbar 需要浮层,先挂一个空壳 GetMaterialApp
    await tester.pumpWidget(GetMaterialApp(home: Scaffold(body: SizedBox.shrink())));
    await tester.pump();
    final controller = Get.find<MusicPlayerController>();
    controller.clearPlaylist();
    controller.playlist.assignAll([track('x1'), track('x2'), track('x3')]);
    controller.currentIndex.value = 0;

    controller.playNextInQueue(track('x9'));
    expect(controller.playlist.length, 4);
    expect(controller.playlist[1].id, 'x9');

    controller.removeTrackAt(0);
    expect(controller.playlist.length, 3);
    expect(controller.currentIndex.value, 0);

    // 移除最后一首(当前曲目),索引应回退而不是越界
    controller.currentIndex.value = 2;
    controller.removeTrackAt(2);
    expect(controller.playlist.isEmpty, isFalse);

    controller.clearPlaylist();
    expect(controller.playlist.isEmpty, isTrue);

    // 推进 fake 时钟:消化 snackbar 浮层与播放失败后的 0.5s 自动跳歌计时器链
    Get.closeAllSnackbars();
    await tester.pump(const Duration(seconds: 10));
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('移除到队列为空后播放页仍可构建', (tester) async {
    final controller = Get.find<MusicPlayerController>();
    controller.playlist.assignAll([track('y1')]);
    controller.currentIndex.value = 0;
    controller.removeTrackAt(0);
    expect(controller.playlist.isEmpty, isTrue);

    // 先推进时钟消化计时器链,再渲染空队列播放页
    Get.closeAllSnackbars();
    await tester.pump(const Duration(seconds: 10));
    await tester.pump(const Duration(seconds: 10));

    final errors = await pumpAndCollect(
        tester, const MusicPlayerPage(), const Size(375, 667));
    expect(errors, isEmpty, reason: '空队列播放页构建异常: $errors');
  });
}
