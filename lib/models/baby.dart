import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:image/image.dart' as img;

part 'baby.g.dart';

@HiveType(typeId: 4)
class Baby extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  String avatarPath;

  @HiveField(3)
  int starCount;

  @HiveField(4)
  double piggyBankBalance; // 存钱罐 (Generate Interest)

  @HiveField(5)
  double pocketMoneyBalance; // 零花钱 (Interest flows here)

  @HiveField(6)
  DateTime? lastInterestDate;

  @HiveField(7)
  DateTime? birthDate;

  /// male / female / unknown
  @HiveField(8, defaultValue: 'unknown')
  String gender;

  Baby({
    required this.id,
    required this.name,
    required this.avatarPath,
    this.starCount = 0,
    this.piggyBankBalance = 0.0,
    this.pocketMoneyBalance = 0.0,
    this.lastInterestDate,
    this.birthDate,
    this.gender = 'unknown',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'avatarPath': avatarPath,
        'starCount': starCount,
        'piggyBankBalance': piggyBankBalance,
        'pocketMoneyBalance': pocketMoneyBalance,
        'lastInterestDate': lastInterestDate?.toIso8601String(),
        'birthDate': birthDate?.toIso8601String(),
        'gender': gender,
      };

  factory Baby.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic value) {
      if (value == null) return null;
      if (value is DateTime) return value;
      final text = value.toString().trim();
      if (text.isEmpty) return null;
      return DateTime.tryParse(text);
    }

    int parseInt(dynamic value, [int fallback = 0]) {
      if (value == null) return fallback;
      if (value is int) return value;
      if (value is num) return value.round();
      return int.tryParse(value.toString()) ?? fallback;
    }

    double parseDouble(dynamic value, [double fallback = 0]) {
      if (value == null) return fallback;
      if (value is num) return value.toDouble();
      return double.tryParse(value.toString()) ?? fallback;
    }

    return Baby(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '宝宝',
      avatarPath: json['avatarPath']?.toString() ?? '',
      starCount: parseInt(json['starCount']),
      piggyBankBalance: parseDouble(json['piggyBankBalance']),
      pocketMoneyBalance: parseDouble(json['pocketMoneyBalance']),
      lastInterestDate: parseDate(json['lastInterestDate']),
      birthDate: parseDate(json['birthDate']),
      gender: json['gender']?.toString() ?? 'unknown',
    );
  }

  /// 家庭同步载荷：名字/性别/生日全量保留；头像压缩后内联，避免超 300K 被整条跳过。
  Future<Map<String, dynamic>> toSyncJson() async {
    final json = toJson();
    json['avatarPath'] = await buildSyncAvatar(avatarPath);
    return json;
  }

  /// 是否像同步补齐时生成的占位名（`宝宝` / `宝宝xxxx`）。
  static bool isPlaceholderName(String? name) {
    final value = (name ?? '').trim();
    if (value.isEmpty) return true;
    if (value == '宝宝') return true;
    return RegExp(r'^宝宝[\w\-]{1,8}$').hasMatch(value);
  }

  /// 远端与本地名字合并：真实名字优先，占位名不覆盖已有真名。
  static String preferName(String? remote, String? local) {
    final r = (remote ?? '').trim();
    final l = (local ?? '').trim();
    if (r.isEmpty) return l.isEmpty ? '宝宝' : l;
    if (isPlaceholderName(r) && l.isNotEmpty && !isPlaceholderName(l)) {
      return l;
    }
    return r;
  }

  /// 远端与本地头像合并：可用内容优先；空/本机无效路径不覆盖已有头像。
  static String preferAvatar(String? remote, String? local) {
    final r = normalizeIncomingAvatar(remote);
    final l = normalizeIncomingAvatar(local);
    if (r.isNotEmpty) return r;
    return l;
  }

  /// 应用远端头像字段：保留可跨设备内容；本机不存在的文件路径丢弃。
  static String normalizeIncomingAvatar(String? path) {
    if (path == null) return '';
    final value = path.trim();
    if (value.isEmpty) return '';
    if (value.startsWith('assets/')) return value;
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    if (value.startsWith('data:image')) return value;
    if (_looksLikeBase64Image(value)) return value;
    // 短 emoji / 内置标识
    if (value.length <= 16 &&
        !value.contains('/') &&
        !value.contains('\\') &&
        !value.contains(',')) {
      return value;
    }
    // 本机路径：仅当文件仍存在时保留
    try {
      if (File(value).existsSync()) return value;
    } catch (_) {}
    return '';
  }

  /// 推送用头像：assets/http/emoji 原样；文件/大图压缩成 raw base64。
  static Future<String> buildSyncAvatar(
    String? path, {
    int maxChars = 120000,
  }) async {
    if (path == null) return '';
    final value = path.trim();
    if (value.isEmpty) return '';
    if (value.startsWith('assets/')) return value;
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    if (value.length <= 16 &&
        !value.contains('/') &&
        !value.contains('\\') &&
        !value.contains(',')) {
      return value;
    }

    try {
      final bytes = await _loadAvatarBytes(value);
      if (bytes == null || bytes.isEmpty) return '';
      final compressed = await compressAvatarBytes(bytes, maxChars: maxChars);
      return compressed ?? '';
    } catch (e) {
      debugPrint('Baby.buildSyncAvatar failed: $e');
      return '';
    }
  }

  /// 兼容旧调用名：仅判断「不经压缩也能直接同步」的短引用。
  static String syncableAvatarPath(String? path) {
    if (path == null) return '';
    final value = path.trim();
    if (value.isEmpty) return '';
    if (value.startsWith('assets/')) return value;
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    if (value.length <= 16 &&
        !value.contains('/') &&
        !value.contains('\\') &&
        !value.contains(',')) {
      return value;
    }
    return '';
  }

  static Future<Uint8List?> _loadAvatarBytes(String value) async {
    if (value.startsWith('data:image')) {
      final comma = value.indexOf(',');
      if (comma <= 0) return null;
      return base64Decode(value.substring(comma + 1));
    }
    if (_looksLikeBase64Image(value)) {
      return base64Decode(value);
    }
    try {
      final file = File(value);
      if (await file.exists()) {
        return await file.readAsBytes();
      }
    } catch (_) {}
    return null;
  }

  /// 把头像压到适合家庭同步的体积（默认 ≤120K base64 字符）。
  static Future<String?> compressAvatarBytes(
    Uint8List bytes, {
    int maxChars = 120000,
  }) async {
    final rawB64 = base64Encode(bytes);
    if (rawB64.length <= maxChars) return rawB64;

    return compute(_compressAvatarIsolate, {
      'bytes': bytes,
      'maxChars': maxChars,
    });
  }

  static bool _looksLikeBase64Image(String value) {
    if (value.length < 64) return false;
    if (value.contains('/') || value.contains('\\') || value.contains(':')) {
      if (!RegExp(r'^[A-Za-z0-9+/=\r\n]+$').hasMatch(value)) return false;
    }
    return RegExp(r'^[A-Za-z0-9+/=\r\n]+$').hasMatch(value);
  }
}

String? _compressAvatarIsolate(Map<String, dynamic> args) {
  final bytes = args['bytes'] as Uint8List;
  final maxChars = args['maxChars'] as int? ?? 120000;
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      final raw = base64Encode(bytes);
      return raw.length <= maxChars ? raw : null;
    }
    var image = decoded;
    for (final size in const [256, 192, 128, 96]) {
      if (image.width > size || image.height > size) {
        image = img.copyResize(
          decoded,
          width: decoded.width >= decoded.height ? size : null,
          height: decoded.height > decoded.width ? size : null,
          interpolation: img.Interpolation.average,
        );
      }
      for (final quality in const [75, 60, 45, 30]) {
        final jpg = img.encodeJpg(image, quality: quality);
        final b64 = base64Encode(jpg);
        if (b64.length <= maxChars) return b64;
      }
    }
    return null;
  } catch (_) {
    return null;
  }
}
