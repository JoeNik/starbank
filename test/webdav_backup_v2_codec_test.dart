import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:star_bank/services/webdav_backup_v2_service.dart';
import 'package:star_bank/services/storage_service.dart';

void main() {
  test('canonicalJson sorts map keys and preserves list order', () {
    final a = {
      'b': 2,
      'a': [
        {'z': 1, 'x': 2},
      ],
    };
    final b = {
      'a': [
        {'x': 2, 'z': 1},
      ],
      'b': 2,
    };

    expect(
      WebDavBackupV2Service.canonicalJson(a),
      WebDavBackupV2Service.canonicalJson(b),
    );

    final changedOrder = {
      'a': [
        {'z': 1, 'x': 2},
        {'z': 3, 'x': 4},
      ],
      'b': 2,
    };
    final reversedOrder = {
      'a': [
        {'x': 4, 'z': 3},
        {'x': 2, 'z': 1},
      ],
      'b': 2,
    };

    expect(
      WebDavBackupV2Service.canonicalJson(changedOrder),
      isNot(WebDavBackupV2Service.canonicalJson(reversedOrder)),
    );
  });

  test('sha256Hex is stable for canonical json bytes', () {
    final json = WebDavBackupV2Service.canonicalJson({
      'section': 'core.logs',
      'items': [
        {'timestamp': '2026-05-27T00:00:00.000', 'value': 1},
      ],
    });

    final hashA = WebDavBackupV2Service.sha256Hex(utf8.encode(json));
    final hashB = WebDavBackupV2Service.sha256Hex(utf8.encode(json));

    expect(hashA, hashB);
    expect(hashA.length, 64);
  });

  test('restoreBundleFromBytes rejects object hash mismatch', () {
    final service = WebDavBackupV2Service(
      storage: StorageService(),
      read: (_) async => Uint8List(0),
      write: (_, __) async {},
      remove: (_) async {},
      mkdir: (_) async {},
      list: (_) async => const [],
    );
    final originalJson = utf8.encode(WebDavBackupV2Service.canonicalJson({
      'name': 'stable',
    }));
    final originalHash = WebDavBackupV2Service.sha256Hex(originalJson);
    final corruptedStored = Uint8List.fromList(
      WebDavBackupV2Service.gzipBytes(
        utf8.encode(WebDavBackupV2Service.canonicalJson({'name': 'changed'})),
      ),
    );

    final manifest = {
      'type': 'starbank.webdav.v2.manifest',
      'formatVersion': webDavBackupV2FormatVersion,
      'sections': {
        'genericSettings': {
          'kind': 'value',
          'object': {'hash': originalHash, 'label': 'genericSettings'},
        },
      },
      'objects': {
        originalHash: {
          'hash': originalHash,
          'kind': 'json',
          'contentType': 'application/json',
          'contentEncoding': 'gzip',
          'rawSize': originalJson.length,
          'storedSize': corruptedStored.length,
          'path': '$webDavBackupV2ObjectDir/xx/$originalHash.json.gz',
        },
      },
      'warnings': const [],
    };

    expect(
      () => service.restoreBundleFromBytes(
        manifest,
        {originalHash: corruptedStored},
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('备份对象校验失败'),
        ),
      ),
    );
  });

  test('generic settings whitelist includes stable baby cloud settings only',
      () {
    expect(
      WebDavBackupV2Service.shouldBackupGenericSetting(
        'baby_cloud_current_source_id',
      ),
      isTrue,
    );
    expect(
      WebDavBackupV2Service.shouldBackupGenericSetting('baby_cloud_actor_role'),
      isTrue,
    );
    expect(
      WebDavBackupV2Service.shouldBackupGenericSetting(
        'baby_cloud_actor_role_baby-1',
      ),
      isTrue,
    );
    expect(
      WebDavBackupV2Service.shouldBackupGenericSetting(
        'baby_cloud_aliyun_oauth_state',
      ),
      isFalse,
    );
    expect(
      WebDavBackupV2Service.shouldBackupGenericSetting(
        'baby_cloud_last_sync_source-1_baby-1',
      ),
      isFalse,
    );
  });
}
