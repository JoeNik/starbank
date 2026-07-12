class TuneHubMethod {
  final String type; // "http"
  final String method; // "GET", "POST"
  final String url;
  final Map<String, dynamic> params;
  final Map<String, dynamic>? body;
  final Map<String, String>? headers;
  final String? transform; // raw code or description

  TuneHubMethod({
    required this.type,
    required this.method,
    required this.url,
    required this.params,
    this.body,
    this.headers,
    this.transform,
  });

  factory TuneHubMethod.fromJson(Map<String, dynamic> json) {
    final paramsRaw = json['params'];
    final headersRaw = json['headers'];
    final bodyRaw = json['body'];
    return TuneHubMethod(
      type: (json['type'] ?? 'http').toString(),
      method: (json['method'] ?? 'GET').toString(),
      url: (json['url'] ?? '').toString(),
      params: paramsRaw is Map
          ? Map<String, dynamic>.from(paramsRaw)
          : <String, dynamic>{},
      body: bodyRaw is Map ? Map<String, dynamic>.from(bodyRaw) : null,
      headers: headersRaw is Map
          ? headersRaw.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''))
          : null,
      transform: json['transform']?.toString(),
    );
  }
}
