import 'package:hive/hive.dart';

part 'cftts_config.g.dart';

/// CFTTS 配置模型
/// typeId: 41
@HiveType(typeId: 41)
class CfttsConfig extends HiveObject {
  /// 基础URL
  @HiveField(0, defaultValue: 'http://localhost:8080')
  String baseUrl;

  /// API Key 密钥
  @HiveField(1, defaultValue: '')
  String apiKey;

  /// 语音风格
  @HiveField(2, defaultValue: 'zh-CN-XiaoxiaoNeural')
  String voice;

  /// 情感风格（对应 model 字段）
  @HiveField(3, defaultValue: 'cheerful')
  String model;

  /// 语速
  @HiveField(4, defaultValue: 1.0)
  double speed;

  CfttsConfig({
    this.baseUrl = 'http://localhost:8080',
    this.apiKey = '',
    this.voice = 'zh-CN-XiaoxiaoNeural',
    this.model = 'cheerful',
    this.speed = 1.0,
  });

  Map<String, dynamic> toJson() => {
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'voice': voice,
        'model': model,
        'speed': speed,
      };

  factory CfttsConfig.fromJson(Map<String, dynamic> json) => CfttsConfig(
        baseUrl: json['baseUrl'] as String? ?? 'http://localhost:8080',
        apiKey: json['apiKey'] as String? ?? '',
        voice: json['voice'] as String? ?? 'zh-CN-XiaoxiaoNeural',
        model: json['model'] as String? ?? 'cheerful',
        speed: (json['speed'] as num?)?.toDouble() ?? 1.0,
      );
}
