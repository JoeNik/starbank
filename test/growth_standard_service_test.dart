import 'package:flutter_test/flutter_test.dart';
import 'package:star_bank/models/baby.dart';
import 'package:star_bank/services/growth_standard_service.dart';

void main() {
  Baby baby(String gender) => Baby(
        id: 'baby-$gender',
        name: '宝宝',
        avatarPath: '',
        gender: gender,
      );

  test('男童 84 月龄身高使用 WHO 官方百分位数据', () {
    final band = GrowthStandardService.bandAtAgeMonths(
      baby: baby('male'),
      metric: GrowthMetric.height,
      ageMonths: 84,
    );

    expect(band, isNotNull);
    expect(band!.low, 111.8);
    expect(band.median, 121.7);
    expect(band.high, 131.7);
    expect(band.sourceLabel, GrowthStandardService.whoSourceTitle);
  });

  test('女童 120 月龄体重使用 WHO 官方百分位数据', () {
    final band = GrowthStandardService.bandAtAgeMonths(
      baby: baby('female'),
      metric: GrowthMetric.weight,
      ageMonths: 120,
    );

    expect(band, isNotNull);
    expect(band!.low, 23.68);
    expect(band.median, 31.86);
    expect(band.high, 45.70);
    expect(band.sourceLabel, GrowthStandardService.whoSourceTitle);
  });

  test('身高参考覆盖至 228 月，229 月无参考值', () {
    expect(
      GrowthStandardService.bandAtAgeMonths(
        baby: baby('male'),
        metric: GrowthMetric.height,
        ageMonths: 228,
      ),
      isNotNull,
    );
    expect(
      GrowthStandardService.bandAtAgeMonths(
        baby: baby('male'),
        metric: GrowthMetric.height,
        ageMonths: 229,
      ),
      isNull,
    );
  });

  test('体重参考覆盖至 120 月，121 月无参考值', () {
    expect(
      GrowthStandardService.bandAtAgeMonths(
        baby: baby('female'),
        metric: GrowthMetric.weight,
        ageMonths: 120,
      ),
      isNotNull,
    );
    expect(
      GrowthStandardService.bandAtAgeMonths(
        baby: baby('female'),
        metric: GrowthMetric.weight,
        ageMonths: 121,
      ),
      isNull,
    );
  });

  test('72 月仍属国家标准，超过 72 月切换为 WHO 参考', () {
    final at72 = GrowthStandardService.bandAtAgeMonths(
      baby: baby('male'),
      metric: GrowthMetric.height,
      ageMonths: 72,
    );
    final after72 = GrowthStandardService.bandAtAgeMonths(
      baby: baby('male'),
      metric: GrowthMetric.height,
      ageMonths: 72.5,
    );

    expect(at72?.sourceLabel, GrowthStandardService.nationalSourceTitle);
    expect(after72?.sourceLabel, GrowthStandardService.whoSourceTitle);
  });
}
