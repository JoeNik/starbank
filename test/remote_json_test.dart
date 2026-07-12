import 'package:flutter_test/flutter_test.dart';
import 'package:star_bank/utils/remote_json.dart';

void main() {
  group('tryDecodeJson', () {
    test('returns null for empty or invalid body', () {
      expect(tryDecodeJson(null), isNull);
      expect(tryDecodeJson(''), isNull);
      expect(tryDecodeJson('   '), isNull);
      expect(tryDecodeJson('not-json'), isNull);
      expect(tryDecodeJson('{'), isNull);
    });

    test('decodes object and list', () {
      expect(tryDecodeJsonObject('{"a":1}')?['a'], 1);
      expect(tryDecodeJsonList('[1,2,3]'), [1, 2, 3]);
      expect(tryDecodeJsonObject('[]'), isNull);
      expect(tryDecodeJsonList('{}'), isNull);
    });
  });

  group('chat completion extractors', () {
    test('extracts plain content', () {
      final data = {
        'choices': [
          {
            'message': {
              'role': 'assistant',
              'content': 'hello',
            }
          }
        ]
      };
      expect(extractChatCompletionContent(data), 'hello');
    });

    test('extracts multi-part content', () {
      final data = {
        'choices': [
          {
            'message': {
              'role': 'assistant',
              'content': [
                {'type': 'text', 'text': 'part-a'},
                {'type': 'text', 'text': 'part-b'},
              ],
            }
          }
        ]
      };
      expect(extractChatCompletionContent(data), 'part-apart-b');
    });

    test('returns null when choices missing or empty', () {
      expect(extractChatCompletionContent({}), isNull);
      expect(extractChatCompletionContent({'choices': []}), isNull);
      expect(
        extractChatCompletionContent({
          'choices': [
            {'message': {}}
          ]
        }),
        isNull,
      );
    });
  });

  group('image payload', () {
    test('extracts url and base64', () {
      final urls = extractImagePayloadUrls({
        'data': [
          {'url': 'https://example.com/a.png'},
          {'b64_json': 'abc'},
        ]
      });
      expect(urls, [
        'https://example.com/a.png',
        'data:image/png;base64,abc',
      ]);
    });

    test('throws when data missing or empty', () {
      expect(() => extractImagePayloadUrls({}), throwsFormatException);
      expect(() => extractImagePayloadUrls({'data': []}), throwsFormatException);
    });
  });

  group('openAiErrorMessage', () {
    test('reads nested error message and falls back for empty body', () {
      expect(
        openAiErrorMessage('{"error":{"message":"bad key"}}', 401),
        'bad key',
      );
      expect(openAiErrorMessage('', 500), '请求失败: 500');
      expect(openAiErrorMessage(null, 502), '请求失败: 502');
    });
  });
}
