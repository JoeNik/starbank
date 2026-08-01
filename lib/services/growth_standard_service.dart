import '../models/baby.dart';
import '../utils/baby_profile_utils.dart';

enum GrowthMetric {
  height,
  weight,
  headCircumference,
}

class GrowthStandardBand {
  final double ageMonths;
  final double low;
  final double median;
  final double high;
  final String sourceLabel;

  const GrowthStandardBand({
    required this.ageMonths,
    required this.low,
    required this.median,
    required this.high,
    required this.sourceLabel,
  });
}

class GrowthStandardService {
  const GrowthStandardService._();

  static const nationalSourceTitle = '国家卫健委《7岁以下儿童生长标准》';
  static const whoSourceTitle = 'WHO 2007 年 5–19 岁生长参考';
  static const sourceTitle = '国家卫健委与 WHO 儿童生长参考';
  static const sourceDescription =
      '0–6 岁采用国家卫健委《7岁以下儿童生长标准》；6 岁后采用 WHO 2007 年 5–19 岁生长参考。'
      'WHO 身高年龄参考覆盖至 19 岁，体重年龄参考覆盖至 10 岁。';
  static const whoReferenceUrl =
      'https://www.who.int/tools/growth-reference-data-for-5to19-years';

  static List<GrowthStandardBand> bandsFor({
    required Baby baby,
    required GrowthMetric metric,
  }) {
    if (baby.gender != 'male' && baby.gender != 'female') return const [];
    final national = _nationalTableFor(metric, baby.gender);
    final who = _whoTableFor(metric, baby.gender);
    return [
      for (final row in national) _bandFromRow(row, nationalSourceTitle),
      for (final row in who)
        if (national.isEmpty || row[0] > national.last[0])
          _bandFromRow(row, whoSourceTitle),
    ];
  }

  static GrowthStandardBand? bandAt({
    required Baby baby,
    required DateTime recordDate,
    required GrowthMetric metric,
  }) {
    final month = BabyProfileUtils.ageMonths(baby, recordDate);
    if (month < 0) return null;
    return bandAtAgeMonths(
      baby: baby,
      metric: metric,
      ageMonths: month.toDouble(),
    );
  }

  static GrowthStandardBand? bandAtAgeMonths({
    required Baby baby,
    required GrowthMetric metric,
    required double ageMonths,
  }) {
    if (baby.gender != 'male' && baby.gender != 'female') return null;
    final national = _nationalTableFor(metric, baby.gender);
    final who = _whoTableFor(metric, baby.gender);
    final useWho = national.isNotEmpty &&
        ageMonths > national.last[0].toDouble() &&
        who.isNotEmpty;
    final table = useWho ? who : national;
    final source = useWho ? whoSourceTitle : nationalSourceTitle;
    return _interpolate(table, ageMonths, source);
  }

  static String unavailableReason(GrowthMetric metric, int ageMonths) {
    if (ageMonths < 0) return '请先设置生日和性别后查看国家标准曲线';
    switch (metric) {
      case GrowthMetric.height:
        if (ageMonths > 228) return 'WHO 身高年龄参考覆盖至 19 岁';
        break;
      case GrowthMetric.weight:
        if (ageMonths > 120) {
          return 'WHO 体重年龄参考仅覆盖至 10 岁；青春期建议结合身高评估 BMI';
        }
        break;
      case GrowthMetric.headCircumference:
        if (ageMonths > 60) return '国家标准头围曲线暂未覆盖 5 岁以上';
        break;
    }
    return '请先设置生日和性别后查看国家标准曲线';
  }

  static GrowthStandardBand _bandFromRow(
    List<num> row,
    String source,
  ) {
    return GrowthStandardBand(
      ageMonths: row[0].toDouble(),
      low: row[1].toDouble(),
      median: row[2].toDouble(),
      high: row[3].toDouble(),
      sourceLabel: source,
    );
  }

