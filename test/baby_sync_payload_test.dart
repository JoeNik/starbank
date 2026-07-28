import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:star_bank/models/baby.dart';

void main() {
  group('Baby.syncableAvatarPath', () {
    test('keeps assets and http urls', () {
      expect(Baby.syncableAvatarPath('assets/avatars/a.png'),
          'assets/avatars/a.png');
      expect(Baby.syncableAvatarPath('https://cdn.example/a.png'),
          'https://cdn.example/a.png');
      expect(Baby.syncableAvatarPath('http://cdn.example/a.png'),
          'http://cdn.example/a.png');
    });

    test('keeps short emoji-like tokens', () {
      expect(Baby.syncableAvatarPath('👶'), '👶');
      expect(Baby.syncableAvatarPath('star'), 'star');
    });

    test('strips local paths and large raw references without compression', () {
      expect(Baby.syncableAvatarPath('/data/user/0/app/avatar.jpg'), '');
      expect(Baby.syncableAvatarPath(r'C:\Users\a\avatar.png'), '');
      expect(
          Baby.syncableAvatarPath('data:image/png;base64,${'A' * 100}'), '');
      expect(Baby.syncableAvatarPath('iVBORw0KGgo${'A' * 200}'), '');
    });
  });

  group('Baby name/avatar merge', () {
    test('preferName keeps real local name over placeholder remote', () {
      expect(Baby.preferName('宝宝ab12', '小明'), '小明');
      expect(Baby.preferName('小红', '小明'), '小红');
      expect(Baby.preferName('', '小明'), '小明');
      expect(Baby.preferName('宝宝', ''), '宝宝');
    });

    test('preferAvatar keeps local when remote empty', () {
      expect(Baby.preferAvatar('', 'assets/a.png'), 'assets/a.png');
      expect(Baby.preferAvatar('https://x/a.png', 'assets/a.png'),
          'https://x/a.png');
      expect(Baby.preferAvatar('/missing/path.jpg', 'assets/a.png'),
          'assets/a.png');
    });

    test('isPlaceholderName detects sync placeholders', () {
      expect(Baby.isPlaceholderName('宝宝'), isTrue);
      expect(Baby.isPlaceholderName('宝宝ab12'), isTrue);
      expect(Baby.isPlaceholderName('小明'), isFalse);
      expect(Baby.isPlaceholderName(''), isTrue);
    });
  });

  group('Baby.toSyncJson', () {
    test('keeps name and strips missing local avatar path', () async {
      final baby = Baby(
        id: 'abc123',
        name: '小明',
        avatarPath: '/local/path/photo.jpg',
        starCount: 12,
        piggyBankBalance: 3.5,
        pocketMoneyBalance: 1.2,
        gender: 'male',
      );
      final json = await baby.toSyncJson();
      expect(json['id'], 'abc123');
      expect(json['name'], '小明');
      expect(json['avatarPath'], '');
      expect(json['starCount'], 12);
      expect(json['gender'], 'male');
    });

    test('compresses oversized raw avatar bytes into sync payload', () async {
      // 构造一张简单 PNG 再放大体积意义不大；用重复字节模拟大图压缩路径
      final tinyPng = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
      );
      final compressed =
          await Baby.compressAvatarBytes(Uint8List.fromList(tinyPng));
      expect(compressed, isNotNull);
      expect(compressed!.isNotEmpty, isTrue);

      final baby = Baby(
        id: 'id1',
        name: '小红',
        avatarPath: compressed,
      );
      final json = await baby.toSyncJson();
      expect(json['name'], '小红');
      expect((json['avatarPath'] as String).isNotEmpty, isTrue);
    });

    test('fromJson tolerates stringy numbers and missing fields', () {
      final baby = Baby.fromJson({
        'id': 42,
        'name': null,
        'avatarPath': null,
        'starCount': '7',
        'piggyBankBalance': '1.5',
        'pocketMoneyBalance': 2,
      });
      expect(baby.id, '42');
      expect(baby.name, '宝宝');
      expect(baby.avatarPath, '');
      expect(baby.starCount, 7);
      expect(baby.piggyBankBalance, 1.5);
      expect(baby.pocketMoneyBalance, 2);
      expect(baby.gender, 'unknown');
    });
  });
}
