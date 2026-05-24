import 'package:hive/hive.dart';

part 'openai_tts_config.g.dart';

@HiveType(typeId: 42)
class OpenAITtsConfig extends HiveObject {
  static const List<String> xiaomiMimoV25PresetVoices = [
    'mimo_default',
    '冰糖',
    '茉莉',
    '苏打',
    '白桦',
    'Mia',
    'Chloe',
    'Milo',
    'Dean',
  ];

  static String normalizeXiaomiMimoV25Voice(String voice) {
    if (xiaomiMimoV25PresetVoices.contains(voice)) {
      return voice;
    }
    switch (voice) {
      case 'xiaomi_xinran':
      case 'xiaomi_chenxi':
      case 'xiaomi_xixi':
      case 'xiaomi_yunyang':
      case '':
        return 'mimo_default';
      default:
        return 'mimo_default';
    }
  }

  @HiveField(0)
  String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  String baseUrl;

  @HiveField(3)
  String apiKey;

  @HiveField(4, defaultValue: 'openai_standard')
  String providerType;

  @HiveField(5, defaultValue: 'bearer')
  String authType;

  @HiveField(6)
  List<String> models;

  @HiveField(7)
  String selectedModel;

  @HiveField(8)
  List<String> voices;

  @HiveField(9)
  String selectedVoice;

  @HiveField(10)
  List<String> stylePresets;

  @HiveField(11)
  String selectedStylePreset;

  @HiveField(12, defaultValue: 'mp3')
  String audioFormat;

  @HiveField(13, defaultValue: false)
  bool isDefault;

  @HiveField(14, defaultValue: true)
  bool supportsModelFetch;

  @HiveField(15, defaultValue: false)
  bool supportsVoiceFetch;

  @HiveField(16, defaultValue: true)
  bool isEnabled;

  OpenAITtsConfig({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.apiKey,
    this.providerType = 'openai_standard',
    this.authType = 'bearer',
    this.models = const [],
    this.selectedModel = '',
    this.voices = const [],
    this.selectedVoice = '',
    this.stylePresets = const [],
    this.selectedStylePreset = '',
    this.audioFormat = 'mp3',
    this.isDefault = false,
    this.supportsModelFetch = true,
    this.supportsVoiceFetch = false,
    this.isEnabled = true,
  });

  factory OpenAITtsConfig.createXiaomiMimoTemplate() {
    return OpenAITtsConfig(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: 'Xiaomi MIMO V2.5 TTS',
      baseUrl: 'https://api.xiaomimimo.com/v1',
      apiKey: '',
      providerType: 'xiaomi_mimo_v25',
      authType: 'api-key',
      models: const [
        'mimo-v2.5-tts',
        'mimo-v2.5-tts-voicedesign',
        'mimo-v2.5-tts-voiceclone',
      ],
      selectedModel: 'mimo-v2.5-tts',
      voices: xiaomiMimoV25PresetVoices,
      selectedVoice: 'mimo_default',
      stylePresets: const [
        '默认',
        '自然',
        '温柔',
        '开心',
        '讲故事',
      ],
      selectedStylePreset: '默认',
      audioFormat: 'wav',
      supportsModelFetch: true,
      supportsVoiceFetch: false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'providerType': providerType,
        'authType': authType,
        'models': models,
        'selectedModel': selectedModel,
        'voices': voices,
        'selectedVoice': selectedVoice,
        'stylePresets': stylePresets,
        'selectedStylePreset': selectedStylePreset,
        'audioFormat': audioFormat,
        'isDefault': isDefault,
        'supportsModelFetch': supportsModelFetch,
        'supportsVoiceFetch': supportsVoiceFetch,
        'isEnabled': isEnabled,
      };

  factory OpenAITtsConfig.fromJson(Map<String, dynamic> json) {
    return OpenAITtsConfig(
      id: json['id'] as String,
      name: json['name'] as String,
      baseUrl: json['baseUrl'] as String,
      apiKey: json['apiKey'] as String,
      providerType: json['providerType'] as String? ?? 'openai_standard',
      authType: json['authType'] as String? ?? 'bearer',
      models: (json['models'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      selectedModel: json['selectedModel'] as String? ?? '',
      voices: (json['voices'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      selectedVoice: json['selectedVoice'] as String? ?? '',
      stylePresets: (json['stylePresets'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      selectedStylePreset: json['selectedStylePreset'] as String? ?? '',
      audioFormat: json['audioFormat'] as String? ?? 'mp3',
      isDefault: json['isDefault'] as bool? ?? false,
      supportsModelFetch: json['supportsModelFetch'] as bool? ?? true,
      supportsVoiceFetch: json['supportsVoiceFetch'] as bool? ?? false,
      isEnabled: json['isEnabled'] as bool? ?? true,
    );
  }
}