  static GrowthStandardBand? _interpolate(
    List<List<num>> table,
    double ageMonths,
    String source,
  ) {
    if (table.isEmpty ||
        ageMonths < table.first[0] ||
        ageMonths > table.last[0]) {
      return null;
    }
    for (var i = 0; i < table.length - 1; i++) {
      final a = table[i];
      final b = table[i + 1];
      final start = a[0].toDouble();
      final end = b[0].toDouble();
      if (ageMonths < start || ageMonths > end) continue;
      final t = (ageMonths - start) / (end - start);
      double lerp(num x, num y) => (x + (y - x) * t).toDouble();
      return GrowthStandardBand(
        ageMonths: ageMonths,
        low: lerp(a[1], b[1]),
        median: lerp(a[2], b[2]),
        high: lerp(a[3], b[3]),
        sourceLabel: source,
      );
    }
    return _bandFromRow(table.last, source);
  }

  static List<List<num>> _nationalTableFor(
    GrowthMetric metric,
    String gender,
  ) {
    final male = gender == 'male';
    switch (metric) {
      case GrowthMetric.height:
        return male ? _heightMale : _heightFemale;
      case GrowthMetric.weight:
        return male ? _weightMale : _weightFemale;
      case GrowthMetric.headCircumference:
        return male ? _headMale : _headFemale;
    }
  }

  static List<List<num>> _whoTableFor(
    GrowthMetric metric,
    String gender,
  ) {
    final male = gender == 'male';
    switch (metric) {
      case GrowthMetric.height:
        return male ? _whoHeightMale : _whoHeightFemale;
      case GrowthMetric.weight:
        return male ? _whoWeightMale : _whoWeightFemale;
      case GrowthMetric.headCircumference:
        return const [];
    }
  }

  // 国家卫健委儿童生长标准常用检查点，列为：月龄、3%、50%、97%。
  // 0-6 月逐月，之后按标准随访常用月龄给出；曲线绘制时做线性插值。
  static const _heightMale = [
    [0, 46.9, 50.4, 54.0],
    [1, 50.7, 54.8, 59.0],
    [2, 54.3, 58.7, 63.3],
    [3, 57.5, 62.0, 66.6],
    [4, 60.1, 64.6, 69.3],
    [5, 62.1, 66.7, 71.5],
    [6, 63.7, 68.4, 73.3],
    [8, 66.3, 71.2, 76.3],
    [10, 68.9, 74.0, 79.3],
    [12, 71.2, 76.5, 82.1],
    [15, 74.0, 79.8, 85.8],
    [18, 76.6, 82.7, 89.1],
    [21, 79.1, 85.6, 92.4],
    [24, 81.6, 88.5, 95.8],
    [30, 86.9, 94.3, 102.1],
    [36, 92.4, 100.2, 108.3],
    [42, 97.2, 105.4, 113.8],
    [48, 101.8, 110.3, 119.0],
    [54, 106.2, 115.0, 123.9],
    [60, 109.8, 118.9, 128.2],
    [66, 113.3, 122.7, 132.4],
    [72, 116.0, 125.8, 135.8],
  ];

  static const _heightFemale = [
    [0, 46.4, 49.7, 53.2],
    [1, 49.8, 53.7, 57.8],
    [2, 53.2, 57.4, 61.8],
    [3, 56.3, 60.6, 65.1],
    [4, 58.8, 63.1, 67.7],
    [5, 60.8, 65.2, 69.8],
    [6, 62.3, 66.8, 71.5],
    [8, 64.7, 69.4, 74.3],
    [10, 67.2, 72.1, 77.3],
    [12, 69.7, 75.0, 80.5],
    [15, 72.9, 78.5, 84.3],
    [18, 75.6, 81.5, 87.7],
    [21, 78.1, 84.4, 91.1],
    [24, 80.5, 87.2, 94.3],
    [30, 85.7, 92.9, 100.3],
    [36, 91.0, 98.7, 106.7],
    [42, 95.6, 103.7, 112.0],
    [48, 100.2, 108.6, 117.2],
    [54, 104.4, 113.2, 122.2],
    [60, 108.5, 117.7, 127.2],
    [66, 112.2, 121.7, 131.7],
    [72, 115.7, 125.7, 136.1],
  ];

