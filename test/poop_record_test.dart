import 'package:flutter_test/flutter_test.dart';
import 'package:star_bank/models/poop_record.dart';

void main() {
  test('fromJson reads backed-up scalar fields with explicit validation', () {
    final record = PoopRecord.fromJson({
      'id': 123,
      'babyId': 'baby-1',
      'dateTime': '2026-07-05T08:30:00.000',
      'note': '量正常',
      'type': '1',
      'color': 2.0,
    });

    expect(record.id, '123');
    expect(record.babyId, 'baby-1');
    expect(record.dateTime, DateTime(2026, 7, 5, 8, 30));
    expect(record.note, '量正常');
    expect(record.type, 1);
    expect(record.color, 2);
  });

  test('fromJson rejects records without required ownership fields', () {
    expect(
      () => PoopRecord.fromJson({
        'id': 'poop-1',
        'dateTime': '2026-07-05T08:30:00.000',
      }),
      throwsA(isA<FormatException>()),
    );
  });

  test('fromHiveFields keeps optional model defaults for old field sets', () {
    final record = PoopRecord.fromHiveFields({
      0: 'poop-1',
      1: 'baby-1',
      2: DateTime(2026, 7, 5, 8, 30),
    });

    expect(record.note, '');
    expect(record.type, 0);
    expect(record.color, 0);
  });
}
