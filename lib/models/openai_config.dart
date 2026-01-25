import 'package:hive/hive.dart';

part 'openai_config.g.dart';

/// OpenAI 配置模型
@HiveType(typeId: 10)
class OpenAIConfig extends HiveObject {
  /// 唯一标识
  @HiveField(0)
  String id;

  /// 配置名称
  @HiveField(1)
  String name;

  /// API 地址 (Base URL)
  @HiveField(2)
  String baseUrl;

  /// API Key
  @HiveField(3)
  String apiKey;

  /// 可用的模型列表
  @HiveField(4)
  List<String> models;

  /// 当前选中的模型
  @HiveField(5)
  String selectedModel;

  /// 是否为默认配置
  @HiveField(6)
  bool isDefault;

  OpenAIConfig({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.apiKey,
    this.models = const [],
    this.selectedModel = '',
    this.isDefault = false,
  });

  /// 转换为 JSON
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'models': models,
        'selectedModel': selectedModel,
        'isDefault': isDefault,
      };

  /// 从 JSON 创建
  factory OpenAIConfig.fromJson(Map<String, dynamic> json) => OpenAIConfig(
        id: json['id'] as String,
        name: json['name'] as String,
        baseUrl: json['baseUrl'] as String,
        apiKey: json['apiKey'] as String,
        models: (json['models'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
        selectedModel: json['selectedModel'] as String? ?? '',
        isDefault: json['isDefault'] as bool? ?? false,
      );
}