  static const _weightMale = [
    [0, 2.58, 3.32, 4.18],
    [1, 3.52, 4.51, 5.67],
    [2, 4.47, 5.68, 7.14],
    [3, 5.29, 6.70, 8.40],
    [4, 5.91, 7.45, 9.32],
    [5, 6.36, 8.00, 9.99],
    [6, 6.70, 8.41, 10.50],
    [8, 7.23, 9.05, 11.29],
    [10, 7.67, 9.58, 11.95],
    [12, 8.06, 10.05, 12.54],
    [15, 8.57, 10.68, 13.32],
    [18, 9.07, 11.29, 14.09],
    [21, 9.59, 11.93, 14.90],
    [24, 10.09, 12.54, 15.67],
    [30, 10.97, 13.64, 17.06],
    [36, 11.79, 14.65, 18.37],
    [42, 12.55, 15.63, 19.68],
    [48, 13.24, 16.64, 21.01],
    [54, 13.93, 17.46, 22.21],
    [60, 14.66, 18.37, 23.50],
    [66, 15.30, 19.27, 24.74],
    [72, 15.87, 20.26, 26.15],
  ];

  static const _weightFemale = [
    [0, 2.54, 3.21, 4.10],
    [1, 3.33, 4.20, 5.35],
    [2, 4.15, 5.21, 6.60],
    [3, 4.90, 6.13, 7.73],
    [4, 5.48, 6.83, 8.59],
    [5, 5.92, 7.36, 9.23],
    [6, 6.26, 7.77, 9.73],
    [8, 6.79, 8.41, 10.51],
    [10, 7.23, 8.94, 11.16],
    [12, 7.61, 9.40, 11.73],
    [15, 8.12, 10.02, 12.50],
    [18, 8.63, 10.65, 13.30],
    [21, 9.15, 11.30, 14.12],
    [24, 9.64, 11.92, 14.92],
    [30, 10.52, 13.05, 16.46],
    [36, 11.34, 14.13, 17.92],
    [42, 12.10, 15.16, 19.34],
    [48, 12.80, 16.17, 20.80],
    [54, 13.47, 17.18, 22.18],
    [60, 14.11, 18.26, 23.73],
    [66, 14.74, 19.33, 25.29],
    [72, 15.31, 20.37, 26.87],
  ];

  // WHO 2007 expanded percentile tables, sampled every 6 months.
  // Columns: age in months, P3, P50, P97. The official monthly source tables:
  // https://www.who.int/tools/growth-reference-data-for-5to19-years
  static const _whoHeightMale = [
    [72, 106.7, 116.0, 125.2],
    [78, 109.3, 118.9, 128.5],
    [84, 111.8, 121.7, 131.7],
    [90, 114.3, 124.5, 134.8],
    [96, 116.6, 127.3, 137.9],
    [102, 119.0, 129.9, 140.9],
    [108, 121.3, 132.6, 143.9],
    [114, 123.5, 135.2, 146.8],
    [120, 125.8, 137.8, 149.8],
    [126, 128.1, 140.4, 152.7],
    [132, 130.5, 143.1, 155.8],
    [138, 133.0, 146.0, 159.0],
    [144, 135.8, 149.1, 162.4],
    [150, 138.8, 152.4, 166.1],
    [156, 142.1, 156.0, 170.0],
    [162, 145.4, 159.7, 173.9],
    [168, 148.7, 163.2, 177.6],
    [174, 151.7, 166.3, 180.9],
    [180, 154.3, 169.0, 183.6],
    [186, 156.5, 171.1, 185.8],
    [192, 158.3, 172.9, 187.5],
    [198, 159.7, 174.2, 188.7],
    [204, 160.8, 175.2, 189.5],
    [210, 161.5, 175.8, 190.0],
    [216, 162.1, 176.1, 190.2],
    [222, 162.5, 176.4, 190.3],
    [228, 162.8, 176.5, 190.3],
  ];

