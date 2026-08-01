import 'package:flutter_test/flutter_test.dart';
import 'package:star_bank/pages/growth_record_page.dart';

void main() {
  test('图表横轴上限会纳入超出参考表的实测月龄', () {
    expect(
      growthChartMaxAgeMonths(120, const [24, 72, 144]),
      144,
    );
  });

  test('无超龄实测点时保持参考表上限', () {
    expect(
      growthChartMaxAgeMonths(228, const [24, 84, 120]),
      228,
    );
  });
}
