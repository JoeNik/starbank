import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:star_bank/controllers/app_mode_controller.dart';
import 'package:star_bank/controllers/shop_controller.dart';
import 'package:star_bank/controllers/user_controller.dart';
import 'package:star_bank/main.dart' as app;
import 'package:star_bank/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('core startup bindings register UserController permanently', () async {
    final temp = await Directory.systemTemp.createTemp('starbank_startup_');
    try {
      Hive.init(temp.path);
      final storage = await StorageService().init();
      Get.put(storage, permanent: true);

      app.ensureCoreBindingsForStartup();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(Get.isRegistered<UserController>(), isTrue);
      expect(Get.isRegistered<ShopController>(), isTrue);
      expect(Get.isRegistered<AppModeController>(), isTrue);
      expect(Get.find<UserController>().babies, isNotEmpty);
    } finally {
      Get.reset();
      await Hive.close();
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    }
  });

  test('optional feature boxes recover without blocking core startup',
      () async {
    final temp = await Directory.systemTemp.createTemp('starbank_recover_');
    try {
      Hive.init(temp.path);
      final legacyBox = await Hive.openBox('baby_cloud_media');
      await legacyBox.put('legacy', {'shape': 'old'});

      final storage = await StorageService().init();
      Get.put(storage, permanent: true);
      app.ensureCoreBindingsForStartup();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(Get.isRegistered<UserController>(), isTrue);
      expect(storage.babyCloudMediaBox.isOpen, isTrue);
      expect(
        storage.settingsBox.get('active_recovered_box_baby_cloud_media'),
        isNotNull,
      );
    } finally {
      Get.reset();
      await Hive.close();
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    }
  });
}