  static const _whoHeightFemale = [
    [72, 105.5, 115.1, 124.8],
    [78, 108.0, 118.0, 127.9],
    [84, 110.5, 120.8, 131.1],
    [90, 113.1, 123.7, 134.3],
    [96, 115.7, 126.6, 137.5],
    [102, 118.3, 129.5, 140.7],
    [108, 121.0, 132.5, 144.0],
    [114, 123.8, 135.5, 147.3],
    [120, 126.6, 138.6, 150.7],
    [126, 129.5, 141.8, 154.1],
    [132, 132.5, 145.0, 157.5],
    [138, 135.5, 148.2, 160.9],
    [144, 138.4, 151.2, 164.1],
    [150, 141.0, 154.0, 167.0],
    [156, 143.3, 156.4, 169.4],
    [162, 145.2, 158.3, 171.4],
    [168, 146.7, 159.8, 172.8],
    [174, 147.9, 160.9, 173.9],
    [180, 148.7, 161.7, 174.6],
    [186, 149.3, 162.2, 175.0],
    [192, 149.8, 162.5, 175.3],
    [198, 150.0, 162.7, 175.4],
    [204, 150.3, 162.9, 175.4],
    [210, 150.5, 163.0, 175.5],
    [216, 150.6, 163.1, 175.5],
    [222, 150.8, 163.1, 175.5],
    [228, 150.9, 163.2, 175.5],
  ];

  static const _whoWeightMale = [
    [72, 16.11, 20.51, 26.66],
    [78, 17.00, 21.68, 28.35],
    [84, 17.92, 22.89, 30.13],
    [90, 18.84, 24.14, 32.02],
    [96, 19.76, 25.42, 34.03],
    [102, 20.68, 26.74, 36.21],
    [108, 21.60, 28.11, 38.56],
    [114, 22.56, 29.57, 41.13],
    [120, 23.58, 31.16, 43.94],
  ];

  static const _whoWeightFemale = [
    [72, 15.51, 20.16, 27.27],
    [78, 16.25, 21.23, 28.95],
    [84, 17.05, 22.37, 30.75],
    [90, 17.93, 23.64, 32.75],
    [96, 18.90, 25.03, 34.95],
    [102, 19.96, 26.55, 37.35],
    [108, 21.12, 28.20, 39.96],
    [114, 22.35, 29.97, 42.73],
    [120, 23.68, 31.86, 45.70],
  ];

  static const _headMale = [
    [0, 32.1, 34.5, 36.8],
    [1, 34.5, 36.9, 39.4],
    [2, 36.4, 38.9, 41.5],
    [3, 37.9, 40.5, 43.2],
    [4, 39.2, 41.7, 44.5],
    [5, 40.2, 42.7, 45.5],
    [6, 41.0, 43.6, 46.3],
    [8, 42.2, 44.8, 47.5],
    [10, 43.1, 45.7, 48.4],
    [12, 43.8, 46.4, 49.1],
    [15, 44.5, 47.1, 49.8],
    [18, 45.0, 47.6, 50.2],
    [21, 45.5, 48.0, 50.7],
    [24, 45.9, 48.4, 51.1],
    [30, 46.6, 49.2, 51.9],
    [36, 47.0, 49.7, 52.3],
    [42, 47.5, 50.1, 52.7],
    [48, 47.8, 50.4, 53.1],
    [54, 48.2, 50.8, 53.4],
    [60, 48.5, 51.1, 53.7],
  ];

  static const _headFemale = [
    [0, 31.6, 33.9, 36.2],
    [1, 33.8, 36.2, 38.6],
    [2, 35.6, 38.0, 40.5],
    [3, 37.1, 39.5, 42.1],
    [4, 38.3, 40.7, 43.3],
    [5, 39.3, 41.6, 44.3],
    [6, 40.1, 42.4, 45.1],
    [8, 41.2, 43.6, 46.3],
    [10, 42.1, 44.5, 47.2],
    [12, 42.7, 45.1, 47.8],
    [15, 43.4, 45.8, 48.5],
    [18, 43.9, 46.4, 49.1],
    [21, 44.4, 46.9, 49.6],
    [24, 44.8, 47.3, 50.0],
    [30, 45.5, 48.0, 50.7],
    [36, 46.0, 48.5, 51.2],
    [42, 46.5, 49.0, 51.6],
    [48, 46.9, 49.4, 52.0],
    [54, 47.2, 49.7, 52.3],
    [60, 47.5, 50.0, 52.6],
  ];
}
