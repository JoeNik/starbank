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
    return TuneHubMethod(
      type: json['type'] ?? 'http',
      method: json['method'] ?? 'GET',
      url: json['url'] ?? '',
      params: json['params'] ?? {},
      body: json['body'],
      headers: json['headers'] != null
          ? Map<String, String>.from(json['headers'])
          : null,
      transform: json['transform'],
    );
  }
}
